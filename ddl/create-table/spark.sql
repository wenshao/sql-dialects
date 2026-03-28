-- Spark SQL: CREATE TABLE
--
-- 参考资料:
--   [1] Spark SQL Reference - CREATE TABLE
--       https://spark.apache.org/docs/latest/sql-ref-syntax-ddl-create-table.html
--   [2] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html
--   [3] Delta Lake Documentation
--       https://docs.delta.io/latest/delta-batch.html
--   [4] Spark SQL - DataSource V2
--       https://spark.apache.org/docs/latest/sql-data-sources.html

-- ============================================================
-- 1. 基本语法: Managed Table（Spark 管理数据 + 元数据）
-- ============================================================
CREATE TABLE users (
    id         BIGINT,
    username   STRING,
    email      STRING,
    age        INT,
    balance    DECIMAL(10,2),
    bio        STRING,
    created_at TIMESTAMP
)
USING PARQUET;

-- ============================================================
-- 2. USING 子句: Spark SQL 最核心的建表设计
-- ============================================================

-- 2.1 设计哲学: 数据源即存储格式
-- USING 子句是 Spark SQL 相对于传统数据库最独特的建表设计。它通过 DataSource API
-- 将"存储格式"提升为建表的一等公民，与 MySQL 的 ENGINE 概念有本质区别:
--   MySQL ENGINE:   选择不同的存储引擎（InnoDB/MyISAM），引擎决定索引、锁、事务
--   Hive STORED AS: 选择文件格式（ORC/Parquet/TextFile），但仅限 Hive 内置格式
--   Spark USING:    通过 DataSource API v2 支持任意数据源，包括文件格式和外部系统
--
-- 设计 trade-off:
--   优点: 极大的灵活性——一条 SQL 可以读写 Parquet、Delta、Iceberg、JDBC、Kafka 等
--   缺点: 不同数据源的能力差异巨大（如 Parquet 不支持 UPDATE，Delta 支持）
--         用户必须了解底层格式才能写出正确的 SQL，增加了认知负担
--
-- 对比:
--   Hive:       STORED AS ORC/PARQUET/TEXTFILE（仅文件格式，不支持插件式扩展）
--   Flink SQL:  WITH ('connector' = 'kafka') 通过属性指定连接器
--   Trino:      通过 Catalog 概念区分数据源（hive.schema.table / mysql.schema.table）
--   MaxCompute: 无 USING，固定内部列式存储

-- 2.2 常见数据源格式
CREATE TABLE logs_parquet (ts TIMESTAMP, msg STRING) USING PARQUET;
CREATE TABLE logs_orc    (ts TIMESTAMP, msg STRING) USING ORC;
CREATE TABLE logs_csv    (ts TIMESTAMP, msg STRING) USING CSV
    OPTIONS (header 'true', inferSchema 'true', path '/data/logs.csv');
CREATE TABLE logs_json   (ts TIMESTAMP, msg STRING) USING JSON
    OPTIONS (path '/data/logs.json');

-- 2.3 Delta Lake 表（Databricks / OSS Delta Lake）
CREATE TABLE users_delta (
    id       BIGINT,
    username STRING,
    email    STRING
) USING DELTA
LOCATION '/delta/users';

-- 2.4 Iceberg 表（Spark 3.0+ with Iceberg catalog）
CREATE TABLE catalog.db.users_ice (
    id       BIGINT,
    username STRING,
    email    STRING
) USING ICEBERG
PARTITIONED BY (bucket(16, id));

-- 对引擎开发者的启示:
--   Spark 的 DataSource API 证明了"可插拔数据源"的价值。如果你的引擎需要对接多种
--   外部存储，DataSource V2（Spark 3.0+）的 Catalog + Table + ScanBuilder 三层
--   抽象是优秀的参考设计。Flink SQL 的 Connector 体系也采用了类似思路。

-- ============================================================
-- 3. Managed vs External: 数据所有权模型
-- ============================================================

