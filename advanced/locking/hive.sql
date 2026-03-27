-- Hive: 锁机制 (Locking)
--
-- 参考资料:
--   [1] Apache Hive Documentation - Locking
--       https://cwiki.apache.org/confluence/display/Hive/Locking
--   [2] Apache Hive Documentation - Hive Transactions (ACID)
--       https://cwiki.apache.org/confluence/display/Hive/Hive+Transactions
--   [3] Apache Hive Documentation - SHOW LOCKS
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-ShowLocks

-- ============================================================
-- Hive 锁模型概述
-- ============================================================
-- Hive 有两种锁模式:
-- 1. 传统锁管理器 (ZooKeeper-based): Hive 0.7+
-- 2. ACID 事务锁管理器 (DbTxnManager): Hive 0.13+
--
-- ACID 表（ORC + 事务表）支持行级操作
-- 非 ACID 表只有分区/表级锁

-- ============================================================
-- 启用 ACID 事务
-- ============================================================

-- 在 hive-site.xml 中配置:
-- hive.support.concurrency = true
-- hive.txn.manager = org.apache.hadoop.hive.ql.lockmgr.DbTxnManager
-- hive.compactor.initiator.on = true
-- hive.compactor.worker.threads = 4

SET hive.support.concurrency = true;
SET hive.txn.manager = org.apache.hadoop.hive.ql.lockmgr.DbTxnManager;

-- ============================================================
-- ACID 表（支持 INSERT/UPDATE/DELETE）
-- ============================================================

-- 创建事务表（必须是 ORC 格式 + bucketed）
CREATE TABLE orders (
    id     BIGINT,
    status STRING,
    amount DECIMAL(10,2)
)
CLUSTERED BY (id) INTO 8 BUCKETS
STORED AS ORC
TBLPROPERTIES ('transactional'='true');

-- Hive 3.0+: 不再要求 bucketed
CREATE TABLE orders_v2 (
    id     BIGINT,
    status STRING
)
STORED AS ORC
TBLPROPERTIES ('transactional'='true');

-- ============================================================
-- 锁类型
-- ============================================================

-- SHARED (S): SELECT 操作获取
-- EXCLUSIVE (X): INSERT/UPDATE/DELETE/DROP 获取
-- SEMI-SHARED: 用于某些 DDL 操作

-- 锁粒度: 数据库 -> 表 -> 分区

-- ============================================================
-- 查看锁
-- ============================================================

SHOW LOCKS;
SHOW LOCKS orders;
SHOW LOCKS orders PARTITION (dt='2024-01-15');
SHOW LOCKS orders EXTENDED;

-- 查看事务
SHOW TRANSACTIONS;

-- ============================================================
-- 乐观锁
-- ============================================================

-- 使用版本号列
ALTER TABLE orders ADD COLUMNS (version INT);

-- Hive 中通常使用 INSERT OVERWRITE 模式而非 UPDATE
INSERT OVERWRITE TABLE orders
SELECT
    id,
    CASE WHEN id = 100 THEN 'shipped' ELSE status END,
    amount,
    CASE WHEN id = 100 THEN version + 1 ELSE version END
FROM orders;

-- ACID 表支持 UPDATE
UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;

-- ============================================================
-- 锁超时与死锁
-- ============================================================

-- 锁获取超时
SET hive.lock.sleep.between.retries = 60;  -- 秒
SET hive.lock.numretries = 5;

-- ACID 模式下的锁超时
SET hive.txn.timeout = 300;  -- 秒

-- Hive 自动检测死锁并终止其中一个操作

-- ============================================================
-- Compaction（压缩）
-- ============================================================

-- ACID 表使用 delta 文件存储变更，需要定期压缩
-- Minor compaction: 合并 delta 文件
-- Major compaction: 合并 base 文件和 delta 文件

ALTER TABLE orders COMPACT 'minor';
ALTER TABLE orders COMPACT 'major';
ALTER TABLE orders PARTITION (dt='2024-01-15') COMPACT 'major';

-- 查看压缩状态
SHOW COMPACTIONS;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 不支持 SELECT FOR UPDATE / FOR SHARE
-- 2. ACID 功能需要 ORC 格式
-- 3. 非 ACID 表只支持 INSERT（不支持 UPDATE/DELETE）
-- 4. 锁管理依赖 Hive Metastore 数据库
-- 5. 高并发场景下建议使用分区减少锁竞争
-- 6. Hive 3.0+ 默认所有表都是 ACID 表
