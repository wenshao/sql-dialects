-- MySQL: UPDATE
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - UPDATE
--       https://dev.mysql.com/doc/refman/8.0/en/update.html
--   [2] MySQL 8.0 Reference Manual - JOIN
--       https://dev.mysql.com/doc/refman/8.0/en/join.html

-- 基本更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- 带 LIMIT（MySQL 特有）
UPDATE users SET status = 0 WHERE status = 1 ORDER BY created_at LIMIT 100;

-- 多表更新（JOIN）
UPDATE users u
JOIN orders o ON u.id = o.user_id
SET u.status = 1
WHERE o.amount > 1000;

-- 子查询更新
-- 注意：5.7 及之前会报 ERROR 1093，不能在 UPDATE 的子查询中引用同一张表
-- 需要包一层派生表：SET age = (SELECT avg_age FROM (SELECT AVG(age) AS avg_age FROM users) t)
-- 8.0+: 部分场景已解除此限制
UPDATE users SET age = (SELECT avg_age FROM (SELECT AVG(age) AS avg_age FROM users) t) WHERE age IS NULL;

-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- 自引用更新
UPDATE users SET age = age + 1;

-- 8.0+: WITH CTE
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users u JOIN vip v ON u.id = v.user_id SET u.status = 2;
