-- Spark SQL: UPDATE (Spark 3.0+ with Delta Lake / Iceberg)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- UPDATE is NOT supported on standard Spark tables (Parquet/ORC/CSV)
-- It requires a table format that supports row-level operations:
-- Delta Lake, Iceberg, or Hudi

-- Delta Lake: Basic update
UPDATE users SET age = 26 WHERE username = 'alice';

-- Delta Lake: Multi-column update
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- Delta Lake: Update with subquery
UPDATE users SET age = (SELECT AVG(age) FROM users) WHERE age IS NULL;

-- Delta Lake: CASE expression
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- Delta Lake: Update with join condition (using subquery)
UPDATE users SET status = 2
WHERE id IN (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
);

-- Iceberg: Basic update (Spark 3.1+ with Iceberg 0.12+)
UPDATE catalog.db.users SET age = 26 WHERE username = 'alice';

-- For standard Spark tables, the workaround is to rewrite the entire table:
-- INSERT OVERWRITE approach
CREATE OR REPLACE TEMP VIEW updated_users AS
SELECT
    id, username,
    CASE WHEN username = 'alice' THEN 'new@example.com' ELSE email END AS email,
    CASE WHEN username = 'alice' THEN 26 ELSE age END AS age
FROM users;

INSERT OVERWRITE TABLE users
SELECT * FROM updated_users;

-- Alternative: Create new table and swap
CREATE TABLE users_new AS
SELECT id, username,
    CASE WHEN age IS NULL THEN 0 ELSE age END AS age,
    email
FROM users;
DROP TABLE users;
ALTER TABLE users_new RENAME TO users;

-- Delta Lake: Update with complex expressions
UPDATE orders SET
    total = quantity * unit_price,
    updated_at = current_timestamp()
WHERE total IS NULL;

-- Delta Lake: Time travel (undo an update by restoring previous version)
-- RESTORE TABLE users TO VERSION AS OF 5;
-- RESTORE TABLE users TO TIMESTAMP AS OF '2024-01-15 10:00:00';

-- Note: UPDATE requires Delta Lake, Iceberg, or Hudi table format
-- Note: Standard Hive/Parquet tables do not support UPDATE
-- Note: No RETURNING clause
-- Note: No FROM clause for multi-table update (use subqueries or MERGE)
-- Note: For large-scale updates, consider using MERGE or INSERT OVERWRITE
