// 米哈游活动日历的缓存代理：App 只请求本后端，上游挂了也能返回最近一次成功的数据。

export const SUPPORTED_CALENDAR_GAMES = new Set(['genshin', 'starrail', 'zenless']);

const LANG_PATTERN = /^[a-z]{2}(-[a-z]{2,4})?$/;

export function normalizeCalendarLang(rawLang) {
  const lang = String(rawLang ?? 'zh-cn').trim().toLowerCase();
  return LANG_PATTERN.test(lang) ? lang : null;
}

export function isValidCalendarPayload(payload) {
  return Boolean(
    payload &&
    typeof payload === 'object' &&
    !Array.isArray(payload) &&
    (Array.isArray(payload.events) || Array.isArray(payload.challenges))
  );
}

export function createCalendarProxy({
  upstreamBaseURL,
  freshMs,
  timeoutMs,
  store,
  fetchImpl = fetch,
  now = () => Date.now()
}) {
  const memory = new Map();
  const inFlight = new Map();
  const baseURL = upstreamBaseURL.replace(/\/+$/, '');

  async function readCached(key, game, lang) {
    const cached = memory.get(key);
    if (cached) return cached;

    const stored = await store.getCalendarCache({ game, lang }).catch((error) => {
      console.error('Failed to read calendar cache', error);
      return null;
    });
    if (!stored) return null;

    const entry = { payload: stored.payload, fetchedAt: new Date(stored.fetchedAt).getTime() };
    memory.set(key, entry);
    return entry;
  }

  async function fetchUpstream(game, lang) {
    const url = `${baseURL}/mihoyo/${encodeURIComponent(game)}/calendar?lang=${encodeURIComponent(lang)}`;
    const response = await fetchImpl(url, {
      headers: { Accept: 'application/json' },
      signal: AbortSignal.timeout(timeoutMs)
    });

    if (response.status === 404) {
      return { notFound: true };
    }
    if (!response.ok) {
      throw new Error(`Upstream calendar returned HTTP ${response.status}`);
    }

    const payload = await response.json();
    if (!isValidCalendarPayload(payload)) {
      throw new Error('Upstream calendar payload is missing events/challenges');
    }
    return { payload };
  }

  async function refresh(key, game, lang) {
    const result = await fetchUpstream(game, lang);
    if (result.notFound) return result;

    const entry = { payload: result.payload, fetchedAt: now() };
    memory.set(key, entry);
    await store.saveCalendarCache({ game, lang, payload: entry.payload }).catch((error) => {
      console.error('Failed to save calendar cache', error);
    });
    return { entry };
  }

  // 同一个 game+lang 同时只打一次上游，其余请求共用结果。
  function refreshOnce(key, game, lang) {
    if (!inFlight.has(key)) {
      inFlight.set(key, refresh(key, game, lang).finally(() => inFlight.delete(key)));
    }
    return inFlight.get(key);
  }

  return {
    // 返回 { status: 'hit' | 'miss' | 'stale' | 'not_found' | 'unavailable', payload?, fetchedAt? }
    async get({ game, lang }) {
      const key = `${game}:${lang}`;
      const cached = await readCached(key, game, lang);

      if (cached && now() - cached.fetchedAt < freshMs) {
        return { status: 'hit', payload: cached.payload, fetchedAt: cached.fetchedAt };
      }

      try {
        const result = await refreshOnce(key, game, lang);
        if (result.notFound) return { status: 'not_found' };
        return { status: 'miss', payload: result.entry.payload, fetchedAt: result.entry.fetchedAt };
      } catch (error) {
        console.error(`Calendar upstream failed for ${key}`, error?.message ?? error);
        if (cached) {
          return { status: 'stale', payload: cached.payload, fetchedAt: cached.fetchedAt };
        }
        return { status: 'unavailable' };
      }
    }
  };
}
