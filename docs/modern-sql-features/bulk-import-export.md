# 批量导入导出 (Bulk Import and Export)

批量数据导入导出是 SQL 方言中标准化程度最低的领域之一。与 SELECT、JOIN、GROUP BY 等经过 SQL 标准严格定义的操作不同，批量数据移动从未被纳入 ISO SQL 标准，完全由各引擎自行设计。其结果是：同样是"将 CSV 文件加载到表中"这一基本需求，45 个数据库可能出现 30 种以上的语法变体。这种碎片化源于三重差异——存储架构差异（行式 vs 列式 vs 对象存储）、部署形态差异（单机 vs 分布式 vs 云原生）、以及历史演进差异（1990 年代的 `bcp` 到 2020 年代的云 Stage 模式）。

对引擎开发者而言，理解这些差异有助于在设计数据加载接口时做出更好的取舍——在性能、安全性、事务语义和用户体验之间找到平衡点。

## 无 SQL 标准 (No SQL Standard)

ISO/IEC 9075 SQL 标准（包括 SQL:2023）中没有定义任何批量导入导出语句。`COPY`、`LOAD DATA`、`BULK INSERT` 等都是纯粹的厂商扩展。SQL 标准只定义了 `INSERT INTO ... VALUES` 和 `INSERT INTO ... SELECT` 等逐行或基于查询的数据写入方式。

这意味着：
- 没有可移植的批量加载语法
- 每个引擎的文件格式选项、错误处理、事务语义都不同
- 迁移批量加载脚本通常需要完全重写

## 支持矩阵

### COPY 命令支持 (PostgreSQL 风格: COPY TO/FROM)

| 引擎 | COPY FROM (导入) | COPY TO (导出) | 二进制格式 | 查询导出 | 版本 |
|------|:---:|:---:|:---:|:---:|------|
| PostgreSQL | ✅ | ✅ | ✅ | ✅ `COPY (SELECT...) TO` | 7.0+ |
| Greenplum | ✅ | ✅ | ✅ | ✅ | 4.0+ |
| CockroachDB | ✅ | ✅ | ❌ | ✅ | 2.1+ |
| YugabyteDB | ✅ | ✅ | ✅ | ✅ | 2.0+ |
| TimescaleDB | ✅ | ✅ | ✅ | ✅ | 继承 PG |
| Redshift | ✅ (S3) | ✅ `UNLOAD` | ❌ | ✅ `UNLOAD` | GA |
| DuckDB | ✅ | ✅ | ❌ | ✅ | 0.2+ |
| Materialize | ✅ `COPY FROM STDIN` | ✅ `COPY TO STDOUT` | ❌ | ✅ | GA |
| Vertica | ✅ | ❌ (用 EXPORT) | ❌ | ❌ | 7.0+ |
| RisingWave | ✅ `COPY FROM` | ❌ | ❌ | ❌ | GA |
| Firebolt | ✅ `COPY INTO` | ❌ | ❌ | ❌ | GA |
| MySQL | ❌ | ❌ | -- | -- | -- |
| SQL Server | ❌ | ❌ | -- | -- | -- |
| Oracle | ❌ | ❌ | -- | -- | -- |

> 注：Redshift 的 COPY 语法源自 PostgreSQL 但已大幅修改，主要面向 S3 数据源。Snowflake 和 Databricks 的 COPY INTO 将在后续章节单独列出。

### LOAD DATA 支持 (MySQL 风格: LOAD DATA INFILE)

| 引擎 | 语法 | LOCAL (客户端文件) | REPLACE/IGNORE | 字符集指定 | 版本 |
|------|------|:---:|:---:|:---:|------|
| MySQL | `LOAD DATA [LOCAL] INFILE` | ✅ | ✅ | ✅ | 3.23+ |
| MariaDB | `LOAD DATA [LOCAL] INFILE` | ✅ | ✅ | ✅ | 5.1+ |
| TiDB | `LOAD DATA [LOCAL] INFILE` | ✅ | ✅ | ✅ | 2.0+ |
| OceanBase | `LOAD DATA [LOCAL] INFILE` | ✅ | ✅ | ✅ | MySQL 模式 |
| SingleStore | `LOAD DATA INFILE` | ✅ | ✅ | ✅ | 5.0+ |
| StarRocks | `LOAD DATA INFILE` (有限) | ❌ | ❌ | ❌ | 有限支持 |
| Hive | `LOAD DATA [LOCAL] INPATH` | ✅ | ✅ (OVERWRITE) | ❌ | 0.5+ |
| Impala | `LOAD DATA INPATH` | ❌ | ✅ (OVERWRITE) | ❌ | 1.0+ |

> 注：Hive 和 Impala 的 LOAD DATA 本质是 HDFS 文件移动/复制，不涉及数据解析和转换。

### BULK INSERT 支持 (SQL Server 风格)

| 引擎 | 语法 | FORMAT FILE | 批次控制 | MAXERRORS | 版本 |
|------|------|:---:|:---:|:---:|------|
| SQL Server | `BULK INSERT` | ✅ | ✅ `BATCHSIZE` | ✅ | 7.0+ |
| Azure Synapse | `BULK INSERT` / `COPY INTO` | ✅ | ✅ | ✅ | GA |
| SAP HANA | `IMPORT FROM` | ❌ | ✅ | ✅ `ERROR LOG` | 1.0+ |
| Informix | `LOAD FROM` | ❌ | ❌ | ❌ | 7.0+ |
| DB2 | `LOAD` / `IMPORT` | ✅ | ✅ | ✅ | 7.0+ |

### COPY INTO 支持 (Snowflake/Databricks 风格：云存储加载)

| 引擎 | COPY INTO (导入) | COPY INTO / UNLOAD (导出) | Stage 概念 | 自动压缩检测 | 版本 |
|------|:---:|:---:|:---:|:---:|------|
| Snowflake | ✅ | ✅ | ✅ (内部/外部 Stage) | ✅ | GA |
| Databricks | ✅ | ❌ (用 INSERT OVERWRITE DIRECTORY) | ✅ (Volume) | ✅ | DBR 10.0+ |
| Azure Synapse | ✅ | ❌ (用 CETAS) | ✅ (外部数据源) | ✅ | GA |
| Firebolt | ✅ | ❌ | ❌ | ✅ | GA |
| DatabendDB | ✅ | ✅ | ✅ (内部/外部 Stage) | ✅ | GA |
| Yellowbrick | ✅ (类 PG COPY) | ✅ | ❌ | ✅ | GA |

### 外部表加载 (External Table for Loading)

| 引擎 | 外部表语法 | 可写外部表 | 典型数据源 | 版本 |
|------|------|:---:|------|------|
| Oracle | `CREATE TABLE ... ORGANIZATION EXTERNAL` | ❌ (Oracle 10gR2+ 可写，ORACLE_DATAPUMP 驱动) | 本地文件 | 9iR2+ |
| Hive | `CREATE EXTERNAL TABLE` | ✅ | HDFS, S3 | 0.5+ |
| Spark SQL | `CREATE TABLE ... USING` | ✅ | 文件, JDBC, 任意 | 2.0+ |
| Trino | Connector 架构 | 部分 | 任意 | 早期 |
| Presto | Connector 架构 | 部分 | 任意 | 早期 |
| BigQuery | `CREATE EXTERNAL TABLE` | ❌ | GCS, Drive, S3 | GA |
| Snowflake | `CREATE EXTERNAL TABLE` | ❌ | S3, Azure, GCS | GA |
| Redshift | Redshift Spectrum | ❌ | S3 | 2017+ |
| SQL Server | PolyBase `CREATE EXTERNAL TABLE` | ❌ | S3, ADLS, HDFS | 2016+ |
| Greenplum | `CREATE EXTERNAL TABLE` (gpfdist) | ✅ | gpfdist, S3, HDFS | 4.0+ |
| ClickHouse | 表引擎 (S3, URL, File) | 部分 | S3, HTTP, 本地 | 18.0+ |
| DuckDB | `read_csv()` / `read_parquet()` 函数 | ❌ | 本地, S3, HTTP | 0.2+ |
| Vertica | `CREATE EXTERNAL TABLE AS COPY` | ❌ | S3, GCS, HDFS, 本地 | 9.0+ |
| Amazon Athena | `CREATE EXTERNAL TABLE` (Hive 风格) | ❌ | S3 | GA |
| Exasol | `IMPORT FROM` (外部数据) | ❌ | 文件, JDBC | 6.0+ |
| Doris | `CREATE TABLE ... ENGINE = BROKER` | ❌ | HDFS, S3 | 0.14+ |
| StarRocks | `CREATE EXTERNAL TABLE` / Files 函数 | ❌ | HDFS, S3, 本地 | 2.0+ |
| CrateDB | `COPY FROM` (URL) | ❌ | URL, S3 | 0.57+ |
| Firebolt | 外部表 | ❌ | S3 | GA |

