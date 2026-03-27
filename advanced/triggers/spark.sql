-- Spark SQL: Triggers
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- Spark SQL does NOT support triggers
-- As a batch/streaming processing engine, Spark has no event-driven trigger mechanism

-- Alternatives to triggers in Spark:

-- 1. Delta Lake Change Data Feed (CDF) -- trigger-like change tracking
-- Enable CDF on a Delta table:
-- ALTER TABLE users SET TBLPROPERTIES (delta.enableChangeDataFeed = true);
-- Read changes:
-- SELECT * FROM table_changes('users', 2);  -- Changes since version 2
-- SELECT * FROM table_changes('users', '2024-01-01', '2024-01-31');

-- 2. Structured Streaming (real-time trigger-like processing)
-- In PySpark:
-- df = spark.readStream.format("delta").table("users")
-- df.writeStream \
--   .foreachBatch(lambda batch_df, batch_id: process_changes(batch_df)) \
--   .start()

-- 3. Delta Lake constraints (instead of validation triggers)
-- ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
-- ALTER TABLE users ADD CONSTRAINT chk_email CHECK (email LIKE '%@%');

-- 4. Pre/Post processing in ETL pipelines
-- In PySpark:
-- # Before writing
-- df = df.filter("age >= 0").withColumn("updated_at", current_timestamp())
-- # Write
-- df.write.mode("overwrite").saveAsTable("users")
-- # After writing
-- audit_df = spark.createDataFrame([("users", "INSERT", datetime.now())])
-- audit_df.write.mode("append").saveAsTable("audit_log")

-- 5. Views for computed values (instead of trigger-computed columns)
CREATE OR REPLACE VIEW users_enriched AS
SELECT *,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS age_group,
    CURRENT_TIMESTAMP() AS computed_at
FROM users;

-- 6. MERGE for complex update logic (instead of trigger on UPDATE)
MERGE INTO users AS t
USING updates AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET
        t.email = s.email,
        t.updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
    INSERT (id, username, email, created_at, updated_at)
    VALUES (s.id, s.username, s.email, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());

-- 7. Delta Lake event hooks (Databricks-specific)
-- # Python hook
-- from delta.tables import DeltaTable
-- dt = DeltaTable.forName(spark, "users")
-- dt.history()  -- View all changes

-- 8. Databricks SQL Alerts (monitoring triggers)
-- CREATE ALERT user_count_alert
-- ... WHEN COUNT(*) FROM users < 100 ...

-- 9. Auto Loader (Databricks: trigger on new file arrival)
-- df = spark.readStream.format("cloudFiles") \
--   .option("cloudFiles.format", "json") \
--   .load("/data/incoming/")

-- Note: No CREATE TRIGGER statement
-- Note: Delta Lake CDF provides change tracking (read changes after the fact)
-- Note: Structured Streaming can react to changes in real-time
-- Note: Delta Lake constraints replace validation triggers
-- Note: ETL pipeline hooks in PySpark replace pre/post-processing triggers
-- Note: For audit trails, use Delta Lake's built-in versioning and history