-- Managed Table: Spark 管理数据生命周期，DROP TABLE 删除数据文件
CREATE TABLE managed_users (id BIGINT, name STRING) USING PARQUET;

-- External Table: Spark 仅管理元数据，DROP TABLE 不删除数据
CREATE TABLE external_logs (log_date STRING, message STRING, level STRING)
USING PARQUET
LOCATION '/data/logs/';

-- 对比:
--   Hive:      同样区分 Managed/External（语义完全一致，Spark 继承自 Hive）
--   Trino:     通过 Catalog 类型区分（Hive Connector 继承此语义）
--   BigQuery:  外部表通过 CREATE EXTERNAL TABLE 显式声明
--   MaxCompute: 也区分内部表和外部表（与 Hive 语义对齐）
--
-- 对引擎开发者的启示:
--   数据所有权模型是数据湖引擎的基础设计决策。Spark 继承 Hive 的 Managed/External
--   二分法已成为事实标准。但 Delta Lake/Iceberg 的出现模糊了这一界限——即使是
--   External 表也可以有 ACID 事务。

-- ============================================================
-- 4. 分区与分桶: 数据布局优化
-- ============================================================

-- 4.1 分区表（Hive 风格目录分区）
CREATE TABLE orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    order_date DATE
) USING PARQUET
PARTITIONED BY (order_date);
-- 物理布局: /warehouse/orders/order_date=2024-01-15/part-00000.parquet

-- 4.2 分桶表（Hash 分布，优化 JOIN）
CREATE TABLE user_events (
    user_id    BIGINT,
    event_type STRING,
    ts         TIMESTAMP
) USING PARQUET
CLUSTERED BY (user_id) SORTED BY (ts) INTO 32 BUCKETS;

-- 对比 Hive/Spark 分区 vs 传统数据库分区:
--   Spark/Hive: 分区 = 文件系统目录，分区列不在数据文件中（目录名包含分区值）
--   MySQL:      分区 = 引擎内部数据组织，分区键必须在主键中
--   PostgreSQL: 分区 = 独立子表，通过继承或声明式分区实现
--   ClickHouse: PARTITION BY 表达式灵活，但也是目录级别
--   Iceberg:    Hidden Partitioning——分区对用户透明，通过 transforms 定义
--
-- 设计启示:
--   目录级分区的核心价值是 partition pruning（文件系统级别跳过整个目录）。
--   但分区键基数不能太高（>10000 个分区会导致小文件问题和 Metastore 压力）。
--   Iceberg 的 Hidden Partitioning 是更优雅的设计——用户不需要感知分区列。

-- ============================================================
-- 5. CTAS 与 REPLACE TABLE
-- ============================================================

-- CTAS (Create Table As Select)
CREATE TABLE active_users AS
SELECT * FROM users WHERE age >= 18;

-- 带格式和分区的 CTAS
CREATE TABLE top_users
USING DELTA
PARTITIONED BY (city)
AS SELECT * FROM users WHERE age > 25;

-- REPLACE TABLE（Spark 3.0+, Delta Lake）
CREATE OR REPLACE TABLE users_v2 (
    id       BIGINT,
    username STRING
) USING DELTA;

-- 对比:
--   BigQuery: CTAS 是最常用的建表方式（不推荐空表 DDL + INSERT 模式）
--   Hive:     CTAS 支持但不复制分区定义，需显式指定
--   Trino:    CREATE TABLE AS 广泛使用
--   MySQL:    CREATE TABLE ... SELECT 存在，但不复制索引和约束

-- ============================================================
-- 6. 临时视图（Spark 没有临时表，只有临时视图）
-- ============================================================

CREATE TEMPORARY VIEW tmp_users AS
SELECT * FROM users WHERE age >= 18;

CREATE OR REPLACE TEMP VIEW tmp_users AS
SELECT * FROM users WHERE age >= 18;

