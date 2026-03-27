-- BigQuery: INSERT
--
-- 参考资料:
--   [1] BigQuery SQL Reference - INSERT
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax#insert_statement
--   [2] BigQuery Documentation - Loading Data
--       https://cloud.google.com/bigquery/docs/loading-data
--   [3] BigQuery Documentation - DML Quotas
--       https://cloud.google.com/bigquery/quotas#dml

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- 单行插入
INSERT INTO myproject.mydataset.users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);

-- 多行插入
INSERT INTO myproject.mydataset.users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- 从查询结果插入
INSERT INTO myproject.mydataset.users_archive (username, email, age)
SELECT username, email, age FROM myproject.mydataset.users WHERE age > 60;

-- CTE + INSERT
WITH new_users AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age
    UNION ALL
    SELECT 'bob', 'bob@example.com', 30
)
INSERT INTO myproject.mydataset.users (username, email, age)
SELECT * FROM new_users;

-- ============================================================
-- 2. DML 配额: BigQuery INSERT 的根本约束
-- ============================================================

-- BigQuery 的 DML 操作有严格的配额限制:
--   每个表每天最多 1500 次 DML 操作
--   DML 操作之间最少 10 秒间隔（并发限制约 5 个）
--   每次 DML 最大影响 20 GB 数据
--
-- 为什么有这些限制?
-- (a) 无服务器架构: BigQuery 不是为高频小批量 DML 设计的。
--     每次 DML 都需要: 分配 slot → 读取数据 → 修改 → 写回。
--     这不是就地修改（in-place），而是 COW（Copy-on-Write）。
--
-- (b) Capacitor 格式: 数据存储在不可变的列式文件中。
--     INSERT 需要创建新的存储文件（而非追加到已有文件）。
--     过多的小文件 = 元数据爆炸 = 查询性能下降。
--
-- (c) 成本模型: 每次 DML 都消耗 slot（计算资源）。
--     高频小 DML = 大量 slot 调度开销 = 不经济。
--
-- 对比:
--   MySQL:      无 DML 配额（设计为高频 OLTP）
--   PostgreSQL: 无 DML 配额
--   ClickHouse: 无 DML 配额（但推荐批量 INSERT）
--   Snowflake:  无严格配额（但微批 DML 也有性能问题）

-- ============================================================
-- 3. 数据加载的正确方式（不是 SQL INSERT）
-- ============================================================

-- BigQuery 推荐的数据加载方式不是 SQL INSERT:
--
-- 3.1 LOAD 作业（批量加载，最推荐）
-- bq load --source_format=CSV mydataset.users gs://bucket/data.csv
-- 特点: 免费（不消耗 slot），不受 DML 配额限制，支持 GB-TB 级数据
-- 支持格式: CSV, JSON, Avro, Parquet, ORC
--
-- 3.2 Streaming API（实时写入）
-- 通过 BigQuery Storage Write API 写入
-- 特点: 秒级延迟，按写入量计费，有去重机制
-- 适用: 实时日志、事件流、IoT 数据
--
-- 3.3 CTAS（CREATE TABLE AS SELECT）
-- 最常用的大批量数据生成方式:
-- CREATE TABLE mydataset.result AS SELECT ... FROM ...;
-- 特点: 不受 DML 配额限制，原子操作，可以跨表

-- 设计启示:
--   BigQuery 将"数据加载"和"数据修改"区分为不同的操作:
--   LOAD = 批量导入（免费，无限制）
--   INSERT = DML 操作（有限制）
--   这与传统数据库"一切都是 SQL"的模式不同。

-- ============================================================
-- 4. 嵌套类型 INSERT（STRUCT 和 ARRAY）
-- ============================================================

-- 插入 STRUCT
INSERT INTO myproject.mydataset.events (user_id, event_name, properties)
VALUES (1, 'login', STRUCT('web' AS source, 'chrome' AS browser));

-- 插入 ARRAY
INSERT INTO myproject.mydataset.users (username, tags)
VALUES ('alice', ['vip', 'active', 'premium']);

-- 插入嵌套 STRUCT 的 ARRAY
INSERT INTO myproject.mydataset.orders (user_id, items) VALUES (
    1,
    [STRUCT('ProductA' AS name, 2 AS qty, 29.99 AS price),
     STRUCT('ProductB' AS name, 1 AS qty, 49.99 AS price)]
);

-- 设计分析:
--   BigQuery 的 STRUCT/ARRAY 是一等类型，INSERT 时直接构造。
--   对比 MySQL/PostgreSQL: 需要 JSON 字符串或单独的子表。
--   BigQuery 鼓励"宽表"设计（嵌套类型代替 JOIN），
--   因为 JOIN 在分布式环境中成本高，嵌套类型保持数据局部性。

-- ============================================================
-- 5. 分区表 INSERT
-- ============================================================

-- 自动路由到正确分区
INSERT INTO myproject.mydataset.events (event_date, user_id, event_name)
VALUES ('2024-01-15', 1, 'login');
-- BigQuery 根据 event_date 值自动写入正确分区

-- 写入特定分区（使用伪列）
INSERT INTO myproject.mydataset.events (event_date, user_id, event_name)
VALUES (DATE '2024-01-15', 1, 'login');

-- 按摄入时间分区的表: 自动使用当前时间作为分区键

-- ============================================================
-- 6. 对比与引擎开发者启示
-- ============================================================
-- BigQuery INSERT 的核心特征:
--   (1) DML 配额限制 → SQL INSERT 不是主要数据加载方式
--   (2) LOAD 作业 → 免费批量导入（设计重点）
--   (3) Streaming API → 实时写入（但有延迟和成本）
--   (4) STRUCT/ARRAY 直接 INSERT → 嵌套类型是一等公民
--   (5) 无冲突处理 → 用 MERGE 替代 UPSERT
--
-- 对引擎开发者的启示:
--   云数仓应该将"批量加载"作为主数据入口（免费/无限制），
--   SQL INSERT 只是补充（有限制）。
--   这与 OLTP 的"一切通过 SQL"模式截然不同。
--   Snowflake 的 COPY INTO、Redshift 的 COPY 命令都遵循同样的设计。
