-- ClickHouse: 事务
--
-- 参考资料:
--   [1] ClickHouse - BEGIN TRANSACTION (experimental)
--       https://clickhouse.com/docs/en/sql-reference/statements/begin-transaction
--   [2] ClickHouse - Transactional Semantics
--       https://clickhouse.com/docs/en/guides/developer/transactional

-- ============================================================
-- 1. 为什么 ClickHouse 不支持传统事务（对引擎开发者）
-- ============================================================

-- ClickHouse 的核心设计与 ACID 事务存在根本矛盾:
--
-- (a) INSERT-only + 不可变 data part:
--     每次 INSERT 创建新的 data part（一组不可变文件）。
--     事务的 ROLLBACK 需要"撤销写入"，但不可变文件无法修改。
--     → 需要额外的版本管理机制来支持回滚。
--
-- (b) 后台 merge:
--     MergeTree 引擎持续在后台合并 data part。
--     merge 是异步的、不可预测的，与事务的确定性语义冲突。
--     事务 A 读到的 part 在事务 B 提交时可能已被 merge 为新 part。
--
-- (c) 批量写入模型:
--     ClickHouse 为每秒百万行的吞吐量优化。
--     行级锁、MVCC 等事务基础设施会显著降低写入吞吐量。
--
-- (d) 分析场景不需要事务:
--     OLAP 数据通常是追加的（日志、事件、指标），不需要 UPDATE/DELETE。
--     数据一致性通过 ETL 管道保证，而非数据库事务。

-- ============================================================
-- 2. 单语句原子性（ClickHouse 的事务保证）
-- ============================================================

-- 每个 INSERT 语句是原子的（全部成功或全部失败）
INSERT INTO users VALUES
    (1, 'alice', 'alice@e.com'),
    (2, 'bob', 'bob@e.com');
-- → 这两行要么全部写入，要么全部失败

-- INSERT ... SELECT 也是原子的
INSERT INTO users_archive SELECT * FROM users WHERE age > 60;

-- 但多个 INSERT 语句之间没有原子性:
-- INSERT INTO accounts VALUES (1, -100);  -- 扣款
-- INSERT INTO accounts VALUES (2, +100);  -- 加款
-- → 如果第二个 INSERT 失败，第一个已经生效，数据不一致!

-- ============================================================
-- 3. 实验性事务支持（22.7+）
-- ============================================================

-- ClickHouse 22.7+ 引入了实验性的多语句事务:
-- SET allow_experimental_transactions = 1;
--
-- BEGIN TRANSACTION;
-- INSERT INTO users VALUES (1, 'alice', 'alice@e.com');
-- INSERT INTO orders VALUES (1, 1, 100.00);
-- COMMIT;
--
-- 如果任一 INSERT 失败 → ROLLBACK → 两个都不生效。
--
-- 限制:
--   仅支持 MergeTree 系列引擎
--   不支持分布式表（Distributed 引擎）
--   不支持 ALTER TABLE 在事务中
--   不支持 SELECT 的 snapshot isolation（有限的隔离级别）
--   生产环境不推荐使用

-- ============================================================
-- 4. ClickHouse 的"事务替代方案"
-- ============================================================

-- 4.1 分区原子替换（最常用的"事务"方案）
-- 步骤:
CREATE TABLE orders_staging AS orders;         -- 创建结构相同的临时表
INSERT INTO orders_staging SELECT * FROM external_source;  -- 写入新数据
-- 校验数据:
SELECT count(*), sum(amount) FROM orders_staging;
-- 原子替换:
ALTER TABLE orders REPLACE PARTITION '2024-01' FROM orders_staging;
-- 清理:
DROP TABLE orders_staging;
-- → 分区替换是文件系统 rename 操作，原子且瞬间完成

-- 4.2 EXCHANGE TABLES（原子表交换）
EXCHANGE TABLES users AND users_new;
-- → 两个表的全部数据原子交换（文件系统 rename）

-- 4.3 INSERT 去重（幂等性保证）
-- MergeTree 对近期 INSERT 的数据块自动去重（基于块哈希）。
-- 网络超时后重试 INSERT → 不会产生重复数据。
-- 这是 ClickHouse 对"exactly-once 语义"的支持。

-- 4.4 insert_quorum（多副本写入确认）
SET insert_quorum = 2;               -- 确保数据写入 2 个副本
SET insert_quorum_parallel = 1;      -- 并行写入副本
INSERT INTO orders VALUES (...);
-- → 只有 2 个副本都确认后才返回成功

-- ============================================================
-- 5. ReplacingMergeTree: 最终一致的去重
-- ============================================================

-- 用 INSERT 新版本 + 后台 merge 去重代替 UPDATE 事务:
INSERT INTO users VALUES (1, 'alice', 'old@e.com', 1);    -- version=1
INSERT INTO users VALUES (1, 'alice', 'new@e.com', 2);    -- version=2
-- 后台 merge → 保留 version=2 的行
-- 查询时 FINAL 强制去重:
SELECT * FROM users FINAL WHERE id = 1;
-- OPTIMIZE TABLE users FINAL;  -- 强制立即 merge

-- ============================================================
-- 6. 分布式表的一致性
-- ============================================================

-- 分布式 INSERT 不保证原子性:
-- INSERT INTO orders_distributed VALUES (...);
-- → 数据发送到多个 shard，部分 shard 可能失败。
-- 解决方案:
--   (a) insert_quorum: 确保指定数量的副本确认
--   (b) 幂等 INSERT + 重试: 利用块去重保证 exactly-once
--   (c) insert_distributed_sync = 1: 同步写入所有 shard（但降低吞吐量）

-- ============================================================
-- 7. 对比与引擎开发者启示
-- ============================================================
-- ClickHouse 的事务设计:
--   支持: 单语句原子性、分区原子替换、INSERT 去重、insert_quorum
--   不支持: 传统多语句 ACID 事务（实验性除外）
--
-- 对比:
--   MySQL/PostgreSQL: 完整 ACID 事务（MVCC + WAL）
--   SQLite:           完整 ACID 事务（WAL / journal）
--   BigQuery:         有限的多语句事务（快照隔离）
--   ClickHouse:       单语句原子性 + 分区原子替换
--
-- 对引擎开发者的启示:
--   OLAP 引擎不需要完整的 ACID 事务，但需要:
--   (1) 单语句原子性（最基本的保证）
--   (2) 批量操作的原子性（分区替换/表交换）
--   (3) 幂等写入（INSERT 去重，支持重试）
--   (4) 多副本确认（write quorum）
--   这些"轻量级事务"覆盖了 95% 的分析场景需求。
