-- Spark SQL: DELETE (Spark 3.0+ with Delta Lake / Iceberg)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- DELETE is NOT supported on standard Spark tables (Parquet/ORC/CSV)
-- Requires Delta Lake, Iceberg, or Hudi

-- Delta Lake: Basic delete
DELETE FROM users WHERE username = 'alice';

-- Delta Lake: Delete with complex condition
DELETE FROM users WHERE age < 18 OR status = 0;

-- Delta Lake: Delete with subquery
DELETE FROM users WHERE id IN (
    SELECT user_id FROM blacklist
);

-- Delta Lake: Delete with EXISTS
DELETE FROM users
WHERE EXISTS (
    SELECT 1 FROM blacklist WHERE blacklist.email = users.email
);

-- Iceberg: Basic delete (Spark 3.1+ with Iceberg)
DELETE FROM catalog.db.users WHERE username = 'alice';

-- For standard Spark tables, use INSERT OVERWRITE as workaround:
INSERT OVERWRITE TABLE users
SELECT * FROM users WHERE username != 'alice';

-- Alternative: Filter and recreate
CREATE TABLE users_clean AS
SELECT * FROM users WHERE status != 0;
DROP TABLE users;
ALTER TABLE users_clean RENAME TO users;

-- Delete all rows
DELETE FROM users;
-- Or for standard tables:
TRUNCATE TABLE users;

-- Delta Lake: Vacuum (physically remove deleted files)
-- VACUUM users RETAIN 168 HOURS;   -- Default 7 days retention

-- Delta Lake: Time travel to undo delete
-- RESTORE TABLE users TO VERSION AS OF 5;

-- Delta Lake: Delete with complex join condition using MERGE
MERGE INTO users
USING blacklist ON users.email = blacklist.email
WHEN MATCHED THEN DELETE;

-- Note: DELETE requires Delta Lake, Iceberg, or Hudi table format
-- Note: Standard Hive/Parquet tables use TRUNCATE (all rows) or INSERT OVERWRITE
-- Note: No RETURNING clause
-- Note: No USING clause for multi-table delete (use subqueries or MERGE)
-- Note: Deleted data files are not immediately removed; use VACUUM (Delta) or
--       expire_snapshots (Iceberg) to reclaim space
