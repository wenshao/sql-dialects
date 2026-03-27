-- ClickHouse: INSERT
--
-- 参考资料:
--   [1] ClickHouse SQL Reference - INSERT INTO
--       https://clickhouse.com/docs/en/sql-reference/statements/insert-into
--   [2] ClickHouse - Async Insert
--       https://clickhouse.com/docs/en/cloud/bestpractices/asynchronous-inserts
--   [3] ClickHouse - Data Ingestion Best Practices
--       https://clickhouse.com/docs/en/cloud/bestpractices/bulk-inserts

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- 单行插入（不推荐，见下文分析）
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 多行插入（推荐每批 1000+ 行）
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- 从查询结果插入
INSERT INTO users_archive SELECT * FROM users WHERE age > 60;

-- ============================================================
-- 2. INSERT-only 哲学: 为什么 ClickHouse 只推荐 INSERT
-- ============================================================

-- ClickHouse 的核心设计是 INSERT-only（追加写入）:
--   INSERT: 高效（批量追加到新 data part）
--   UPDATE: 低效（ALTER TABLE UPDATE，异步 mutation，重写 part）
--   DELETE: 低效（ALTER TABLE DELETE，同上）
--
-- 为什么?
-- (a) 列式存储: 数据按列存储在不可变的 data part 文件中。
--     修改一行 = 修改所有列文件 = 重写整个 data part。
--     追加一行 = 创建新 data part（后台 merge 合并 part）。
--
-- (b) 压缩: 列数据经过 LZ4/ZSTD 压缩，修改中间一个值需要解压-修改-重压。
--     追加到新 part 不需要触碰已压缩的数据。
--
-- (c) MergeTree 的 merge 机制:
--     INSERT → 创建新 data part（毫秒级）
--     后台 merge → 合并小 part 为大 part（异步，优化存储和查询性能）
--     这个模型天然适合追加，不适合就地修改。
--
-- 性能基准:
--   INSERT 批量写入: 100 万行/秒（取决于列数和数据大小）
--   ALTER TABLE UPDATE: 100 万行可能需要数秒到数分钟（重写整个 part）

-- ============================================================
-- 3. 批量 INSERT 最佳实践
-- ============================================================

-- 3.1 每批插入量
-- 推荐: 每批 10,000 - 1,000,000 行，或 1-10 MB 数据
-- 原因: 每次 INSERT 创建一个 data part
--   太小（每行一个 INSERT）→ 海量小 part → merge 压力 → "too many parts" 错误
--   太大（单次 10 亿行）→ 内存不足 → 写入超时

-- 3.2 FORMAT 子句（ClickHouse 特有，直接解析多种格式）
INSERT INTO users FORMAT CSV
'alice','alice@example.com',25
'bob','bob@example.com',30;

INSERT INTO users FORMAT JSONEachRow
{"username": "alice", "email": "alice@example.com", "age": 25}
{"username": "bob", "email": "bob@example.com", "age": 30};

INSERT INTO users FORMAT TabSeparated
alice	alice@example.com	25
bob	bob@example.com	30;

-- 设计分析:
--   FORMAT 子句是 ClickHouse 最独特的 INSERT 特性。
--   传统数据库需要: 文件 → ETL 工具解析 → SQL INSERT
--   ClickHouse: 文件 → 直接 INSERT ... FORMAT CSV（零 ETL）
--   支持 40+ 种格式: CSV, JSON, Parquet, ORC, Avro, ProtoBuf 等

-- 3.3 从外部数据源直接 INSERT
-- 从 S3
INSERT INTO users
SELECT * FROM s3('https://bucket.s3.amazonaws.com/data.csv', 'CSV',
    'username String, email String, age UInt8');

-- 从 URL
INSERT INTO users
SELECT * FROM url('http://example.com/data.csv', 'CSV',
    'username String, email String, age UInt8');

-- 从远程 ClickHouse
INSERT INTO users
SELECT * FROM remote('other-host:9000', 'db', 'users', 'user', 'pass');

