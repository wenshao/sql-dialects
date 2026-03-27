# 条件函数 (Conditional Functions) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| CASE WHEN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| COALESCE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| NULLIF | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| IF() | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| IIF() | ❌ | ❌ | ✅ | ❌ | ✅ 2012+ | ❌ | ❌ | ❌ | ❌ |
| IFNULL | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ |
| NVL | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| NVL2 | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| ISNULL | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| DECODE | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ |
| GREATEST/LEAST | ✅ | ✅ | ✅ 3.34+ | ✅ | ✅ 2022+ | ✅ | ❌ | ✅ | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| CASE WHEN | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| COALESCE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| IF() | ✅ | ✅ IFF | ❌ | ✅ | ✅ if | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| IFNULL | ✅ | ✅ | ❌ | ❌ | ✅ ifNull | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| NVL | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |
| GREATEST/LEAST | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

## 关键差异

- **CASE WHEN** 和 **COALESCE** 是唯一在所有方言中通用的条件表达式
- **IF()** 函数：MySQL/BigQuery/Hive/ClickHouse/Spark 支持，PostgreSQL/Oracle/SQL Server 不支持
- **NVL** 是 Oracle 特有，ISNULL 是 SQL Server 特有，IFNULL 是 MySQL 特有
- **Snowflake** 使用 IFF() 而非 IF()（三参数条件函数）
- **DECODE** 是 Oracle 特色函数，部分方言兼容（Db2, Firebird）
- **IIF()** 仅 SQL Server 和 SQLite 支持
- **GREATEST/LEAST** 在 SQL Server 2022 之前不支持
