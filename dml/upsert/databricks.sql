-- Databricks SQL: UPSERT
--
-- 参考资料:
--   [1] Databricks SQL Language Reference
--       https://docs.databricks.com/en/sql/language-manual/index.html
--   [2] Databricks SQL - Built-in Functions
--       https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html
--   [3] Delta Lake Documentation
--       https://docs.delta.io/latest/index.html

-- MERGE INTO 是 Delta Lake 的核心功能（ACID 保证）

-- ============================================================
-- 基本 MERGE INTO
-- ============================================================

MERGE INTO users AS t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age) AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age, updated_at = current_timestamp()
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE 批量操作
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age, updated_at = current_timestamp()
WHEN NOT MATCHED THEN
    INSERT (username, email, age, created_at)
    VALUES (s.username, s.email, s.age, current_timestamp());

-- MERGE 带条件
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED AND s.age > t.age THEN
    UPDATE SET age = s.age, updated_at = current_timestamp()
WHEN MATCHED AND s.status = 'delete' THEN
    DELETE
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE 多 WHEN 子句
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED AND s.action = 'delete' THEN
    DELETE
WHEN MATCHED AND s.action = 'update' THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED AND s.action != 'delete' THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE 使用 UPDATE SET *（所有列）
MERGE INTO users AS t
USING staging_users AS s
ON t.id = s.id
WHEN MATCHED THEN
    UPDATE SET *                             -- 更新所有列
WHEN NOT MATCHED THEN
    INSERT *;                                -- 插入所有列

-- 仅插入不存在的行
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE + CTE
WITH new_data AS (
    SELECT username, email, MAX(age) AS age
    FROM staging_users
    GROUP BY username, email
)
MERGE INTO users AS t
USING new_data AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- ============================================================
-- SCD Type 2（缓慢变化维度）
-- ============================================================

MERGE INTO dim_users AS t
USING (
    SELECT s.*, current_timestamp() AS effective_date
    FROM staging_users s
) AS s
ON t.username = s.username AND t.is_current = true
WHEN MATCHED AND (t.email != s.email OR t.age != s.age) THEN
    UPDATE SET is_current = false, end_date = s.effective_date
WHEN NOT MATCHED THEN
    INSERT (username, email, age, is_current, start_date)
    VALUES (s.username, s.email, s.age, true, s.effective_date);

-- 然后插入新的当前版本行
INSERT INTO dim_users (username, email, age, is_current, start_date)
SELECT s.username, s.email, s.age, true, current_timestamp()
FROM staging_users s
INNER JOIN dim_users t ON s.username = t.username
WHERE t.is_current = false AND t.end_date = (
    SELECT MAX(end_date) FROM dim_users WHERE username = s.username
);

-- ============================================================
-- MERGE 与 Schema Evolution
-- ============================================================

-- 自动合并 Schema（暂存表有新列时）
SET spark.databricks.delta.schema.autoMerge.enabled = true;

MERGE INTO users AS t
USING staging_users_v2 AS s  -- staging_users_v2 可能有新列
ON t.id = s.id
WHEN MATCHED THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;

-- 注意：MERGE INTO 是 Delta Lake 的核心功能，完全 ACID
-- 注意：支持 UPDATE SET * 和 INSERT * 简写
-- 注意：Schema Evolution 允许 MERGE 时自动添加新列
-- 注意：MERGE 在大表上可能需要较长时间，建议配合分区/Liquid Clustering
-- 注意：可以通过 DESCRIBE HISTORY 查看 MERGE 操作历史
-- 注意：MERGE 操作的原子性保证不会产生脏数据
