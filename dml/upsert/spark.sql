-- Spark SQL: UPSERT / MERGE (Spark 2.0+ with Delta Lake / Iceberg)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- Spark has no INSERT ... ON CONFLICT syntax
-- MERGE INTO is the standard approach (Delta Lake, Iceberg, Hudi)

-- Delta Lake: Basic MERGE (upsert)
MERGE INTO users AS t
USING new_users AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN NOT MATCHED THEN
    INSERT (id, username, email, age) VALUES (s.id, s.username, s.email, s.age);

-- MERGE with all clauses
MERGE INTO users AS t
USING updates AS s
ON t.id = s.id
WHEN MATCHED AND s.delete_flag = true THEN
    DELETE
WHEN MATCHED THEN
    UPDATE SET *
WHEN NOT MATCHED THEN
    INSERT *;

-- MERGE with conditional update
MERGE INTO users AS t
USING new_data AS s
ON t.username = s.username
WHEN MATCHED AND s.age > t.age THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN MATCHED THEN
    UPDATE SET t.email = s.email
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE from a subquery
MERGE INTO users AS t
USING (
    SELECT username, email, age
    FROM staging_users
    WHERE valid = true
) AS s
ON t.username = s.username
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;

-- MERGE from VALUES
MERGE INTO users AS t
USING (
    SELECT * FROM VALUES
        ('alice', 'alice_new@example.com', 26),
        ('dave', 'dave@example.com', 28)
    AS s(username, email, age)
) AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET t.email = s.email, t.age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- WHEN NOT MATCHED BY SOURCE (Spark 3.4+, Delta Lake)
MERGE INTO users AS t
USING new_users AS s
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *
WHEN NOT MATCHED BY SOURCE THEN DELETE;

-- Iceberg: MERGE INTO (Spark 3.0+ with Iceberg)
MERGE INTO catalog.db.users AS t
USING catalog.db.new_users AS s
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;

-- For standard Spark tables (Parquet/ORC), simulate upsert:
-- Step 1: Left anti join + union
CREATE OR REPLACE TEMP VIEW merged_users AS
SELECT s.* FROM new_users s
UNION ALL
SELECT t.* FROM users t
LEFT ANTI JOIN new_users s ON t.id = s.id;

INSERT OVERWRITE TABLE users
SELECT * FROM merged_users;

-- Note: MERGE INTO requires Delta Lake, Iceberg, or Hudi
-- Note: UPDATE SET * and INSERT * use all columns (schema must match)
-- Note: No INSERT ... ON CONFLICT syntax
-- Note: Standard Spark tables require INSERT OVERWRITE workaround
-- Note: No RETURNING clause on MERGE