### 支持的文件格式

| 引擎 | CSV | TSV | JSON | Parquet | ORC | Avro | 其他 |
|------|:---:|:---:|:---:|:---:|:---:|:---:|------|
| PostgreSQL | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | text, binary |
| MySQL | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | fixed-width |
| MariaDB | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | fixed-width |
| SQLite | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | .import 仅 CSV |
| Oracle | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | fixed-width, XML |
| SQL Server | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | fixed-width, XML |
| DB2 | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | IXF, ASC |
| Snowflake | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | XML |
| BigQuery | ✅ | ❌ | ✅ (NDJSON) | ✅ | ✅ | ✅ | Datastore Backup |
| Redshift | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Shapefile |
| DuckDB | ✅ | ✅ | ✅ | ✅ | ✅ (扩展, 0.10+) | ❌ | Excel, SQLite |
| ClickHouse | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 70+ 格式 (Arrow, MsgPack, Protobuf 等) |
| Trino | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | RCFile |
| Presto | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | RCFile |
| Spark SQL | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 自定义 DataSource |
| Hive | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | RCFile, SequenceFile |
| Flink SQL | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | Canal, Debezium |
| Databricks | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | XML, 自定义 |
| Teradata | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | FastLoad 格式 |
| Greenplum | ✅ | ✅ | ❌ | ✅ (外部表) | ❌ | ❌ | text, custom |
| CockroachDB | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | PGDUMP, MYSQLDUMP |
| TiDB | ✅ | ✅ | ❌ | ✅ (Lightning) | ❌ | ❌ | SQL dump |
| OceanBase | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | -- |
| YugabyteDB | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | text, binary (PG) |
| SingleStore | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | -- |
| Vertica | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | -- |
| Impala | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | RCFile, SequenceFile |
| StarRocks | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | -- |
| Doris | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | -- |
| MonetDB | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | compressed CSV |
| CrateDB | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | -- |
| QuestDB | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ILP (InfluxDB Line Protocol) |
| Exasol | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | FBV |
| SAP HANA | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | -- |
| Informix | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | -- |
| Firebird | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 无原生批量加载 |
| H2 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | CSVREAD 函数 |
| HSQLDB | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | TEXT TABLE |
| Derby | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 无原生批量加载 |
| Amazon Athena | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Ion, 继承 Hive |
| Azure Synapse | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | -- |
| Google Spanner | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | Mutation API (非 SQL) |
| Materialize | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | text (PG COPY) |
| RisingWave | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | -- |
| InfluxDB | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | Line Protocol (专有) |
| DatabendDB | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | TSV, NDJSON |
| Yellowbrick | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | -- |
| Firebolt | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | -- |

### 数据源位置 (Source Locations)

| 引擎 | 本地文件 | 服务端文件 | STDIN/管道 | S3 | GCS | Azure Blob | HDFS |
|------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| PostgreSQL | ✅ (\copy) | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| MySQL | ✅ (LOCAL) | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| MariaDB | ✅ (LOCAL) | ✅ | ❌ | ✅ (S3 引擎) | ❌ | ❌ | ❌ |
| SQLite | ✅ | -- | ✅ | ❌ | ❌ | ❌ | ❌ |
| Oracle | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| SQL Server | ✅ | ✅ | ❌ | ✅ (PolyBase) | ❌ | ✅ (PolyBase) | ✅ (PolyBase) |
| DB2 | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Snowflake | ❌ (需 PUT 上传) | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ |
| BigQuery | ✅ (bq CLI) | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| Redshift | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| DuckDB | ✅ | -- | ✅ | ✅ | ✅ | ✅ | ❌ |
| ClickHouse | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Trino | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| Presto | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| Spark SQL | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| Hive | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| Flink SQL | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ |
| Databricks | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ |
| Teradata | ✅ | ✅ | ❌ | ✅ (NOS) | ✅ (NOS) | ✅ (NOS) | ❌ |
| Greenplum | ✅ | ✅ (gpfdist) | ❌ | ✅ | ❌ | ❌ | ✅ |
| CockroachDB | ❌ | ✅ (nodelocal) | ✅ | ✅ | ✅ | ✅ | ❌ |
| TiDB | ✅ (LOCAL) | ✅ | ❌ | ✅ (Lightning) | ❌ | ❌ | ❌ |
| OceanBase | ✅ (LOCAL) | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| YugabyteDB | ✅ (\copy) | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| SingleStore | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| Vertica | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Impala | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| StarRocks | ❌ | ✅ | ✅ (Stream Load) | ✅ (Broker Load) | ❌ | ❌ | ✅ |
| Doris | ❌ | ✅ | ✅ (Stream Load) | ✅ (Broker Load) | ❌ | ❌ | ✅ |
| MonetDB | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| CrateDB | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |
| TimescaleDB | ✅ (\copy) | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| QuestDB | ✅ | ✅ | ✅ (REST API) | ❌ | ❌ | ❌ | ❌ |
| Exasol | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ❌ |
| SAP HANA | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| Informix | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Amazon Athena | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| Azure Synapse | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (ADLS) | ❌ |
| Google Spanner | ❌ | ❌ | ❌ | ❌ | ✅ (Dataflow) | ❌ | ❌ |
| Materialize | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| RisingWave | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| InfluxDB | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| DatabendDB | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ |
| Yellowbrick | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| Firebolt | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |

### 导出/卸载命令 (Export / Unload)

| 引擎 | 导出语法 | 输出格式 | 支持压缩 | 可导出查询结果 |
|------|------|------|:---:|:---:|
| PostgreSQL | `COPY ... TO` / `\copy ... TO` | CSV, text, binary | 是 (16+, gzip) | ✅ |
| MySQL | `SELECT ... INTO OUTFILE` | CSV, TSV | ❌ | ✅ |
| MariaDB | `SELECT ... INTO OUTFILE` | CSV, TSV | ❌ | ✅ |
| SQL Server | `bcp ... out` / `OPENROWSET` | CSV, native | ❌ | ✅ |
| Oracle | `SQL*Plus SPOOL` / Data Pump `EXPDP` | CSV, dump | ✅ (Data Pump) | ✅ |
| DB2 | `EXPORT TO` | CSV, IXF, DEL | ❌ | ✅ |
| Snowflake | `COPY INTO @stage` | CSV, JSON, Parquet | ✅ | ✅ |
| BigQuery | `EXPORT DATA` / `bq extract` | CSV, JSON, Parquet, Avro | ✅ (gzip) | ✅ |
| Redshift | `UNLOAD` | CSV, JSON, Parquet | ✅ (gzip, zstd, bzip2) | ✅ |
| DuckDB | `COPY ... TO` | CSV, JSON, Parquet | ✅ | ✅ |
| ClickHouse | `INSERT INTO FUNCTION` / `SELECT ... INTO OUTFILE` | CSV, JSON, Parquet 等 | ✅ | ✅ |
| Spark SQL | `INSERT OVERWRITE DIRECTORY` | CSV, JSON, Parquet, ORC | ✅ | ✅ |
| Hive | `INSERT OVERWRITE DIRECTORY` | 表格式 | ✅ | ✅ |
| Databricks | `INSERT OVERWRITE DIRECTORY` / `dbutils.fs` | CSV, JSON, Parquet | ✅ | ✅ |
| Greenplum | `COPY ... TO` / writable external table | CSV, text | ❌ | ✅ |
| CockroachDB | `EXPORT INTO` | CSV, Parquet | ✅ | ✅ |
| Vertica | `EXPORT TO PARQUET` / `EXPORT TO CSV` | CSV, Parquet | ✅ | ✅ |
| StarRocks | `EXPORT` / `SELECT INTO OUTFILE` | CSV, Parquet | ✅ | ✅ |
| Doris | `EXPORT` / `SELECT INTO OUTFILE` | CSV, Parquet | ✅ | ✅ |
| MonetDB | `COPY ... INTO` (文件) | CSV | ❌ | ✅ |
| DatabendDB | `COPY INTO @stage` | CSV, JSON, Parquet | ✅ | ✅ |
| Teradata | `FastExport` / NOS `WRITE_NOS` | CSV, JSON, Parquet | ❌ | ✅ |
| Exasol | `EXPORT INTO` | CSV, FBV | ❌ | ✅ |
| SAP HANA | `EXPORT INTO` | CSV | ✅ | ✅ |

> 注：未列出的引擎通常不提供 SQL 级别的导出命令，需要依赖客户端工具或 API。

### 并行加载支持 (Parallel Loading)

