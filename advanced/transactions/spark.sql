-- Spark SQL: Transactions
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- Standard Spark SQL does NOT support multi-statement transactions
-- Each SQL statement is an independent operation

-- Delta Lake provides ACID transactions (Databricks / open source Delta Lake)

-- Delta Lake: Implicit transactions
-- Each INSERT, UPDATE, DELETE, MERGE is an atomic transaction
INSERT INTO delta_users VALUES (1, 'alice', 'alice@example.com');
-- This is a complete ACID transaction

-- Delta Lake: Multi-table atomic operations (not natively multi-statement)
-- Use MERGE for complex operations within a single table
MERGE INTO users AS t
USING updates AS s
ON t.id = s.id
WHEN MATCHED AND s.delete_flag THEN DELETE
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;

-- Delta Lake: Optimistic concurrency control
-- If two transactions conflict, one will fail and needs retry
-- Conflicts are detected at the file level

-- Delta Lake: Time travel (access previous versions)
SELECT * FROM users VERSION AS OF 5;                   -- By version number
SELECT * FROM users TIMESTAMP AS OF '2024-01-15 10:00:00'; -- By timestamp
SELECT * FROM users@v5;                                -- Short syntax (Databricks)

-- Delta Lake: Restore to previous version
RESTORE TABLE users TO VERSION AS OF 5;
RESTORE TABLE users TO TIMESTAMP AS OF '2024-01-15 10:00:00';

-- Delta Lake: History (view all transactions)
DESCRIBE HISTORY users;
DESCRIBE HISTORY users LIMIT 10;

-- Delta Lake: Vacuum (clean up old versions)
VACUUM users;                                          -- Default: 7-day retention
VACUUM users RETAIN 168 HOURS;                         -- Explicit retention

-- Delta Lake: Schema evolution (transactional schema changes)
-- SET spark.databricks.delta.schema.autoMerge.enabled = true;
-- ALTER TABLE users ADD COLUMNS (phone STRING);

-- Iceberg: ACID transactions
-- Each write operation is atomic in Iceberg
-- Iceberg uses snapshot isolation
-- SELECT * FROM catalog.db.users.snapshots;           -- View snapshots
-- SELECT * FROM catalog.db.users.history;             -- View history
-- CALL catalog.system.rollback_to_snapshot('db.users', 123456);

-- Savepoint-like behavior with Delta Lake:
-- 1. Check current version: DESCRIBE HISTORY users LIMIT 1;
-- 2. Make changes
-- 3. If something goes wrong: RESTORE TABLE users TO VERSION AS OF <saved_version>;

-- Write isolation levels in Delta Lake:
-- Serializable (default): Full conflict detection
-- WriteSerializable: Less strict, allows some concurrent writes

-- SET delta.isolationLevel = 'Serializable';

-- Optimistic concurrency control pattern:
-- 1. Read version N
-- 2. Compute changes based on version N
-- 3. Write changes -- Delta checks if version N is still current
-- 4. If conflict: retry from step 1

-- Databricks: Multi-statement transactions (Unity Catalog, preview)
-- BEGIN TRANSACTION;
-- UPDATE accounts SET balance = balance - 100 WHERE id = 1;
-- UPDATE accounts SET balance = balance + 100 WHERE id = 2;
-- COMMIT;

-- Note: Standard Spark SQL has no transaction support
-- Note: Delta Lake provides ACID through optimistic concurrency control
-- Note: Each DML operation on Delta tables is an atomic transaction
-- Note: Multi-statement transactions are NOT supported (except Databricks preview)
-- Note: Time travel allows "undo" by restoring previous versions
-- Note: Iceberg provides similar ACID guarantees with snapshots
-- Note: Hive ACID transactions exist but have significant limitations
-- Note: For cross-table atomicity, use application-level coordination
