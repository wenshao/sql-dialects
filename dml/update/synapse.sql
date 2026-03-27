-- Azure Synapse: UPDATE
--
-- 参考资料:
--   [1] Synapse SQL Features
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features
--   [2] Synapse T-SQL Differences
--       https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features

-- 基本更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = N'new@example.com', age = 26 WHERE username = 'alice';

-- 子查询更新
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- FROM 子句（多表更新，T-SQL 风格）
UPDATE u
SET u.status = 1
FROM users u
INNER JOIN orders o ON u.id = o.user_id
WHERE o.amount > 1000;

-- 多表 JOIN 更新
UPDATE u
SET u.status = 1
FROM users u
INNER JOIN orders o ON u.id = o.user_id
INNER JOIN payments p ON o.id = p.order_id
WHERE p.amount > 1000;

-- CTE + UPDATE
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE u
SET u.status = 2
FROM users u
INNER JOIN vip v ON u.id = v.user_id;

-- CASE 表达式
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- 自引用更新
UPDATE users SET age = age + 1;

-- 基于子查询的批量更新
UPDATE u
SET u.email = t.new_email
FROM users u
INNER JOIN (
    SELECT 'alice' AS username, N'alice_new@example.com' AS new_email
    UNION ALL
    SELECT 'bob', N'bob_new@example.com'
) t ON u.username = t.username;

-- CTAS 模式更新（大批量更新推荐）
CREATE TABLE users_updated
WITH (DISTRIBUTION = HASH(id), CLUSTERED COLUMNSTORE INDEX)
AS
SELECT
    id, username,
    CASE WHEN age < 18 THEN 0 WHEN age >= 65 THEN 2 ELSE 1 END AS status,
    email, age, created_at
FROM users;

RENAME OBJECT users TO users_old;
RENAME OBJECT users_updated TO users;
DROP TABLE users_old;

-- 注意：大批量 UPDATE 建议用 CTAS + RENAME 模式（更高效）
-- 注意：UPDATE 在列存储表上会创建 delete bitmap + 新行
-- 注意：频繁 UPDATE 后需要 ALTER INDEX REBUILD 优化列存储
-- 注意：Synapse 中 UPDATE 性能不如 CTAS 重建
-- 注意：Serverless 池不支持 UPDATE（只读外部数据）
-- 注意：不支持 UPDATE ... OUTPUT（SQL Server 的功能）