| 引擎 | 并行机制 | 推荐文件策略 | 备注 |
|------|------|------|------|
| PostgreSQL | 多进程 `COPY` (手动分文件) | 手动分文件 + 并发连接 | 单个 COPY 为单线程 |
| MySQL | 多连接并发 LOAD DATA | 手动分文件 | 单个 LOAD DATA 单线程 |
| SQL Server | `BULK INSERT` + TABLOCK | 多文件并发 | 最小日志模式可并行 |
| Oracle | SQL*Loader `PARALLEL=TRUE` | 自动 | Direct Path 支持并行 |
| Snowflake | 自动并行 (多文件自动分发) | 按节点数拆分文件 | 推荐 100-250MB/文件 |
| BigQuery | Load Job 自动并行 | 无需拆分 | 完全托管 |
| Redshift | 按 slice 并行 (多文件) | 文件数 = slice 数的倍数 | 推荐按 manifest 分发 |
| ClickHouse | 多分区并行写入 | 按分区键分文件 | MergeTree 后台合并 |
| DuckDB | 多线程扫描 (Parquet) | 多文件 glob | 自动并行化 |
| Spark SQL | 按 partition 并行 | 按分区拆分 | Executor 级并行 |
| Hive | MapReduce/Tez 并行 | 按 HDFS block | 计算框架级并行 |
| Greenplum | gpfdist 分发到各 segment | gpfdist 自动分发 | 推荐多 gpfdist 实例 |
| CockroachDB | 分布式 IMPORT | 多文件自动分发 | 按 range 并行 |
| StarRocks | Broker Load 多 BE 并行 | 多文件 | 按 BE 节点数分发 |
| Doris | Broker Load 多 BE 并行 | 多文件 | 按 BE 节点数分发 |
| Vertica | 多线程 COPY | 自动 | 按 projection 并行 |
| SingleStore | 分布式 LOAD DATA | 自动按 partition 分发 | pipeline 机制 |
| Teradata | FastLoad 多 AMP 并行 | 自动 | 按 hash 分发 |
| DatabendDB | 多 micro-block 并行 | 多文件 | 云原生并行 |

### 错误处理 (Error Handling during Load)

| 引擎 | 错误策略 | REJECT LIMIT | 错误日志 | 默认行为 |
|------|------|:---:|:---:|------|
| PostgreSQL | 全部回滚 | ❌ | ❌ | 任何错误终止并回滚 |
| MySQL | IGNORE 跳过 / REPLACE 替换 | ❌ | ✅ (SHOW WARNINGS) | 错误终止 |
| SQL Server | MAXERRORS | ✅ | ✅ (错误文件) | MAXERRORS=10 |
| Oracle | SQL*Loader ERRORS= | ✅ | ✅ (.bad/.log 文件) | ERRORS=50 |
| Snowflake | ON_ERROR (CONTINUE/SKIP_FILE/ABORT) | ❌ | ✅ (VALIDATION_MODE) | ABORT_STATEMENT |
| BigQuery | max_bad_records | ✅ | ✅ | 0 (严格模式) |
| Redshift | MAXERROR | ✅ | ✅ (stl_load_errors) | MAXERROR=0 |
| ClickHouse | input_format_allow_errors_num | ✅ | ❌ | 0 (严格模式) |
| DuckDB | ignore_errors | ❌ | ✅ (reject table) | 错误终止 |
| Spark SQL | mode (PERMISSIVE/DROPMALFORMED/FAILFAST) | ❌ | ✅ (badRecordsPath) | PERMISSIVE |
| Hive | -- | ❌ | ❌ | 文件移动，不验证 |
| Databricks | _rescued_data 列 | ❌ | ✅ (rescue 列) | PERMISSIVE |
| CockroachDB | -- | ❌ | ❌ | 错误终止 |
| Vertica | REJECTED DATA / EXCEPTIONS | ✅ | ✅ (rejected 文件) | 终止 |
| StarRocks | max_filter_ratio | ✅ | ✅ (BE 日志) | 0 (严格模式) |
| Doris | max_filter_ratio | ✅ | ✅ (BE 日志) | 0 (严格模式) |
| SingleStore | -- | ❌ | ✅ (SHOW WARNINGS) | IGNORE 可选 |
| Azure Synapse | MAXERRORS | ✅ | ✅ | 错误终止 |
| Greenplum | SEGMENT REJECT LIMIT | ✅ | ✅ (error log table) | 错误终止 |
| Exasol | REJECT LIMIT | ✅ | ✅ | 错误终止 |
| DatabendDB | ON_ERROR (CONTINUE/ABORT) | ❌ | ✅ | ABORT |

### 事务语义 (Transaction Semantics)

| 引擎 | 加载事务性 | 原子性 | 部分提交 | 说明 |
|------|:---:|:---:|:---:|------|
| PostgreSQL | ✅ 完全事务 | ✅ 原子 | ❌ | COPY 在一个事务中执行，失败全部回滚 |
| MySQL | 部分 | ❌ | ✅ | LOAD DATA 非原子：已插入的行不回滚 (InnoDB autocommit) |
| MariaDB | 部分 | ❌ | ✅ | 同 MySQL |
| SQL Server | ✅ (BATCHSIZE 控制) | 可选 | ✅ | BATCHSIZE 控制每批提交，批内原子 |
| Oracle | Direct Path 非事务 | ❌ (Direct Path) | ✅ | Conventional Path 走事务；Direct Path 写入 HWM 之上 |
| Snowflake | ✅ 文件级 | 文件级原子 | 文件粒度 | 每个文件作为一个微事务 |
| BigQuery | ✅ Load Job | ✅ 原子 | ❌ | Load Job 整体成功或失败 |
| Redshift | ✅ 事务 | ✅ 原子 | ❌ | COPY 在隐式事务中执行 |
| DuckDB | ✅ 完全事务 | ✅ 原子 | ❌ | 失败全部回滚 |
| ClickHouse | ❌ | ❌ | ✅ | INSERT 只保证 block 级原子性 |
| Hive | ❌ | ❌ | ✅ | 文件移动操作，无事务概念 (除 ACID 表) |
| Spark SQL | ❌ | ❌ | ✅ | 分区级写入，无跨分区事务 |
| CockroachDB | ✅ 分布式事务 | ✅ 原子 | ❌ | IMPORT 原子执行 |
| TiDB | 部分 | ❌ | ✅ | LOAD DATA 默认非事务；可配置事务大小 |
| Greenplum | ✅ 事务 | ✅ 原子 | ❌ | 继承 PostgreSQL 事务模型 |
| Vertica | ✅ 事务 | ✅ 原子 | ❌ | COPY 在事务中执行 |
| MonetDB | ✅ 事务 | ✅ 原子 | ❌ | COPY INTO 事务性 |
| Doris | ❌ | ❌ | ✅ | 导入任务级别，内部 two-phase commit |
| StarRocks | ❌ | ❌ | ✅ | 导入任务级别，内部 two-phase commit |

### 压缩支持 (Compression during Import/Export)

| 引擎 | gzip | zstd | snappy | lz4 | bzip2 | 自动检测 |
|------|:---:|:---:|:---:|:---:|:---:|:---:|
| PostgreSQL | 是 (16+) | ❌ | ❌ | ❌ | ❌ | ❌ |
| MySQL | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| SQL Server | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Oracle | ❌ (Data Pump 支持) | ❌ | ❌ | ❌ | ❌ | ❌ |
| Snowflake | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| BigQuery | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ |
| Redshift | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
| DuckDB | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| ClickHouse | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Spark SQL | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Hive | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Databricks | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Trino | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Greenplum | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| CockroachDB | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| Vertica | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
| StarRocks | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Doris | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| SingleStore | ✅ | ❌ | ✅ | ✅ | ❌ | ❌ |
| DatabendDB | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
| Exasol | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |

## 各引擎详细语法

### PostgreSQL COPY

```sql
-- 从服务端文件导入
COPY orders (id, customer_name, amount, order_date)
FROM '/data/orders.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ',', NULL '');

-- 从标准输入导入（客户端文件，最常用方式）
-- psql: \copy orders FROM '/local/path/orders.csv' WITH (FORMAT csv, HEADER true)

-- 二进制格式（最高性能，跳过文本解析）
COPY orders FROM STDIN WITH (FORMAT binary);

-- 导出到文件
COPY orders TO '/data/orders_export.csv' WITH (FORMAT csv, HEADER true);

-- 导出查询结果（非常灵活）
COPY (SELECT * FROM orders WHERE amount > 1000)
TO '/data/high_value_orders.csv' WITH (FORMAT csv, HEADER true);

-- WITH 参数:
-- FORMAT: csv | text (默认) | binary
-- HEADER: true | false
-- DELIMITER: 分隔符 (默认 tab)
-- NULL: NULL 值的字符串表示 (默认 \N)
-- QUOTE: 引用字符 (默认 ")
-- ESCAPE: 转义字符 (默认 ")
-- ENCODING: 字符编码
-- FORCE_NULL: 指定列的空字符串视为 NULL
-- FREEZE: 加载后立即冻结行 (避免 vacuum)
```

