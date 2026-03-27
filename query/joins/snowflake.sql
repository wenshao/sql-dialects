-- Snowflake: JOIN
--
-- 参考资料:
--   [1] Snowflake SQL Reference - JOIN
--       https://docs.snowflake.com/en/sql-reference/constructs/join
--   [2] Snowflake SQL Reference - SELECT
--       https://docs.snowflake.com/en/sql-reference/sql/select

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

-- 自连接
SELECT e.username AS employee, m.username AS manager
FROM users e
LEFT JOIN users m ON e.manager_id = m.id;

-- USING
SELECT * FROM users JOIN orders USING (user_id);

-- NATURAL JOIN
SELECT * FROM users NATURAL JOIN orders;

-- LATERAL（子查询可以引用外部表的列）
SELECT u.username, latest.amount
FROM users u
JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) latest;

-- LEFT JOIN LATERAL
SELECT u.username, latest.amount
FROM users u
LEFT JOIN LATERAL (
    SELECT amount FROM orders WHERE user_id = u.id ORDER BY created_at DESC LIMIT 1
) latest;

-- FLATTEN：展开 VARIANT / ARRAY / OBJECT 列（Snowflake 特有）
SELECT u.username, f.value AS tag
FROM users u,
LATERAL FLATTEN(input => u.tags) f;

-- FLATTEN 嵌套结构
SELECT u.username, f.value:name::STRING AS item_name
FROM users u,
LATERAL FLATTEN(input => u.order_details) f;

-- ASOF JOIN（时间序列匹配，最近时间点连接）
SELECT s.symbol, s.price, t.trade_price
FROM stock_prices s
ASOF JOIN trades t
    MATCH_CONDITION(s.timestamp >= t.timestamp)
    ON s.symbol = t.symbol;

-- 多表 JOIN
SELECT u.username, o.amount, p.product_name
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id;

-- TABLESAMPLE
SELECT u.username, o.amount
FROM users u TABLESAMPLE (10)
JOIN orders o ON u.id = o.user_id;
