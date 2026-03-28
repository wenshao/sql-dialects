# Amazon Redshift: CREATE TABLE

> 参考资料:
> - [Redshift CREATE TABLE](https://docs.aws.amazon.com/redshift/latest/dg/r_CREATE_TABLE_NEW.html)
> - [Redshift Distribution Styles](https://docs.aws.amazon.com/redshift/latest/dg/c_choosing_dist_sort.html)
> - [Redshift Column Compression Encodings](https://docs.aws.amazon.com/redshift/latest/dg/c_Compression_Encodings.html)


## 1. 基本语法

```sql
CREATE TABLE users (
    id         BIGINT IDENTITY(1, 1),
    username   VARCHAR(64) NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        INTEGER,
    balance    DECIMAL(10, 2) DEFAULT 0.00,
    bio        VARCHAR(65535),
    created_at TIMESTAMP NOT NULL DEFAULT GETDATE(),
    updated_at TIMESTAMP NOT NULL DEFAULT GETDATE(),
    PRIMARY KEY (id)
)
DISTSTYLE KEY
DISTKEY (id)
SORTKEY (created_at);
```


## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 DISTKEY/DISTSTYLE: 数据分布策略（Redshift 核心设计）

Redshift 最独特的设计是建表时显式声明数据如何分布到各计算节点的 Slice。
分布策略直接决定了 JOIN 和聚合的性能（数据是否需要跨节点传输）。

四种分布样式:
EVEN:  轮询分配到所有 Slice（默认）。简单但 JOIN 时需要 Redistribution。
KEY:   按指定列的 Hash 值分配。相同 DISTKEY 值的行在同一 Slice。
JOIN 两张表时如果 DISTKEY 相同 → 本地 JOIN，零网络开销。
ALL:   每个节点存一份完整拷贝。适合小维度表（<= 数百万行）。
JOIN 时维度表永远是本地的，但写入放大 N 倍（N=节点数）。
AUTO:  Redshift 自动选择（2019+）。小表先用 ALL，增长后切 EVEN。

**设计 trade-off:**
- **优点**:  用户显式控制数据分布，性能可预测，DBA 可深度优化
- **缺点**:  新手容易选错 DISTKEY 导致数据倾斜(skew)，修改 DISTKEY 需要全表重建

**对比其他引擎的数据分布:**

BigQuery:    不暴露分布策略（内部自动管理），用户零负担但无法手动优化
Snowflake:   自动微分区（micro-partition），无 DISTKEY 概念
ClickHouse:  Distributed 引擎 + sharding_key（类似 DISTKEY 但更灵活）
Doris/SR:    DISTRIBUTED BY HASH(col) BUCKETS N（语法类似但多了 bucket 数）
PostgreSQL:  单机无分布（Citus 扩展用 distribution column）

**对引擎开发者的启示:**

OLAP 引擎的分布策略设计是核心决策:
暴露给用户 = 性能可控但增加使用门槛（Redshift 路线）
自动管理 = 用户友好但极端场景无法手动优化（BigQuery/Snowflake 路线）
推荐: 默认自动 + 提供 hint 级手动控制（两全其美）

DISTSTYLE EVEN
```sql
CREATE TABLE logs (
    id         BIGINT IDENTITY(1, 1),
    message    VARCHAR(4096),
    created_at TIMESTAMP DEFAULT GETDATE()
) DISTSTYLE EVEN;
```


DISTSTYLE ALL（小维度表）
```sql
CREATE TABLE countries (
    code CHAR(2) NOT NULL,
    name VARCHAR(100) NOT NULL
) DISTSTYLE ALL;
```


DISTSTYLE AUTO（推荐）
```sql
CREATE TABLE orders (
    id         BIGINT IDENTITY(1, 1),
    user_id    BIGINT NOT NULL,
    amount     DECIMAL(10, 2),
    order_date DATE
) DISTSTYLE AUTO;
```


### 2.2 SORTKEY: 物理排序决定查询性能

SORTKEY 决定数据在磁盘上的物理排列顺序，直接影响 Zone Map 过滤效率。
Redshift 没有传统索引(B-Tree)，完全依赖 Zone Map + SORTKEY 实现谓词过滤。

Zone Map: 每个 1MB 数据块记录每列的 min/max 值。
查询 WHERE created_at > '2024-01-01' 时:
如果 SORTKEY = created_at: Zone Map 可以精确跳过无关块 → 极快
如果无 SORTKEY: 必须扫描所有块的 Zone Map → 效率差

两种 SORTKEY:
COMPOUND（默认）: 按列顺序优先级排序。第一列最有效，后续列依次递减。
INTERLEAVED:      所有列等权排序。多列过滤更均匀，但 VACUUM 成本 4x+。
AWS 已不推荐新表使用 INTERLEAVED（2021+）。
AUTO:             Redshift 自动管理排序。

复合排序键（COMPOUND）
```sql
CREATE TABLE events (
    id         BIGINT IDENTITY(1, 1),
    event_type VARCHAR(50),
    event_date DATE,
    user_id    BIGINT
) SORTKEY (event_date, event_type);
```


自动排序键
```sql
CREATE TABLE auto_sorted (
    id   BIGINT IDENTITY(1, 1),
    data VARCHAR(256)
) SORTKEY AUTO;
```


### 2.3 ENCODE: 列压缩编码

Redshift 是列存引擎，每列独立压缩。选择正确的编码可减少 60-90% 存储。
RAW:      不压缩（排序键默认）
AZ64:     Amazon 专有编码（推荐用于整数/日期/时间戳）
ZSTD:     Zstandard 压缩（推荐用于 VARCHAR/CHAR）
LZO:      较老的压缩，ZSTD 通常更好
BYTEDICT: 字典编码（低基数列，如 status/category）
RUNLENGTH: 连续相同值压缩（排序后的低基数列效果极佳）
DELTA:    差值编码（递增整数列，如自增ID/时间戳）
```sql
CREATE TABLE compressed (
    id         BIGINT IDENTITY(1, 1) ENCODE RAW,
    name       VARCHAR(100) ENCODE ZSTD,
    status     SMALLINT ENCODE AZ64,
    amount     DECIMAL(10,2) ENCODE AZ64,
    notes      VARCHAR(1000) ENCODE ZSTD,
    created_at TIMESTAMP ENCODE AZ64
);
```


## 3. 外部表与 Spectrum

Redshift Spectrum: 直接查询 S3 上的数据（Parquet/ORC/CSV/JSON）。
核心价值: 冷数据放 S3（成本低 10x），热数据放 Redshift，统一查询。

```sql
CREATE EXTERNAL SCHEMA spectrum_schema
FROM DATA CATALOG
DATABASE 'my_glue_db'
IAM_ROLE 'arn:aws:iam::123456789012:role/MySpectrumRole';

CREATE EXTERNAL TABLE spectrum_schema.external_events (
    id         BIGINT,
    event_type VARCHAR(50),
    event_date DATE
)
STORED AS PARQUET
LOCATION 's3://my-bucket/events/';
```


分区外部表（按日期目录分区）
```sql
CREATE EXTERNAL TABLE spectrum_schema.partitioned_logs (
    id      BIGINT,
    message VARCHAR(4096)
)
PARTITIONED BY (log_date DATE)
STORED AS PARQUET
LOCATION 's3://my-bucket/logs/';
```


**对比其他引擎的外部表:**

BigQuery:    外部表 + Federated Query（类似但更自动化）
Snowflake:   External Stage + External Table
Databricks:  Unity Catalog + External Locations
ClickHouse:  S3 Table Function / s3 Engine
Hive:        外部表是核心概念（EXTERNAL TABLE + LOCATION）

## 4. SUPER 类型与 CTAS

SUPER: 半结构化数据类型（2020+），Redshift 的 JSON 方案。
```sql
CREATE TABLE events_json (
    id   BIGINT IDENTITY(1, 1),
    data SUPER
);
```


CTAS（CREATE TABLE AS）: 可在 CTAS 中指定分布和排序
```sql
CREATE TABLE users_summary
DISTSTYLE KEY DISTKEY (city) SORTKEY (cnt) AS
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users GROUP BY city;
```


## 5. 限制与注意事项（基于 PostgreSQL 8.0.2 的代价）

无 B-Tree 索引: 完全依赖 Zone Map（列存引擎不需要行级索引）
无 SERIAL: 用 IDENTITY(seed, step) 替代
VARCHAR 最大 65535 字节（不是字符）— 无 TEXT 类型
无 ARRAY / UUID / JSONB 等现代 PostgreSQL 类型
无 CTE 递归 (WITH RECURSIVE): 不支持（PostgreSQL 8.x 限制）
无窗口函数 FILTER 子句
外键/唯一约束: 定义但不强制执行（信息性约束，优化器使用）
主键: 强制执行唯一性
无触发器、有限的存储过程支持

## 6. 版本演进

2012:    Redshift 发布（基于 ParAccel / PostgreSQL 8.0.2）
2017:    Redshift Spectrum (S3 外部表)
2018:    弹性扩缩容(Elastic Resize)，自动 WLM
2019:    AQUA（高级查询加速器），自动物化视图
2020:    SUPER 类型，联邦查询(Federated Query)
2021:    RA3 节点（存算分离），数据共享(Data Sharing)
2022:    Redshift Serverless GA，流式摄入(Streaming Ingestion)
2023:    零 ETL 集成（Aurora→Redshift），多数据仓库写入
2024:    AI 驱动的自动优化，零 ETL 扩展到 DynamoDB
2025:    多集群自动扩缩，增强的半结构化数据处理

## 7. 横向对比: Redshift vs 其他 OLAP 引擎

1. 架构:
Redshift:   MPP + 列存，传统 data warehouse 架构
BigQuery:   Serverless，存算完全分离，按查询付费
Snowflake:  存算分离，虚拟仓库(Virtual Warehouse)，按使用付费
ClickHouse: MPP + 列存 + MergeTree，OLAP 实时分析
Databricks: Lakehouse，Delta Lake + Spark

2. 数据分布:
Redshift:   DISTKEY（用户手动选择或 AUTO）
BigQuery:   自动管理（用户无需关心）
Snowflake:  自动微分区（用户无需关心）
ClickHouse: sharding_key + Distributed 引擎

3. 半结构化数据:
Redshift:   SUPER 类型 + PartiQL 查询（2020+）
BigQuery:   STRUCT/ARRAY（原生嵌套类型）
Snowflake:  VARIANT 类型（最灵活）
ClickHouse: JSON 类型（实验性），嵌套 Nested 类型
