-- Vertica: UPSERT
--
-- 参考资料:
--   [1] Vertica SQL Reference
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm
--   [2] Vertica Functions
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm

-- MERGE（SQL 标准，Vertica 原生支持）
MERGE INTO users t
USING staging_users s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET
    username = s.username,
    email = s.email,
    age = s.age,
    updated_at = CURRENT_TIMESTAMP
WHEN NOT MATCHED THEN INSERT (id, username, email, age)
    VALUES (s.id, s.username, s.email, s.age);

-- 批量 MERGE（从子查询）
MERGE INTO users t
USING (
    SELECT 1 AS id, 'alice' AS username, 'new@example.com' AS email, 26 AS age
    UNION ALL
    SELECT 2, 'bob', 'bob_new@example.com', 31
) s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET
    email = s.email, age = s.age
WHEN NOT MATCHED THEN INSERT (id, username, email, age)
    VALUES (s.id, s.username, s.email, s.age);

-- 条件 MERGE（只在满足条件时更新）
MERGE INTO users t
USING staging_users s ON t.id = s.id
WHEN MATCHED AND s.updated_at > t.updated_at THEN UPDATE SET
    username = s.username,
    email = s.email,
    updated_at = s.updated_at
WHEN NOT MATCHED THEN INSERT (id, username, email, updated_at)
    VALUES (s.id, s.username, s.email, s.updated_at);

-- MERGE + DELETE
MERGE INTO users t
USING staging_users s ON t.id = s.id
WHEN MATCHED AND s.status = 0 THEN DELETE
WHEN MATCHED THEN UPDATE SET
    email = s.email, age = s.age
WHEN NOT MATCHED THEN INSERT (id, username, email, age)
    VALUES (s.id, s.username, s.email, s.age);

-- CTE + MERGE
WITH new_data AS (
    SELECT id, username, email, age FROM staging_users WHERE status = 1
)
MERGE INTO users t
USING new_data s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET
    email = s.email, age = s.age
WHEN NOT MATCHED THEN INSERT (id, username, email, age)
    VALUES (s.id, s.username, s.email, s.age);

-- 替代方案：DELETE + INSERT（简单但非原子）
DELETE FROM users WHERE id IN (SELECT id FROM staging_users);
INSERT INTO users SELECT * FROM staging_users;

-- COPY + MERGE（大批量场景）
-- 1. COPY 到临时表
-- COPY staging_users FROM '/data/updates.csv' DELIMITER ',';
-- 2. MERGE 到目标表
-- MERGE INTO users ... USING staging_users ...

-- 注意：MERGE 是 Vertica 推荐的 UPSERT 方式
-- 注意：MERGE 支持 MATCHED + DELETE 组合
-- 注意：MERGE 支持多个 WHEN MATCHED 子句
-- 注意：大批量 UPSERT 建议先 COPY 到临时表再 MERGE
