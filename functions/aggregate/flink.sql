-- Flink SQL: Aggregate Functions (Flink 1.11+)
--
-- 参考资料:
--   [1] Flink SQL Documentation
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/
--   [2] Flink SQL - Built-in Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/
--   [3] Flink SQL - Data Types
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/

-- Basic aggregates
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;

-- GROUP BY
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city;

-- HAVING
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > 10;

-- GROUPING SETS
SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS ((city), (status), ());

-- ROLLUP
SELECT city, status, COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);

-- CUBE
SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE (city, status);

-- GROUPING() function
SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users
GROUP BY ROLLUP (city);

-- String aggregation
SELECT LISTAGG(username, ', ') FROM users;
SELECT LISTAGG(username) FROM users;                   -- No separator

-- Array aggregation (Flink 1.15+)
SELECT ARRAY_AGG(username) FROM users;
SELECT COLLECT(username) FROM users;                   -- Multiset aggregate

-- FIRST_VALUE / LAST_VALUE (aggregate, not window)
SELECT city, FIRST_VALUE(username) FROM users GROUP BY city;
SELECT city, LAST_VALUE(username) FROM users GROUP BY city;

-- Approximate aggregates
SELECT APPROX_COUNT_DISTINCT(city) FROM users;         -- HyperLogLog (not in all versions)

-- Statistical functions
SELECT STDDEV_POP(amount) FROM orders;                 -- Population standard deviation
SELECT STDDEV_SAMP(amount) FROM orders;                -- Sample standard deviation
SELECT VAR_POP(amount) FROM orders;                    -- Population variance
SELECT VAR_SAMP(amount) FROM orders;                   -- Sample variance

-- Conditional aggregation (FILTER clause, Flink 1.14+)
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE age < 30) AS young,
    COUNT(*) FILTER (WHERE age >= 30) AS senior,
    SUM(amount) FILTER (WHERE status = 1) AS active_total
FROM users;

-- Boolean aggregates (Flink 1.15+)
SELECT EVERY(active) FROM users;                       -- All TRUE

-- Streaming aggregates with GROUP BY windows

-- TUMBLE window aggregation
SELECT
    user_id,
    TUMBLE_START(event_time, INTERVAL '1' HOUR) AS window_start,
    TUMBLE_END(event_time, INTERVAL '1' HOUR) AS window_end,
    COUNT(*) AS event_count,
    SUM(amount) AS total_amount
FROM orders
GROUP BY user_id, TUMBLE(event_time, INTERVAL '1' HOUR);

-- HOP window aggregation
SELECT
    user_id,
    HOP_START(event_time, INTERVAL '5' MINUTE, INTERVAL '1' HOUR) AS window_start,
    COUNT(*) AS event_count
FROM events
GROUP BY user_id, HOP(event_time, INTERVAL '5' MINUTE, INTERVAL '1' HOUR);

-- SESSION window aggregation
SELECT
    user_id,
    SESSION_START(event_time, INTERVAL '30' MINUTE) AS window_start,
    SESSION_END(event_time, INTERVAL '30' MINUTE) AS window_end,
    COUNT(*) AS page_views
FROM page_events
GROUP BY user_id, SESSION(event_time, INTERVAL '30' MINUTE);

-- Window TVF aggregation (Flink 1.13+, recommended)
SELECT window_start, window_end, user_id,
    COUNT(*) AS cnt, SUM(amount) AS total
FROM TABLE(
    TUMBLE(TABLE orders, DESCRIPTOR(event_time), INTERVAL '1' HOUR)
)
GROUP BY window_start, window_end, user_id;

-- DISTINCT aggregates in streaming
-- Note: DISTINCT aggregation requires additional state in streaming mode
SELECT city, COUNT(DISTINCT username) AS unique_users
FROM users
GROUP BY city;

-- State TTL for streaming aggregates (Flink 1.17+)
SELECT /*+ STATE_TTL('users' = '1d') */
    city, COUNT(*) AS cnt
FROM users
GROUP BY city;

-- JSON aggregation (Flink 1.15+)
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT JSON_OBJECTAGG(KEY username VALUE age) FROM users;

-- Note: Streaming aggregates maintain state; use STATE_TTL to limit memory
-- Note: Group windows (TUMBLE/HOP/SESSION) are unique to streaming
-- Note: Window TVFs are recommended over older GROUP BY window syntax
-- Note: DISTINCT aggregates require more state in streaming mode
-- Note: No FILTER clause before Flink 1.14
-- Note: No HISTOGRAM or MODE functions
-- Note: No GROUP BY ALL
-- Note: LISTAGG is the string aggregation function
-- Note: COUNT DISTINCT on high-cardinality columns can be expensive in streaming
