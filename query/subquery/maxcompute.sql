-- MaxCompute: 子查询
--
-- 参考资料:
--   [1] MaxCompute SQL - Subquery
--       https://help.aliyun.com/zh/maxcompute/user-guide/subquery
--   [2] MaxCompute SQL - SELECT
--       https://help.aliyun.com/zh/maxcompute/user-guide/select

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

-- FROM 子查询（派生表，必须有别名）
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- 关联子查询
SELECT u.username,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

-- IN 子查询 + LATERAL VIEW
SELECT u.username, tag
FROM users u
LATERAL VIEW EXPLODE(u.tags) t AS tag
WHERE tag IN (SELECT tag_name FROM popular_tags);

-- 嵌套子查询
SELECT * FROM users
WHERE city IN (
    SELECT city FROM (
        SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
    ) t WHERE t.cnt > 100
);

-- SEMI JOIN（半连接优化，等价于 IN 子查询）
SELECT u.*
FROM users u
LEFT SEMI JOIN orders o ON u.id = o.user_id;

-- ANTI JOIN（反连接优化，等价于 NOT IN / NOT EXISTS）
SELECT u.*
FROM users u
LEFT ANTI JOIN orders o ON u.id = o.user_id;

-- 注意：MaxCompute 不支持 ALL / ANY / SOME 运算符
-- 注意：MaxCompute 不支持 LATERAL 子查询（标准 SQL 侧向子查询）
-- 注意：MaxCompute 子查询嵌套层数有限制
-- 注意：关联子查询在某些场景下性能较差，建议改写为 JOIN
