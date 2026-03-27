-- CockroachDB: Date/Time Types (v23.1+)
--
-- 参考资料:
--   [1] CockroachDB - SQL Statements
--       https://www.cockroachlabs.com/docs/stable/sql-statements
--   [2] CockroachDB - Functions and Operators
--       https://www.cockroachlabs.com/docs/stable/functions-and-operators
--   [3] CockroachDB - Data Types
--       https://www.cockroachlabs.com/docs/stable/data-types

-- DATE: date only, 0001-01-01 ~ 9999-12-31
-- TIME: time without time zone
-- TIMETZ: time with time zone
-- TIMESTAMP: timestamp without time zone
-- TIMESTAMPTZ: timestamp with time zone (recommended)
-- INTERVAL: time duration

CREATE TABLE events (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_date   DATE,
    event_time   TIME,
    event_timetz TIMETZ,
    local_dt     TIMESTAMP,                    -- without time zone
    created_at   TIMESTAMPTZ DEFAULT now()     -- with time zone (recommended)
);

-- TIMESTAMPTZ is recommended (stores UTC, converts on display)
-- TIMESTAMP stores without time zone information

-- INTERVAL
SELECT INTERVAL '1 year 2 months 3 days 4 hours';
SELECT now() + INTERVAL '7 days';
SELECT now() - INTERVAL '2 hours 30 minutes';

-- Current date/time (same as PostgreSQL)
SELECT NOW();                                  -- TIMESTAMPTZ
SELECT CURRENT_TIMESTAMP;                      -- TIMESTAMPTZ (transaction time)
SELECT CLOCK_TIMESTAMP();                      -- actual execution time
SELECT CURRENT_DATE;                           -- DATE
SELECT CURRENT_TIME;                           -- TIMETZ
SELECT LOCALTIME;                              -- TIME
SELECT LOCALTIMESTAMP;                         -- TIMESTAMP

-- Date construction
SELECT MAKE_DATE(2024, 1, 15);
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);
SELECT MAKE_TIMESTAMPTZ(2024, 1, 15, 10, 30, 0, 'Asia/Shanghai');
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');

-- Date arithmetic
SELECT '2024-01-15'::DATE + INTERVAL '1 month';
SELECT '2024-01-15'::DATE + 7;                 -- add 7 days
SELECT NOW() - INTERVAL '2 hours';
SELECT '2024-12-31'::DATE - '2024-01-01'::DATE; -- 365 (integer days)
SELECT AGE('2024-12-31', '2024-01-01');         -- interval

-- EXTRACT
SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(MONTH FROM NOW());
SELECT EXTRACT(DAY FROM NOW());
SELECT EXTRACT(HOUR FROM NOW());
SELECT EXTRACT(DOW FROM NOW());                -- 0=Sunday
SELECT EXTRACT(EPOCH FROM NOW());              -- Unix timestamp
SELECT DATE_PART('year', NOW());               -- same as EXTRACT

-- Truncation
SELECT DATE_TRUNC('month', NOW());
SELECT DATE_TRUNC('year', NOW());
SELECT DATE_TRUNC('hour', NOW());

-- Formatting
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(NOW(), 'Day, Month DD, YYYY');

-- Time zone conversion
SELECT NOW() AT TIME ZONE 'Asia/Shanghai';
SELECT NOW() AT TIME ZONE 'UTC';

-- AS OF SYSTEM TIME (CockroachDB-specific: historical queries)
SELECT * FROM users AS OF SYSTEM TIME '-10s';  -- 10 seconds ago
SELECT * FROM users AS OF SYSTEM TIME '2024-01-15 10:00:00';
SELECT * FROM users AS OF SYSTEM TIME INTERVAL '-1h'; -- 1 hour ago

-- Follower reads (lower latency with stale data)
SELECT * FROM users AS OF SYSTEM TIME follower_read_timestamp();

-- Generate series
SELECT generate_series('2024-01-01'::DATE, '2024-01-31'::DATE, '1 day'::INTERVAL);

-- Note: Same date/time types as PostgreSQL
-- Note: TIMESTAMPTZ recommended over TIMESTAMP
-- Note: AS OF SYSTEM TIME for historical queries and follower reads
-- Note: follower_read_timestamp() for automatic staleness-based reads
-- Note: All time zones from IANA tz database supported
