-- Spark SQL: JOIN (Spark 2.0+)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- INNER JOIN
SELECT u.username, o.amount
FROM users u
INNER JOIN orders o ON u.id = o.user_id;

-- LEFT JOIN
SELECT u.username, o.amount
FROM users u
LEFT JOIN orders o ON u.id = o.user_id;

-- RIGHT JOIN
SELECT u.username, o.amount
FROM users u
RIGHT JOIN orders o ON u.id = o.user_id;

-- FULL OUTER JOIN
SELECT u.username, o.amount
FROM users u
FULL OUTER JOIN orders o ON u.id = o.user_id;

-- CROSS JOIN
SELECT u.username, r.role_name
FROM users u
CROSS JOIN roles r;

-- Self join
SELECT e.username AS employee, m.username AS manager
FROM users e
LEFT JOIN users m ON e.manager_id = m.id;

-- USING
SELECT * FROM users JOIN orders USING (user_id);

-- NATURAL JOIN
SELECT * FROM users NATURAL JOIN orders;

-- SEMI JOIN (LEFT SEMI JOIN: return left rows that have a match)
SELECT * FROM users u
LEFT SEMI JOIN orders o ON u.id = o.user_id;

-- ANTI JOIN (LEFT ANTI JOIN: return left rows that have no match)
SELECT * FROM users u
LEFT ANTI JOIN orders o ON u.id = o.user_id;

-- LATERAL VIEW (explode arrays/maps into rows)
SELECT u.username, tag
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag;

-- LATERAL VIEW OUTER (keep rows with empty arrays)
SELECT u.username, tag
FROM users u
LATERAL VIEW OUTER EXPLODE(u.tags) t AS tag;

-- LATERAL VIEW with posexplode (include position)
SELECT u.username, pos, tag
FROM users u
LATERAL VIEW POSEXPLODE(u.tags) t AS pos, tag;

-- LATERAL VIEW with explode on map
SELECT u.username, key, value
FROM users u
LATERAL VIEW EXPLODE(u.properties) t AS key, value;

-- Multiple LATERAL VIEWs
SELECT u.username, tag, score
FROM users u
LATERAL VIEW EXPLODE(u.tags) t1 AS tag
LATERAL VIEW EXPLODE(u.scores) t2 AS score;

-- Broadcast join hint (small table broadcast)
SELECT /*+ BROADCAST(r) */ u.username, r.role_name
FROM users u
JOIN roles r ON u.role_id = r.id;

-- Other join hints (Spark 3.0+)
SELECT /*+ SHUFFLE_MERGE(o) */ u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

SELECT /*+ SHUFFLE_HASH(o) */ u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

-- Bucket join (when both tables are bucketed on join key)
-- Automatic when tables share the same bucketing scheme

-- Skew join hint (Spark 3.0+, for data skew)
SELECT /*+ SKEW('users') */ u.username, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

-- Range join (inequality join)
SELECT e.event_name, p.period_name
FROM events e
JOIN periods p ON e.event_time >= p.start_time AND e.event_time < p.end_time;

-- TRANSFORM (run external script on data)
SELECT TRANSFORM(username, age)
    USING 'python3 process.py'
    AS (processed_name STRING, processed_age INT)
FROM users;

-- Note: LEFT SEMI JOIN and LEFT ANTI JOIN are Spark-specific SQL syntax
-- Note: LATERAL VIEW + EXPLODE replaces PostgreSQL-style UNNEST
-- Note: Join hints control physical execution strategy (broadcast, shuffle, etc.)
-- Note: LATERAL subquery join supported from Spark 3.4+ (also use LATERAL VIEW for arrays)
-- Note: No ASOF JOIN (use window functions with range conditions instead)