-- 从命令行管道
-- cat data.csv | clickhouse-client --query="INSERT INTO users FORMAT CSV"
-- 这是 ClickHouse 最常见的数据加载方式（管道 + FORMAT）

-- ============================================================
-- 4. 异步 INSERT（22.8+）
-- ============================================================

-- 问题: 高频小批量 INSERT 会创建太多小 data part
-- 解决: 异步 INSERT 让服务端自动攒批

INSERT INTO users SETTINGS async_insert = 1, wait_for_async_insert = 1
VALUES ('alice', 'alice@example.com', 25);

-- 工作原理:
--   客户端发送小批量 INSERT → 服务端缓冲 → 达到阈值后一次性写入
--   阈值参数:
--     async_insert_max_data_size = 10485760  (10MB)
--     async_insert_busy_timeout_ms = 200     (200ms)
--     async_insert_stale_timeout_ms = 0      (空闲时立即刷入)
--
-- wait_for_async_insert:
--   0 = 不等待（fire-and-forget，可能丢失）
--   1 = 等待写入完成（安全但增加延迟）
--
-- 对比:
--   MySQL:      无类似机制（每个 INSERT 立即写入）
--   PostgreSQL: 无类似机制
--   BigQuery:   Streaming API 有类似缓冲
--   Kafka:      Producer 的 linger.ms 和 batch.size 是相同概念

-- ============================================================
-- 5. Buffer 表（另一种写入缓冲方案）
-- ============================================================

-- CREATE TABLE users_buffer AS users ENGINE = Buffer(
--     currentDatabase(), users,
--     16,        -- min_time_to_flush
--     100,       -- max_time_to_flush
--     10000,     -- min_rows_to_flush
--     1000000,   -- max_rows_to_flush
--     10000000,  -- min_bytes_to_flush
--     100000000  -- max_bytes_to_flush
-- );
-- INSERT INTO users_buffer VALUES (...);
-- 达到阈值后自动刷入 users 表

-- Buffer 表 vs 异步 INSERT:
--   Buffer 表: 旧方案，表级别配置，有丢失风险
--   异步 INSERT: 新方案（22.8+），服务端级别，更可靠

-- ============================================================
-- 6. 物化视图触发（INSERT 的连锁反应）
-- ============================================================

-- INSERT 到基表时，自动触发所有关联物化视图的 SELECT → INSERT:
-- INSERT INTO raw_events VALUES (...)
-- → mv_hourly_counts: SELECT ... GROUP BY hour
-- → mv_user_funnel: SELECT ... WHERE event_type IN (...)
-- → mv_error_alert: SELECT ... WHERE level = 'ERROR'
-- 一次 INSERT 可以触发多个下游写入（见 views/clickhouse.sql）

-- ============================================================
-- 7. INSERT 去重（块级幂等性）
-- ============================================================

-- MergeTree 表自动对最近插入的数据块去重:
-- 相同内容的 INSERT 块在短时间内（默认几分钟）再次插入会被忽略。
-- 基于块哈希（block hash），不是行级去重。
-- 这保证了网络重试的 INSERT 幂等性。
--
-- 对比:
--   BigQuery Streaming API: 有 insertId 去重（窗口更短）
--   Kafka:                  幂等 Producer（exactly-once 语义）

-- ============================================================
-- 8. 引擎开发者启示
-- ============================================================
-- ClickHouse INSERT 的核心设计:
--   (1) INSERT-only 哲学 → 列存 + 不可变 data part + 后台 merge
--   (2) FORMAT 子句 → 零 ETL 数据加载
--   (3) 异步 INSERT → 服务端攒批，解决小批量写入问题
--   (4) 块级去重 → 网络重试幂等性
--   (5) 物化视图触发 → INSERT 是数据管道的起点
--
-- 对引擎开发者的启示:
--   OLAP 引擎的 INSERT 应该优化批量吞吐量（而非单行延迟）。
--   FORMAT 子句是极有价值的设计: 减少了对外部 ETL 工具的依赖。
--   异步 INSERT 是解决"用户习惯逐行写入但引擎需要批量"的优雅方案。
