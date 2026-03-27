-- PostgreSQL: UPDATE
--
-- 参考资料:
--   [1] PostgreSQL Documentation - UPDATE
--       https://www.postgresql.org/docs/current/sql-update.html

-- 基本更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- 多列用元组赋值
UPDATE users SET (email, age) = ('new@example.com', 26) WHERE username = 'alice';

-- FROM 子句（多表更新，PostgreSQL 特有语法）
UPDATE users SET status = 1
FROM orders
WHERE users.id = orders.user_id AND orders.amount > 1000;

-- 子查询更新
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- RETURNING
UPDATE users SET age = 26 WHERE username = 'alice' RETURNING id, username, age;

-- CTE + UPDATE
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users SET status = 2
FROM vip
WHERE users.id = vip.user_id;

-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- 从子查询批量更新
UPDATE users u SET
    email = t.new_email
FROM (VALUES ('alice', 'alice_new@example.com'), ('bob', 'bob_new@example.com'))
    AS t(username, new_email)
WHERE u.username = t.username;
