-- MaxCompute (ODPS): 事务
--
-- 参考资料:
--   [1] MaxCompute SQL Overview
--       https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview
--   [2] MaxCompute Documentation
--       https://help.aliyun.com/zh/maxcompute/

-- MaxCompute 的事务支持有限，仅事务表支持 ACID

-- ============================================================
-- 非事务表（传统模式）
-- ============================================================

-- 非事务表不支持 UPDATE / DELETE
-- 写入方式是 INSERT INTO / INSERT OVERWRITE

-- INSERT INTO 追加数据
INSERT INTO orders PARTITION (dt = '20240115')
VALUES (1, 100, 50.00, GETDATE());

-- INSERT OVERWRITE 覆盖写入（原子操作）
INSERT OVERWRITE TABLE orders PARTITION (dt = '20240115')
SELECT * FROM staging_orders WHERE dt = '20240115';

-- INSERT OVERWRITE 是原子的：
-- 成功则全部替换，失败则保留原数据

-- ============================================================
-- 事务表（ACID 表）
-- ============================================================

-- 创建事务表
CREATE TABLE users (
    id       BIGINT,
    username STRING,
    email    STRING,
    PRIMARY KEY (id)
) TBLPROPERTIES ('transactional' = 'true');

-- 事务表支持 UPDATE 和 DELETE
UPDATE users SET email = 'new@example.com' WHERE id = 1;
DELETE FROM users WHERE id = 1;

-- ============================================================
-- 事务表的 ACID 特性
-- ============================================================

-- 原子性（Atomicity）: 单个 SQL 语句是原子的
-- 一致性（Consistency）: 通过主键保证数据一致性
-- 隔离性（Isolation）: 快照隔离
-- 持久性（Durability）: 数据持久化到分布式存储

-- ============================================================
-- MERGE（事务表的原子 UPSERT）
-- ============================================================

MERGE INTO users AS target
USING staging_users AS source
ON target.id = source.id
WHEN MATCHED THEN
    UPDATE SET username = source.username, email = source.email
WHEN NOT MATCHED THEN
    INSERT VALUES (source.id, source.username, source.email);

-- ============================================================
-- 并发控制
-- ============================================================

-- MaxCompute 使用乐观并发控制
-- 同一个分区的并发写入会排队
-- 不同分区可以并行写入

-- 分区级别锁：
-- 同一个分区同时只能有一个写入操作
-- 多个读取可以并行

-- ============================================================
-- 幂等写入
-- ============================================================

-- INSERT OVERWRITE 天然幂等
-- 重复执行结果相同
INSERT OVERWRITE TABLE daily_summary PARTITION (dt = '20240115')
SELECT user_id, COUNT(*), SUM(amount)
FROM orders WHERE dt = '20240115'
GROUP BY user_id;

-- ============================================================
-- 数据质量保证（替代事务验证）
-- ============================================================

-- 在 ETL 管道中使用数据质量检查
-- 步骤 1: 写入临时表
INSERT OVERWRITE TABLE staging_data PARTITION (dt = '20240115')
SELECT * FROM raw_data;

-- 步骤 2: 验证数据
SELECT COUNT(*) FROM staging_data WHERE dt = '20240115' AND amount < 0;
-- 如果返回 0，则数据质量合格

-- 步骤 3: 写入目标表
INSERT OVERWRITE TABLE final_data PARTITION (dt = '20240115')
SELECT * FROM staging_data WHERE dt = '20240115';

-- 注意：非事务表不支持 UPDATE/DELETE
-- 注意：INSERT OVERWRITE 是原子操作（最重要的事务保证）
-- 注意：事务表支持行级 UPDATE/DELETE 但性能较低
-- 注意：分区级别的并发控制（同分区串行，不同分区并行）
-- 注意：MaxCompute 是批处理引擎，不适合高并发 OLTP 事务
