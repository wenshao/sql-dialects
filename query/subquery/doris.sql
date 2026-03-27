-- Apache Doris: 子查询
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

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

-- FROM 子查询（派生表，必须有别名）
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- 关联子查询
SELECT u.username,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

-- 行子查询
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);

-- 嵌套子查询
SELECT * FROM users
WHERE city IN (
    SELECT city FROM (
        SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
    ) t WHERE t.cnt > 100
);

-- SEMI JOIN（等价于 IN 子查询，优化器自动选择）
SELECT u.*
FROM users u
LEFT SEMI JOIN orders o ON u.id = o.user_id;

-- ANTI JOIN（等价于 NOT IN / NOT EXISTS）
SELECT u.*
FROM users u
LEFT ANTI JOIN orders o ON u.id = o.user_id;

-- 子查询 + 聚合
SELECT * FROM users
WHERE id IN (
    SELECT user_id FROM orders
    GROUP BY user_id HAVING SUM(amount) > 10000
);

-- 注意：Doris 兼容 MySQL 协议，支持标准子查询语法
-- 注意：优化器会自动将 IN/EXISTS 子查询改写为 SEMI JOIN
-- 注意：不支持 LATERAL 子查询
