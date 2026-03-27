-- H2: 子查询
--
-- 参考资料:
--   [1] H2 SQL Reference - Commands
--       https://h2database.com/html/commands.html
--   [2] H2 - Data Types
--       https://h2database.com/html/datatypes.html
--   [3] H2 - Functions
--       https://h2database.com/html/functions.html

-- 标量子查询
SELECT username,
    (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
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

-- FROM 子查询
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- 关联子查询
SELECT u.username,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

-- ANY / ALL / SOME
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'New York');
SELECT * FROM users WHERE age > ALL (SELECT age FROM users WHERE city = 'New York');

-- IN + 多列
SELECT * FROM users
WHERE (city, age) IN (SELECT city, MAX(age) FROM users GROUP BY city);

-- CTE 代替复杂嵌套子查询
WITH high_value_orders AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id HAVING SUM(amount) > 1000
)
SELECT u.username, h.total
FROM users u JOIN high_value_orders h ON u.id = h.user_id;

-- ============================================================
-- CSVREAD 子查询
-- ============================================================

-- 从 CSV 文件中查询
SELECT * FROM users
WHERE id IN (SELECT CAST(C1 AS INT) FROM CSVREAD('/path/to/ids.csv'));

-- 注意：H2 支持完整的 SQL 标准子查询
-- 注意：支持 ANY / ALL / SOME 运算符
-- 注意：支持多列 IN 子查询
-- 注意：CTE 可以简化复杂的嵌套子查询
