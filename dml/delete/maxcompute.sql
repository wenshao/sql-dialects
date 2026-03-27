-- MaxCompute (ODPS): DELETE
--
-- 参考资料:
--   [1] MaxCompute SQL - DELETE
--       https://help.aliyun.com/zh/maxcompute/user-guide/delete-1
--   [2] MaxCompute SQL Overview
--       https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview

-- 注意: MaxCompute 普通表不支持 DELETE，必须使用 事务表（Transactional Table）
-- 创建事务表: CREATE TABLE t (...) TBLPROPERTIES ('transactional' = 'true');
-- 非事务表只能通过 INSERT OVERWRITE 实现删除效果

-- === 事务表 DELETE ===

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- EXISTS 子查询
DELETE FROM users
WHERE EXISTS (SELECT 1 FROM blacklist WHERE blacklist.email = users.email);

-- 条件删除
DELETE FROM users WHERE status = 0 AND last_login < '2023-01-01';

-- 删除所有行
DELETE FROM users;

-- === 非事务表替代方案: INSERT OVERWRITE ===

-- 用 INSERT OVERWRITE 模拟删除（保留不删除的行）
INSERT OVERWRITE TABLE users
SELECT * FROM users WHERE username != 'alice';

-- 用 INSERT OVERWRITE 模拟分区级删除
INSERT OVERWRITE TABLE events PARTITION (dt = '2024-01-15')
SELECT user_id, event_name, event_time
FROM events
WHERE dt = '2024-01-15' AND event_name != 'spam';

-- 删除整个分区（非事务表也支持）
ALTER TABLE events DROP PARTITION (dt = '2024-01-15');

-- 删除多个分区
ALTER TABLE events DROP PARTITION (dt >= '2024-01-01' AND dt <= '2024-01-31');

-- TRUNCATE（清空表数据）
TRUNCATE TABLE users;
