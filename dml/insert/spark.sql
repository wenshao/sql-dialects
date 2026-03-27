-- Spark SQL: INSERT (Spark 2.0+)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- Basic insert
INSERT INTO users VALUES (1, 'alice', 'alice@example.com', 25);

-- Named columns
INSERT INTO users (id, username, email, age)
VALUES (1, 'alice', 'alice@example.com', 25);

-- Multi-row insert (Spark 2.4+)
INSERT INTO users VALUES
    (1, 'alice', 'alice@example.com', 25),
    (2, 'bob', 'bob@example.com', 30),
    (3, 'charlie', 'charlie@example.com', 35);

-- Insert from query
INSERT INTO users_archive
SELECT * FROM users WHERE age > 60;

-- INSERT OVERWRITE (replaces all data in table or partition)
INSERT OVERWRITE TABLE users
SELECT * FROM staging_users;

-- INSERT OVERWRITE with partition
INSERT OVERWRITE TABLE orders PARTITION (order_date = '2024-01-15')
SELECT id, user_id, amount FROM staging_orders
WHERE order_date = '2024-01-15';

-- Dynamic partition insert
INSERT OVERWRITE TABLE orders PARTITION (order_date)
SELECT id, user_id, amount, order_date FROM staging_orders;

-- SET for dynamic partition mode
-- SET spark.sql.sources.partitionOverwriteMode = dynamic;
-- Only overwrites partitions that appear in the data

-- Insert into partitioned table
INSERT INTO orders PARTITION (order_date = '2024-01-15')
VALUES (1, 100, 99.99);

-- CREATE TABLE AS SELECT (CTAS) for initial load
CREATE TABLE active_users AS
SELECT * FROM users WHERE status = 1;

-- INSERT INTO with CTE (Spark 3.0+)
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email
)
INSERT INTO users (username, email)
SELECT username, email FROM new_users;

-- Delta Lake: INSERT with schema evolution
-- SET spark.databricks.delta.schema.autoMerge.enabled = true;
-- INSERT INTO delta_table SELECT * FROM source_with_new_columns;

-- Load data from files (Hive-compatible)
LOAD DATA INPATH '/data/users.csv' INTO TABLE users;
LOAD DATA INPATH '/data/users.csv' OVERWRITE INTO TABLE users;
LOAD DATA LOCAL INPATH '/local/users.csv' INTO TABLE users;

-- Insert using inline table (VALUES as a table)
INSERT INTO users
SELECT * FROM VALUES
    (1, 'alice', 'alice@example.com', 25),
    (2, 'bob', 'bob@example.com', 30)
AS t(id, username, email, age);

-- Note: No RETURNING clause
-- Note: No INSERT OR IGNORE / INSERT OR REPLACE (use MERGE instead)
-- Note: INSERT OVERWRITE is a key Spark feature for idempotent data pipelines
-- Note: Dynamic partition insert requires proper Spark configuration
-- Note: Spark manages file layout; no direct COPY command like in databases
