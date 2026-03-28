# Trino: CREATE TABLE

> 参考资料:
> - [Trino Documentation - CREATE TABLE](https://trino.io/docs/current/sql/create-table.html)
> - [Trino Documentation - Data Types](https://trino.io/docs/current/language/types.html)
> - [Trino Documentation - Connectors](https://trino.io/docs/current/connector.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

## 基本语法（取决于底层 Connector）

```sql
CREATE TABLE users (
    id         BIGINT,
    username   VARCHAR,
    email      VARCHAR,
    age        INTEGER,
    balance    DECIMAL(10,2),
    bio        VARCHAR,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

```

## 语法设计分析（对 SQL 引擎开发者）


### Connector 架构: Trino 的核心设计哲学

Trino（前身 PrestoSQL/PrestoDB）是纯查询引擎，不存储任何数据。
所有 DDL 操作的能力取决于底层 Connector 的实现。

三级命名空间: catalog.schema.table
  catalog = 一个 Connector 实例（对应一个数据源）
  schema  = 数据源中的 schema/database
  table   = 具体的表

核心 Connector:
  - Hive:     HDFS/S3 上的 Parquet/ORC/CSV/JSON 文件（最早最成熟）
  - Iceberg:  Apache Iceberg 表格式（推荐，功能最完善）
  - Delta:    Delta Lake 表格式
  - Hudi:     Apache Hudi 表格式
  - MySQL:    读写 MySQL 数据库
  - PostgreSQL: 读写 PostgreSQL 数据库
  - Memory:   内存表（测试用，重启丢失）
  - Kafka:    读取 Kafka Topic
  - MongoDB:  读写 MongoDB
  - Elasticsearch: 读取 Elasticsearch 索引

**设计 trade-off:**
  优点: 一个引擎查询所有数据源，支持跨源 JOIN（联邦查询）
  缺点: DDL 能力参差不齐（Memory 支持建表，Kafka 不支持建表）；
        性能取决于 Connector 的 pushdown 能力；无法控制底层存储布局

**对比:**
  Flink:      也有 Connector 架构，但配置在 DDL 的 WITH 子句中
  Spark SQL:  DataSource API（类似，但 Spark 有自己的存储层）
  DuckDB:     通过 Extensions 支持多数据源（但主要是嵌入式本地查询）
  Databricks: 主要面向 Delta Lake，外部数据通过 Unity Catalog 联邦访问
  传统 RDBMS:  只能访问本地存储，外部数据需要 ETL

**对引擎开发者的启示:**
  Connector 架构是构建联邦查询引擎的基础模式。
  关键设计决策: Connector 提供的是全量数据还是支持下推（filter/project pushdown）？
  下推越多，性能越好，但 Connector 实现复杂度越高。
  Trino 的 SPI（Service Provider Interface）设计值得学习。

### Hive Connector 建表（传统方式）

```sql
CREATE TABLE hive.mydb.users (
    id         BIGINT,
    username   VARCHAR,
    email      VARCHAR,
    age        INTEGER,
    created_at TIMESTAMP,
    dt         VARCHAR                         -- 分区列在列定义中声明
)
WITH (
    format = 'ORC',                            -- PARQUET, ORC, AVRO, JSON, CSV
    partitioned_by = ARRAY['dt'],              -- 引用已声明的列作为分区
    bucketed_by = ARRAY['id'],
    bucket_count = 256
);

```

Hive Connector 的 WITH 子句设计:
使用 key = value 语法（不是 'key' = 'value'，注意 Flink 是字符串键值对）
分区列必须先在列定义中声明，再在 WITH 中引用（Trino 特有约束）
**对比:** Hive DDL: PARTITIONED BY (dt STRING) 是在单独的子句中定义新列
Trino 的做法更接近 SQL 标准（所有列统一定义）

### Iceberg Connector 建表（推荐，功能最完善）

```sql
CREATE TABLE iceberg.mydb.orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2),
    order_date DATE
)
WITH (
    format = 'PARQUET',
    partitioning = ARRAY['month(order_date)'],   -- Iceberg 分区转换
    sorted_by = ARRAY['user_id']
);

```

Iceberg 分区转换（Hidden Partitioning，Iceberg 的创新）:
  year(col)           → 按年分区
  month(col)          → 按月分区
  day(col)            → 按天分区
  hour(col)           → 按小时分区
  bucket(N, col)      → Hash 分桶
  truncate(N, col)    → 截断值分区

**设计分析:**
  传统分区（Hive）: 用户必须显式管理分区列，查询时必须指定分区值
  Iceberg Hidden Partitioning: 分区对用户透明，查询引擎自动推导
  例: WHERE order_date = DATE '2024-03-15' → 自动定位 month=2024-03 分区

**对比:**
  Hive:       PARTITIONED BY (year INT, month INT)（用户管理，易出错）
  Databricks: PARTITIONED BY (order_date) 或 CLUSTER BY（Liquid Clustering）
  Flink:      PARTITIONED BY (dt, hr)（类似 Hive）
  DuckDB:     无分区概念（单机嵌入式，不需要分区）

## 无约束、无索引、无自增: 查询引擎的取舍

Trino 不支持:
  - PRIMARY KEY / UNIQUE / FOREIGN KEY / CHECK（无约束语法）
  - CREATE INDEX（无索引）
  - AUTO_INCREMENT / SEQUENCE / IDENTITY（无自增）
  - TRIGGER（无触发器）
  - STORED PROCEDURE（无存储过程）

**设计哲理:**
  Trino 是"查询引擎"而非"存储引擎"。约束、索引、触发器都是存储层的职责。
  Trino 只负责将 SQL 查询翻译为对底层存储的高效读写操作。

**对比:**
  Flink: 类似（不存储数据），但有 PRIMARY KEY NOT ENFORCED（语义提示）
  DuckDB: 全面支持约束和索引（因为它自己管理存储）
  Databricks: PRIMARY KEY 信息性，索引用 Liquid Clustering/Z-ORDER 替代
  BigQuery: PRIMARY KEY/FOREIGN KEY 信息性，无索引

**对引擎开发者的启示:**
  "查询引擎"和"存储引擎"的职责边界决定了 DDL 的支持范围。
  如果引擎不管理存储，约束和索引语法是不必要的。
  但 Flink 的 PRIMARY KEY NOT ENFORCED 模式证明: 即使不强制，
  语义信息对优化器也有价值。

## CTAS 与结构复制

CTAS（最常用的建表方式之一）
```sql
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > TIMESTAMP '2024-01-01 00:00:00';

```

WITH NO DATA（只复制结构，不复制数据）
```sql
CREATE TABLE users_empty AS SELECT * FROM users WITH NO DATA;
```

**对比:**
  MySQL: CREATE TABLE LIKE（复制结构+索引）
  PostgreSQL: CREATE TABLE ... (LIKE source INCLUDING ALL)
  DuckDB: CREATE TABLE LIKE 或 CTAS
  Databricks: CREATE TABLE LIKE 或 DEEP CLONE / SHALLOW CLONE

CREATE OR REPLACE（Iceberg Connector 支持）
```sql
CREATE OR REPLACE TABLE iceberg.mydb.users (id BIGINT, username VARCHAR);

```

其他 Connector
```sql
CREATE TABLE delta.mydb.events (
    id         BIGINT,
    event_type VARCHAR,
    event_time TIMESTAMP
) WITH (
    location = 's3://bucket/delta/events/',
    partitioned_by = ARRAY['event_type']
);

CREATE TABLE memory.default.temp (id BIGINT, name VARCHAR);

```

## 类型系统: ROW 而非 STRUCT

Trino 使用 ROW 类型（SQL 标准），而非 STRUCT（Spark/Databricks/DuckDB）
这是一个重要的术语差异:
  Trino: ROW(street VARCHAR, city VARCHAR)
  Spark:  STRUCT<street: STRING, city: STRING>
  DuckDB: STRUCT(street VARCHAR, city VARCHAR)
  Flink:  ROW<street STRING, city STRING>（也用 ROW）

ROW 类型的其他特点:
  - 字段访问: row_col.field_name（点号访问，与 STRUCT 相同）
  - 匿名 ROW: ROW(VARCHAR, INTEGER)（按位置访问，不推荐）
  - 嵌套: ROW(name VARCHAR, address ROW(city VARCHAR, zip VARCHAR))

完整类型列表:
BOOLEAN, TINYINT, SMALLINT, INTEGER, BIGINT
REAL, DOUBLE, DECIMAL(P,S)
VARCHAR, CHAR(N), VARBINARY
DATE, TIME, TIMESTAMP, TIMESTAMP WITH TIME ZONE
ARRAY(T), MAP(K,V), ROW(name T, ...)
JSON, UUID, IPADDRESS

## 联邦查询: 跨 Connector 建表

Trino 独有能力: 跨 Connector CTAS（联邦数据移动）
```sql
CREATE TABLE iceberg.analytics.user_orders AS
SELECT u.username, o.amount, o.order_date
FROM mysql.production.users u
JOIN hive.warehouse.orders o ON u.id = o.user_id
WHERE o.order_date > DATE '2024-01-01';

```

一条 SQL 实现: MySQL → Hive JOIN → 写入 Iceberg
这是 Trino 作为联邦查询引擎的核心价值

## 版本演进

PrestoDB 0.69 (2014): Facebook 开源 Presto
PrestoSQL (2019-01): Presto 创始人 fork → 独立项目
Trino 351 (2020-12): PrestoSQL 更名为 Trino（商标原因）
Trino 390+ (2022):   Iceberg Connector 成熟，支持 MERGE/UPDATE/DELETE
Trino 400+ (2023):   Fault-tolerant execution（失败重试）、Polymorphic Table Functions
Trino 430+ (2024):   JSON_TABLE、增强 Iceberg 支持、OpenTelemetry 集成
Trino 450+ (2025):   改进的动态过滤、增强的 Task 级调度

**对引擎开发者:** 的参考:
  Trino 的成功证明了"不存储数据的查询引擎"是一个可行的架构。
  关键是 SPI（Service Provider Interface）设计足够灵活，让第三方可以实现 Connector。
  Presto → PrestoSQL → Trino 的分裂也警示:
  开源项目的治理结构（谁拥有商标？）比技术架构更重要。
