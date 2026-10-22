import { createServer } from 'node:http';
import { promises as fs } from 'node:fs';
import { createHash, verify, X509Certificate } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createDatabase } from './db.js';
import { normalizeExtractedEvents } from './event-filter.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const usageFile = path.join(rootDir, 'data', 'daily-ai-usage.json');

await loadDotEnv();

const port = Number(process.env.PORT ?? 8787);
const host = process.env.HOST ?? '0.0.0.0';
const deepSeekApiKey = process.env.DEEPSEEK_API_KEY ?? '';
const maxTextChars = Number(process.env.MAX_TEXT_CHARS ?? 50000);
const deepSeekTimeoutMs = Number(process.env.DEEPSEEK_TIMEOUT_MS ?? 90000);
const appBundleId = process.env.APP_BUNDLE_ID ?? 'ailesson.path.Object1';
const allowUnverifiedStoreKitJWS = process.env.ALLOW_UNVERIFIED_STOREKIT_JWS === 'true';
const appStoreRootCertificate = await loadAppStoreRootCertificate();
const premiumProductIDs = new Set([
  'ailesson.path.Object1.premium.monthly',
  'ailesson.path.Object1.premium.lifetime'
]);
const database = createDatabase({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_SSL === 'true' ? { rejectUnauthorized: false } : undefined
});
const dailyLimits = {
  free: 2,
  premium: 5
};
const rateLimits = {
  quota: {
    name: 'quota',
    limit: parsePositiveInteger(process.env.QUOTA_RATE_LIMIT_PER_MINUTE, 120),
    windowMs: 60 * 1000,
    message: '查询次数过于频繁，请稍后再试'
  },
  extract: {
    name: 'extract',
    limit: parsePositiveInteger(process.env.EXTRACT_RATE_LIMIT_PER_HOUR, 30),
    windowMs: 60 * 60 * 1000,
    message: '提取请求过于频繁，请稍后再试'
  }
};
const rateLimitBuckets = new Map();

await database.init();

const server = createServer((req, res) => {
  handleRequest(req, res).catch((error) => {
    console.error(error);
    sendJSON(res, 500, {
      error: 'internal_error',
      message: '服务器内部错误'
    });
  });
});

server.listen(port, host, () => {
  console.log(`AI backend listening on http://${host}:${port}`);
  console.log(`Simulator URL: http://127.0.0.1:${port}`);
  console.log(`Real device URL: http://<your-mac-lan-ip>:${port}`);
});

async function handleRequest(req, res) {
  const pathname = getPathname(req.url);

  if (req.method === 'GET' && pathname === '/health') {
    const databaseHealth = await database.health().catch((error) => ({
      ok: false,
      configured: database.isEnabled,
      message: error?.message ?? 'database unavailable'
    }));

    sendJSON(res, 200, {
      ok: true,
      deepSeekConfigured: Boolean(deepSeekApiKey),
      database: databaseHealth
    });
    return;
  }

  if (req.method === 'GET' && pathname === '/privacy') {
    sendHTML(res, 200, privacyPolicyHTML());
    return;
  }

  if (req.method === 'GET' && pathname === '/terms') {
    sendHTML(res, 200, termsOfServiceHTML());
    return;
  }

  if (req.method === 'DELETE' && pathname === '/api/user-data') {
    await handleDeleteUserData(req, res);
    return;
  }

  if (req.method === 'GET' && pathname === '/api/quota') {
    await handleGetQuota(req, res);
    return;
  }

  if (req.method === 'POST' && pathname === '/api/extract-events') {
    await handleExtractEvents(req, res);
    return;
  }

  sendJSON(res, 404, {
    error: 'not_found',
    message: '接口不存在'
  });
}

