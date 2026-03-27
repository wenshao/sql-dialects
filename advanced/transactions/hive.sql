-- Hive: 事务
--
-- 参考资料:
--   [1] Apache Hive - Hive Transactions
--       https://cwiki.apache.org/confluence/display/Hive/Hive+Transactions
--   [2] Apache Hive Language Manual - DML
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DML

-- Hive 3.0+ 支持 ACID 事务（仅 ORC 格式）

-- ============================================================
-- ACID 表（事务表）
-- ============================================================

-- 创建 ACID 表
CREATE TABLE users (
    id       BIGINT,
    username STRING,
    email    STRING
)
STORED AS ORC
TBLPROPERTIES ('transactional' = 'true');

-- ACID 配置（hive-site.xml）
-- hive.support.concurrency = true
-- hive.txn.manager = org.apache.hadoop.hive.ql.lockmgr.DbTxnManager
-- hive.enforce.bucketing = true（Hive 2.0+ 此配置已移除，默认开启）

-- ============================================================
-- 事务操作
-- ============================================================

-- INSERT
INSERT INTO users VALUES (1, 'alice', 'alice@example.com');

-- UPDATE（仅 ACID 表）
UPDATE users SET email = 'new@example.com' WHERE id = 1;

-- DELETE（仅 ACID 表）
DELETE FROM users WHERE id = 1;

-- ============================================================
-- MERGE（Hive 2.2+，仅 ACID 表）
-- ============================================================

MERGE INTO users AS target
USING staging_users AS source
ON target.id = source.id
WHEN MATCHED AND source.action = 'update' THEN
    UPDATE SET username = source.username, email = source.email
WHEN MATCHED AND source.action = 'delete' THEN
    DELETE
WHEN NOT MATCHED THEN
    INSERT VALUES (source.id, source.username, source.email);

-- ============================================================
-- INSERT OVERWRITE（非事务表的原子操作）
-- ============================================================

-- INSERT OVERWRITE 是原子的
INSERT OVERWRITE TABLE orders PARTITION (dt = '20240115')
SELECT * FROM staging_orders WHERE dt = '20240115';

-- 动态分区插入
SET hive.exec.dynamic.partition.mode = nonstrict;
INSERT OVERWRITE TABLE orders PARTITION (dt)
SELECT id, user_id, amount, dt FROM staging_orders;

-- ============================================================
-- 锁机制
-- ============================================================

-- Hive 使用 DbTxnManager 管理锁
-- 共享锁（S）: SELECT
-- 排他锁（X）: INSERT, UPDATE, DELETE
-- 半共享锁（SS）: 分区级别的共享

-- 查看锁
SHOW LOCKS;
SHOW LOCKS database.table;

-- 解锁（需要 admin 权限）
UNLOCK TABLE users;

-- ============================================================
-- 压缩（Compaction）
-- ============================================================

-- ACID 表使用 delta 文件存储变更
-- 需要定期压缩合并

-- Minor Compaction（合并 delta 文件）
ALTER TABLE users COMPACT 'minor';

-- Major Compaction（重写所有数据文件 + delta 文件）
ALTER TABLE users COMPACT 'major';

-- 查看压缩状态
SHOW COMPACTIONS;

-- 自动压缩配置
-- hive.compactor.initiator.on = true
-- hive.compactor.worker.threads = 1

-- ============================================================
-- 隔离级别
-- ============================================================

-- Hive ACID 使用快照隔离（Snapshot Isolation）
-- 读取不阻塞写入，写入不阻塞读取
-- 不支持修改隔离级别

-- ============================================================
-- 事务限制
-- ============================================================

-- 只有 ORC 格式支持完整 ACID
-- 必须启用分桶（Hive 2.x），Hive 3.0+ 不要求分桶
-- 外部表不支持 ACID
-- DDL 不在事务范围内

-- 注意：只有 ORC 格式的托管表支持 ACID 事务
-- 注意：Hive 3.0+ 默认所有托管表都是 ACID 表
-- 注意：ACID 表需要定期压缩以维持性能
-- 注意：不支持 BEGIN/COMMIT/ROLLBACK 显式事务控制
-- 注意：每个 SQL 语句是一个独立的隐式事务
