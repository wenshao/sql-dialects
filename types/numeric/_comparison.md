# 数值类型 (Numeric Types) — 方言对比

## 类型支持对比

### 传统 RDBMS

| 类型 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| TINYINT (1B) | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ |
| SMALLINT (2B) | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| INT/INTEGER (4B) | ✅ | ✅ | ✅ 动态 | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| BIGINT (8B) | ✅ | ✅ | ✅ 动态 | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| NUMBER/NUMERIC | ❌ | ✅ | ✅ | ✅ NUMBER | ✅ | ❌ | ✅ | ✅ | ✅ |
| DECIMAL | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ |
| FLOAT (4B) | ✅ | ✅ REAL | ✅ REAL | ✅ | ✅ REAL | ✅ | ✅ | ✅ | ✅ |
| DOUBLE (8B) | ✅ | ✅ DOUBLE PRECISION | ✅ REAL | ✅ | ✅ FLOAT | ✅ | ✅ DOUBLE PRECISION | ✅ | ✅ |
| BOOLEAN | ⚠️ TINYINT | ✅ | ❌ | ❌ | ✅ BIT | ⚠️ TINYINT | ✅ | ✅ | ✅ |
| UNSIGNED | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| MONEY | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |

### 大数据 / 分析引擎

| 类型 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| TINYINT | ❌ | ❌ | ✅ | ✅ | ✅ Int8/UInt8 | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| SMALLINT | ❌ | ❌ | ✅ | ✅ | ✅ Int16/UInt16 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| INT | ❌ | ❌ | ✅ | ✅ | ✅ Int32/UInt32 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| BIGINT | ❌ INT64 | ❌ NUMBER | ✅ | ✅ | ✅ Int64/UInt64 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| NUMERIC/DECIMAL | ✅ NUMERIC | ✅ NUMBER | ✅ | ✅ | ✅ Decimal | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| FLOAT | ✅ FLOAT64 | ✅ FLOAT | ✅ | ✅ | ✅ Float32/64 | ✅ | ✅ REAL/DOUBLE | ✅ | ✅ | ✅ | ✅ | ✅ |
| BOOLEAN | ✅ BOOL | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| UNSIGNED | ❌ | ❌ | ❌ | ❌ | ✅ UInt8-256 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| INT128/INT256 | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ LARGEINT | ❌ | ❌ | ✅ LARGEINT | ✅ HUGEINT | ❌ | ❌ |
| BIGNUMERIC | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

## 关键差异

- **Oracle** 没有 INT/BIGINT 等整数类型，统一使用 NUMBER(p,s)
- **BigQuery** 只有 INT64 和 FLOAT64 两种数值基础类型（加 NUMERIC/BIGNUMERIC）
- **Snowflake** 所有整数类型都映射到 NUMBER(38,0)
- **SQLite** 只有动态类型，INTEGER 可存储 1-8 字节
- **ClickHouse** 类型最丰富：支持 UInt8-256 无符号整数和 Int128/Int256
- **MySQL/MariaDB** 独有 UNSIGNED 修饰符
- **BOOLEAN**：MySQL 用 TINYINT(1) 模拟，Oracle 无原生布尔，SQL Server 用 BIT
- **DECIMAL 精度**：Oracle NUMBER 最大 38 位，BigQuery BIGNUMERIC 76 位
