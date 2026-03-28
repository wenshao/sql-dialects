-- StarRocks: INSERT
--
-- 参考资料:
--   [1] StarRocks Documentation - INSERT / Stream Load
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/

-- ============================================================
-- 1. 写入方式 (与 Doris 同源 + Pipe)
-- ============================================================
-- INSERT INTO:    少量数据
-- Stream Load:    批量数据(HTTP 接口)
-- Broker Load:    HDFS/S3 大文件
-- Routine Load:   Kafka 持续消费
-- Pipe(3.2+):     对象存储持续加载(StarRocks 独有)

-- ============================================================
-- 2. SQL INSERT
-- ============================================================
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@e.com', 25);

INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@e.com', 25),
    ('bob', 'bob@e.com', 30);

INSERT INTO users_archive SELECT * FROM users WHERE age > 60;

-- INSERT OVERWRITE
INSERT OVERWRITE users SELECT * FROM staging_users;

-- 带 Label
INSERT INTO users WITH LABEL my_label
(username, email, age) VALUES ('alice', 'alice@e.com', 25);

-- ============================================================
-- 3. Stream Load
-- ============================================================
-- curl -u user:passwd -H "label:load_20240115" -T data.csv \
--   http://fe_host:8030/api/db/users/_stream_load

-- ============================================================
-- 4. Pipe 持续加载 (3.2+，StarRocks 独有)
-- ============================================================
-- CREATE PIPE my_pipe AS INSERT INTO target
-- SELECT * FROM FILES(
--     'path' = 's3://bucket/data/',
--     'format' = 'parquet',
--     'aws.s3.access_key' = '...',
--     'aws.s3.secret_key' = '...'
-- );
--
-- 设计分析:
--   Pipe 自动监控对象存储目录，新文件自动加载。
--   类似 Snowflake 的 Snowpipe——但集成在引擎内部。
--   Doris 没有等价功能(需要外部调度 + Broker Load)。
--
-- SHOW PIPES;
-- ALTER PIPE my_pipe SET ("poll_interval" = "60");
-- DROP PIPE my_pipe;

-- ============================================================
-- 5. Broker Load / Routine Load
-- ============================================================
-- 与 Doris 语法基本相同(同源)。

-- ============================================================
-- 6. StarRocks vs Doris INSERT 差异
-- ============================================================
-- Pipe(3.2+): StarRocks 独有，对象存储持续加载
-- CTAS 自动分布: StarRocks 3.0+ 不需要 DISTRIBUTED BY
-- INSERT OVERWRITE: 语法略有差异
-- Label 机制: 两者都支持
--
-- 对引擎开发者的启示:
--   数据导入是 OLAP 引擎的核心竞争力之一。
--   Stream Load 的设计启示:
--     跳过 SQL 层 → 直接推送数据到 BE → 减少解析开销
--     HTTP 接口 → 无需特殊客户端/驱动
--     Tablet 级别写入 → 利用分桶并行
