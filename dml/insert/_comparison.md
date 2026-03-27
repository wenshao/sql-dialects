# 插入 (INSERT) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| 单行 INSERT | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 多行 VALUES | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ |
| INSERT SELECT | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| CTE + INSERT | ✅ 8.0.19+ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| RETURNING | ❌ | ✅ | ✅ 3.35+ | ✅ | ✅ OUTPUT | ✅ 10.5+ | ✅ RETURNING | ✅ FINAL TABLE | ❌ |
| INSERT IGNORE | ✅ | ❌ | ✅ INSERT OR IGNORE | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| 默认值行 | ✅ DEFAULT | ✅ DEFAULT | ✅ DEFAULT | ✅ DEFAULT | ✅ DEFAULT | ✅ DEFAULT | ✅ DEFAULT | ✅ DEFAULT | ✅ DEFAULT |
| 多表 INSERT | ❌ | ❌ | ❌ | ✅ INSERT ALL | ❌ | ❌ | ❌ | ❌ | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 多行 VALUES | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| INSERT SELECT | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| INSERT OVERWRITE | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| 批量加载 | ✅ LOAD | ✅ COPY | ✅ TUNNEL | ✅ LOAD | ✅ 多格式 | ✅ Stream Load | ❌ | ✅ COPY | ✅ Stream Load | ✅ COPY | ❌ | ❌ |
| STRUCT/ARRAY 插入 | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| 流式插入 | ✅ Streaming | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ Streaming | ✅ |

### 云数据仓库 / 分布式 / 特殊用途

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| 多行 VALUES | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| INSERT OVERWRITE | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ |
| RETURNING | ❌ | ✅ OUTPUT | ❌ | ✅ | ❌ | ❌ | ❌ |
| COPY/LOAD | ✅ COPY | ✅ COPY | ❌ | ✅ COPY | ❌ | ✅ COPY | ✅ FastLoad |

## 关键差异

- **Oracle** 不支持多行 VALUES 语法，需用 INSERT ALL 或 SELECT UNION ALL
- **Firebird** 也不支持多行 VALUES，需逐行插入或用 EXECUTE BLOCK
- **INSERT OVERWRITE** 是大数据引擎（Hive/Spark/MaxCompute）的特色，覆盖分区数据
- **PostgreSQL** RETURNING 子句最完善，可返回插入的行数据
- **SQL Server** 使用 OUTPUT 子句替代 RETURNING
- **Db2** 使用 SELECT FROM FINAL TABLE(INSERT...) 获取插入数据
- **ClickHouse** 支持多种格式直接插入（CSV, JSON, Parquet 等）
- **Flink** 不支持 VALUES 直接插入，数据来自流式 SOURCE
- **BigQuery** DML 操作有配额限制（每表每天 1500 次）
