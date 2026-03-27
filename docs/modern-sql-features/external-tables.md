# 外部表 / SQL 查数据湖

用 SQL 直接查询数据库外部的文件——从 Hive EXTERNAL TABLE 到现代 Lakehouse 架构的演进。

## 支持矩阵

| 引擎 | 特性 | 数据源 | 备注 |
|------|------|--------|------|
| Hive | EXTERNAL TABLE | HDFS, S3 | **最早的大规模实践** |
| BigQuery | External Tables | GCS, Drive, Bigtable, S3 | 联邦查询 |
| Snowflake | External Tables | S3, Azure Blob, GCS | 只读 |
| Trino/Presto | Connector 架构 | 几乎任何数据源 | 最灵活 |
| Oracle | External Tables | 本地文件 | 9iR2+, SQL*Loader 格式 |
| SQL Server | PolyBase / OPENROWSET | S3, ADLS, Oracle, HDFS | 2016+ |
| Redshift | Spectrum | S3 | 通过外部 Schema |
| DuckDB | read_csv / read_parquet | 本地文件, S3, HTTP | 函数式接口 |
| Spark SQL | DataSource API | 任何数据源 | 可编程扩展 |
| ClickHouse | 表引擎 (S3, URL, File) | S3, HTTP, 本地文件 | 引擎即数据源 |
| MySQL | CSV 引擎 / FEDERATED | 本地 CSV, 远程 MySQL | 功能有限 |
| PostgreSQL | FDW (Foreign Data Wrapper) | 任何数据源 | 可编程扩展 |

## 设计动机

### 传统方式: ETL 先行

```
外部文件 (CSV/Parquet/JSON)
    ↓ ETL 工具导入
数据库表
    ↓ SQL 查询
结果
```

问题：导入耗时长、占用存储、数据可能过期。

### 外部表方式: 查询时读取

```
外部文件 (CSV/Parquet/JSON)
    ↓ 外部表定义（元数据）
SQL 查询直接读取
    ↓
结果
```

优势：零拷贝、数据始终最新、存储与计算分离。

## 各引擎语法对比

### Hive EXTERNAL TABLE（最早的大规模实践）

```sql
-- Hive 区分 MANAGED TABLE 和 EXTERNAL TABLE
-- MANAGED: Hive 管理数据生命周期，DROP TABLE 删除数据
-- EXTERNAL: Hive 只管理元数据，DROP TABLE 不删除数据

-- 创建外部表: CSV 格式
CREATE EXTERNAL TABLE access_logs (
    ip_address STRING,
    request_time TIMESTAMP,
    method STRING,
    url STRING,
    status_code INT
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 's3://data-lake/access-logs/';

-- 创建外部表: Parquet 格式（更常见）
CREATE EXTERNAL TABLE events (
    event_id BIGINT,
    user_id BIGINT,
    event_type STRING,
    event_time TIMESTAMP
)
STORED AS PARQUET
LOCATION 's3://data-lake/events/';

-- 分区外部表
CREATE EXTERNAL TABLE events_partitioned (
    event_id BIGINT,
    user_id BIGINT,
    event_type STRING
)
PARTITIONED BY (dt STRING)
STORED AS PARQUET
LOCATION 's3://data-lake/events/';

-- 手动添加分区（指向已有数据）
ALTER TABLE events_partitioned ADD PARTITION (dt='2024-03-01')
    LOCATION 's3://data-lake/events/dt=2024-03-01/';

-- 自动发现分区
MSCK REPAIR TABLE events_partitioned;
```

### BigQuery External Tables

```sql
-- 从 GCS 创建外部表
CREATE EXTERNAL TABLE dataset.external_events
OPTIONS (
    format = 'PARQUET',
    uris = ['gs://my-bucket/events/*.parquet']
);

-- CSV 格式，指定 schema
CREATE EXTERNAL TABLE dataset.csv_logs (
    ip STRING,
    timestamp TIMESTAMP,
    status INT64
)
OPTIONS (
    format = 'CSV',
    uris = ['gs://my-bucket/logs/*.csv'],
    skip_leading_rows = 1
);

-- BigLake 表: 统一的数据湖访问（支持行级安全、列级安全）
CREATE EXTERNAL TABLE dataset.biglake_events
WITH CONNECTION `project.region.connection-id`
OPTIONS (
    format = 'PARQUET',
    uris = ['gs://my-bucket/events/*']
);

-- 从 Google Drive 查询
CREATE EXTERNAL TABLE dataset.sheets_data
OPTIONS (
    format = 'GOOGLE_SHEETS',
    uris = ['https://docs.google.com/spreadsheets/d/xxx'],
    sheet_range = 'Sheet1'
);
```

