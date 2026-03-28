-- Apache Doris: 子查询
--
-- 参考资料:
--   [1] Doris Documentation - Subquery
--       https://doris.apache.org/docs/sql-manual/sql-statements/

-- 标量子查询
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS cnt FROM users;

-- IN / NOT IN
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);

-- EXISTS / NOT EXISTS
SELECT * FROM users u WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
SELECT * FROM users u WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 比较运算符
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');

-- 派生表
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

-- SEMI / ANTI JOIN (优化器自动改写)
SELECT u.* FROM users u LEFT SEMI JOIN orders o ON u.id = o.user_id;
SELECT u.* FROM users u LEFT ANTI JOIN orders o ON u.id = o.user_id;

-- 对引擎开发者的启示:
--   子查询去关联(Decorrelation)是 CBO 的核心能力:
--     关联子查询 → 改写为 JOIN → CBO 选择最优 JOIN 策略
--     StarRocks 的 CBO 在子查询去关联方面比 Doris 更成熟。
