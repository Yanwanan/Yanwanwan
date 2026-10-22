import pg from 'pg';

const { Pool } = pg;

export function createDatabase({ connectionString, ssl } = {}) {
  if (!connectionString) {
    return {
      isEnabled: false,
      async init() {},
      async health() { return { ok: false, configured: false }; },
      async deleteInstallData() { return { deletedUsageRows: 0 }; }
    };
  }

  const pool = new Pool({
    connectionString,
    ssl
  });

  return {
    isEnabled: true,

    async init() {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS daily_ai_usage (
          usage_date text NOT NULL,
          install_id text NOT NULL,
          tier text NOT NULL,
          used integer NOT NULL DEFAULT 0,
          updated_at timestamptz NOT NULL DEFAULT now(),
          PRIMARY KEY (usage_date, install_id)
        )
      `);

      await pool.query(`
        CREATE TABLE IF NOT EXISTS extraction_cache (
          id bigserial PRIMARY KEY,
          cache_key text NOT NULL UNIQUE,
          article_url text,
          normalized_url text,
          content_hash text NOT NULL,
          game_name text NOT NULL,
          events_json jsonb NOT NULL,
          created_at timestamptz NOT NULL DEFAULT now(),
          updated_at timestamptz NOT NULL DEFAULT now(),
          last_accessed_at timestamptz NOT NULL DEFAULT now()
        )
      `);

      await pool.query(`
        CREATE INDEX IF NOT EXISTS extraction_cache_url_idx
        ON extraction_cache (normalized_url)
      `);

      await pool.query(`
        CREATE INDEX IF NOT EXISTS extraction_cache_content_hash_idx
        ON extraction_cache (content_hash)
      `);
    },

    async health() {
      await pool.query('SELECT 1');
      return { ok: true, configured: true };
    },

    async getDailyQuota({ date, installId, tier, limit }) {
      const result = await pool.query(
        `
          SELECT used
          FROM daily_ai_usage
          WHERE usage_date = $1 AND install_id = $2
        `,
        [date, installId]
      );

      return {
        date,
        tier,
        used: result.rows[0]?.used ?? 0,
        limit
      };
    },

    async reserveDailyUsage({ date, installId, tier, limit }) {
      const result = await pool.query(
        `
          INSERT INTO daily_ai_usage (usage_date, install_id, tier, used, updated_at)
          VALUES ($1, $2, $3, 1, now())
          ON CONFLICT (usage_date, install_id)
          DO UPDATE SET
            used = daily_ai_usage.used + 1,
            tier = EXCLUDED.tier,
            updated_at = now()
          WHERE daily_ai_usage.used < $4
          RETURNING used
        `,
        [date, installId, tier, limit]
      );

      if (result.rows.length === 0) {
        return null;
      }

      return {
        date,
        tier,
        used: result.rows[0].used,
        limit
      };
    },

    async refundDailyUsage({ date, installId, tier, limit }) {
      const result = await pool.query(
        `
          UPDATE daily_ai_usage
          SET used = GREATEST(used - 1, 0),
              tier = $3,
              updated_at = now()
          WHERE usage_date = $1 AND install_id = $2
          RETURNING used
        `,
        [date, installId, tier]
      );

      return {
        date,
        tier,
        used: result.rows[0]?.used ?? 0,
        limit
      };
    },

    async getCachedExtraction({ cacheKey }) {
      const result = await pool.query(
        `
          UPDATE extraction_cache
          SET last_accessed_at = now()
          WHERE cache_key = $1
          RETURNING
            article_url,
            normalized_url,
            content_hash,
            game_name,
            events_json,
            updated_at
        `,
        [cacheKey]
      );

      const row = result.rows[0];
      if (!row) return null;

      return {
        articleUrl: row.article_url,
        normalizedUrl: row.normalized_url,
        contentHash: row.content_hash,
        gameName: row.game_name,
        events: Array.isArray(row.events_json) ? row.events_json : [],
        updatedAt: row.updated_at
      };
    },

    async saveExtraction({ cacheKey, articleUrl, normalizedUrl, contentHash, gameName, events }) {
      await pool.query(
        `
          INSERT INTO extraction_cache (
            cache_key,
            article_url,
            normalized_url,
            content_hash,
            game_name,
            events_json,
            created_at,
            updated_at,
            last_accessed_at
          )
          VALUES ($1, $2, $3, $4, $5, $6::jsonb, now(), now(), now())
          ON CONFLICT (cache_key)
          DO UPDATE SET
            article_url = EXCLUDED.article_url,
            normalized_url = EXCLUDED.normalized_url,
            content_hash = EXCLUDED.content_hash,
            game_name = EXCLUDED.game_name,
            events_json = EXCLUDED.events_json,
            updated_at = now(),
            last_accessed_at = now()
        `,
        [
          cacheKey,
          articleUrl,
          normalizedUrl,
          contentHash,
          gameName,
          JSON.stringify(events)
        ]
      );
    },

    async deleteInstallData({ installId }) {
      const result = await pool.query(
        `
          DELETE FROM daily_ai_usage
          WHERE install_id = $1
        `,
        [installId]
      );
      return { deletedUsageRows: result.rowCount ?? 0 };
    }
  };
}
