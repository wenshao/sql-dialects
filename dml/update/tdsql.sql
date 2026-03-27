-- TDSQL: UPDATE
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

-- 基本更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- 带 LIMIT
UPDATE users SET status = 0 WHERE status = 1 ORDER BY created_at LIMIT 100;

-- 多表更新（JOIN）
UPDATE users u
JOIN orders o ON u.id = o.user_id
SET u.status = 1
WHERE o.amount > 1000;

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

-- WITH CTE
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users u JOIN vip v ON u.id = v.user_id SET u.status = 2;

-- 注意事项：
-- 不能修改 shardkey 列的值
-- 更新带 shardkey 条件时只路由到对应分片
-- 不带 shardkey 条件的更新会扫描所有分片（性能差）
-- 多表 JOIN UPDATE 在跨分片时使用分布式事务
-- 广播表的更新会同步到所有节点