### MySQL LOAD DATA INFILE

```sql
-- 从服务端文件加载
LOAD DATA INFILE '/var/lib/mysql-files/orders.csv'
INTO TABLE orders
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(id, customer_name, amount, @order_date)
SET order_date = STR_TO_DATE(@order_date, '%Y-%m-%d');

-- 从客户端文件加载（需启用 local_infile）
LOAD DATA LOCAL INFILE '/local/path/orders.csv'
INTO TABLE orders
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- 冲突处理
LOAD DATA INFILE '/data/orders.csv' REPLACE INTO TABLE orders ...;  -- 替换
LOAD DATA INFILE '/data/orders.csv' IGNORE INTO TABLE orders ...;   -- 跳过

-- 安全限制:
-- secure_file_priv 控制服务端文件路径
-- LOCAL INFILE 默认关闭 (MySQL 8.0+)
SHOW VARIABLES LIKE 'secure_file_priv';

-- 导出
SELECT * FROM orders
INTO OUTFILE '/var/lib/mysql-files/orders_export.csv'
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n';
```

### MariaDB

```sql
-- 基本语法与 MySQL 相同
LOAD DATA [LOCAL] INFILE '/data/orders.csv'
INTO TABLE orders
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- MariaDB 独有: LOAD DATA 支持从 S3 加载 (MariaDB 10.5+ S3 引擎)
-- 需先配置 S3 存储引擎
-- ALTER TABLE orders ENGINE = S3;
-- 然后通过 S3 引擎表来访问 S3 数据
```

### SQL Server BULK INSERT

```sql
-- BULK INSERT
BULK INSERT orders
FROM '/data/orders.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2,            -- 跳过表头
    TABLOCK,                 -- 表锁 (最小日志模式下提升性能)
    BATCHSIZE = 100000,      -- 每批次行数
    MAXERRORS = 100,          -- 允许的最大错误数
    FORMAT = 'CSV',          -- SQL Server 2017+
    CODEPAGE = '65001'       -- UTF-8
);

-- bcp 命令行工具
-- bcp mydb.dbo.orders in /data/orders.csv -c -t"," -S server -U user -P pass

-- OPENROWSET(BULK) 在查询中使用文件
INSERT INTO orders
SELECT * FROM OPENROWSET(
    BULK '/data/orders.csv',
    FORMATFILE = '/data/orders.fmt',
    FIRSTROW = 2
) AS bulk_data;

-- 最小日志记录 (Minimal Logging) 条件:
-- 1. 目标表是堆或空表
-- 2. 使用 TABLOCK hint
-- 3. 数据库恢复模式为 SIMPLE 或 BULK_LOGGED
ALTER DATABASE mydb SET RECOVERY BULK_LOGGED;
BULK INSERT orders FROM '/data/orders.csv' WITH (TABLOCK);
ALTER DATABASE mydb SET RECOVERY FULL;
```

### Oracle SQL*Loader / External Tables

```sql
-- SQL*Loader 控制文件 (orders.ctl):
-- LOAD DATA
-- INFILE '/data/orders.csv'
-- INTO TABLE orders
-- FIELDS TERMINATED BY ','
-- OPTIONALLY ENCLOSED BY '"'
-- TRAILING NULLCOLS
-- (id, customer_name, amount, order_date DATE "YYYY-MM-DD")

-- 常规路径: sqlldr user/pass@db control=orders.ctl
-- 直接路径: sqlldr user/pass@db control=orders.ctl direct=true

-- 外部表方式 (SQL 内操作)
CREATE TABLE ext_orders (
    id NUMBER,
    customer_name VARCHAR2(100),
    amount NUMBER
)
ORGANIZATION EXTERNAL (
    TYPE ORACLE_LOADER
    DEFAULT DIRECTORY data_dir
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE
        FIELDS TERMINATED BY ','
    )
    LOCATION ('orders.csv')
);

-- 直接路径插入 (跳过缓冲区)
INSERT /*+ APPEND */ INTO orders SELECT * FROM ext_orders;

-- Oracle Data Pump (EXPDP/IMPDP) 用于数据库间迁移
-- expdp user/pass@db tables=orders directory=data_dir dumpfile=orders.dmp
-- impdp user/pass@db tables=orders directory=data_dir dumpfile=orders.dmp
```

### DB2 LOAD / IMPORT

```sql
-- IMPORT (通过 SQL 层，支持触发器和约束)
IMPORT FROM '/data/orders.csv' OF DEL
MODIFIED BY COLDEL, CHARDEL" DATEFORMAT="YYYY-MM-DD"
INSERT INTO orders;

-- LOAD (旁路 SQL 层，更快但限制更多)
LOAD FROM '/data/orders.csv' OF DEL
MODIFIED BY COLDEL, CHARDEL"
INSERT INTO orders;

-- LOAD 有四个阶段:
-- 1. LOAD: 读取数据写入表空间
-- 2. BUILD: 重建索引
-- 3. DELETE: 处理唯一性冲突
-- 4. INDEX COPY: 将索引从临时空间复制到正式空间

-- EXPORT
EXPORT TO '/data/orders_export.csv' OF DEL
MODIFIED BY COLDEL, CHARDEL"
SELECT * FROM orders WHERE amount > 1000;
```

### Snowflake COPY INTO

```sql
-- 1. 创建 Stage
CREATE STAGE my_s3_stage
    URL = 's3://my-bucket/data/'
    CREDENTIALS = (AWS_KEY_ID = '...' AWS_SECRET_KEY = '...');

-- 或使用内部 Stage
CREATE STAGE my_internal_stage;
-- PUT file:///local/path/orders.csv @my_internal_stage;

-- 2. 创建文件格式
CREATE FILE FORMAT my_csv_format
    TYPE = CSV
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('NULL', '');

-- 3. COPY INTO 加载
COPY INTO orders
FROM @my_s3_stage/orders/
FILE_FORMAT = (FORMAT_NAME = my_csv_format)
PATTERN = '.*\.csv\.gz'
ON_ERROR = 'CONTINUE';

-- 从 Parquet 加载 (按列名匹配)
COPY INTO orders
FROM @my_s3_stage/orders/
FILE_FORMAT = (TYPE = PARQUET)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

-- 加载时做数据转换
COPY INTO orders (id, name, amount_cents)
FROM (
    SELECT $1, $2, $3 * 100
    FROM @my_s3_stage/orders.csv
    (FILE_FORMAT => my_csv_format)
);

-- 导出到 Stage
COPY INTO @my_s3_stage/export/orders_
FROM (SELECT * FROM orders WHERE order_date >= '2024-01-01')
FILE_FORMAT = (TYPE = PARQUET)
HEADER = TRUE
MAX_FILE_SIZE = 268435456;  -- 256MB per file

-- 查看加载历史
SELECT * FROM TABLE(information_schema.copy_history(
    TABLE_NAME => 'orders',
    START_TIME => DATEADD(hours, -24, CURRENT_TIMESTAMP())
));

-- ON_ERROR 选项:
-- ABORT_STATEMENT (默认): 遇错终止
-- CONTINUE: 跳过错误行
-- SKIP_FILE: 跳过包含错误的整个文件
-- SKIP_FILE_<n>: 文件中错误行超过 n 条时跳过该文件
-- SKIP_FILE_<n>%: 文件中错误行超过 n% 时跳过该文件
```

### BigQuery

```sql
-- BigQuery 使用 Load Job（而非 SQL COPY 语句）
-- bq CLI:
-- bq load --source_format=CSV --skip_leading_rows=1 \
--   dataset.orders gs://bucket/orders.csv id:INTEGER,name:STRING,amount:FLOAT

-- SQL DDL 方式: 创建外部表后查询
CREATE EXTERNAL TABLE dataset.ext_orders
OPTIONS (
    format = 'CSV',
    uris = ['gs://bucket/orders/*.csv'],
    skip_leading_rows = 1
);

INSERT INTO dataset.orders SELECT * FROM dataset.ext_orders;

-- EXPORT DATA (BigQuery → GCS)
EXPORT DATA OPTIONS (
    uri = 'gs://bucket/export/orders_*.csv',
    format = 'CSV',
    overwrite = true,
    header = true
) AS
SELECT * FROM dataset.orders WHERE order_date >= '2024-01-01';

-- Parquet 导出
EXPORT DATA OPTIONS (
    uri = 'gs://bucket/export/orders_*.parquet',
    format = 'PARQUET',
    compression = 'SNAPPY'
) AS
SELECT * FROM dataset.orders;

-- Load Job 特性:
-- 1. 免费 (不消耗查询 slot)
-- 2. 每个项目每天最多 100,000 个 load job
-- 3. 每个 load job 最大 15TB
-- 4. 支持 schema auto-detection
```

