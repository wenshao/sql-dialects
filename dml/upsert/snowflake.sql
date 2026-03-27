-- Snowflake: UPSERT
--
-- 参考资料:
--   [1] Snowflake SQL Reference - MERGE
--       https://docs.snowflake.com/en/sql-reference/sql/merge
--   [2] Snowflake SQL Reference - INSERT
--       https://docs.snowflake.com/en/sql-reference/sql/insert

-- 方式一: MERGE（推荐，SQL 标准语法）
MERGE INTO users AS t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age) AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE 批量操作
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE 带条件
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED AND s.age > t.age THEN
    UPDATE SET age = s.age
WHEN MATCHED AND s.age <= t.age THEN
    DELETE
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE 多 WHEN MATCHED 子句
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED AND s.status = 'delete' THEN
    DELETE
WHEN MATCHED AND s.status = 'update' THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED AND s.status != 'delete' THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- 仅插入不存在的行
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE + VALUES 子句（多行）
MERGE INTO users AS t
USING (
    SELECT column1 AS username, column2 AS email, column3 AS age
    FROM VALUES ('alice', 'alice@example.com', 25), ('bob', 'bob@example.com', 30)
) AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- 方式二: INSERT ... ON CONFLICT（不支持，需用 MERGE）
