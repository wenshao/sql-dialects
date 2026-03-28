-- DuckDB: CREATE TABLE
--
-- 参考资料:
--   [1] DuckDB Documentation - CREATE TABLE
--       https://duckdb.org/docs/sql/statements/create_table
--   [2] DuckDB Documentation - Data Types
--       https://duckdb.org/docs/sql/data_types/overview
--   [3] DuckDB Documentation - Data Import
--       https://duckdb.org/docs/data/overview

-- ============================================================
-- 1. 基本语法
-- ============================================================
CREATE TABLE users (
    id         BIGINT       PRIMARY KEY,
    username   VARCHAR(64)  NOT NULL UNIQUE,
    email      VARCHAR(255) NOT NULL UNIQUE,
    age        INTEGER,
    balance    DECIMAL(10,2) DEFAULT 0.00,
    bio        VARCHAR,                         -- VARCHAR 无长度限制也可以
    created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 PostgreSQL 兼容语法: DuckDB 的核心设计选择
-- DuckDB 选择 PostgreSQL 方言作为语法基础，这是一个深思熟虑的设计决策。
--
-- 设计理由:
--   - PostgreSQL 是最接近 SQL 标准的主流数据库
--   - 大量数据分析师和工程师熟悉 PostgreSQL 语法
--   - 降低从 PostgreSQL 迁移到 DuckDB 的成本
--   - Python 生态中 PostgreSQL 是最常用的 RDBMS（SQLAlchemy 默认方言）
--
-- 但 DuckDB 不是 PostgreSQL 的复制品，关键差异:
--   - 无服务器架构（嵌入式，进程内运行）
--   - 列式存储（OLAP 优化，而非 OLTP）
--   - 无多用户并发控制（单写多读）
--   - 无 LISTEN/NOTIFY、无复制、无 WAL
--   - 扩展了 LIST/STRUCT/MAP/UNION 等分析型类型
--
-- 对比其他嵌入式数据库:
--   SQLite: 动态类型（弱类型），行存储，面向 OLTP，无并行查询
--   DuckDB: 强类型，列存储，面向 OLAP，向量化执行 + 并行查询
--   两者定位互补: SQLite=嵌入式 OLTP，DuckDB=嵌入式 OLAP
--
-- 对引擎开发者的启示:
--   选择语法方言是引擎设计的第一个重大决策。
--   MySQL 兼容 → 面向 Web 开发者（TiDB、OceanBase 的选择）
--   PostgreSQL 兼容 → 面向分析师/数据工程师（DuckDB、CockroachDB 的选择）
--   ANSI SQL → 面向企业市场（Trino、Spark SQL 的选择）

-- 2.2 无 AUTO_INCREMENT / SERIAL: 嵌入式 OLAP 的选择
-- DuckDB 不提供 AUTO_INCREMENT 关键字，需要用 SEQUENCE 模拟。
CREATE SEQUENCE users_id_seq START 1;
CREATE TABLE users_with_seq (
    id       BIGINT DEFAULT nextval('users_id_seq') PRIMARY KEY,
    username VARCHAR NOT NULL
);
-- 设计理由:
--   DuckDB 是分析引擎，数据通常通过 CTAS/COPY 批量加载而非逐行 INSERT。
--   SEQUENCE 是 PostgreSQL 标准做法（SERIAL 只是 SEQUENCE 的语法糖）。
--
-- 对比:
--   MySQL:      AUTO_INCREMENT（最简单，表级属性）
--   PostgreSQL: SERIAL → GENERATED AS IDENTITY（10+，SQL 标准推荐）
--   SQLite:     INTEGER PRIMARY KEY 自动成为 rowid
--   Databricks: GENERATED ALWAYS AS IDENTITY（不保证连续）
--   Flink:      无自增（ID 由 Source 系统生成）
--   Trino:      无自增（查询引擎不负责 ID 生成）

-- 2.3 无 ON UPDATE 触发器: 无 updated_at 自动更新
-- DuckDB 没有触发器（Trigger），因此无法自动更新 updated_at。
-- 这是 OLAP 引擎的常见限制: 分析负载以读为主，很少做单行 UPDATE。
--
-- 对比:
--   MySQL:      ON UPDATE CURRENT_TIMESTAMP（存储层内置）
--   PostgreSQL: 需要触发器函数
--   Databricks: 无触发器，可用 MERGE INTO 批量更新
--   Flink:      无 UPDATE 概念（流处理用 Changelog 语义）

-- ============================================================
-- 3. DuckDB 特有类型系统（分析引擎的优势）
-- ============================================================
CREATE TABLE complex_data (
    id       BIGINT PRIMARY KEY,
    tags     VARCHAR[],                                    -- LIST (动态数组)
    scores   INTEGER[3],                                   -- 固定大小 LIST
    address  STRUCT(street VARCHAR, city VARCHAR, zip VARCHAR),  -- 结构体
    meta     MAP(VARCHAR, VARCHAR),                         -- 键值对
    value    UNION(i INTEGER, s VARCHAR, f FLOAT)           -- 标签联合类型
);

-- 类型设计分析:
-- LIST（数组）: VARCHAR[] 或 LIST(VARCHAR)
--   - 与 PostgreSQL 数组语法兼容（INT[]）
--   - 支持嵌套: LIST(LIST(INT))
--   - 1-based 索引（list[1] 取第一个元素），与 PostgreSQL 一致
--
-- STRUCT（结构体）:
--   - 类似 JSON 但强类型，查询时编译期类型检查
--   - 使用点号访问: address.city
--   - 对比 Trino 的 ROW 类型（功能相同，名称不同）
--
-- MAP（映射）:
--   - Key 必须是同一类型，Value 必须是同一类型
--   - 使用 map['key'] 或 element_at(map, 'key') 访问
--
-- UNION（联合类型，DuckDB 独有）:
--   - 类似 TypeScript 的联合类型: number | string | null
--   - 存储时带标签指示当前存储的类型
--   - 其他数据库没有此类型（通常用 JSON 或 VARIANT 模拟）
--
-- 对比:
--   Flink:      ROW/ARRAY/MAP/MULTISET，无 UNION
--   Trino:      ROW/ARRAY/MAP，无 UNION
--   Databricks: STRUCT/ARRAY/MAP，无 UNION
--   BigQuery:   STRUCT/ARRAY，无 MAP/UNION
--   PostgreSQL: 数组/composite type，无原生 MAP/UNION

-- ============================================================
-- 4. 从文件直接建表: DuckDB 的杀手特性
-- ============================================================
-- CTAS + 文件读取（Schema 自动推断）
CREATE TABLE sales AS SELECT * FROM read_csv('sales.csv');
CREATE TABLE events AS SELECT * FROM read_parquet('events.parquet');
CREATE TABLE logs AS SELECT * FROM read_json('logs.json');

-- Glob 模式读取多文件
CREATE TABLE all_events AS SELECT * FROM read_parquet('data/events_*.parquet');

-- 远程文件（HTTP/S3）
CREATE TABLE remote_data AS SELECT * FROM read_parquet('s3://bucket/data.parquet');
CREATE TABLE http_data AS SELECT * FROM read_csv('https://example.com/data.csv');

-- 设计分析:
-- 这是 DuckDB 最革命性的设计: 模糊了"表"和"文件"的边界。
-- 传统数据库: 先建表 → 再 LOAD DATA → 再查询（三步）
-- DuckDB: 直接查文件 或 一步建表+导入（一步）
--
-- 关键实现:
--   - Schema 推断: 自动检测 CSV 列名/类型、Parquet 的 Schema
--   - 惰性求值: read_parquet 不立即加载全部数据
--   - 零拷贝: Apache Arrow 集成，与 Pandas/Polars 共享内存
--
-- 对比:
--   Spark SQL:  spark.read.parquet("path")（API，非 SQL）
--   Trino:      需要先配置 Hive/Iceberg Catalog
--   Databricks: COPY INTO 或 CREATE TABLE USING PARQUET LOCATION
--   Flink:      需要 filesystem connector + WITH 配置
--   PostgreSQL: COPY FROM（仅 CSV，无 Parquet 支持）
--   ClickHouse: file() 函数（类似，但不如 DuckDB 灵活）

-- ============================================================
-- 5. 其他建表模式
-- ============================================================
-- CREATE OR REPLACE
CREATE OR REPLACE TABLE users (id BIGINT PRIMARY KEY, username VARCHAR NOT NULL);

-- CREATE TABLE IF NOT EXISTS
CREATE TABLE IF NOT EXISTS users (id BIGINT PRIMARY KEY, username VARCHAR NOT NULL);

-- TEMPORARY TABLE（会话级别）
CREATE TEMP TABLE tmp_results AS SELECT * FROM users WHERE age > 30;

-- Generated Columns（虚拟列）
CREATE TABLE products (
    price    DECIMAL(10,2),
    quantity INTEGER,
    total    DECIMAL(10,2) GENERATED ALWAYS AS (price * quantity)
);

-- ENUM 类型
CREATE TYPE mood AS ENUM ('happy', 'sad', 'neutral');
CREATE TABLE diary (id BIGINT, entry VARCHAR, mood mood);

-- ============================================================
-- 6. 横向对比: DuckDB vs 其他引擎
-- ============================================================
-- 1. 运行模式:
--   DuckDB: 嵌入式（进程内），无需安装服务器，import duckdb 即可使用
--   MySQL/PostgreSQL: C/S 架构，需要独立服务器进程
--   SQLite: 嵌入式（OLTP），DuckDB 的 OLAP 对应物
--   Flink: 分布式集群部署
--   Trino: 分布式查询引擎（Coordinator + Worker）

-- 2. 约束执行:
--   DuckDB: PRIMARY KEY、UNIQUE、CHECK、NOT NULL、FOREIGN KEY 全部强制执行
--   MySQL/PostgreSQL: 同上（传统 RDBMS 标准行为）
--   Flink: 只有 NOT ENFORCED（语义提示）
--   Trino: 无约束
--   Databricks: PRIMARY KEY/FOREIGN KEY 信息性（不强制）

-- 3. DDL 事务性:
--   DuckDB: DDL 是事务性的（可以 BEGIN; CREATE TABLE; ROLLBACK;）
--   PostgreSQL: 同上
--   MySQL: DDL 隐式提交（不可回滚）
--   Flink: 无事务 DDL（DDL 立即生效）

-- ============================================================
-- 7. 版本演进
-- ============================================================
-- DuckDB 0.3 (2021): 初始稳定版，基本 SQL 支持
-- DuckDB 0.5 (2022): STRUCT/LIST/MAP 类型完善
-- DuckDB 0.8 (2023): UNION 类型、Generated Columns、并行 CSV 读取
-- DuckDB 0.9 (2023): ON CONFLICT、RETURNING、PIVOT/UNPIVOT
-- DuckDB 0.10 (2024): ATTACH 多数据库、固定大小 LIST
-- DuckDB 1.0 (2024-06): 首个稳定版本，存储格式向后兼容承诺
-- DuckDB 1.1 (2024-09): Community Extensions、COMMENT ON、FROM-first 查询
-- DuckDB 1.2 (2025-02): IEEE 754 浮点默认、CREATE SECRET、增强 JSON
-- DuckDB 1.3 (2025-05): 增量 Checkpoint、Lambda 函数增强
--
-- 对引擎开发者的参考:
--   DuckDB 展示了嵌入式 OLAP 引擎的设计路径:
--   先做好单机列存 + 向量化执行 → 再丰富类型系统 → 最后稳定存储格式（1.0）。
--   "文件即表"的设计理念打破了传统数据库的 ETL 范式。
