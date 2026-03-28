-- Flink SQL: CREATE TABLE
--
-- 参考资料:
--   [1] Flink SQL - CREATE TABLE
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/create/
--   [2] Flink SQL - Data Types
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/
--   [3] Flink SQL - Connectors
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/connectors/table/overview/

-- ============================================================
-- 1. 基本语法: Kafka Source 表
-- ============================================================
CREATE TABLE user_events (
    user_id    BIGINT,
    event_type STRING,
    event_time TIMESTAMP(3),
    payload    STRING,
    -- Watermark: 声明事件时间与乱序容忍度
    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'user-events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-consumer',
    'format' = 'json',
    'scan.startup.mode' = 'latest-offset'
);

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 WITH 子句: 连接器配置（Flink 最独特的设计）
-- Flink 的 CREATE TABLE 必须包含 WITH 子句指定连接器，这是流处理引擎的核心设计。
-- 与传统数据库的 ENGINE 子句不同，Flink 的 WITH 定义的是数据的来源/去向。
--
-- 设计哲学: 表 = Schema + Connector（表本身不存储数据，只是外部系统的映射）
--   - 'connector' = 'kafka'        → 读/写 Kafka Topic
--   - 'connector' = 'jdbc'         → 读/写关系型数据库
--   - 'connector' = 'filesystem'   → 读/写文件系统（HDFS/S3/本地）
--   - 'connector' = 'upsert-kafka' → 支持 Changelog 语义的 Kafka
--   - 'connector' = 'hbase'        → 读/写 HBase
--   - 'connector' = 'elasticsearch' → 写入 Elasticsearch
--   - 'connector' = 'datagen'      → 生成测试数据
--   - 'connector' = 'print'        → 打印到标准输出（调试用）
--   - 'connector' = 'blackhole'    → 丢弃所有数据（性能测试用）
--
-- 设计 trade-off:
--   优点: 统一 SQL 接口操作异构数据源，流批一体
--   缺点: 每个连接器的配置项不同，学习曲线陡峭；连接器的能力差异大
--         （Kafka 支持流读写，JDBC 只支持 Lookup/Sink）
--
-- 对比:
--   Trino:      也用 Connector 架构，但配置在 catalog 层面（不在 DDL 中）
--   Spark SQL:  USING 子句 + OPTIONS（类似但更简洁）
--   Databricks: Delta Lake 是默认存储，外部表用 USING + LOCATION
--   DuckDB:     通过 read_csv/read_parquet 函数读取（无 Connector 概念）
--   传统 RDBMS:  表直接对应磁盘存储，无 Connector 抽象层
--
-- 对引擎开发者的启示:
--   如果设计流处理引擎，Connector 抽象是必须的（数据不在引擎内）。
--   关键决策: Connector 配置放在 DDL（Flink 做法）还是 Catalog（Trino 做法）？
--   Flink 的做法让每个表自包含配置信息，但导致 DDL 冗长；
--   Trino 的做法更干净，但需要集中管理 Catalog 配置。

-- 2.2 WATERMARK: 事件时间与乱序处理（流处理独有概念）
-- WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
-- 含义: 当收到 event_time=10:00:05 的事件时，认为 10:00:00 之前的事件已全部到达。
--
-- 设计背景:
--   流数据天然乱序（网络延迟、设备离线等），Watermark 是平衡 完整性 vs 延迟 的机制。
--   - 大 Watermark（如 1 小时）: 结果更完整，但延迟高
--   - 小 Watermark（如 5 秒）: 延迟低，但可能丢失迟到数据
--   - 无 Watermark: 只能用 Processing Time（不准确但无延迟）
--
-- 迟到数据处理:
--   Watermark 之后到达的数据默认丢弃。可通过以下方式处理:
--   - Allowed Lateness: 窗口关闭后继续接收（仅 DataStream API）
--   - Side Output: 将迟到数据输出到旁路流
--
-- 对比:
--   Spark Structured Streaming: withWatermark("event_time", "5 seconds")（API 层面，非 DDL）
--   Kafka Streams: 窗口的 grace period（类似概念，不同术语）
--   Google Dataflow: Watermark 概念的发明者（Millwheel 论文 2013）
--   传统数据库: 无此概念（批处理假设数据完整）