async function handleDeleteUserData(req, res) {
  if (!enforceRateLimit(req, res, rateLimits.quota)) {
    return;
  }

  const installId = getHeader(req, 'x-install-id')?.trim();
  if (!installId || installId.length > 120) {
    sendJSON(res, 400, {
      error: 'missing_install_id',
      message: '缺少有效安装标识'
    });
    return;
  }

  let deletedUsageRows = 0;
  if (database.isEnabled) {
    const result = await database.deleteInstallData({ installId });
    deletedUsageRows = result.deletedUsageRows;
  } else {
    const usage = await readUsage();
    for (const day of Object.keys(usage)) {
      if (usage[day]?.[installId]) {
        delete usage[day][installId];
        deletedUsageRows += 1;
      }
      if (Object.keys(usage[day] ?? {}).length === 0) {
        delete usage[day];
      }
    }
    await writeUsage(usage);
  }

  sendJSON(res, 200, {
    ok: true,
    deletedUsageRows,
    message: '当前安装标识对应的额度记录已删除'
  });
}

async function handleGetQuota(req, res) {
  if (!enforceRateLimit(req, res, rateLimits.quota)) {
    return;
  }

  const installId = getHeader(req, 'x-install-id')?.trim();

  if (!installId || installId.length > 120) {
    sendJSON(res, 400, {
      error: 'missing_install_id',
      message: '缺少设备标识，请更新 App 后重试'
    });
    return;
  }

  const tier = await getVerifiedEntitlementTier(req);
  const quota = await getDailyQuota({ installId, tier });
  const canExtract = quota.used < quota.limit;
  sendJSON(res, 200, {
    quota,
    canExtract,
    message: canExtract ? null : dailyLimitMessage(tier)
  });
}

async function handleExtractEvents(req, res) {
  if (!enforceRateLimit(req, res, rateLimits.extract)) {
    return;
  }

  if (!deepSeekApiKey || deepSeekApiKey.startsWith('sk-your-')) {
    sendJSON(res, 500, {
      error: 'deepseek_not_configured',
      message: '请先在 Backend/.env 配置 DEEPSEEK_API_KEY'
    });
    return;
  }

  const body = await readJSONBody(req);
  const installId = getHeader(req, 'x-install-id')?.trim();
  const gameName = typeof body.gameName === 'string' ? body.gameName.trim() : '';
  const articleUrl = typeof body.articleURL === 'string' ? body.articleURL.trim() : '';
  const text = typeof body.text === 'string' ? body.text.trim() : '';

  if (!installId || installId.length > 120) {
    sendJSON(res, 400, {
      error: 'missing_install_id',
      message: '缺少设备标识，请更新 App 后重试'
    });
    return;
  }

  if (!gameName) {
    sendJSON(res, 400, {
      error: 'missing_game_name',
      message: '缺少 gameName'
    });
    return;
  }

  if (!text) {
    sendJSON(res, 400, {
      error: 'missing_text',
      message: '缺少公告正文 text'
    });
    return;
  }

  const tier = await getVerifiedEntitlementTier(req);
  const limitedText = text.slice(0, maxTextChars);
  const normalizedUrl = normalizeArticleURL(articleUrl);
  const contentHash = hashText(limitedText);
  const cacheKey = buildExtractionCacheKey({ normalizedUrl, contentHash, gameName });

  // Every user-triggered extraction consumes quota, whether served from cache or DeepSeek.
  let reservedQuota = null;
  if (database.isEnabled) {
    reservedQuota = await reserveDailyUsage({ installId, tier });
    if (!reservedQuota) {
      const quota = await getDailyQuota({ installId, tier });
      sendDailyLimitExceeded(res, { tier, quota });
      return;
    }
  } else {
    const quota = await getDailyQuota({ installId, tier });
    if (quota.used >= quota.limit) {
      sendDailyLimitExceeded(res, { tier, quota });
      return;
    }
  }

  if (database.isEnabled) {
    let cached;
    try {
      cached = await database.getCachedExtraction({ cacheKey });
    } catch (error) {
      if (reservedQuota) {
        await refundDailyUsage({ installId, tier }).catch((refundError) => {
          console.error('Failed to refund daily usage after cache lookup error', refundError);
        });
      }
      throw error;
    }

    if (cached) {
      const cachedEvents = normalizeExtractedEvents(cached.events);
      sendJSON(res, 200, {
        events: cachedEvents,
        quota: reservedQuota,
        cache: {
          hit: true,
          articleURL: cached.articleUrl,
          updatedAt: cached.updatedAt
        }
      });
      return;
    }
  }

  let events;
  try {
    events = await extractEventsWithDeepSeek({
      gameName,
      text: limitedText
    });
  } catch (error) {
    // DeepSeek failures should not consume user quota.
    if (reservedQuota) {
      await refundDailyUsage({ installId, tier }).catch((refundError) => {
        console.error('Failed to refund daily AI usage', refundError);
      });
    }

    console.error(error);
    sendJSON(res, 502, {
      error: 'deepseek_error',
      message: error?.message ?? 'DeepSeek 请求失败，请稍后重试'
    });
    return;
  }

  if (database.isEnabled) {
    await database.saveExtraction({
      cacheKey,
      articleUrl: articleUrl || null,
      normalizedUrl,
      contentHash,
      gameName,
      events
    }).catch((error) => {
      console.error('Failed to save extraction cache', error);
    });
  }

  const updatedQuota = reservedQuota ?? await incrementDailyUsage({ installId, tier });

  sendJSON(res, 200, {
    events,
    quota: updatedQuota,
    cache: {
      hit: false
    }
  });
}

