# 字符串类型 (String Types) — 方言对比

## 类型支持对比

### 传统 RDBMS

| 类型 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| CHAR(n) | ✅ 255 | ✅ 10485760 | ❌ TEXT | ✅ 2000 | ✅ 8000 | ✅ 255 | ✅ 32767 | ✅ 254 | ✅ 5000 |
| VARCHAR(n) | ✅ 65535 | ✅ 10485760 | ❌ TEXT | ✅ 4000/32767 | ✅ 8000 | ✅ 65535 | ✅ 32767 | ✅ 32672 | ✅ 5000 |
| TEXT | ✅ 分层 | ✅ 无限 | ✅ 无限 | ❌ CLOB | ✅ 2GB | ✅ 分层 | ❌ BLOB SUB_TYPE 1 | ✅ CLOB | ✅ NCLOB |
| NCHAR/NVARCHAR | ✅ | ❌ | ❌ | ✅ | ✅ NVARCHAR | ✅ | ❌ | ❌ | ✅ |
| CLOB/NCLOB | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| BINARY/VARBINARY | ✅ | ✅ BYTEA | ✅ BLOB | ✅ RAW | ✅ | ✅ | ✅ | ✅ | ✅ |
| BLOB | ✅ 分层 | ❌ BYTEA | ✅ | ✅ | ❌ VARBINARY(MAX) | ✅ 分层 | ✅ | ✅ | ✅ |
| ENUM | ✅ | ✅ 自定义 | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| SET | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| UUID | ❌ | ✅ | ❌ | ❌ | ✅ UNIQUEIDENTIFIER | ❌ | ❌ | ❌ | ❌ |
| 字符集 | 多种 | UTF-8 | UTF-8 | 多种 | Unicode | 多种 | 多种 | 多种 | Unicode |

### 大数据 / 分析引擎

| 类型 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| STRING | ✅ 无限 | ✅ 16MB | ✅ 8MB | ✅ 无限 | ✅ String | ✅ 无限 | ✅ VARCHAR | ✅ TEXT | ✅ 无限 | ✅ VARCHAR | ✅ 无限 | ✅ STRING |
| CHAR(n) | ❌ | ✅ | ✅ | ✅ | ✅ FixedString | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| VARCHAR(n) | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| BYTES/BINARY | ✅ BYTES | ✅ BINARY | ✅ | ✅ | ❌ | ❌ | ✅ VARBINARY | ✅ BYTEA | ❌ | ✅ BLOB | ✅ | ✅ |
| UUID | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| ENUM | ❌ | ❌ | ❌ | ❌ | ✅ Enum8/16 | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| ARRAY\<STRING\> | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |

## 关键差异

- **SQLite** 只有 TEXT 类型，所有字符串都是动态类型
- **BigQuery** 只有 STRING，无 CHAR/VARCHAR 区分
- **Spark** 也只有 STRING 类型，无 CHAR/VARCHAR
- **Oracle** 使用 VARCHAR2 而非 VARCHAR（VARCHAR 是保留词）
- **MySQL** TEXT 分四层：TINYTEXT/TEXT/MEDIUMTEXT/LONGTEXT
- **PostgreSQL** VARCHAR 无长度限制时等价于 TEXT
- **ClickHouse** 使用 FixedString(n) 替代 CHAR(n)，String 替代 VARCHAR
- **SQL Server** 区分 VARCHAR (非 Unicode) 和 NVARCHAR (Unicode)
- **字符集**：MySQL/MariaDB 每表可指定字符集，PostgreSQL 全库统一 UTF-8
