-- ClickHouse: 子查询
--
-- 参考资料:
--   [1] ClickHouse SQL Reference - SELECT
--       https://clickhouse.com/docs/en/sql-reference/statements/select
--   [2] ClickHouse SQL Reference - IN Operators
--       https://clickhouse.com/docs/en/sql-reference/statements/select/in

-- 标量子查询
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

-- WHERE 子查询
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);

-- EXISTS
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 比较运算符 + 子查询
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);

-- FROM 子查询
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- IN + 子查询（支持元组）
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);

-- GLOBAL IN（分布式环境中，子查询只在发起节点执行一次，广播结果）
SELECT * FROM users WHERE id GLOBAL IN (SELECT user_id FROM orders WHERE amount > 100);

-- GLOBAL NOT IN
SELECT * FROM users WHERE id GLOBAL NOT IN (SELECT user_id FROM blacklist);

-- 关联子查询
SELECT u.username,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

-- 子查询 + ARRAY JOIN
SELECT u.username, tag
FROM (
    SELECT * FROM users WHERE status = 1
) u
ARRAY JOIN u.tags AS tag;

-- 子查询结果作为数组
SELECT username,
    (SELECT groupArray(amount) FROM orders WHERE user_id = users.id) AS order_amounts
FROM users;

-- 嵌套子查询
SELECT * FROM users
WHERE city IN (
    SELECT city FROM (
        SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
    ) WHERE cnt > 100
);

-- 注意：ClickHouse 支持 ANY 但不支持 ALL / SOME 子查询运算符
-- 注意：ClickHouse 不支持 LATERAL 子查询
-- 注意：分布式表使用 IN 子查询时建议使用 GLOBAL IN 避免数据倾斜