### Snowflake External Tables

```sql
-- 1. 创建 Stage（指向外部存储）
CREATE STAGE my_s3_stage
    URL = 's3://my-bucket/data/'
    CREDENTIALS = (AWS_KEY_ID = '...' AWS_SECRET_KEY = '...');

-- 2. 创建外部表
CREATE EXTERNAL TABLE ext_events (
    event_id NUMBER AS (value:event_id::NUMBER),
    user_id NUMBER AS (value:user_id::NUMBER),
    event_type VARCHAR AS (value:event_type::VARCHAR),
    event_time TIMESTAMP AS (value:event_time::TIMESTAMP)
)
WITH LOCATION = @my_s3_stage/events/
FILE_FORMAT = (TYPE = PARQUET);

-- 外部表自动推断 Parquet schema
CREATE EXTERNAL TABLE ext_auto
WITH LOCATION = @my_s3_stage/events/
FILE_FORMAT = (TYPE = PARQUET)
AUTO_REFRESH = TRUE;           -- 自动刷新元数据

-- 分区外部表
CREATE EXTERNAL TABLE ext_partitioned (
    dt DATE AS (TO_DATE(SPLIT_PART(metadata$filename, '/', 3), 'YYYY-MM-DD'))
)
PARTITION BY (dt)
WITH LOCATION = @my_s3_stage/events/
FILE_FORMAT = (TYPE = PARQUET);

-- 注意: Snowflake 外部表是只读的
-- 要修改数据，需要 COPY INTO 导入为内部表
```

### Trino/Presto Connector 架构

```sql
-- Trino 通过 Connector 抽象统一所有数据源
-- 每个 Catalog 对应一个 Connector 实例

-- 查询 Hive 数据湖（Hive Connector）
SELECT * FROM hive.default.events WHERE dt = '2024-03-01';

-- 查询 MySQL（MySQL Connector）
SELECT * FROM mysql.mydb.users WHERE active = true;

-- 跨数据源 JOIN（Trino 的核心能力）
SELECT u.name, COUNT(e.event_id)
FROM mysql.mydb.users u
JOIN hive.default.events e ON u.id = e.user_id
GROUP BY u.name;

-- Iceberg Connector
SELECT * FROM iceberg.db.events WHERE dt = '2024-03-01';

-- Delta Lake Connector
SELECT * FROM delta.db.events;

-- Connector 的统一接口:
-- ConnectorMetadata: 获取表/列/分区信息
-- ConnectorSplitManager: 将数据分片
-- ConnectorPageSourceProvider: 读取数据页
-- ConnectorRecordSetProvider: 读取记录集
```

### Oracle External Tables

```sql
-- Oracle 9iR2+ 支持外部表
CREATE TABLE ext_employees (
    emp_id NUMBER,
    name VARCHAR2(100),
    dept VARCHAR2(50),
    salary NUMBER
)
ORGANIZATION EXTERNAL (
    TYPE ORACLE_LOADER
    DEFAULT DIRECTORY ext_data_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE
        FIELDS TERMINATED BY ','
        MISSING FIELD VALUES ARE NULL
        (emp_id, name, dept, salary)
    )
    LOCATION ('employees.csv')
)
REJECT LIMIT UNLIMITED;

-- Oracle 12c+: ORACLE_HDFS 和 ORACLE_HIVE 类型
-- 可以直接查询 HDFS 和 Hive 数据
```

### SQL Server PolyBase

```sql
-- SQL Server 2016+ PolyBase
-- 1. 创建外部数据源
CREATE EXTERNAL DATA SOURCE my_s3
WITH (
    TYPE = HADOOP,
    LOCATION = 's3://my-bucket/'
);

-- 2. 创建外部文件格式
CREATE EXTERNAL FILE FORMAT parquet_format
WITH (FORMAT_TYPE = PARQUET);

-- 3. 创建外部表
CREATE EXTERNAL TABLE ext_events (
    event_id BIGINT,
    user_id BIGINT,
    event_type NVARCHAR(50)
)
WITH (
    LOCATION = '/events/',
    DATA_SOURCE = my_s3,
    FILE_FORMAT = parquet_format
);

-- SQL Server 2022+: OPENROWSET 直接查询
SELECT * FROM OPENROWSET(
    BULK 's3://my-bucket/events/*.parquet',
    FORMAT = 'PARQUET'
) AS events;
```

### Redshift Spectrum