-- 2.3 PROCTIME(): 处理时间属性
-- Processing Time 是数据到达 Flink 的系统时钟时间（非事件时间）。
CREATE TABLE sensor_readings (
    sensor_id   STRING,
    temperature DOUBLE,
    proc_time   AS PROCTIME()   -- 虚拟列，不存储在物理数据中
) WITH (
    'connector' = 'kafka',
    'topic' = 'sensors',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

-- 设计分析:
--   PROCTIME() 是计算列（Computed Column），类型为 TIMESTAMP_LTZ(3) NOT NULL。
--   它不能从数据中读取，只在查询时由 Flink 运行时生成。
--   用途: Lookup Join 的时间条件、Processing Time 窗口
--   限制: 不确定性（重放数据时结果不同），不适合精确的业务逻辑

-- ============================================================
-- 3. PRIMARY KEY ... NOT ENFORCED: 语义约束
-- ============================================================
CREATE TABLE users (
    id         BIGINT,
    username   STRING,
    email      STRING,
    PRIMARY KEY (id) NOT ENFORCED  -- 声明但不强制执行
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:mysql://localhost:3306/mydb',
    'table-name' = 'users'
);

-- NOT ENFORCED 的设计哲理:
-- Flink 不存储数据，无法在写入时检查唯一性。
-- PRIMARY KEY 的作用是语义提示（告诉优化器这个列是唯一的）:
--   - 指导 Changelog 语义: 有 PK 的表支持 UPDATE/DELETE 消息
--   - 影响 Upsert Kafka: PK 作为 Kafka 消息的 Key
--   - Lookup Join 优化: 按 PK 查询外部表
--
-- 对比:
--   BigQuery/Snowflake: PRIMARY KEY 也是信息性的（不强制），原因相同（分布式代价太高）
--   MySQL/PostgreSQL:   PRIMARY KEY 强制唯一性 + NOT NULL
--   Databricks:         PRIMARY KEY 是信息性的（用于 Photon 优化器提示）
--   Trino:              无 PRIMARY KEY 语法

-- ============================================================
-- 4. Changelog 语义: Flink 的核心设计（对引擎开发者关键）
-- ============================================================
-- Flink 中的每行数据携带一个 ChangeFlag:
--   +I (INSERT)        → 新增一行
--   -U (UPDATE_BEFORE) → 更新前的旧值（用于撤回）
--   +U (UPDATE_AFTER)  → 更新后的新值
--   -D (DELETE)        → 删除一行
--
-- 这是 Flink 与所有批处理引擎的根本区别。
-- 批处理引擎只有 INSERT 语义；Flink 的动态表（Dynamic Table）支持完整的 CRUD。
--
-- 实际影响:
--   - 有 PK 的表: 产生 Upsert 流（+I, +U, -D），无需 -U
--   - 无 PK 的 GROUP BY: 产生 Retract 流（+I, -U, +U），需要撤回旧值再发送新值
--   - Append-only 表: 只产生 +I（如日志流）
--
-- Upsert Kafka Connector 的设计正是为了支持 Changelog:
CREATE TABLE user_profiles (
    user_id  BIGINT,
    username STRING,
    email    STRING,
    PRIMARY KEY (user_id) NOT ENFORCED
) WITH (
    'connector' = 'upsert-kafka',
    'topic' = 'user-profiles',
    'properties.bootstrap.servers' = 'kafka:9092',
    'key.format' = 'json',
    'value.format' = 'json'
);
-- upsert-kafka 将 PK 编码为 Kafka Key，value=null 表示 DELETE

-- ============================================================
-- 5. Metadata 列与 Computed 列
-- ============================================================
CREATE TABLE kafka_events (
    user_id      BIGINT,
    event_type   STRING,
    event_time   TIMESTAMP(3),
    -- Metadata 列: 从连接器底层读取系统字段
    kafka_topic  STRING METADATA FROM 'topic' VIRTUAL,
    kafka_offset BIGINT METADATA FROM 'offset' VIRTUAL,
    kafka_ts     TIMESTAMP_LTZ(3) METADATA FROM 'timestamp' VIRTUAL,
    -- Computed 列: 基于其他列计算
    event_date   AS CAST(event_time AS DATE),
    event_hour   AS EXTRACT(HOUR FROM event_time),
    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'format' = 'json'
);

-- Metadata 列的设计意义:
--   传统数据库中，行数据和系统元数据是分离的。
--   Flink 通过 METADATA 关键字将连接器的系统字段暴露为普通列。
--   VIRTUAL 表示只读（不写回连接器），省略 VIRTUAL 则可写。

-- ============================================================
-- 6. 其他建表模式
-- ============================================================
-- CTAS（不支持流模式，仅批模式）
CREATE TABLE users_backup AS SELECT * FROM users WHERE age > 18;

-- CREATE TABLE LIKE（复制 Schema）
CREATE TABLE user_events_copy (LIKE user_events);

-- TEMPORARY TABLE（会话级别）
CREATE TEMPORARY TABLE tmp_results (
    id    BIGINT,
    total DECIMAL(10,2)
) WITH (
    'connector' = 'blackhole'
);

-- ============================================================
-- 7. 横向对比: Flink vs 其他引擎的 CREATE TABLE
-- ============================================================
-- 1. 数据存储:
--   Flink: 不存储数据，表是外部系统的映射
--   DuckDB/MySQL/PostgreSQL: 表直接对应磁盘文件
--   Trino: 也不存储数据，但 DDL 取决于 Connector（如 Hive/Iceberg）
--   Databricks: Delta Lake 存储，自带 ACID 和 Time Travel

-- 2. 类型系统:
--   Flink: STRING（无长度限制）、BYTES、ROW、ARRAY、MAP、MULTISET
--   DuckDB: VARCHAR、LIST、STRUCT、MAP、UNION（PostgreSQL 兼容）
--   Trino:  VARCHAR、ROW（非 STRUCT）、ARRAY、MAP
--   Databricks: STRING、STRUCT、ARRAY、MAP

-- 3. 约束:
--   Flink: 只有 PRIMARY KEY NOT ENFORCED（语义提示）
--   DuckDB: PRIMARY KEY、UNIQUE、CHECK、NOT NULL（全部强制执行）
--   Trino: 无约束语法
--   Databricks: PRIMARY KEY/FOREIGN KEY（信息性，用于优化器提示）

-- 4. 自增/序列:
--   Flink: 无（ID 应由 Source 系统生成或用 UUID()）
--   DuckDB: SEQUENCE + nextval()
--   Trino: 无
--   Databricks: GENERATED ALWAYS AS IDENTITY

-- ============================================================
-- 8. 版本演进
-- ============================================================
-- Flink 1.9:  引入 Blink Planner（替代旧的 Flink Planner）
-- Flink 1.11: CREATE TABLE + WITH 语法稳定化，Watermark DDL 语法
-- Flink 1.12: Upsert Kafka、METADATA 列、CDC Connector（Debezium/Canal）
-- Flink 1.13: CREATE TABLE LIKE、STATEMENT SET（多 Sink 写入）
-- Flink 1.14: 流批一体优化，CTAS 支持（批模式）
-- Flink 1.16: Lookup Join Retry Hint、异步 Lookup
-- Flink 1.17: STATE_TTL Hint、Hybrid Source
-- Flink 1.18: CTAS 流模式支持（预览）、Retry Lookup 增强
-- Flink 1.19: 物化表（Materialized Table）预览，自动刷新
-- Flink 2.0:  移除旧 Planner，统一 DataStream/Table API
--
-- 对引擎开发者的参考:
--   Flink 的 DDL 演进展示了流处理引擎的发展路径:
--   先解决连接器抽象 → 再补充 CDC 和 Changelog → 最后走向流批统一。
--   WATERMARK 在 DDL 层面声明是 Flink 的创新，避免了 Spark 那样在 API 层配置的分散性。