### Redshift COPY / UNLOAD

```sql
-- 从 S3 加载 (强烈推荐)
COPY orders
FROM 's3://my-bucket/data/orders/'
IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftRole'
FORMAT AS PARQUET;

-- CSV 加载
COPY orders
FROM 's3://my-bucket/data/orders.csv'
IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftRole'
CSV
IGNOREHEADER 1
DELIMITER ','
REGION 'us-east-1'
GZIP;

-- Manifest 文件 (精确指定文件列表)
COPY orders
FROM 's3://my-bucket/manifests/orders.manifest'
IAM_ROLE '...'
MANIFEST;

-- UNLOAD (导出到 S3)
UNLOAD ('SELECT * FROM orders WHERE amount > 1000')
TO 's3://my-bucket/export/orders_'
IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftRole'
FORMAT AS PARQUET
PARTITION BY (order_date)
ALLOWOVERWRITE;

-- 性能最佳实践:
-- 1. 文件数 = slice 数的倍数 (并行加载)
-- 2. 每个文件 100MB-1GB (压缩后)
-- 3. 列式格式 (Parquet/ORC) 优于 CSV
-- 4. 使用 COMPUPDATE OFF 跳过压缩分析

-- 查看加载错误
SELECT * FROM stl_load_errors ORDER BY starttime DESC LIMIT 10;
```

### ClickHouse

```sql
-- INSERT FORMAT (内联数据)
INSERT INTO orders FORMAT CSV
1,"Alice",100,"2024-03-01"
2,"Bob",200,"2024-03-02"

-- JSONEachRow
INSERT INTO orders FORMAT JSONEachRow
{"id": 1, "name": "Alice", "amount": 100}
{"id": 2, "name": "Bob", "amount": 200}

-- clickhouse-client 从文件加载
-- clickhouse-client --query "INSERT INTO orders FORMAT CSV" < orders.csv
-- clickhouse-client --query "INSERT INTO orders FORMAT Parquet" < orders.parquet

-- HTTP 接口
-- curl 'http://localhost:8123/?query=INSERT+INTO+orders+FORMAT+CSV' --data-binary @orders.csv

-- 从 S3 加载
INSERT INTO orders
SELECT * FROM s3(
    'https://bucket.s3.amazonaws.com/orders/*.parquet',
    'Parquet'
);

-- 从 URL 加载
INSERT INTO orders
SELECT * FROM url('http://example.com/data.csv', CSV, 'id UInt64, name String');

-- 从 HDFS 加载
INSERT INTO orders
SELECT * FROM hdfs('hdfs://namenode:8020/data/orders/*.csv', 'CSV');

-- S3 表引擎 (作为持久化外部表)
CREATE TABLE s3_orders (
    id UInt64,
    name String,
    amount Decimal(10,2)
) ENGINE = S3('https://bucket.s3.amazonaws.com/orders/*.parquet', 'Parquet');

-- 导出到文件
SELECT * FROM orders INTO OUTFILE '/data/export.csv' FORMAT CSV;

-- 导出到 S3
INSERT INTO FUNCTION s3('https://bucket.s3.amazonaws.com/export/orders.parquet', 'Parquet')
SELECT * FROM orders;

-- ClickHouse 支持 70+ 种数据格式:
-- CSV, TSV, JSONEachRow, JSONCompactEachRow, Parquet, ORC, Avro, Arrow,
-- Native (二进制), RowBinary, MsgPack, Protobuf, CapnProto, ...
```

### DuckDB

```sql
-- COPY FROM (导入)
COPY orders FROM '/data/orders.csv' (HEADER, DELIMITER ',');

-- Parquet 导入 (最高性能)
COPY orders FROM '/data/orders.parquet' (FORMAT PARQUET);

-- 函数式读取 (更灵活)
INSERT INTO orders SELECT * FROM read_csv('/data/orders.csv', header=true);
INSERT INTO orders SELECT * FROM read_parquet('/data/orders/*.parquet');

-- 直接查询文件 (无需建表)
SELECT * FROM '/data/orders.parquet';
SELECT * FROM read_csv_auto('/data/orders.csv');

-- 从 S3 加载
SET s3_region = 'us-east-1';
SET s3_access_key_id = '...';
SET s3_secret_access_key = '...';
SELECT * FROM read_parquet('s3://bucket/orders/*.parquet');

-- 从 HTTP URL 加载
SELECT * FROM read_parquet('https://example.com/data.parquet');

-- 导出到文件
COPY orders TO '/data/export.csv' (HEADER, DELIMITER ',');
COPY orders TO '/data/export.parquet' (FORMAT PARQUET);
COPY (SELECT * FROM orders WHERE amount > 100)
TO '/data/filtered.parquet' (FORMAT PARQUET, COMPRESSION ZSTD);

-- 分区导出
COPY orders TO '/data/export' (FORMAT PARQUET, PARTITION_BY (order_date));
```

### Spark SQL

```sql
-- 读取文件创建表
CREATE TABLE orders USING PARQUET LOCATION 's3://bucket/orders/';

-- 从 CSV 文件创建表
CREATE TABLE orders USING CSV
OPTIONS (header "true", inferSchema "true", path "s3://bucket/orders.csv");

-- 加载数据到已有表 (INSERT INTO ... SELECT)
INSERT INTO orders
SELECT * FROM parquet.`s3://bucket/staging/orders/`;

-- 导出到文件
INSERT OVERWRITE DIRECTORY 's3://bucket/export/orders/'
USING PARQUET
SELECT * FROM orders WHERE order_date >= '2024-01-01';

-- CSV 导出
INSERT OVERWRITE DIRECTORY '/data/export/'
USING CSV
OPTIONS (header "true")
SELECT * FROM orders;

-- Spark 的 DataFrameReader API (非 SQL):
-- spark.read.format("parquet").load("s3://bucket/orders/")
-- spark.read.format("csv").option("header", "true").load("s3://bucket/orders.csv")
-- spark.write.format("parquet").partitionBy("year","month").save("s3://bucket/output/")
```

### Hive

```sql
-- LOAD DATA (文件移动操作，不解析数据)
LOAD DATA LOCAL INPATH '/data/orders.csv' INTO TABLE orders;
LOAD DATA INPATH 'hdfs:///data/orders/' INTO TABLE orders;
LOAD DATA INPATH 'hdfs:///data/orders/' OVERWRITE INTO TABLE orders;

-- 加载到分区表
LOAD DATA INPATH 'hdfs:///data/orders/dt=2024-01-01/'
INTO TABLE orders PARTITION (dt='2024-01-01');

-- 通过 INSERT SELECT 加载 (实际执行 MapReduce/Tez)
INSERT INTO orders
SELECT * FROM staging_orders;

-- INSERT OVERWRITE 导出到目录
INSERT OVERWRITE DIRECTORY 'hdfs:///export/orders/'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
SELECT * FROM orders WHERE year = 2024;

-- INSERT OVERWRITE LOCAL DIRECTORY 导出到本地
INSERT OVERWRITE LOCAL DIRECTORY '/data/export/'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
SELECT * FROM orders;

-- 注意: Hive LOAD DATA 本质上是 HDFS mv 操作
-- 数据文件必须与表的 STORED AS 格式匹配
-- 不做数据验证 (schema 不匹配会在查询时报错)
```

### Flink SQL

```sql
-- Flink SQL 通过 connector 实现数据导入导出
-- 创建 source 表 (文件系统 connector)
CREATE TABLE csv_source (
    id BIGINT,
    name STRING,
    amount DECIMAL(10, 2),
    order_date DATE
) WITH (
    'connector' = 'filesystem',
    'path' = 's3://bucket/orders/',
    'format' = 'csv',
    'csv.field-delimiter' = ',',
    'csv.ignore-parse-errors' = 'true'
);

-- 创建 sink 表
CREATE TABLE parquet_sink (
    id BIGINT,
    name STRING,
    amount DECIMAL(10, 2),
    order_date DATE
) WITH (
    'connector' = 'filesystem',
    'path' = 's3://bucket/export/',
    'format' = 'parquet',
    'sink.rolling-policy.file-size' = '256MB'
);

-- 批量导入 (SET 'execution.runtime-mode' = 'batch')
INSERT INTO parquet_sink SELECT * FROM csv_source;