async function extractEventsWithDeepSeek({ gameName, text }) {
  const today = formatDateOnlyInShanghai(new Date());
  const exampleEnd = formatDateTimeInShanghai(new Date(Date.now() + 21 * 86400 * 1000));

  const system = `
你是一个从游戏公告中提取结构化活动数据的助手，必须以 JSON 格式返回结果。

【时间规则】所有时间使用北京时间（UTC+8），格式严格为 "YYYY-MM-DD HH:mm"（例如 "2025-06-25 10:00"）。
必须按照原文公告中给出的具体时间填写，不得只写日期、不得省略小时分钟、不得换算时区。
如果公告只给了日期没有时间，填 "YYYY-MM-DD 00:00"。
如果公告写的是"当前版本结束"或"版本维护时"，请根据上下文中版本结束时间推断并填入。

【提取规则】请提取所有相关活动的起止时间，即使公告只写了"当前版本结束"，也请尽量提取。
过期判断将由客户端处理，不需要在此过滤。

收录类型：
1. 版本限时活动（有明确开始和结束时间）
2. 周常任务（endDate 填当前版本的维护时间）
3. 副本/关卡挑战

排除：社交媒体活动、充值礼包、线下活动、官方直播、投票问卷、每日签到/打卡活动、登录/累计登录/签到奖励、时装/皮肤折扣或销售活动。
必须排除所有卡池/抽卡相关内容，包括但不限于角色或武器祈愿、跃迁、寻访、调频、UP 池、复刻池、概率提升、补给、招募、召唤、唤取等。
同时排除标题或分类中包含"角色"或"武器"的条目。

返回 JSON 格式如下：
{"events":[{"title":"活动名","startDate":"YYYY-MM-DD HH:mm","endDate":"YYYY-MM-DD HH:mm","category":"版本活动"}]}

category 规则：
- 版本限时活动 → "版本活动"
- 周常/每周任务 → "周常任务"
- 副本/关卡挑战 → "副本挑战"

找不到则返回 JSON：{"events":[]}。
`.trim();

  const user = `
游戏：${gameName}
今天（北京时间）：${today}
示例版本结束时间：${exampleEnd}

以下是从公告页面提取的正文：
${text}
`.trim();

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), deepSeekTimeoutMs);
  let response;

  try {
    response = await fetch('https://api.deepseek.com/chat/completions', {
      method: 'POST',
      signal: controller.signal,
      headers: {
        'Authorization': `Bearer ${deepSeekApiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: 'deepseek-chat',
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: user }
        ],
        response_format: { type: 'json_object' },
        temperature: 0,
        max_tokens: 4000
      })
    });
  } catch (error) {
    if (error?.name === 'AbortError') {
      throw new Error(`DeepSeek 请求超时（${Math.round(deepSeekTimeoutMs / 1000)} 秒）`);
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`DeepSeek ${response.status}: ${body.slice(0, 240)}`);
  }

  const data = await response.json();
  const content = data?.choices?.[0]?.message?.content;
  if (typeof content !== 'string') {
    throw new Error('DeepSeek 响应格式异常');
  }

  const parsed = JSON.parse(extractJSONPayload(content));
  const rawEvents = Array.isArray(parsed.events) ? parsed.events : [];
  return normalizeExtractedEvents(rawEvents);
}

function extractJSONPayload(content) {
  const trimmed = content.trim();
  const fenced = extractFirstFencedBlock(trimmed);
  if (fenced) return extractJSONObject(fenced) ?? fenced;
  return extractJSONObject(trimmed) ?? trimmed;
}

function extractJSONObject(text) {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start === -1 || end === -1 || start > end) return null;
  return text.slice(start, end + 1).trim();
}

function extractFirstFencedBlock(text) {
  const opening = text.indexOf('```');
  if (opening === -1) return null;
  const afterOpening = text.slice(opening + 3);
  const firstNewline = afterOpening.indexOf('\n');
  const contentStart = firstNewline === -1 ? opening + 3 : opening + 3 + firstNewline + 1;
  const closing = text.indexOf('```', contentStart);
  if (closing === -1) return null;
  return text.slice(contentStart, closing).trim();
}

function formatDateOnlyInShanghai(date) {
  return formatParts(date).slice(0, 3).join('-');
}

function formatDateTimeInShanghai(date) {
  const [year, month, day, hour, minute] = formatParts(date);
  return `${year}-${month}-${day} ${hour}:${minute}`;
}

function formatParts(date) {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Shanghai',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23'
  });

  const parts = Object.fromEntries(
    formatter.formatToParts(date).map((part) => [part.type, part.value])
  );

  return [parts.year, parts.month, parts.day, parts.hour, parts.minute];
}

async function readJSONBody(req) {
  const chunks = [];
  let total = 0;

  for await (const chunk of req) {
    total += chunk.length;
    if (total > 2 * 1024 * 1024) {
      throw new Error('请求体过大');
    }
    chunks.push(chunk);
  }

  const raw = Buffer.concat(chunks).toString('utf8');
  if (!raw.trim()) return {};
  return JSON.parse(raw);
}

function getHeader(req, name) {
  const value = req.headers[name];
  if (Array.isArray(value)) return value[0];
  return value;
}

async function getVerifiedEntitlementTier(req) {
  const transactionJWS = getHeader(req, 'x-app-store-transaction')?.trim();
  if (!transactionJWS) return 'free';

  const transaction = verifyAppStoreTransactionJWS(transactionJWS);
  if (!transaction) return 'free';

  const productId = typeof transaction.productId === 'string'
    ? transaction.productId
    : (typeof transaction.productID === 'string' ? transaction.productID : '');
  const bundleId = typeof transaction.bundleId === 'string'
    ? transaction.bundleId
    : (typeof transaction.bundleID === 'string' ? transaction.bundleID : '');
  if (!premiumProductIDs.has(productId)) return 'free';
  if (bundleId !== appBundleId) return 'free';
  if (transaction.revocationDate) return 'free';

  const expiresDate = Number(transaction.expiresDate ?? 0);
  if (expiresDate > 0 && expiresDate <= Date.now()) return 'free';

  return 'premium';
}

function verifyAppStoreTransactionJWS(jws) {
  try {
    const parts = jws.split('.');
    if (parts.length !== 3) return null;

    const [encodedHeader, encodedPayload, encodedSignature] = parts;
    const header = parseBase64URLJSON(encodedHeader);
    const payload = parseBase64URLJSON(encodedPayload);
    if (!header || !payload || header.alg !== 'ES256') return null;

    if (!allowUnverifiedStoreKitJWS) {
      if (!appStoreRootCertificate) return null;
      const certificates = parseJWSCertificateChain(header.x5c);
      if (!verifyCertificateChain(certificates, appStoreRootCertificate)) return null;

      const signature = base64URLToBuffer(encodedSignature);
      const signedData = Buffer.from(`${encodedHeader}.${encodedPayload}`, 'utf8');
      const isSignatureValid = verify(
        'sha256',
        signedData,
        {
          key: certificates[0].publicKey,
          dsaEncoding: 'ieee-p1363'
        },
        signature
      );
      if (!isSignatureValid) return null;
    }

    return payload;
  } catch {
    return null;
  }
}

function parseJWSCertificateChain(x5c) {
  if (!Array.isArray(x5c) || x5c.length === 0) return [];
  return x5c.map((certificate) => new X509Certificate(pemFromBase64Certificate(certificate)));
}

function verifyCertificateChain(certificates, trustedRoot) {
  if (certificates.length === 0) return false;

  for (const certificate of certificates) {
    if (!isCertificateCurrentlyValid(certificate)) return false;
  }

  for (let i = 0; i < certificates.length - 1; i += 1) {
    const certificate = certificates[i];
    const issuer = certificates[i + 1];
    if (certificate.issuer !== issuer.subject) return false;
    if (!certificate.verify(issuer.publicKey)) return false;
  }

  const chainRoot = certificates[certificates.length - 1];
  if (
    chainRoot.fingerprint256 === trustedRoot.fingerprint256 &&
    chainRoot.subject === trustedRoot.subject
  ) {
    return true;
  }

  return chainRoot.issuer === trustedRoot.subject && chainRoot.verify(trustedRoot.publicKey);
}

function isCertificateCurrentlyValid(certificate) {
  const now = Date.now();
  return Date.parse(certificate.validFrom) <= now && now <= Date.parse(certificate.validTo);
}

function parseBase64URLJSON(value) {
  try {
    return JSON.parse(base64URLToBuffer(value).toString('utf8'));
  } catch {
    return null;
  }
}

function base64URLToBuffer(value) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(normalized.length + ((4 - normalized.length % 4) % 4), '=');
  return Buffer.from(padded, 'base64');
}

