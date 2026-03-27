-- ClickHouse: INSERT
--
-- 参考资料:
--   [1] ClickHouse SQL Reference - INSERT INTO
--       https://clickhouse.com/docs/en/sql-reference/statements/insert-into
--   [2] ClickHouse - Data Types
--       https://clickhouse.com/docs/en/sql-reference/data-types

-- 注意: ClickHouse 面向 OLAP 场景，推荐大批量插入，避免频繁小批次写入

-- 单行插入
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 多行插入（推荐每批 1000+ 行以获得最佳性能）
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- 从查询结果插入
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- FORMAT 子句（指定输入格式，ClickHouse 特有）
INSERT INTO users FORMAT CSV
'alice','alice@example.com',25
'bob','bob@example.com',30;

-- JSON 格式插入
INSERT INTO users FORMAT JSONEachRow
{"username": "alice", "email": "alice@example.com", "age": 25}
{"username": "bob", "email": "bob@example.com", "age": 30};

-- 从文件插入（命令行）
-- cat data.csv | clickhouse-client --query="INSERT INTO users FORMAT CSV"

-- 从远程表插入
INSERT INTO users (username, email, age)
SELECT username, email, age
FROM remote('other-host:9000', 'db', 'users', 'user', 'pass');

-- 从 S3 插入
INSERT INTO users
SELECT * FROM s3('https://bucket.s3.amazonaws.com/data.csv', 'CSV',
    'username String, email String, age UInt8');

-- 从 URL 插入
INSERT INTO users
SELECT * FROM url('http://example.com/data.csv', 'CSV',
    'username String, email String, age UInt8');

-- 指定设置（控制插入行为）
INSERT INTO users SETTINGS async_insert = 1, wait_for_async_insert = 1
VALUES ('alice', 'alice@example.com', 25);

-- 异步插入（22.8+，高吞吐场景）
-- SET async_insert = 1;
-- INSERT INTO users VALUES (...);  -- 服务端自动攒批

-- Buffer 表（高频小批量写入缓冲）
-- INSERT INTO users_buffer VALUES (...);  -- 自动攒批后刷入目标表

-- 物化视图自动路由（INSERT 到源表时触发物化视图的 SELECT 并写入目标表）
-- INSERT INTO source_table VALUES (...);  -- 物化视图自动处理
