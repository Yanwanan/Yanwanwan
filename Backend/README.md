# 提取 Backend

这个后端做两件事：把 DeepSeek API key 留在服务器环境变量里；代理并缓存米哈游活动日历。App 只请求自己的后端接口。

正式发布时建议部署到 Railway，并绑定 Railway Postgres。后端会使用 Postgres 保存：

- 每日提取次数
- 公告 URL + 正文 hash 的提取缓存
- DeepSeek 返回的结构化活动
- 米哈游活动日历（每个游戏 + 语言最近一次成功的数据）

命中缓存时不会调用 DeepSeek，但仍会消耗 1 次每日提取次数。

## 本地运行

```bash
cd Backend
cp .env.example .env
```

把 `.env` 里的 `DEEPSEEK_API_KEY` 换成真实 key。需要测试正式缓存/次数限制时，也填入 `DATABASE_URL`。

会员额度由后端校验 App Store 交易 JWS 后决定。正式环境需要配置 Apple 根证书：

```env
APP_BUNDLE_ID=ailesson.path.Object1
APP_STORE_ROOT_CERT_PATH=./certs/AppleRootCA-G3.pem
```

本地 StoreKit 调试如果暂时没有证书链，可临时设置 `ALLOW_UNVERIFIED_STOREKIT_JWS=true`，只用于本地开发，不要带到线上。

然后运行：

```bash
npm start
```

长公告提取可能比较慢。默认后端等待 DeepSeek 90 秒，App 等待后端 120 秒；需要调整时可修改 `.env` 里的 `DEEPSEEK_TIMEOUT_MS`。

健康检查：

```bash
curl http://127.0.0.1:8787/health
```

上架用链接：

```bash
curl http://127.0.0.1:8787/privacy
curl http://127.0.0.1:8787/terms
```

真机调试时，手机和 Mac 必须在同一个 Wi-Fi 下，App 里需要填 Mac 的局域网 IP：

```bash
ipconfig getifaddr en0
curl http://你的Mac局域网IP:8787/health
```

模拟器继续使用 `http://127.0.0.1:8787`。

## Railway 部署

1. 在 Railway 新建 Project。
2. 添加 Postgres 数据库。
3. 添加 Node 后端服务，根目录选择 `Backend`。
4. 在后端服务里配置环境变量：

```env
DEEPSEEK_API_KEY=你的 DeepSeek key
DATABASE_URL=${{Postgres.DATABASE_URL}}
MAX_TEXT_CHARS=50000
DEEPSEEK_TIMEOUT_MS=90000
QUOTA_RATE_LIMIT_PER_MINUTE=120
EXTRACT_RATE_LIMIT_PER_HOUR=30
TRUST_PROXY_HEADERS=true
APP_BUNDLE_ID=ailesson.path.Object1
APP_STORE_ROOT_CERT_PATH=./certs/AppleRootCA-G3.pem
ALLOW_UNVERIFIED_STOREKIT_JWS=false
CALENDAR_UPSTREAM_BASE_URL=https://api.ennead.cc
CALENDAR_CACHE_TTL_SECONDS=600
```

Railway 会自动提供 `PORT`，不需要手动设置。部署成功后打开 `/health`，确认：

```json
{
  "ok": true,
  "deepSeekConfigured": true,
  "database": {
    "ok": true,
    "configured": true
  }
}
```

拿到 Railway 的 HTTPS 域名后，把 iOS 的 Release 后端地址改成该域名：

```swift
static let aiBackendBaseURL = "https://你的 Railway 域名"
```

提取接口：

```bash
curl -X POST http://127.0.0.1:8787/api/extract-events \
  -H 'Content-Type: application/json' \
  -H 'X-Install-ID: test-install-id' \
  -H 'X-App-Store-Transaction: 这里填 App 传来的 StoreKit 交易 JWS' \
  -d '{"gameName":"测试游戏","articleURL":"https://example.com/notice","text":"公告正文"}'
```

## 活动日历代理

`GET /api/calendar/{genshin|starrail|zenless}?lang=zh-cn`

- 原样返回上游 `/mihoyo/{game}/calendar` 的 JSON，App 解码逻辑不变。
- 缓存 10 分钟内直接返回（`CALENDAR_CACHE_TTL_SECONDS`），过期后再请求上游。
- 上游失败或返回格式不对时，返回最近一次成功的数据，不覆盖缓存；从未成功过则返回 502。
- 响应头 `X-Calendar-Cache` 为 `hit` / `miss` / `stale`，`X-Calendar-Fetched-At` 为数据抓取时间。
- 缓存存在内存和 Postgres 的 `calendar_cache` 表里，重启后仍可用；未配置数据库时只用内存缓存。
- 以后换数据源只需改 `CALENDAR_UPSTREAM_BASE_URL` 或 `src/calendar-proxy.js`，不用发 App 新版。

## 查询次数限制

后端按 `X-Install-ID` 和北京时间日期记录提取调用次数：

- 免费版：每日 2 次
- 会员：每日 5 次
- 同一 IP 默认每小时最多 30 次提取请求，避免伪造设备 ID 绕过每日次数后刷 DeepSeek 成本。可通过 `EXTRACT_RATE_LIMIT_PER_HOUR` 调整。

用户发起提取时会先检查并预扣次数；命中缓存时直接返回数据库结果并消耗 1 次，缓存未命中时调用 DeepSeek。DeepSeek 失败或缓存查询失败会退回次数。App 会把 StoreKit 当前权益的交易 JWS 放在 `X-App-Store-Transaction`，后端验证产品 ID、Bundle ID、吊销状态和过期时间后才按会员额度处理；没有凭证或验证失败时按免费版处理。部署在 Railway 这类反向代理后面时，设置 `TRUST_PROXY_HEADERS=true` 才会使用真实客户端 IP 做限流；本地直连环境保持默认 `false`。

## 上架检查

- iOS 主 App 和 Widget 都需要包含 `PrivacyInfo.xcprivacy`。当前项目声明了 `UserDefaults` 的用途，用于 App 和小组件之间保存/读取自身数据。
- App Store Connect 仍需要手动填写 App 隐私标签、内购商品、订阅说明、支持链接和审核信息。
- 后端部署后，会员页会指向生产域名的 `/privacy` 和 `/terms`，提交审核前需要确认这两个页面在公网可访问。