-- Flink 的特殊性:
-- 1. 流批一体: 同样的 SQL 可在流模式和批模式下运行
-- 2. connector 抽象: 不仅支持文件，也支持 Kafka, JDBC 等
-- 3. checkpoint 机制保证 exactly-once
```

### Databricks

```sql
-- COPY INTO (推荐的增量加载方式)
COPY INTO orders
FROM 's3://bucket/data/orders/'
FILEFORMAT = CSV
FORMAT_OPTIONS ('header' = 'true', 'inferSchema' = 'true')
COPY_OPTIONS ('mergeSchema' = 'true');

-- 从 Parquet 加载
COPY INTO orders
FROM 's3://bucket/data/orders/'
FILEFORMAT = PARQUET;

-- COPY INTO 的关键特性:
-- 1. 幂等: 同一文件不会重复加载 (文件级去重)
-- 2. 增量: 只加载新文件
-- 3. schema 演进: mergeSchema 选项
-- 4. 错误处理: _rescued_data 列捕获不匹配数据

-- 使用 Volume (Unity Catalog)
COPY INTO orders
FROM '/Volumes/catalog/schema/volume/orders/'
FILEFORMAT = CSV;

-- 导出
INSERT OVERWRITE DIRECTORY 's3://bucket/export/'
USING PARQUET
SELECT * FROM orders;

-- Auto Loader (Structured Streaming, 非纯 SQL):
-- spark.readStream.format("cloudFiles")
--   .option("cloudFiles.format", "parquet")
--   .load("s3://bucket/data/")
--   .writeStream.table("orders")
```

### Teradata

```sql
-- FastLoad (大批量加载空表，命令行工具)
-- LOGON tdserver/user,pass;
-- DATABASE mydb;
-- BEGIN LOADING orders ERRORFILES err1, err2;
-- DEFINE
--   id (INTEGER), name (VARCHAR(100)), amount (DECIMAL(10,2))
-- FILE=/data/orders.csv;
-- INSERT INTO orders VALUES (:id, :name, :amount);
-- END LOADING;
-- LOGOFF;

-- TPT (Teradata Parallel Transporter) - 现代替代方案
-- 支持 Load, Update, Export, Stream 等多种 operator

-- NOS (Native Object Store) - 直接查询云存储
SELECT * FROM (
    LOCATION = '/s3/bucket/orders/'
    STOREDAS = 'PARQUET'
) AS orders_s3;

-- NOS 写入
CREATE MULTISET TABLE orders_export AS (
    SELECT * FROM orders WHERE amount > 1000
) WITH DATA;

WRITE_NOS (
    ON (SELECT * FROM orders_export)
    USING
        LOCATION ('/s3/bucket/export/')
        STOREDAS ('PARQUET')
) AS d;
```

### CockroachDB

```sql
-- IMPORT INTO (从文件加载)
IMPORT INTO orders (id, name, amount)
CSV DATA (
    'gs://bucket/orders/file1.csv',
    'gs://bucket/orders/file2.csv'
)
WITH skip = '1', delimiter = ',';

-- 从 S3 加载
IMPORT INTO orders
CSV DATA ('s3://bucket/orders/*.csv?AWS_ACCESS_KEY_ID=...&AWS_SECRET_ACCESS_KEY=...')
WITH skip = '1';

-- COPY FROM STDIN (PostgreSQL 兼容)
COPY orders FROM STDIN WITH CSV HEADER;

-- EXPORT (导出)
EXPORT INTO CSV 's3://bucket/export/orders/' FROM SELECT * FROM orders;
EXPORT INTO PARQUET 'gs://bucket/export/' FROM SELECT * FROM orders;

-- IMPORT 特性:
-- 1. 分布式并行加载
-- 2. 原子操作: 成功或全部回滚
-- 3. 不阻塞读取但阻塞写入
```

### TiDB

```sql
-- LOAD DATA INFILE (MySQL 兼容)
LOAD DATA LOCAL INFILE '/data/orders.csv'
INTO TABLE orders
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- TiDB Lightning (独立工具，大规模加载)
-- 支持 Local 模式 (直接写 TiKV SST 文件) 和 TiDB 模式 (通过 SQL)
-- Local 模式速度可达 500GB/小时
-- 支持 CSV, SQL dump, Parquet 格式

-- 从 S3 加载 (通过 Lightning)
-- tidb-lightning --backend=local \
--   --storage.s3.endpoint=... \
--   --mydumper.data-source-dir=s3://bucket/data/

-- LOAD DATA 的事务控制:
-- 默认非事务模式 (分批提交，不可回滚)
-- 可配置: SET @@tidb_dml_batch_size = 20000;
```

### SingleStore (MemSQL)

```sql
-- LOAD DATA INFILE (MySQL 兼容)
LOAD DATA INFILE '/data/orders.csv'
INTO TABLE orders
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- Pipeline (SingleStore 独有的持续加载机制)
CREATE PIPELINE orders_pipeline AS
LOAD DATA S3 's3://bucket/orders/'
CONFIG '{"region": "us-east-1"}'
CREDENTIALS '{"aws_access_key_id": "...", "aws_secret_access_key": "..."}'
INTO TABLE orders
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- 启动 Pipeline
START PIPELINE orders_pipeline;

-- Pipeline 特性:
-- 1. 持续监控数据源，自动加载新文件
-- 2. Exactly-once 语义
-- 3. 支持 S3, Kafka, Azure Blob, GCS, HDFS
-- 4. 自动并行 (按 partition 分发)
```

### Vertica

```sql
-- COPY FROM (主要加载方式)
COPY orders FROM '/data/orders.csv'
DELIMITER ','
ENCLOSED BY '"'
SKIP 1
DIRECT   -- 直接加载 (跳过 WOS，直接写 ROS)
STREAM NAME 'orders_load'
REJECTED DATA '/data/orders_rejects.txt'
EXCEPTIONS '/data/orders_exceptions.txt';

-- 从 S3 加载
COPY orders FROM 's3://bucket/orders/*.csv'
DELIMITER ','
SKIP 1;

-- 从 Parquet 加载
COPY orders FROM 's3://bucket/orders/*.parquet' PARQUET;

-- 导出
EXPORT TO PARQUET (directory = 's3://bucket/export/')
AS SELECT * FROM orders;

EXPORT TO CSV (directory = '/data/export/')
AS SELECT * FROM orders;

-- DIRECT vs TRICKLE 加载:
-- TRICKLE (默认): 数据先写入 WOS (Write Optimized Store)，后台合并到 ROS
-- DIRECT: 数据直接写入 ROS (Read Optimized Store)，适合大批量加载
```

### StarRocks / Doris

```sql
-- Stream Load (HTTP API，小批量)
-- curl --location-trusted -u user:pass \
--   -H "format: csv" -H "column_separator: ," \
--   -T orders.csv \
--   http://fe_host:8030/api/db/orders/_stream_load

-- Broker Load (大批量，从 HDFS/S3)
LOAD LABEL db.label_20240101
(
    DATA INFILE("s3://bucket/orders/*.csv")
    INTO TABLE orders
    COLUMNS TERMINATED BY ","
    (id, name, amount, order_date)
)
WITH BROKER "broker_name"
PROPERTIES (
    "timeout" = "3600",
    "max_filter_ratio" = "0.1"  -- 允许 10% 错误率
);

-- Routine Load (从 Kafka 持续加载)
CREATE ROUTINE LOAD db.orders_routine ON orders
COLUMNS TERMINATED BY ","
PROPERTIES (
    "format" = "csv",
    "max_error_number" = "100"
)
FROM KAFKA (
    "kafka_broker_list" = "broker1:9092",
    "kafka_topic" = "orders"
);

-- 导出
EXPORT TABLE orders
TO "s3://bucket/export/orders/"
PROPERTIES (
    "format" = "parquet",
    "column_separator" = ","
)
WITH BROKER "broker_name";

-- StarRocks 独有: INSERT INTO ... FILES() (3.1+)
INSERT INTO FILES(
    "path" = "s3://bucket/export/",
    "format" = "parquet",
    "compression" = "zstd"
)
SELECT * FROM orders;

-- Doris Stream Load 返回 JSON 结果:
-- {"TxnId": 123, "Status": "Success", "NumberTotalRows": 10000,
--  "NumberFilteredRows": 5, "NumberUnselectedRows": 0}
```

### Greenplum

```sql
-- COPY (PostgreSQL 兼容)
COPY orders FROM '/data/orders.csv' WITH (FORMAT csv, HEADER true);

-- gpfdist 外部表 (推荐的高性能加载方式)
-- 启动 gpfdist: gpfdist -d /data -p 8081 &
CREATE EXTERNAL TABLE ext_orders (LIKE orders)
LOCATION ('gpfdist://etl-host:8081/orders.csv')
FORMAT 'CSV' (HEADER);

INSERT INTO orders SELECT * FROM ext_orders;

-- 可写外部表 (导出)
CREATE WRITABLE EXTERNAL TABLE export_orders (LIKE orders)
LOCATION ('gpfdist://etl-host:8081/export/orders.csv')
FORMAT 'CSV';

