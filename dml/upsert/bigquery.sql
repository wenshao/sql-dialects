-- BigQuery: UPSERT
--
-- 参考资料:
--   [1] BigQuery SQL Reference - MERGE
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax#merge_statement
--   [2] BigQuery SQL Reference - DML Syntax
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax

-- 注意: BigQuery 没有专用的 UPSERT 语法，使用 MERGE 语句实现
-- MERGE 受 DML 配额限制（每个表每秒最多 5 个并发 DML 语句）

-- 方式一: MERGE（推荐）
MERGE INTO dataset.users AS t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age) AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE 批量操作
MERGE INTO dataset.users AS t
USING dataset.staging_users AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE 带条件更新
MERGE INTO dataset.users AS t
USING dataset.staging_users AS s
ON t.username = s.username
WHEN MATCHED AND s.age > t.age THEN
    UPDATE SET age = s.age
WHEN MATCHED AND s.age <= t.age THEN
    DELETE
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE 仅插入不存在的行（INSERT IF NOT EXISTS）
MERGE INTO dataset.users AS t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age) AS s
ON t.username = s.username
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE 多行（通过 UNNEST）
MERGE INTO dataset.users AS t
USING UNNEST([
    STRUCT('alice' AS username, 'alice@example.com' AS email, 25 AS age),
    STRUCT('bob' AS username, 'bob@example.com' AS email, 30 AS age)
]) AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- 方式二: DELETE + INSERT 模拟（不推荐，两次 DML 配额消耗）
-- DELETE FROM dataset.users WHERE username = 'alice';
-- INSERT INTO dataset.users VALUES ('alice', 'alice@example.com', 25);
