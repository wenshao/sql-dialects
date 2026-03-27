-- Vertica: 子查询
--
-- 参考资料:
--   [1] Vertica SQL Reference
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm
--   [2] Vertica Functions
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm

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

-- FROM 子查询（派生表）
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- 关联子查询
SELECT u.username,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

-- LATERAL 子查询
SELECT u.username, latest.*
FROM users u
CROSS JOIN LATERAL (
    SELECT amount, order_date
    FROM orders
    WHERE user_id = u.id
    ORDER BY order_date DESC
    LIMIT 3
) latest;

-- 行子查询
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);

-- 嵌套子查询
SELECT * FROM users
WHERE city IN (
    SELECT city FROM (
        SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
    ) t WHERE t.cnt > 100
);

-- 子查询 + 聚合
SELECT * FROM users
WHERE id IN (
    SELECT user_id FROM orders
    GROUP BY user_id HAVING SUM(amount) > 10000
);

-- WITH 子句（CTE 替代复杂子查询）
WITH high_value AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
SELECT u.* FROM users u JOIN high_value h ON u.id = h.user_id;

-- 注意：Vertica 支持标准 SQL 子查询语法
-- 注意：支持 LATERAL 子查询
-- 注意：支持 ALL/ANY/SOME 运算符
-- 注意：关联子查询的性能取决于 Projection 设计
-- 注意：复杂子查询推荐改写为 CTE 或 JOIN
