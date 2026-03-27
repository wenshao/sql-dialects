-- Apache Doris: INSERT
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- 注意: Doris 支持标准 SQL INSERT，同时提供 Stream Load / Broker Load 等批量导入方式

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
INSERT OVERWRITE TABLE users (username, email, age)
SELECT username, email, age FROM staging_users;

-- 写入分区表
INSERT INTO events PARTITION (p20240115)
SELECT user_id, event_name, event_time FROM staging_events;

-- INSERT OVERWRITE 分区
INSERT OVERWRITE TABLE events PARTITION (p20240115)
SELECT user_id, event_name, event_time FROM staging_events;

-- 自动分区写入（2.1+，Auto Partition）
-- 建表时指定 AUTO PARTITION，INSERT 自动创建分区
-- PARTITION BY RANGE(order_date) ()
-- PROPERTIES ("auto_partition" = "true", "auto_partition_prefix" = "p")

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
-- curl -u user:passwd -H "label:load_20240115" -T data.csv \
--   http://fe_host:8030/api/db/users/_stream_load

-- Broker Load（从 HDFS/S3 加载）
-- LOAD LABEL db.label_20240115 (
--     DATA INFILE("s3://bucket/data.csv")
--     INTO TABLE users
--     FORMAT AS "CSV"
--     (id, username, email, age)
-- )
-- WITH S3 (
--     "AWS_ENDPOINT" = "s3.amazonaws.com",
--     "AWS_ACCESS_KEY" = "...",
--     "AWS_SECRET_KEY" = "..."
-- )
-- PROPERTIES ("timeout" = "3600");

-- Routine Load（持续消费 Kafka）
-- CREATE ROUTINE LOAD db.my_load ON users
-- COLUMNS (id, username, email, age)
-- FROM KAFKA (
--     "kafka_broker_list" = "broker:9092",
--     "kafka_topic" = "user_topic"
-- );

-- 注意：INSERT 适合少量数据，大批量推荐 Stream Load
-- 注意：INSERT 默认同步执行，大数据量可能超时
