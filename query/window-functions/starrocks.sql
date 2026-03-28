-- StarRocks: 窗口函数
--
-- 参考资料:
--   [1] StarRocks Documentation - Window Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/

-- (与 Doris 完全兼容的窗口函数)
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age) AS rn,
    RANK() OVER (ORDER BY age) AS rnk,
    DENSE_RANK() OVER (ORDER BY age) AS dense_rnk
FROM users;

SELECT username, city, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rank FROM users;

SELECT username, LAG(age) OVER (ORDER BY id) AS prev, LEAD(age) OVER (ORDER BY id) AS next FROM users;
SELECT username, FIRST_VALUE(age) OVER (PARTITION BY city ORDER BY age) FROM users;
SELECT username, NTILE(4) OVER (ORDER BY age) AS quartile FROM users;
SELECT username, PERCENT_RANK() OVER (ORDER BY age) AS pct FROM users;

SELECT username, ROW_NUMBER() OVER w AS rn FROM users WINDOW w AS (ORDER BY age);

SELECT username,
    SUM(age) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling
FROM users;

-- ============================================================
-- QUALIFY (3.2+，StarRocks 独有)
-- ============================================================
-- 在窗口函数结果上直接过滤，无需子查询:
-- SELECT username, city, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
-- FROM users QUALIFY rn <= 3;
--
-- 等价于(Doris 写法):
-- SELECT * FROM (SELECT ..., ROW_NUMBER() OVER (...) AS rn FROM users) t WHERE rn <= 3;
--
-- QUALIFY 来自 Teradata，现被 BigQuery/Snowflake/DuckDB 采纳。
-- 这是 StarRocks 相比 Doris 的语法优势之一。