function pemFromBase64Certificate(value) {
  const body = String(value).match(/.{1,64}/g)?.join('\n') ?? '';
  return `-----BEGIN CERTIFICATE-----\n${body}\n-----END CERTIFICATE-----`;
}

function enforceRateLimit(req, res, config) {
  const now = Date.now();
  pruneRateLimitBuckets(now);

  const clientAddress = getClientAddress(req);
  const key = `${config.name}:${clientAddress}`;
  const existing = rateLimitBuckets.get(key);

  if (!existing || existing.resetAt <= now) {
    rateLimitBuckets.set(key, {
      count: 1,
      resetAt: now + config.windowMs
    });
    return true;
  }

  if (existing.count >= config.limit) {
    const retryAfterSeconds = Math.max(1, Math.ceil((existing.resetAt - now) / 1000));
    res.setHeader('Retry-After', String(retryAfterSeconds));
    sendJSON(res, 429, {
      error: 'rate_limited',
      message: config.message,
      retryAfterSeconds
    });
    return false;
  }

  existing.count += 1;
  return true;
}

function pruneRateLimitBuckets(now) {
  if (rateLimitBuckets.size < 10000) return;

  for (const [key, bucket] of rateLimitBuckets.entries()) {
    if (bucket.resetAt <= now) {
      rateLimitBuckets.delete(key);
    }
  }
}

