-- Trino: 锁机制 (Locking)
--
-- 参考资料:
--   [1] Trino Documentation - Connectors
--       https://trino.io/docs/current/connector.html
--   [2] Trino Documentation - Delta Lake Connector
--       https://trino.io/docs/current/connector/delta-lake.html
--   [3] Trino Documentation - Hive Connector
--       https://trino.io/docs/current/connector/hive.html

-- ============================================================
-- Trino 并发模型概述
-- ============================================================
-- Trino 是分布式查询引擎，本身没有存储层:
-- 1. 不支持传统的锁机制
-- 2. 并发控制取决于底层连接器（connector）
-- 3. 不支持 SELECT FOR UPDATE / FOR SHARE
-- 4. 不支持多语句事务
-- 5. 每个语句是独立的自动提交事务

-- ============================================================
-- 连接器级别的并发控制
-- ============================================================

-- Hive 连接器: 使用 Hive Metastore 的锁管理
-- Delta Lake 连接器: 使用 Delta Lake 的乐观并发控制
-- Iceberg 连接器: 使用 Iceberg 的乐观并发控制
-- PostgreSQL/MySQL 连接器: 使用底层数据库的锁机制

-- ============================================================
-- Delta Lake 连接器（乐观并发）
-- ============================================================

-- Delta 表的写入使用乐观并发控制
INSERT INTO delta.myschema.orders VALUES (1, 'new', 100.00);

UPDATE delta.myschema.orders SET status = 'shipped'
WHERE id = 1;

DELETE FROM delta.myschema.orders WHERE status = 'cancelled';

-- MERGE
MERGE INTO delta.myschema.orders t
USING delta.myschema.updates s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET status = s.status
WHEN NOT MATCHED THEN INSERT (id, status, amount) VALUES (s.id, s.status, s.amount);

-- ============================================================
-- Iceberg 连接器（乐观并发）
-- ============================================================

-- Iceberg 表也使用乐观并发控制
INSERT INTO iceberg.myschema.orders VALUES (1, 'new', 100.00);

-- Iceberg 支持快照隔离
-- 并发写入相同表可能导致 CommitFailedException

-- Time Travel
SELECT * FROM iceberg.myschema.orders FOR VERSION AS OF 123456789;
SELECT * FROM iceberg.myschema.orders FOR TIMESTAMP AS OF TIMESTAMP '2024-01-15 10:00:00';

-- ============================================================
-- Hive 连接器
-- ============================================================

-- 对于 ACID 表，锁由 Hive Metastore 管理
-- 对于非 ACID 表，Trino 不获取锁

INSERT INTO hive.myschema.orders VALUES (1, 'new', 100.00);

-- ============================================================
-- 查询管理
-- ============================================================

-- 查看运行中的查询
-- 通过 Trino Web UI 或 JMX

-- 终止查询
CALL system.runtime.kill_query(query_id => 'query_id_here', message => 'killed');

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. Trino 本身不管理锁，取决于连接器
-- 2. 不支持 SELECT FOR UPDATE / FOR SHARE
-- 3. 不支持 LOCK TABLE
-- 4. 不支持多语句事务 (BEGIN/COMMIT)
-- 5. 写入冲突由底层存储格式处理
-- 6. 适合分析查询场景，不适合 OLTP
