-- Trino: 子查询
--
-- 参考资料:
--   [1] Trino - SELECT
--       https://trino.io/docs/current/sql/select.html
--   [2] Trino - SQL Statement List
--       https://trino.io/docs/current/sql.html

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

-- LATERAL 子查询（子查询可以引用外部表的列）
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

-- 行子查询
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);

-- 关联子查询
SELECT u.username,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

-- UNNEST 子查询
SELECT u.username, tag
FROM users u
CROSS JOIN UNNEST(u.tags) AS t(tag)
WHERE tag IN (SELECT tag_name FROM popular_tags);

-- 嵌套子查询
SELECT * FROM users
WHERE city IN (
    SELECT city FROM (
        SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
    ) t WHERE t.cnt > 100
);

-- 数组聚合子查询
SELECT username,
    (SELECT ARRAY_AGG(amount) FROM orders WHERE user_id = users.id) AS order_amounts
FROM users;

-- 注意：Trino 语法高度符合 SQL 标准
-- 注意：子查询性能取决于底层连接器（Hive、MySQL 等）
-- 注意：Trino 支持关联子查询的优化（自动 decorrelation）