-- 全局临时视图（同一 SparkApplication 内跨 SparkSession 可见）
CREATE GLOBAL TEMPORARY VIEW global_users AS
SELECT * FROM users;
-- 访问: SELECT * FROM global_temp.global_users;

-- 设计分析:
--   Spark 使用临时视图而非临时表，根本原因是 Spark 是"计算引擎而非存储引擎"。
--   临时视图只保存查询定义（逻辑计划），不物化数据。如需物化，用 CACHE TABLE。
--   PostgreSQL/MySQL 的 CREATE TEMP TABLE 创建真正的临时存储；Spark 的等价物
--   是 df.cache() 或 CACHE TABLE。

-- ============================================================
-- 7. 表属性与注释
-- ============================================================
CREATE TABLE users_full (
    id       BIGINT COMMENT '主键，业务系统生成',
    username STRING COMMENT '用户名，业务唯一'
) USING PARQUET
COMMENT '用户账户表'
TBLPROPERTIES ('creator' = 'data_team', 'version' = '2.0');

CREATE TABLE IF NOT EXISTS audit_log (
    id       BIGINT,
    action   STRING,
    ts       TIMESTAMP
) USING DELTA;

-- ============================================================
-- 8. Spark SQL 建表的根本约束（对引擎开发者）
-- ============================================================

-- 8.1 无主键 / 无唯一约束 / 无自增
-- 原生 Spark SQL 不支持 PRIMARY KEY、UNIQUE、AUTO_INCREMENT。
-- 根本原因: Spark 是分布式批处理引擎，全局唯一性检查代价极高。
-- Delta Lake 3.0+ 增加了信息性 PK/FK（不强制执行，用于优化器提示）。
-- 自增替代: monotonically_increasing_id()（不连续）或 ROW_NUMBER()（需全排序）。

-- 8.2 无 NOT NULL 以外的强制约束（原生 Spark）
-- NOT NULL 是唯一在写入时强制检查的约束（Spark 3.0+）。
-- CHECK 约束仅 Delta Lake 支持（写入时强制检查）。
-- 这与 BigQuery/Snowflake 的"信息性约束"理念一致——分布式系统中约束执行代价太高。

-- 8.3 STRING 统一字符串类型
-- Spark 推荐使用 STRING 而非 VARCHAR/CHAR。VARCHAR(n) 在 3.1 之前被静默忽略。
-- 这是大数据引擎的通用做法: ClickHouse 用 String，BigQuery 用 STRING。
-- 传统数据库的 VARCHAR(n) 长度限制主要服务于存储优化（内存分配），
-- 在列式存储引擎中意义不大。

-- 对引擎开发者的总结:
--   Spark 的 CREATE TABLE 设计围绕"数据源 + 文件格式"而非"存储引擎 + 索引"。
--   这是批处理引擎与 OLTP 引擎的根本差异。如果你在设计数据湖引擎，
--   Spark 的 DataSource V2 API 是最值得参考的抽象层设计。
--   如果你在设计 Lakehouse 引擎，Delta Lake/Iceberg 在 Spark 之上补全了
--   ACID、约束、UPDATE/DELETE 等能力的方式，是"计算存储分离"架构的典范。

-- ============================================================
-- 9. 版本演进
-- ============================================================
-- Spark 1.0: DataFrame API + SQL 支持，USING 子句
-- Spark 2.0: 统一 DataFrame/Dataset，Structured Streaming
-- Spark 2.4: DEFAULT 值（有限）、高阶函数
-- Spark 3.0: DataSource V2 API、REPLACE TABLE、ANSI 模式（默认关闭）
-- Spark 3.1: VARCHAR(n)/CHAR(n) 强制长度、DROP COLUMN
-- Spark 3.4: DEFAULT 列值、TIMESTAMP_NTZ、递归 CTE（实验性）
-- Spark 4.0: ANSI 模式默认开启、Variant 类型、Collation 支持