function getClientAddress(req) {
  if (process.env.TRUST_PROXY_HEADERS === 'true') {
    const forwarded = getHeader(req, 'x-forwarded-for') ?? getHeader(req, 'cf-connecting-ip');
    const firstAddress = forwarded?.split(',')?.[0]?.trim();
    if (firstAddress) return firstAddress;
  }

  return req.socket?.remoteAddress ?? 'unknown';
}

function parsePositiveInteger(value, fallback) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function sendDailyLimitExceeded(res, { tier, quota }) {
  sendJSON(res, 429, {
    error: 'daily_limit_exceeded',
    message: dailyLimitMessage(tier),
    tier,
    used: quota.used,
    limit: quota.limit
  });
}

function dailyLimitMessage(tier) {
  const limit = dailyLimits[tier] ?? dailyLimits.free;
  return tier === 'premium'
    ? `会员今日 ${limit} 次提取额度已用完，明天会自动恢复。`
    : `免费版今日 ${limit} 次提取额度已用完。升级会员后每日可提取 ${dailyLimits.premium} 次。`;
}

function getPathname(rawUrl) {
  try {
    return new URL(rawUrl, 'http://localhost').pathname;
  } catch {
    return rawUrl;
  }
}

function hashText(text) {
  return createHash('sha256').update(text, 'utf8').digest('hex');
}

