-- TDSQL: DELETE
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- 带 LIMIT / ORDER BY
DELETE FROM users WHERE status = 0 ORDER BY created_at LIMIT 100;

-- 多表删除（JOIN）
DELETE u FROM users u
JOIN blacklist b ON u.email = b.email;

-- 同时从多个表删除
DELETE u, o FROM users u
JOIN orders o ON u.id = o.user_id
WHERE u.status = 0;

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- 删除所有行
DELETE FROM users;
TRUNCATE TABLE users;

-- IGNORE
DELETE IGNORE FROM users WHERE id = 1;

-- WITH CTE
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE u FROM users u JOIN inactive i ON u.id = i.id;

-- 注意事项：
-- DELETE 带 shardkey 条件时只路由到对应分片
-- 不带 shardkey 条件的 DELETE 会扫描所有分片
-- TRUNCATE 会清空所有分片上的数据
-- 广播表的 DELETE 会同步到所有节点
-- 跨分片 DELETE 使用分布式事务确保一致性
