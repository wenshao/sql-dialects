-- KingbaseES (人大金仓): UPDATE
-- PostgreSQL compatible syntax.
--
-- 参考资料:
--   [1] KingbaseES SQL Reference
--       https://help.kingbase.com.cn/v8/index.html
--   [2] KingbaseES Documentation
--       https://help.kingbase.com.cn/v8/index.html

-- 基本更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- FROM 子句（PostgreSQL 风格的多表更新）
UPDATE users SET status = 1
FROM orders
WHERE users.id = orders.user_id AND orders.amount > 1000;

-- 子查询更新
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- 自引用更新
UPDATE users SET age = age + 1;

-- RETURNING
UPDATE users SET age = 26 WHERE username = 'alice' RETURNING id, username, age;

-- WITH CTE
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users SET status = 2 WHERE id IN (SELECT user_id FROM vip);

-- 注意事项：
-- 语法与 PostgreSQL 完全兼容
-- 使用 FROM 子句进行多表更新
-- 支持 RETURNING 子句
-- 支持 CTE + UPDATE