```sql
-- Redshift Spectrum 通过外部 Schema 查询 S3
CREATE EXTERNAL SCHEMA spectrum_schema
FROM DATA CATALOG
DATABASE 'my_glue_db'
IAM_ROLE 'arn:aws:iam::123456789:role/MySpectrumRole';

-- 直接查询 S3 数据（通过 Glue Catalog 元数据）
SELECT event_type, COUNT(*)
FROM spectrum_schema.events
WHERE dt = '2024-03-01'
GROUP BY event_type;

-- Spectrum 的优势: 计算在独立的 Spectrum 层，不占 Redshift 集群资源
-- 可以与内部表 JOIN
SELECT u.name, COUNT(e.event_id)
FROM internal_schema.users u
JOIN spectrum_schema.events e ON u.id = e.user_id
GROUP BY u.name;
```

### DuckDB（最轻量级的实现）

```sql
-- DuckDB 用函数式接口直接查询文件，无需定义外部表

-- 读取本地 CSV
SELECT * FROM read_csv('data/events.csv', header=true);

-- 读取 Parquet（本地或 S3）
SELECT * FROM read_parquet('s3://my-bucket/events/*.parquet');

-- 读取 JSON
SELECT * FROM read_json('data/events.json');

-- Glob 模式匹配
SELECT * FROM read_parquet('data/events/year=*/month=*/*.parquet',
    hive_partitioning=true);

-- 直接 ATTACH 其他数据库
ATTACH 'postgres://user:pass@host/db' AS pg (TYPE postgres);
SELECT * FROM pg.public.users;

-- 创建视图（给外部数据一个稳定的名字）
CREATE VIEW events AS
SELECT * FROM read_parquet('s3://my-bucket/events/*.parquet');

-- DuckDB 的核心优势: 零配置、零依赖、嵌入式
```

## 演进: 从 Hive MetaStore 到现代表格式

```
阶段 1: Hive MetaStore (2010s)
├── 元数据集中管理（表、分区、列信息）
├── 数据在 HDFS/S3 上，格式为 Parquet/ORC
├── 问题: 元数据与数据不一致、无 ACID、schema 变更困难

阶段 2: 开放表格式 (2018+)
├── Apache Iceberg (Netflix, 2018)
│   ├── 快照隔离、时间旅行
│   ├── Schema evolution（无需重写数据）
│   └── Hidden partitioning
├── Delta Lake (Databricks, 2019)
│   ├── ACID 事务
│   ├── DML (UPDATE/DELETE/MERGE)
│   └── 与 Spark 深度集成
├── Apache Hudi (Uber, 2019)
│   ├── 增量处理（Copy-on-Write / Merge-on-Read）
│   └── 面向流批一体
└── 趋势: Iceberg 正在成为事实标准（Snowflake、BigQuery、Trino 等均支持）
```

## 对引擎开发者的建议

### 文件格式抽象层设计

```
FileFormatReader (接口):
├── ParquetReader
├── ORCReader
├── CSVReader
├── JSONReader
└── AvroReader

每个 Reader 需要实现:
1. schema_discovery(): 从文件推断 schema
2. read_batch(projection, filters): 读取数据批次
   - projection: 列裁剪（只读需要的列）
   - filters: 谓词下推（只读满足条件的行/行组）
3. statistics(): 返回统计信息（行数、min/max）
4. split(size_hint): 将数据分片用于并行读取
```

### 谓词下推到文件层

```
-- Parquet 的谓词下推层次:
-- 1. Row Group 级: 通过 min/max 统计信息跳过整个 Row Group
-- 2. Page 级: 通过 Page 级统计信息跳过整个 Page
-- 3. Row 级: 读取数据后再过滤（最慢但最精确）

-- 引擎需要将 SQL WHERE 条件转换为文件级过滤器:
WHERE event_time >= '2024-03-01' AND event_type = 'click'
→ ParquetFilter {
    row_group_filter: [min_max(event_time) >= '2024-03-01'],
    page_filter: [bloom_filter(event_type, 'click')],
    row_filter: [event_time >= '2024-03-01' AND event_type = 'click']
  }
```

## 参考资料

- Hive: [External Tables](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-ExternalTables)
- BigQuery: [External Tables](https://cloud.google.com/bigquery/docs/external-tables)
- Snowflake: [External Tables](https://docs.snowflake.com/en/sql-reference/sql/create-external-table)
- Trino: [Connectors](https://trino.io/docs/current/connector.html)
- DuckDB: [read_parquet](https://duckdb.org/docs/data/parquet/overview)
- Apache Iceberg: [Spec](https://iceberg.apache.org/spec/)
- Delta Lake: [Documentation](https://docs.delta.io/)