function buildExtractionCacheKey({ normalizedUrl, contentHash, gameName }) {
  if (normalizedUrl) {
    return `url:${normalizedUrl}:sha256:${contentHash}`;
  }

  return `text:${gameName.toLowerCase()}:sha256:${contentHash}`;
}

function normalizeArticleURL(rawUrl) {
  if (!rawUrl) return null;

  try {
    const url = new URL(rawUrl);
    url.protocol = url.protocol.toLowerCase();
    url.hostname = url.hostname.toLowerCase();
    url.hash = '';

    if (
      (url.protocol === 'https:' && url.port === '443') ||
      (url.protocol === 'http:' && url.port === '80')
    ) {
      url.port = '';
    }

    for (const key of Array.from(url.searchParams.keys())) {
      if (
        key.startsWith('utm_') ||
        [
          'spm_id_from',
          'share_source',
          'share_medium',
          'share_plat',
          'share_session_id',
          'bbid',
          'ts',
          'vd_source'
        ].includes(key)
      ) {
        url.searchParams.delete(key);
      }
    }

    url.searchParams.sort();
    return url.toString();
  } catch {
    const trimmed = rawUrl.trim();
    return trimmed ? trimmed : null;
  }
}

async function getDailyQuota({ installId, tier }) {
  const today = formatDateOnlyInShanghai(new Date());
  const limit = dailyLimits[tier] ?? dailyLimits.free;

  if (database.isEnabled) {
    return database.getDailyQuota({
      date: today,
      installId,
      tier,
      limit
    });
  }

  const usage = await readUsage();
  const used = usage?.[today]?.[installId]?.used ?? 0;
  return {
    date: today,
    tier,
    used,
    limit
  };
}

async function reserveDailyUsage({ installId, tier }) {
  const today = formatDateOnlyInShanghai(new Date());
  const limit = dailyLimits[tier] ?? dailyLimits.free;

  if (!database.isEnabled) return null;

  return database.reserveDailyUsage({
    date: today,
    installId,
    tier,
    limit
  });
}

async function refundDailyUsage({ installId, tier }) {
  const today = formatDateOnlyInShanghai(new Date());
  const limit = dailyLimits[tier] ?? dailyLimits.free;

  if (!database.isEnabled) {
    return getDailyQuota({ installId, tier });
  }

  return database.refundDailyUsage({
    date: today,
    installId,
    tier,
    limit
  });
}

