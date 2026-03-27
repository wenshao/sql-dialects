-- StarRocks: 事务
--
-- 参考资料:
--   [1] StarRocks SQL Reference
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/
--   [2] StarRocks Documentation
--       https://docs.starrocks.io/docs/

-- StarRocks 提供有限的事务支持

-- ============================================================
-- 导入事务（Load Transaction）
-- ============================================================

-- Stream Load 是原子的
-- 每次 Stream Load 是一个事务，要么全部成功要么全部失败

-- Broker Load 是原子的
LOAD LABEL mydb.load_20240115 (
    DATA INFILE ('hdfs://path/to/data/*')
    INTO TABLE orders
    COLUMNS TERMINATED BY ','
    (id, user_id, amount, order_date)
)
WITH BROKER 'broker_name'
PROPERTIES (
    "timeout" = "3600"
);

-- 查看导入状态
SHOW LOAD WHERE LABEL = 'load_20240115';

-- 取消导入
CANCEL LOAD WHERE LABEL = 'load_20240115';

-- ============================================================
-- INSERT 事务
-- ============================================================

-- 单个 INSERT 是原子的
INSERT INTO users VALUES (1, 'alice', 'alice@example.com');

-- INSERT INTO SELECT 是原子的
INSERT INTO users_backup SELECT * FROM users WHERE status = 1;

-- ============================================================
-- 显式事务（3.0+）
-- ============================================================

-- StarRocks 3.0+ 支持有限的显式事务
BEGIN;
INSERT INTO orders VALUES (1, 100, 50.00, '2024-01-15');
INSERT INTO order_items VALUES (1, 1, 50.00);
COMMIT;

-- 回滚
BEGIN;
INSERT INTO orders VALUES (2, 200, 30.00, '2024-01-15');
ROLLBACK;

-- ============================================================
-- Primary Key 模型的原子更新
-- ============================================================

-- Primary Key 模型支持原子的 UPSERT
-- 插入相同主键的数据时自动覆盖
INSERT INTO users VALUES (1, 'alice_new', 'new@example.com');

-- 部分列更新（3.0+）
-- 通过 Stream Load 的 partial_update 功能
-- 只更新指定的列，其他列保持不变

-- ============================================================
-- DELETE
-- ============================================================

-- Primary Key 模型支持 DELETE
DELETE FROM users WHERE id = 1;

-- 条件 DELETE
DELETE FROM users WHERE status = 0 AND last_login < '2023-01-01';

-- ============================================================
-- UPDATE（Primary Key 模型，2.3+）
-- ============================================================

UPDATE users SET email = 'new@example.com' WHERE id = 1;

-- ============================================================
-- Label 机制（幂等导入）
-- ============================================================

-- 每次导入都有一个 Label
-- 相同 Label 的导入只会执行一次（幂等性保证）

-- Stream Load: 通过 HTTP Header 指定 Label
-- curl -H "label:load_20240115_001" ...

-- INSERT 也可以指定 Label
INSERT INTO users WITH LABEL 'insert_20240115_001'
VALUES (1, 'alice', 'alice@example.com');

-- 重复的 Label 会返回 LABEL_ALREADY_EXISTS 错误

-- ============================================================
-- 并发控制
-- ============================================================

-- Primary Key 模型：行级并发控制
-- 其他模型：导入级别的并发控制

-- 同一表可以并行导入多个批次
-- 不同 Tablet 可以并行写入

-- ============================================================
-- Swap 表（原子替换）
-- ============================================================

-- 原子地交换两个表的数据
ALTER TABLE users SWAP WITH users_new;

-- 常用于全量数据更新：
-- 1. 将新数据写入临时表 users_new
-- 2. 原子交换 users 和 users_new
-- 3. 删除旧数据表

-- 注意：单个导入/INSERT 是原子的
-- 注意：3.0+ 支持有限的显式事务（BEGIN/COMMIT/ROLLBACK）
-- 注意：Label 机制保证导入的幂等性
-- 注意：Primary Key 模型支持行级 UPDATE/DELETE
-- 注意：不支持 SAVEPOINT 和隔离级别设置
