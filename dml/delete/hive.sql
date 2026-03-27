-- Hive: DELETE
--
-- 参考资料:
--   [1] Apache Hive Language Manual - DML
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DML
--   [2] Apache Hive - Hive Transactions
--       https://cwiki.apache.org/confluence/display/Hive/Hive+Transactions

-- 注意: Hive DELETE 仅支持 ACID 事务表（0.14+）
-- 需要配置:
--   SET hive.support.concurrency = true;
--   SET hive.txn.manager = org.apache.hadoop.hive.ql.lockmgr.DbTxnManager;
-- 表必须为 ORC 格式且开启事务:
--   CREATE TABLE t (...) STORED AS ORC TBLPROPERTIES ('transactional' = 'true');

-- === ACID 事务表 DELETE ===

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- 条件删除
DELETE FROM users WHERE status = 0 AND last_login < '2023-01-01';

-- 删除所有行
DELETE FROM users;

-- 限制: 不支持多表 JOIN 删除
-- 限制: 不支持 ORDER BY / LIMIT

-- === 非 ACID 表替代方案 ===

-- 用 INSERT OVERWRITE 模拟删除（保留不删除的行）
INSERT OVERWRITE TABLE users
SELECT * FROM users WHERE username != 'alice';

-- 用 INSERT OVERWRITE 模拟分区级删除
INSERT OVERWRITE TABLE events PARTITION (dt = '2024-01-15')
SELECT user_id, event_name, event_time
FROM events
WHERE dt = '2024-01-15' AND event_name != 'spam';

-- 删除整个分区（所有表都支持，最常用的删除方式）
ALTER TABLE events DROP PARTITION (dt = '2024-01-15');

-- 删除多个分区
ALTER TABLE events DROP IF EXISTS PARTITION (dt >= '2024-01-01', dt <= '2024-01-31');

-- TRUNCATE（清空表/分区数据）
TRUNCATE TABLE users;
TRUNCATE TABLE events PARTITION (dt = '2024-01-15');
