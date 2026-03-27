-- Greenplum: DELETE
--
-- 参考资料:
--   [1] Greenplum SQL Reference
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html
--   [2] Greenplum Admin Guide
--       https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- EXISTS 子查询
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist WHERE blacklist.email = users.email);

-- NOT EXISTS
DELETE FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- USING 子句（PostgreSQL 扩展）
DELETE FROM users
USING blacklist
WHERE users.email = blacklist.email;

-- 多表 USING
DELETE FROM users
USING orders o JOIN returns r ON o.id = r.order_id
WHERE users.id = o.user_id AND r.reason = 'fraud';

-- CTE + DELETE
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);

-- 条件删除
DELETE FROM users WHERE status = 0 AND last_login < '2023-01-01';

-- 带 RETURNING
DELETE FROM users WHERE status = 0
RETURNING id, username;

-- 删除所有行
DELETE FROM users;

-- TRUNCATE（更高效的全表删除）
TRUNCATE TABLE users;
TRUNCATE TABLE users, orders CASCADE;
TRUNCATE TABLE users RESTART IDENTITY;

-- 删除分区数据（更高效）
ALTER TABLE orders TRUNCATE PARTITION p2024_01;
ALTER TABLE orders DROP PARTITION p2024_01;

-- 大批量删除优化（AO 表）
-- AO 表 DELETE 标记行为已删除，但不立即释放空间
-- 需要 VACUUM 回收空间
VACUUM users;
VACUUM FULL users;

-- 注意：Greenplum 兼容 PostgreSQL DELETE 语法
-- 注意：大批量删除后建议 VACUUM 或 ANALYZE
-- 注意：AO 表 DELETE 不回收空间，需要 VACUUM
-- 注意：TRUNCATE 比 DELETE 快很多（不记录行级日志）
