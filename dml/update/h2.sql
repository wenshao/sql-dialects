-- H2: UPDATE
--
-- 参考资料:
--   [1] H2 SQL Reference - Commands
--       https://h2database.com/html/commands.html
--   [2] H2 - Data Types
--       https://h2database.com/html/datatypes.html
--   [3] H2 - Functions
--       https://h2database.com/html/functions.html

-- 基本更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- 更新所有行
UPDATE users SET status = 0;

-- 子查询更新
UPDATE users SET age = (SELECT CAST(AVG(age) AS INT) FROM users) WHERE age IS NULL;

-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- 算术运算
UPDATE orders SET amount = amount * 1.1 WHERE status = 'pending';

-- IN 子查询
UPDATE users SET status = 1
WHERE id IN (SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 1000);

-- EXISTS 子查询
UPDATE users SET status = 1
WHERE EXISTS (SELECT 1 FROM orders WHERE orders.user_id = users.id);

-- FROM 子句（H2 不支持标准 FROM，使用子查询替代）
UPDATE users SET status = 1
WHERE id IN (SELECT o.user_id FROM orders o WHERE o.amount > 1000);

-- LIMIT（限制更新行数）
UPDATE users SET status = 0 WHERE status IS NULL LIMIT 100;

-- CTE + UPDATE
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
UPDATE users SET status = 0 WHERE id IN (SELECT id FROM inactive);

-- 注意：H2 支持标准 SQL UPDATE 语法
-- 注意：支持 LIMIT 子句限制更新行数
-- 注意：不支持 FROM 子句（使用子查询替代）
-- 注意：不支持 RETURNING 子句
-- 注意：在兼容模式下可能支持其他数据库的 UPDATE 语法
