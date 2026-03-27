-- Azure Synapse: 子查询
--
-- 参考资料:
--   [1] Synapse SQL Features
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features
--   [2] Synapse T-SQL Differences
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features

-- 标量子查询
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- WHERE 子查询
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);

-- EXISTS
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 比较运算符 + 子查询
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');

-- FROM 子查询
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- 关联子查询
SELECT u.username,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

-- CROSS APPLY（T-SQL 的 LATERAL 子查询）
SELECT u.username, latest.amount
FROM users u
CROSS APPLY (
    SELECT TOP 1 amount
    FROM orders WHERE user_id = u.id
    ORDER BY created_at DESC
) latest;

-- OUTER APPLY（LEFT LATERAL JOIN）
SELECT u.username, latest.amount
FROM users u
OUTER APPLY (
    SELECT TOP 1 amount
    FROM orders WHERE user_id = u.id
    ORDER BY created_at DESC
) latest;

-- 嵌套子查询
SELECT * FROM users
WHERE city IN (
    SELECT city FROM (
        SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
    ) t WHERE t.cnt > 100
);

-- WITH 子句 + 子查询
WITH top_users AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT * FROM users WHERE id IN (SELECT user_id FROM top_users WHERE total > 10000);

-- Serverless 池中的子查询
SELECT * FROM OPENROWSET(
    BULK '...path...', FORMAT = 'PARQUET'
) AS data
WHERE data.id IN (
    SELECT id FROM OPENROWSET(
        BULK '...path2...', FORMAT = 'PARQUET'
    ) AS ref WHERE ref.status = 1
);

-- 注意：CROSS APPLY / OUTER APPLY 是 T-SQL 的 LATERAL 子查询
-- 注意：NOT IN 在有 NULL 时行为不同，推荐用 NOT EXISTS
-- 注意：关联子查询可能导致数据移动（Shuffle），建议用 JOIN 改写
-- 注意：子查询嵌套层数没有硬性限制，但深嵌套影响性能