async function incrementDailyUsage({ installId, tier }) {
  const today = formatDateOnlyInShanghai(new Date());
  const limit = dailyLimits[tier] ?? dailyLimits.free;

  if (database.isEnabled) {
    return database.reserveDailyUsage({
      date: today,
      installId,
      tier,
      limit
    });
  }

  const usage = await readUsage();
  usage[today] ??= {};
  usage[today][installId] ??= { used: 0, tier, updatedAt: null };
  usage[today][installId].used += 1;
  usage[today][installId].tier = tier;
  usage[today][installId].updatedAt = new Date().toISOString();
  await writeUsage(usage);

  return {
    date: today,
    tier,
    used: usage[today][installId].used,
    limit
  };
}

async function readUsage() {
  try {
    const data = await fs.readFile(usageFile, 'utf8');
    return JSON.parse(data);
  } catch (error) {
    if (error?.code === 'ENOENT') return {};
    throw error;
  }
}

async function writeUsage(usage) {
  await fs.mkdir(path.dirname(usageFile), { recursive: true });
  await fs.writeFile(usageFile, `${JSON.stringify(usage, null, 2)}\n`, 'utf8');
}

function sendJSON(res, status, payload) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(payload));
}

function sendHTML(res, status, html) {
  res.writeHead(status, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'public, max-age=300'
  });
  res.end(html);
}