INSERT INTO export_orders SELECT * FROM orders;

-- S3 外部表 (Greenplum 5+)
CREATE EXTERNAL TABLE s3_orders (LIKE orders)
LOCATION ('s3://bucket/orders/ config=/home/gpadmin/s3.conf')
FORMAT 'CSV';

-- 错误处理
COPY orders FROM '/data/orders.csv' WITH (FORMAT csv)
LOG ERRORS SEGMENT REJECT LIMIT 100 ROWS;
-- 查看错误: SELECT * FROM gp_read_error_log('orders');
```

### 其他引擎简要语法

#### OceanBase / TiDB / YugabyteDB (兼容层)

```sql
-- OceanBase (MySQL 模式): 兼容 LOAD DATA，支持 parallel hint
LOAD DATA /*+ parallel(4) */ INFILE '/data/orders.csv'
INTO TABLE orders FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n' IGNORE 1 LINES;

-- TiDB: 兼容 MySQL LOAD DATA；大规模加载推荐 TiDB Lightning (支持 CSV, SQL, Parquet)
LOAD DATA LOCAL INFILE '/data/orders.csv'
INTO TABLE orders FIELDS TERMINATED BY ',' LINES TERMINATED BY '\n' IGNORE 1 LINES;

-- YugabyteDB: 完全兼容 PostgreSQL COPY
COPY orders FROM '/data/orders.csv' WITH (FORMAT csv, HEADER true);
```

#### MonetDB / CrateDB / QuestDB

```sql
-- MonetDB: COPY INTO，支持 OFFSET 和 RECORDS 参数
COPY INTO orders FROM '/data/orders.csv' USING DELIMITERS ',', '\n', '"' NULL AS '';
COPY 10000 OFFSET 100 RECORDS INTO orders FROM '/data/orders.csv';

-- CrateDB: COPY FROM 支持 URL 和 S3
COPY orders FROM 's3://bucket/orders/*.json' WITH (format = 'json');

-- QuestDB: REST API 或 SQL COPY，CSV 加载约 120 万行/秒 (单核)
COPY orders FROM '/data/orders.csv' WITH HEADER true DELIMITER ',';
-- 推荐使用 ILP (InfluxDB Line Protocol) 获得最高性能
```

#### Exasol / SAP HANA / Informix

```sql
-- Exasol: IMPORT FROM / EXPORT INTO，支持 REJECT LIMIT
IMPORT INTO orders FROM LOCAL CSV FILE '/data/orders.csv'
COLUMN SEPARATOR = ',' SKIP = 1 REJECT LIMIT 100;
EXPORT orders INTO LOCAL CSV FILE '/data/export.csv' WITH COLUMN NAMES;

-- SAP HANA: IMPORT FROM，支持多线程和云存储 (SAP HANA Cloud)
IMPORT FROM CSV FILE '/data/orders.csv' INTO orders
WITH FIELD DELIMITED BY ',' SKIP FIRST 1 ROW ERROR LOG '/data/errors.csv' THREADS 10;

-- Informix: LOAD FROM / UNLOAD TO
LOAD FROM '/data/orders.csv' DELIMITER ',' INSERT INTO orders;
UNLOAD TO '/data/export.csv' DELIMITER ',' SELECT * FROM orders;
```

#### H2 / HSQLDB / Derby

```sql
-- H2: CSVREAD/CSVWRITE 函数
INSERT INTO orders SELECT * FROM CSVREAD('/data/orders.csv');
CALL CSVWRITE('/data/export.csv', 'SELECT * FROM orders');

-- HSQLDB: TEXT TABLE 方式
SET TABLE orders SOURCE '/data/orders.csv;fs=,;ignore_first=true';

-- Derby: 系统过程
CALL SYSCS_UTIL.SYSCS_IMPORT_TABLE(null, 'ORDERS', '/data/orders.csv', ',', '"', null, 0);
```

#### Amazon Athena / Azure Synapse

```sql
-- Athena: 数据在 S3，通过外部表定义查询 (不加载到引擎内部)
CREATE EXTERNAL TABLE orders (id BIGINT, name STRING, amount DECIMAL(10,2))
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE LOCATION 's3://bucket/orders/'
TBLPROPERTIES ('skip.header.line.count'='1');

-- Athena v3 UNLOAD (导出)
UNLOAD (SELECT * FROM orders) TO 's3://bucket/export/'
WITH (format = 'PARQUET', compression = 'SNAPPY');

-- Azure Synapse: COPY INTO (推荐)
COPY INTO orders
FROM 'https://account.blob.core.windows.net/container/orders/*.csv'
WITH (FILE_TYPE = 'CSV', FIRSTROW = 2, CREDENTIAL = (IDENTITY = 'Managed Identity'));

-- Synapse 导出: CETAS (Create External Table As Select)
CREATE EXTERNAL TABLE [export_orders]
WITH (LOCATION = '/export/', DATA_SOURCE = my_adls, FILE_FORMAT = parquet_format)
AS SELECT * FROM orders;
```

#### Google Spanner / InfluxDB / Materialize / RisingWave

```
无 SQL 批量加载语法的引擎:

Spanner: 通过 Mutation API 或 Dataflow 模板加载，无 COPY/LOAD SQL 语法
InfluxDB: 使用 Line Protocol 或 HTTP API /api/v2/write，无 SQL COPY
Materialize: 支持 PG COPY FROM STDIN；主要通过 CREATE SOURCE (Kafka/CDC) 摄入
RisingWave: 支持 COPY FROM；主要通过 CREATE SOURCE 定义流式摄入
```

#### DatabendDB / Yellowbrick / Firebolt

```sql
-- DatabendDB: 与 Snowflake 语法高度兼容的 Stage 模式
COPY INTO orders FROM @my_stage/orders/
FILE_FORMAT = (TYPE = CSV FIELD_DELIMITER = ',' SKIP_HEADER = 1) ON_ERROR = CONTINUE;
COPY INTO @my_stage/export/ FROM (SELECT * FROM orders) FILE_FORMAT = (TYPE = PARQUET);

-- Yellowbrick: PostgreSQL 风格 COPY，扩展 S3 支持
COPY orders FROM 's3://bucket/orders/*.parquet' WITH (FORMAT parquet);

-- Firebolt: 外部表 + COPY INTO
CREATE EXTERNAL TABLE ext_orders (id BIGINT, name TEXT, amount DECIMAL(10,2))
URL = 's3://bucket/orders/' TYPE = (CSV SKIP_HEADER_ROWS = 1);
COPY INTO orders FROM ext_orders;
```

#### SQLite / Firebird / Derby (无 SQL 批量导入)

```
SQLite: CLI 的 .import 命令 (.mode csv; .import file.csv table)
Firebird: 无原生批量加载; gbak (备份恢复) 或第三方工具
Derby: SYSCS_UTIL.SYSCS_IMPORT_TABLE 系统过程
这些引擎依赖外部工具或客户端程序的批量 INSERT。
```

## 云 Stage 模式 (Cloud Stage Patterns)

现代云数据仓库引入了"Stage"概念，将批量加载分解为"上传 → 暂存 → 加载"三步，这与传统数据库的"文件 → 表"两步模式有本质区别。

### Snowflake Stage 模式

```
加载流程:
  本地文件 → PUT 上传 → 内部/外部 Stage → COPY INTO → 目标表
                              ↑
  云存储 (S3/GCS/Azure) ──────┘

三种 Stage 类型:
  1. Table Stage (@%table_name): 每个表自动创建
  2. User Stage (@~): 每个用户自动创建
  3. Named Stage (@stage_name): 手动创建，最灵活

关键特性:
  - 文件去重: 记录已加载文件的元数据 (64天)，防止重复加载
  - 分布式并行: 多个虚拟仓库节点同时读取不同文件
  - 压缩感知: 自动识别 gzip/zstd/snappy/lz4/bzip2/brotli/deflate
  - 加载转换: COPY INTO 支持在加载时做 SELECT 转换
```

### BigQuery Load Job 模式

```
加载流程:
  本地文件 → bq load → BigQuery 服务 → 目标表
  GCS 文件 → Load Job API → BigQuery 服务 → 目标表
  Streaming → insertAll API → 目标表 (实时，但收费)

关键特性:
  - Load Job 免费 (不消耗 slot)
  - Schema auto-detection 支持
  - 每个项目每天最多 100,000 次 load job
  - 单次 load job 最大 15TB
  - Streaming insert 有延迟但实时性好
  - EXPORT DATA 是反向操作 (BigQuery → GCS)
```

### Redshift COPY from S3 模式

```
加载流程:
  S3 文件 → COPY 命令 → Redshift 集群各 slice 并行读取 → 目标表

