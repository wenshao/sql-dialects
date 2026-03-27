-- Trino (formerly PrestoSQL): 事务
--
-- 参考资料:
--   [1] Trino - START TRANSACTION
--       https://trino.io/docs/current/sql/start-transaction.html
--   [2] Trino - Connectors
--       https://trino.io/docs/current/connector.html

-- Trino 的事务支持取决于底层 Connector

-- ============================================================
-- 自动提交（默认行为）
-- ============================================================

-- 每个 SQL 语句是一个独立事务
-- 自动提交，不需要显式 COMMIT

INSERT INTO users VALUES (1, 'alice', 'alice@example.com');
-- 立即提交

UPDATE users SET email = 'new@example.com' WHERE id = 1;
-- 立即提交（仅部分 Connector 支持 UPDATE）

-- ============================================================
-- 不支持显式事务控制
-- ============================================================

-- Trino 支持有限的显式事务控制（需要 Connector 支持）：
-- START TRANSACTION（支持，但每个事务仅限单条语句）
-- COMMIT（支持）
-- ROLLBACK（支持）
-- 不支持 BEGIN（使用 START TRANSACTION 替代）
-- 不支持 SAVEPOINT
-- 不支持多语句事务（每个事务只能包含一条数据修改语句）

-- 在实践中大多数客户端使用自动提交模式

-- ============================================================
-- Connector 特有的事务行为
-- ============================================================

-- Hive Connector:
-- INSERT 是原子的（写入临时目录，完成后移动到目标目录）
-- ACID 表支持 UPDATE/DELETE，非 ACID 表不支持
-- INSERT OVERWRITE 是原子的

-- Iceberg Connector:
-- 支持 INSERT、UPDATE、DELETE、MERGE
-- 每个操作创建新的快照（原子的）
-- 乐观并发控制（冲突时重试）
INSERT INTO iceberg.mydb.orders VALUES (1, 100, '2024-01-15');
DELETE FROM iceberg.mydb.orders WHERE id = 1;
UPDATE iceberg.mydb.orders SET amount = 200 WHERE id = 1;

MERGE INTO iceberg.mydb.users AS target
USING staging AS source ON target.id = source.id
WHEN MATCHED THEN UPDATE SET email = source.email
WHEN NOT MATCHED THEN INSERT VALUES (source.id, source.username, source.email);

-- Delta Lake Connector:
-- 支持 INSERT、UPDATE、DELETE、MERGE
-- 使用 Delta 事务日志保证 ACID

-- PostgreSQL / MySQL Connector:
-- 写入时底层数据库的事务机制生效
-- 但 Trino 不能控制事务边界（不能 BEGIN/COMMIT）

-- ============================================================
-- 一致性保证
-- ============================================================

-- READ COMMITTED: Trino 查询看到查询开始时的一致数据
-- 但不同语句之间可能看到不同的数据状态

-- Iceberg 的时间旅行
SELECT * FROM iceberg.mydb.orders
FOR TIMESTAMP AS OF TIMESTAMP '2024-01-15 10:00:00';

SELECT * FROM iceberg.mydb.orders
FOR VERSION AS OF 12345;  -- 快照 ID

-- ============================================================
-- INSERT 的原子性
-- ============================================================

-- CREATE TABLE AS SELECT（原子操作）
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > TIMESTAMP '2024-01-01 00:00:00';

-- INSERT INTO ... SELECT（原子操作）
INSERT INTO users_archive
SELECT * FROM users WHERE status = 0;

-- ============================================================
-- 故障恢复
-- ============================================================

-- Iceberg: 失败的写入不会影响数据（快照机制）
-- Hive: 失败的写入可能留下临时文件（需要清理）
-- Delta: Delta 日志保证原子性

-- Iceberg 清理
ALTER TABLE iceberg.mydb.orders EXECUTE expire_snapshots(retention_threshold => '7d');
ALTER TABLE iceberg.mydb.orders EXECUTE remove_orphan_files(retention_threshold => '7d');

-- 注意：Trino 支持 START TRANSACTION/COMMIT/ROLLBACK 但每个事务仅限单条语句
-- 注意：实践中每个 SQL 语句通常作为独立的自动提交事务执行
-- 注意：事务能力完全取决于底层 Connector
-- 注意：Iceberg 和 Delta 提供最好的 ACID 保证
-- 注意：Hive Connector 的 INSERT 是原子的，ACID 表支持 UPDATE/DELETE
