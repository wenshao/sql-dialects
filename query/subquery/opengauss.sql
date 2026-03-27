-- openGauss/GaussDB: 子查询
-- PostgreSQL compatible syntax.
--
-- 参考资料:
--   [1] openGauss SQL Reference
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html
--   [2] GaussDB Documentation
--       https://support.huaweicloud.com/gaussdb/index.html

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

-- LATERAL 派生表
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

-- 注意事项：
-- 子查询优化与 PostgreSQL 一致
-- openGauss 支持子查询上拉优化（自动转为 JOIN）
-- GaussDB 分布式版本中子查询会生成分布式执行计划
-- 支持 LATERAL 子查询