function legalPageHTML({ title, updatedAt, body }) {
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${title} | 二游活动小灵通</title>
  <style>
    :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #17213b; background: #f7f8fb; }
    body { margin: 0; }
    main { max-width: 760px; margin: 0 auto; padding: 40px 18px 56px; }
    h1 { margin: 0 0 8px; font-size: 30px; line-height: 1.2; }
    h2 { margin: 28px 0 10px; font-size: 18px; }
    p, li { font-size: 15px; line-height: 1.75; }
    p { margin: 0 0 12px; }
    ul { margin: 0; padding-left: 20px; }
    a { color: #d83d84; }
    .updated { color: #69748a; font-size: 13px; }
  </style>
</head>
<body>
  <main>
    <h1>${title}</h1>
    <p class="updated">更新日期：${updatedAt}</p>
    ${body}
  </main>
</body>
</html>`;
}

function privacyPolicyHTML() {
  return legalPageHTML({
    title: '隐私政策',
    updatedAt: '2026-07-18',
    body: `
    <p>二游活动小灵通用于整理游戏活动和提醒。我们遵循最小必要原则，不出售用户数据，也不进行跨 App 或跨网站追踪。</p>

    <h2>运营者与联系</h2>
    <p>本服务由二游活动小灵通开发者运营。正式发布前将在此补充运营者真实名称、联系邮箱和注册地址。用户可通过公开联系方式提出查阅、更正、删除、撤回同意或投诉请求。</p>

    <h2>我们会处理的数据</h2>
    <ul>
      <li>安装标识：App 会生成一个随机安装标识，用于后端计算每日 AI 提取额度和基础限流。</li>
      <li>公告内容：仅当你主动使用 AI 提取时，游戏名、公告链接和公告正文会发送到后端，用于整理活动。共享结果缓存不保存安装标识与结果之间的映射。</li>
      <li>购买凭证：开通会员后，App 会把 App Store 交易凭证发送给后端，只用于验证会员额度。</li>
      <li>本地内容：你创建的游戏、活动、通知设置和小组件数据主要保存在设备本地；如果系统启用 iCloud，同步由 Apple iCloud 处理。</li>
    </ul>

    <h2>第三方服务与 AI 公示</h2>
    <p>AI 提取功能通过我们的后端调用 DeepSeek；正式发布前将在 App 和本页补充实际模型名称及备案号。Apple 提供 App 内购买、iCloud 和通知能力；活动数据接口用于获取公开活动时间。付款信息不经过我们的服务器。</p>

    <h2>数据保留</h2>
    <p>后端仅按提供服务及安全审计所需的最短期限保留安装标识对应的额度记录。提取缓存保存公告内容哈希、链接和结构化结果，不保存原始公告正文。用户可在 App 的“管理我的数据”中删除额度记录并重置安装标识。</p>

    <h2>存储地域与跨境</h2>
    <p>当前测试环境可能使用境外云服务。正式面向中国大陆运营前，将迁移至已备案的数据基础设施，或依法履行适用的数据跨境义务。</p>

    <h2>你的权利</h2>
    <p>你可在 App 内清除本地数据、删除当前安装标识对应的服务器记录、撤回隐私同意。撤回后，在再次同意前 App 不会启动联网服务。</p>

    <h2>未成年人保护</h2>
    <p>本 App 不以未成年人为主要服务对象。未成年人应在监护人指导下使用 AI 功能和购买服务。</p>

    <h2>联系我们</h2>
    <p>如需隐私相关支持，请通过 App Store 产品页提供的开发者联系方式联系我们。</p>`
  });
}

function termsOfServiceHTML() {
  return legalPageHTML({
    title: '服务条款',
    updatedAt: '2026-07-18',
    body: `
    <p>使用二游活动小灵通，即表示你同意本条款。App 用于个人整理游戏活动信息，提取结果可能受公告内容质量和 AI 服务状态影响，请以游戏官方公告为准。</p>

    <h2>会员与购买</h2>
    <ul>
      <li>月度会员为自动续订订阅，价格以 App Store 购买页显示为准。</li>
      <li>一休尼会员为一次性购买项目，购买后可长期使用当前会员权益。</li>
      <li>购买、续订、取消和退款由 Apple App Store 处理。你可以在系统账户的订阅管理中取消月度会员。</li>
      <li>月度会员会自动续订，除非在当前周期结束前至少 24 小时取消。</li>
    </ul>

    <h2>会员权益</h2>
    <p>会员当前包含更高的自定义游戏数量上限和每日 AI 提取额度。具体额度以 App 内展示为准。为了保证服务稳定，我们仍可能对异常高频请求进行限制。</p>

    <h2>使用限制</h2>
    <p>请勿批量滥用接口、绕过额度限制、提交违法内容，或将本服务用于侵犯他人权益的用途。</p>

    <h2>Apple 标准协议</h2>
    <p>App 内购买还受 <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/">Apple 标准许可协议</a> 约束。</p>

    <h2>联系我们</h2>
    <p>如需服务相关支持，请通过 App Store 产品页提供的开发者联系方式联系我们。</p>`
  });
}

async function loadDotEnv() {
  const envFile = path.join(rootDir, '.env');
  let raw;
  try {
    raw = await fs.readFile(envFile, 'utf8');
  } catch (error) {
    if (error?.code === 'ENOENT') return;
    throw error;
  }

  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const equalsIndex = trimmed.indexOf('=');
    if (equalsIndex === -1) continue;

    const key = trimmed.slice(0, equalsIndex).trim();
    let value = trimmed.slice(equalsIndex + 1).trim();
    if (!key || process.env[key] !== undefined) continue;

    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    process.env[key] = value;
  }
}

async function loadAppStoreRootCertificate() {
  const certPath = process.env.APP_STORE_ROOT_CERT_PATH?.trim();
  const certPem = process.env.APP_STORE_ROOT_CERT_PEM?.trim();

  try {
    if (certPath) {
      const resolvedPath = path.isAbsolute(certPath) ? certPath : path.resolve(rootDir, certPath);
      return new X509Certificate(await fs.readFile(resolvedPath, 'utf8'));
    }

    if (certPem) {
      return new X509Certificate(certPem.replace(/\\n/g, '\n'));
    }
  } catch (error) {
    console.error('Failed to load App Store root certificate', error);
  }

  return null;
}
