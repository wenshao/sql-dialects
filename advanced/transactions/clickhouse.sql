-- ClickHouse: 事务
--
-- 参考资料:
--   [1] ClickHouse - BEGIN TRANSACTION
--       https://clickhouse.com/docs/en/sql-reference/statements/begin-transaction
--   [2] ClickHouse - Transactions
--       https://clickhouse.com/docs/en/guides/developer/transactional

-- ClickHouse 对事务的支持有限
-- 传统 ACID 事务不是 ClickHouse 的设计重点

-- ============================================================
-- 单语句原子性
-- ============================================================

-- 每个 INSERT 语句是原子的
INSERT INTO users VALUES
    (1, 'alice', 'alice@example.com'),
    (2, 'bob', 'bob@example.com');
-- 要么全部插入，要么全部失败

-- 批量 INSERT 是原子的
INSERT INTO users SELECT * FROM staging_users;

-- ============================================================
-- 实验性事务支持（22.7+）
-- ============================================================

-- ClickHouse 22.7+ 引入了实验性事务
-- 需要启用：SET allow_experimental_transactions = 1;

-- BEGIN TRANSACTION;
-- INSERT INTO users VALUES (1, 'alice', 'alice@example.com');
-- INSERT INTO orders VALUES (1, 1, 100.00, '2024-01-15');
-- COMMIT;

-- 注意：这是实验性功能，不建议在生产环境使用

-- ============================================================
-- 分区原子替换（EXCHANGE PARTITION）
-- ============================================================

-- 原子地替换分区数据
ALTER TABLE orders REPLACE PARTITION '202401' FROM orders_staging;

-- 这是 ClickHouse 中最常用的"事务性"数据更新方式
-- 1. 将新数据写入临时表
-- 2. 原子替换分区

-- ============================================================
-- Mutation（异步修改）
-- ============================================================

-- UPDATE 和 DELETE 通过 mutation 实现（异步）
ALTER TABLE users UPDATE email = 'new@example.com' WHERE id = 1;
ALTER TABLE users DELETE WHERE status = 0;

-- mutation 不是立即执行的，而是后台异步处理
-- 查看 mutation 进度
SELECT * FROM system.mutations
WHERE table = 'users' AND is_done = 0;

-- 等待 mutation 完成
-- 方式 1: 查询时用 FINAL
SELECT * FROM users FINAL WHERE id = 1;

-- 方式 2: 等待 mutation 完成
SYSTEM SYNC MUTATION ON users;

-- ============================================================
-- ReplacingMergeTree 去重（最终一致性）
-- ============================================================

-- 插入数据时允许重复主键
INSERT INTO users VALUES (1, 'alice', 'alice@example.com', now());
INSERT INTO users VALUES (1, 'alice_updated', 'new@example.com', now());

-- 后台合并会去重，保留最新版本
-- 查询时用 FINAL 获取去重后的结果
SELECT * FROM users FINAL;

-- 强制合并
OPTIMIZE TABLE users FINAL;

-- ============================================================
-- 批量数据加载模式
-- ============================================================

-- 推荐的数据更新模式：
-- 1. 写入临时表
-- 2. 校验数据
-- 3. 原子替换分区或 RENAME

-- 步骤 1: 创建临时表
CREATE TABLE users_tmp AS users;

-- 步骤 2: 写入数据
INSERT INTO users_tmp SELECT * FROM external_source;

-- 步骤 3: 校验
SELECT COUNT(*) FROM users_tmp;

-- 步骤 4: 原子替换
EXCHANGE TABLES users AND users_tmp;

-- 步骤 5: 清理
DROP TABLE users_tmp;

-- ============================================================
-- 分布式表的一致性
-- ============================================================

-- 分布式 INSERT 不保证原子性
-- 数据可能在部分副本上成功
INSERT INTO orders_dist VALUES (...);

-- insert_quorum: 确保数据写入指定数量的副本
SET insert_quorum = 2;
INSERT INTO orders VALUES (...);

-- insert_quorum_parallel: 并行写入多个副本
SET insert_quorum_parallel = 1;

-- ============================================================
-- 去重（INSERT 去重）
-- ============================================================

-- MergeTree 表自动对最近插入的数据块去重
-- 重复的 INSERT 块会被忽略（基于块哈希）
-- 这保证了 INSERT 的幂等性

-- 注意：ClickHouse 不是为 OLTP 事务设计的
-- 注意：每个 INSERT 是原子的，但不支持多语句事务（实验性除外）
-- 注意：UPDATE/DELETE 通过异步 mutation 实现，不是即时的
-- 注意：分区替换是实现原子数据更新的推荐方式
-- 注意：ReplacingMergeTree + FINAL 实现最终一致的去重
