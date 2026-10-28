import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createCalendarProxy,
  isValidCalendarPayload,
  normalizeCalendarLang
} from '../src/calendar-proxy.js';

const payload = {
  events: [{ id: 1, name: '映夏！归乡？千灵节！', startTime: 1782784800, endTime: 1786391940 }],
  challenges: []
};

function memoryStore(initial = {}) {
  const rows = new Map(Object.entries(initial));
  return {
    rows,
    async getCalendarCache({ game, lang }) { return rows.get(`${game}:${lang}`) ?? null; },
    async saveCalendarCache({ game, lang, payload }) {
      rows.set(`${game}:${lang}`, { payload, fetchedAt: new Date() });
    }
  };
}

function jsonResponse(status, body) {
  return { status, ok: status >= 200 && status < 300, json: async () => body };
}

function makeProxy({ store = memoryStore(), fetchImpl, clock = { t: 1_000_000 } } = {}) {
  const proxy = createCalendarProxy({
    upstreamBaseURL: 'https://upstream.example/',
    freshMs: 60_000,
    timeoutMs: 1000,
    store,
    fetchImpl,
    now: () => clock.t
  });
  return { proxy, store, clock };
}

test('normalizes lang and rejects anything that is not a locale code', () => {
  assert.equal(normalizeCalendarLang(undefined), 'zh-cn');
  assert.equal(normalizeCalendarLang('EN'), 'en');
  assert.equal(normalizeCalendarLang('zh-hant'), 'zh-hant');
  assert.equal(normalizeCalendarLang('en&x=1'), null);
  assert.equal(normalizeCalendarLang('../etc'), null);
});

test('only accepts upstream payloads that contain events or challenges', () => {
  assert.ok(isValidCalendarPayload(payload));
  assert.ok(isValidCalendarPayload({ challenges: [] }));
  assert.ok(!isValidCalendarPayload({ message: 'error' }));
  assert.ok(!isValidCalendarPayload([]));
  assert.ok(!isValidCalendarPayload(null));
});

test('fetches upstream on miss, then serves from cache while fresh', async () => {
  const urls = [];
  const { proxy, store, clock } = makeProxy({
    fetchImpl: async (url) => { urls.push(url); return jsonResponse(200, payload); }
  });

  const first = await proxy.get({ game: 'genshin', lang: 'en' });
  assert.equal(first.status, 'miss');
  assert.deepEqual(first.payload, payload);
  assert.deepEqual(urls, ['https://upstream.example/mihoyo/genshin/calendar?lang=en']);
  assert.ok(store.rows.has('genshin:en'));

  clock.t += 30_000;
  const second = await proxy.get({ game: 'genshin', lang: 'en' });
  assert.equal(second.status, 'hit');
  assert.equal(urls.length, 1);
});

test('serves stale cache when upstream fails after the cache expires', async () => {
  let upstreamUp = true;
  const { proxy, clock } = makeProxy({
    fetchImpl: async () => {
      if (!upstreamUp) throw new Error('TLS handshake failed');
      return jsonResponse(200, payload);
    }
  });

  await proxy.get({ game: 'starrail', lang: 'zh-cn' });
  upstreamUp = false;
  clock.t += 10 * 60_000;

  const result = await proxy.get({ game: 'starrail', lang: 'zh-cn' });
  assert.equal(result.status, 'stale');
  assert.deepEqual(result.payload, payload);
});

test('does not cache a malformed upstream body and keeps the previous data', async () => {
  let body = payload;
  const { proxy, store, clock } = makeProxy({
    fetchImpl: async () => jsonResponse(200, body)
  });

  await proxy.get({ game: 'genshin', lang: 'zh-cn' });
  body = { error: 'maintenance' };
  clock.t += 10 * 60_000;

  const result = await proxy.get({ game: 'genshin', lang: 'zh-cn' });
  assert.equal(result.status, 'stale');
  assert.deepEqual(store.rows.get('genshin:zh-cn').payload, payload);
});

test('falls back to the database cache after a restart when upstream is down', async () => {
  const store = memoryStore({
    'zenless:en': { payload, fetchedAt: new Date(0) }
  });
  const { proxy } = makeProxy({
    store,
    fetchImpl: async () => jsonResponse(503, {})
  });

  const result = await proxy.get({ game: 'zenless', lang: 'en' });
  assert.equal(result.status, 'stale');
  assert.deepEqual(result.payload, payload);
});

test('reports unavailable when upstream fails and nothing is cached', async () => {
  const { proxy } = makeProxy({
    fetchImpl: async () => { throw new Error('down'); }
  });

  const result = await proxy.get({ game: 'genshin', lang: 'en' });
  assert.equal(result.status, 'unavailable');
});

test('passes through upstream 404 so the app can skip unsupported games', async () => {
  const { proxy, store } = makeProxy({
    fetchImpl: async () => jsonResponse(404, {})
  });

  const result = await proxy.get({ game: 'zenless', lang: 'en' });
  assert.equal(result.status, 'not_found');
  assert.equal(store.rows.size, 0);
});

test('coalesces concurrent refreshes into one upstream request', async () => {
  let calls = 0;
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  const { proxy } = makeProxy({
    fetchImpl: async () => { calls += 1; await gate; return jsonResponse(200, payload); }
  });

  const pending = [1, 2, 3].map(() => proxy.get({ game: 'genshin', lang: 'en' }));
  await new Promise((resolve) => setImmediate(resolve));
  release();
  const results = await Promise.all(pending);

  assert.equal(calls, 1);
  assert.ok(results.every((r) => r.status === 'miss'));
});