关键特性:
  - 强制推荐从 S3 加载 (本地加载不支持)
  - 文件数应为 slice 数的倍数 (最佳并行度)
  - Manifest 文件精确控制加载哪些文件
  - 与 Spectrum 集成: 外部表可直接查询 S3
  - UNLOAD 是反向操作 (Redshift → S3)
  - 支持跨区域 COPY (指定 REGION 参数)
```

### Databricks Volume / DBFS 模式

```
加载流程:
  云存储 → COPY INTO → Delta Table
  DBFS 文件 → COPY INTO → Delta Table
  Unity Catalog Volume → COPY INTO → Delta Table

关键特性:
  - 幂等加载: 基于文件元数据的去重
  - Schema 演进: mergeSchema 支持
  - Auto Loader: Structured Streaming 实现的持续加载
  - _rescued_data 列: 捕获 schema 不匹配的数据
  - Delta Lake 事务保证 ACID
```

### DatabendDB Stage 模式

```
加载流程:
  本地文件 → 内部 Stage → COPY INTO → 目标表
  云存储 (S3/GCS/Azure) → 外部 Stage → COPY INTO → 目标表

关键特性:
  - 与 Snowflake 语法高度兼容
  - 支持 Presigned URL 上传
  - 按 micro-block 并行加载
  - 支持加载时数据转换
```

## 性能对比概览

| 类型 | 代表引擎 | 典型速度 | 关键加速手段 |
|------|------|------|------|
| 行式数据库 (本地文件) | PostgreSQL COPY | 10-50 万行/秒 | UNLOGGED TABLE, 禁用索引, FREEZE |
| 行式数据库 (本地文件) | MySQL LOAD DATA | 5-30 万行/秒 | 关闭 autocommit, 禁用唯一性检查 |
| 行式数据库 (本地文件) | SQL Server BULK INSERT | 10-50 万行/秒 | TABLOCK, 最小日志模式 |
| 行式数据库 (直接路径) | Oracle SQL*Loader Direct | 10-100 万行/秒 | 直接路径跳过 SQL 层和缓冲区 |
| 列式单机 | ClickHouse INSERT | 100 万+ 行/秒 | 列式压缩存储, 异步合并, 无事务开销 |
| 列式单机 | DuckDB COPY | 100 万+ 行/秒 | Parquet 列式扫描, 向量化 |
| 云数仓 (分布式) | Snowflake COPY INTO | 极高 (弹性伸缩) | 多仓库节点并行, 文件级分发 |
| 云数仓 (分布式) | BigQuery Load Job | 极高 (托管) | 完全托管基础设施, 免费加载 |
| 云数仓 (分布式) | Redshift COPY | 极高 (按 slice) | 文件数 = slice 倍数, 列式格式 |
| 大数据引擎 | Spark SQL | 取决于集群规模 | Executor 级并行, 弹性扩展 |
| 大数据引擎 | Hive LOAD DATA | 取决于 HDFS | 本质是文件移动，不解析 |
| 时序数据库 | QuestDB CSV | 120 万+ 行/秒 | 时间序列优化存储, 列式追加 |

## 关键发现

1. **COPY 是最广泛的命令名称**，但语义差异巨大。PostgreSQL 的 `COPY FROM/TO` 处理本地/服务端文件和 STDIN；Redshift 的 `COPY` 只接受 S3；Snowflake 的 `COPY INTO` 引入了 Stage 抽象；DuckDB 的 `COPY` 支持直接读取 S3 和 HTTP URL。同一关键字背后是完全不同的数据流架构。

2. **文件格式支持呈现两极分化**。传统关系型数据库（PostgreSQL、MySQL、Oracle、SQL Server）几乎只支持 CSV/TSV 和文本格式。而大数据与云原生引擎（ClickHouse、Snowflake、Spark SQL、Trino）普遍支持 Parquet、ORC、Avro 等列式和序列化格式。ClickHouse 以支持 70+ 种格式独领风骚。

3. **云 Stage 模式是范式转移**。Snowflake 的 Stage 概念将"文件上传"与"数据加载"解耦，实现了文件去重、分布式并行、压缩感知等企业级特性。DatabendDB、Firebolt 等新兴引擎纷纷采用类似模式。这一架构的前提是存储计算分离。

4. **错误处理策略差异显著**。PostgreSQL 最保守——任何错误全部回滚；Snowflake 提供五种灵活策略；Spark SQL 默认 PERMISSIVE 模式（容忍错误，将坏数据放入特殊列）。对于 TB 级加载任务，错误处理策略直接影响运维复杂度。

5. **事务保证与加载性能天然矛盾**。PostgreSQL、CockroachDB 提供完全 ACID 事务但单线程加载；ClickHouse、Hive 放弃事务保证但获得极高吞吐。Snowflake 取折中方案——文件级原子性而非全局原子性。引擎开发者需要在这一频谱上做出明确选择。

6. **并行加载能力与部署架构强相关**。单机数据库（PostgreSQL、MySQL）需要手动分文件并开多连接；MPP 数据库（Redshift、Greenplum）按 slice/segment 自动并行；云原生引擎（Snowflake、BigQuery）完全自动化。加载并行度通常等于计算节点数或切片数。

7. **部分引擎完全没有 SQL 批量加载语法**。SQLite 依赖 CLI 的 `.import`；Google Spanner 只提供 Mutation API；InfluxDB 使用专有的 Line Protocol；Firebird 和 Derby 依赖外部工具。这些引擎的设计哲学中，批量加载不被视为 SQL 层的职责。

8. **MySQL 生态兼容性最广**。TiDB、OceanBase、SingleStore、StarRocks（有限）都兼容 `LOAD DATA INFILE` 语法。PostgreSQL 生态的 COPY 兼容性也很好——Greenplum、YugabyteDB、TimescaleDB、CockroachDB、Materialize 都支持。选择加载语法时，生态兼容性是重要考量。

9. **压缩支持两极化**。传统数据库（MySQL、SQL Server）不原生支持压缩文件加载（需外部管道）。PostgreSQL 16+ 新增了原生 gzip 压缩支持。云和大数据引擎普遍支持 gzip/zstd/snappy 等多种压缩格式并可自动检测。这一差异在 TB 级数据迁移中尤为关键。

10. **导出能力普遍弱于导入**。多数引擎在导入方面投入了大量优化，但导出命令往往功能有限。Redshift 的 `UNLOAD`、BigQuery 的 `EXPORT DATA`、Snowflake 的 `COPY INTO @stage` 是设计较完善的导出方案。CockroachDB 的 `EXPORT INTO` 支持直接导出 Parquet 到云存储，代表了现代设计趋势。

## 参考资料

- PostgreSQL: [COPY](https://www.postgresql.org/docs/current/sql-copy.html)
- MySQL: [LOAD DATA](https://dev.mysql.com/doc/refman/8.0/en/load-data.html)
- SQL Server: [BULK INSERT](https://learn.microsoft.com/en-us/sql/t-sql/statements/bulk-insert-transact-sql)
- Oracle: [SQL*Loader](https://docs.oracle.com/en/database/oracle/oracle-database/19/sutil/oracle-sql-loader.html)
- Snowflake: [COPY INTO](https://docs.snowflake.com/en/sql-reference/sql/copy-into-table)
- BigQuery: [Loading Data](https://cloud.google.com/bigquery/docs/loading-data)
- Redshift: [COPY](https://docs.aws.amazon.com/redshift/latest/dg/r_COPY.html)
- ClickHouse: [INSERT](https://clickhouse.com/docs/en/sql-reference/statements/insert-into)
- DuckDB: [COPY](https://duckdb.org/docs/sql/statements/copy)
- Spark SQL: [DataSource](https://spark.apache.org/docs/latest/sql-data-sources.html)
- Hive: [LOAD DATA](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DML)
- Databricks: [COPY INTO](https://docs.databricks.com/en/sql/language-manual/delta-copy-into.html)
- CockroachDB: [IMPORT INTO](https://www.cockroachlabs.com/docs/stable/import-into)
- Vertica: [COPY](https://docs.vertica.com/latest/en/sql-reference/statements/copy/)
- StarRocks: [Loading](https://docs.starrocks.io/docs/loading/Loading_intro/)
- Doris: [Data Loading](https://doris.apache.org/docs/data-operate/import/load-manual)
- DatabendDB: [COPY INTO](https://docs.databend.com/sql/sql-commands/dml/dml-copy-into-table)
- Teradata: [FastLoad](https://docs.teradata.com/search/documents?query=fastload)
- Greenplum: [gpfdist](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-external-g-using-the-greenplum-parallel-file-server--gpfdist-.html)
- SingleStore: [Pipelines](https://docs.singlestore.com/cloud/load-data/use-pipelines/)
