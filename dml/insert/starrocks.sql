-- StarRocks: INSERT
--
-- 参考资料:
--   [1] StarRocks - INSERT
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/loading_unloading/INSERT/
--   [2] StarRocks - Loading Overview
--       https://docs.starrocks.io/docs/loading/Loading_intro/

-- 注意: StarRocks 支持标准 SQL INSERT，同时提供 Stream Load / Broker Load 等批量导入方式

-- 单行插入
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 多行插入
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- 从查询结果插入
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- INSERT OVERWRITE（覆盖写入）
INSERT OVERWRITE users (username, email, age)
SELECT username, email, age FROM staging_users;

-- 写入分区表
INSERT INTO events PARTITION (p20240115)
SELECT user_id, event_name, event_time FROM staging_events;

-- INSERT OVERWRITE 分区
INSERT OVERWRITE events PARTITION (p20240115)
SELECT user_id, event_name, event_time FROM staging_events;

-- CTE + INSERT
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age
)
INSERT INTO users (username, email, age)
SELECT * FROM new_users;

-- 带 label（用于幂等重试，相同 label 不会重复导入）
INSERT INTO users WITH LABEL my_label_20240115
(username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- Stream Load（HTTP 接口，推荐大批量导入）
-- curl -H "label:load_20240115" -T data.csv \
--   http://fe_host:8030/api/db/users/_stream_load

-- Broker Load（从 HDFS/S3 加载）
-- LOAD LABEL db.label_20240115 (
--     DATA INFILE("s3://bucket/data.csv")
--     INTO TABLE users
--     FORMAT AS "CSV"
-- )
-- WITH BROKER
-- PROPERTIES ("timeout" = "3600");

-- Pipe（3.2+，持续增量导入）
-- CREATE PIPE my_pipe AS
-- INSERT INTO users SELECT * FROM FILES('s3://bucket/data/*.parquet');
