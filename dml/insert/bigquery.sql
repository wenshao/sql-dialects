-- BigQuery: INSERT
--
-- 参考资料:
--   [1] BigQuery SQL Reference - INSERT
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax#insert_statement
--   [2] BigQuery SQL Reference - DML Syntax
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax

-- 注意: BigQuery DML 有配额限制（每个表每秒最多 5 个并发 DML 语句）
-- 对于大批量插入，推荐使用 LOAD 作业或流式插入 API

-- 单行插入
INSERT INTO dataset.users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 多行插入
INSERT INTO dataset.users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- 从查询结果插入
INSERT INTO dataset.users_archive (username, email, age)
SELECT username, email, age FROM dataset.users WHERE age > 60;

-- 插入嵌套/重复字段（STRUCT 和 ARRAY）
INSERT INTO dataset.events (user_id, event_name, properties)
VALUES (1, 'login', STRUCT('web' AS source, 'chrome' AS browser));

-- 插入 ARRAY 类型
INSERT INTO dataset.users (username, tags)
VALUES ('alice', ['vip', 'active', 'premium']);

-- 从子查询插入并转换
INSERT INTO dataset.users (username, email, created_at)
SELECT name, email, CURRENT_TIMESTAMP()
FROM dataset.external_source;

-- CTE + INSERT
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age
    UNION ALL
    SELECT 'bob', 'bob@example.com', 30
)
INSERT INTO dataset.users (username, email, age)
SELECT * FROM new_users;

-- 插入分区表（自动根据分区列路由）
INSERT INTO dataset.events (event_date, user_id, event_name)
VALUES ('2024-01-15', 1, 'login');

-- 指定默认值（BigQuery 使用 NULL 作为缺省默认值）
INSERT INTO dataset.users (username, email) VALUES ('alice', 'alice@example.com');
-- 未指定的列自动填充 NULL
