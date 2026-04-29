# 整数类型 (Integer Types)

`INT` 看似最朴素的 SQL 类型，却是 45+ 数据库方言中差异最大的领域之一：MySQL 的 `TINYINT(1)` 是 1 字节有符号整数（被用作布尔），ClickHouse 的 `Int128` 是 16 字节大整数（用于加密哈希），Snowflake 的 `INT` 实际是 `NUMBER(38, 0)`（变长十进制），SQLite 的 `INTEGER` 根据值大小动态使用 1-8 字节。一个 4 字节的差异（`INT` vs `BIGINT`）能决定一张订单表能撑 21 亿行还是 92 亿亿行；一个 `UNSIGNED` 修饰能把容量翻倍但让 `JOIN` 中的隐式类型转换静默出错；`MEDIUMINT` 是 MySQL 独有的 3 字节类型，节约 25% 存储但跨库迁移时无对应类型。本文系统梳理整数类型的存储规模、值域、UNSIGNED 变体、128 位扩展整数与 SERIAL 自增类型在 45+ SQL 方言中的实现细节，是引擎开发者与跨库迁移工程师的核心参考。

## 整数类型的本质：存储规模 vs 值域

整数类型的核心权衡是**存储规模与值域的指数关系**：每增加 1 字节，可表示范围扩大 256 倍；每增加 1 位，可表示范围翻倍。下表汇总了主流整数类型的位宽、字节数与值域：

| 类型 | 字节 | 位宽 | 有符号最小值 | 有符号最大值 | 无符号最大值 | 典型用途 |
|------|------|------|------------|------------|------------|---------|
| TINYINT (Int8) | 1 | 8 | -128 | 127 | 255 | 状态码、布尔标志 |
| SMALLINT (Int16) | 2 | 16 | -32768 | 32767 | 65535 | 年龄、端口号、年份 |
| MEDIUMINT (MySQL) | 3 | 24 | -8388608 | 8388607 | 16777215 | 中等规模 ID（仅 MySQL） |
| INTEGER / INT (Int32) | 4 | 32 | -2147483648 | 2147483647 | 4294967295 | 通用 ID、计数器 |
| BIGINT (Int64) | 8 | 64 | -9223372036854775808 | 9223372036854775807 | 18446744073709551615 | 大表 ID、时间戳 |
| INT128 (HUGEINT) | 16 | 128 | -2^127 | 2^127 - 1 | 2^128 - 1 | 加密哈希、金融、UUID 整数化 |
| INT256 (ClickHouse) | 32 | 256 | -2^255 | 2^255 - 1 | 2^256 - 1 | 区块链地址、超大 ID 空间 |

> 关键经验：每升一档可表示范围扩大约 65000 倍（16 位提升），存储成本仅翻倍。对于 ID 列，`BIGINT` 是工业级安全选择；对 `TIMESTAMP` 毫秒时间戳，`BIGINT` 同样必备（`INT` 只能撑到 2038 年的 Unix 时间戳问题）。

### UNSIGNED 变体的两面性

`UNSIGNED` 修饰移除符号位，将正值范围翻倍。但代价显著：

1. **跨类型 JOIN 隐患**：`UNSIGNED INT` 与 `INT` 比较时，MySQL 会将 `INT` 隐式转为 `UNSIGNED`，负数变成超大正数。
2. **算术溢出陷阱**：MySQL 中 `1 - 2` 在 `UNSIGNED` 列下会回绕到 `18446744073709551615`（除非启用 `NO_UNSIGNED_SUBTRACTION`）。
3. **方言可移植性差**：标准 SQL 没有 `UNSIGNED`，仅 MySQL 系（MySQL/MariaDB/TiDB/SingleStore/OceanBase MySQL 模式）和列式引擎（ClickHouse/DuckDB/DatabendDB）支持。
4. **驱动协议复杂化**：JDBC `getInt()` 对 `UNSIGNED INT` 列返回值可能为负（需 `getLong()`）。

### 128 位整数的崛起

近 5 年（2019-2024），列式分析引擎大规模引入 128 位整数：

- **ClickHouse**: `Int128`/`UInt128`（19.7, 2019）和 `Int256`/`UInt256`（20.4, 2020）
- **DuckDB**: `HUGEINT`（128 位有符号，0.x 早期版本）
- **CockroachDB**: `INT128`（21.1, 2021）
- **Firebird**: `INT128`（4.0, 2021）
- **StarRocks/Doris**: `LARGEINT`（128 位有符号）
- **MonetDB**: `HUGEINT`（128 位）

典型用途：
- **加密哈希**：MD5（128 位）、SHA-256 截断
- **金融计算**：高精度货币（避免 `DOUBLE` 精度损失）
- **UUID 整数化**：将 36 字符 UUID 压缩为 16 字节
- **区块链**：以太坊地址（160 位需 256 位整型）、交易金额（Wei 单位）
- **超大 ID 空间**：分布式雪花算法的全局唯一 ID

## SQL 标准对整数类型的定义

### SQL:1992 (`SMALLINT` / `INTEGER`)

ISO/IEC 9075:1992 第 4.3.1 节定义了精确数值类型，整数类型仅有：

```
<exact numeric type> ::=
      NUMERIC [ <left paren> <precision> [ <comma> <scale> ] <right paren> ]
    | DECIMAL [ <left paren> <precision> [ <comma> <scale> ] <right paren> ]
    | DEC     [ <left paren> <precision> [ <comma> <scale> ] <right paren> ]
    | INTEGER
    | INT
    | SMALLINT
```

标准的关键约束：

1. **`INTEGER` 至少容纳 ±2^31**：标准未严格规定字节数，但实现普遍使用 4 字节。
2. **`SMALLINT` 至少容纳 ±2^15**：实现普遍使用 2 字节。
3. **`SMALLINT` 的精度 ≤ `INTEGER`**：实现细节由各引擎自定。
4. **不规定无符号变体**：`UNSIGNED` 完全是 MySQL 等引擎的扩展。
5. **不规定 `TINYINT`**：1 字节整数在标准中不存在，是 MySQL/SQL Server/Sybase 等引擎的扩展。

### SQL:2003 (`BIGINT`)

ISO/IEC 9075:2003 正式引入 `BIGINT`：

```
<exact numeric type> ::=
      ...
    | BIGINT      -- 新增
```

标准要求：

1. **`BIGINT` 至少容纳 ±2^63**：实现普遍使用 8 字节。
2. **`BIGINT` 的精度 ≥ `INTEGER`**：保持类型层级。
3. **不规定 128 位整数**：直到 SQL:2023 仍未引入更大的标准整数类型，128 位扩展全是引擎自定义。

### 实际兼容情况

| 标准类型 | 字节数 | 引入版本 | 必须实现的引擎 |
|---------|-------|---------|--------------|
| `SMALLINT` | 2 | SQL:1992 | 几乎全部主流引擎 |
| `INTEGER` / `INT` | 4 | SQL:1992 | 几乎全部主流引擎 |
| `BIGINT` | 8 | SQL:2003 | 几乎全部主流引擎（除部分轻量级嵌入式） |
| `TINYINT` | 1 | 非标准 | MySQL/SQL Server/SAP HANA 等 |
| `MEDIUMINT` | 3 | 非标准 | 仅 MySQL/MariaDB/TiDB |
| `INT128` / `HUGEINT` | 16 | 非标准 | ClickHouse/DuckDB/CockroachDB 等 |

## 支持矩阵 (45+ 引擎)

### TINYINT (1 字节)

| 引擎 | 关键字 | 有符号范围 | 无符号支持 | 版本说明 |
|------|--------|-----------|----------|---------|
| PostgreSQL | -- | -- | -- | 不支持，最小为 `SMALLINT` |
| MySQL | `TINYINT` | -128~127 | `TINYINT UNSIGNED` 0~255 | 全版本 |
| MariaDB | `TINYINT` | -128~127 | `TINYINT UNSIGNED` | 全版本 |
| SQLite | -- (映射 INTEGER) | 动态 | -- | 类型亲和性 |
| Oracle | -- | -- | -- | 仅 `NUMBER(3)` 模拟 |
| SQL Server | `TINYINT` | **0~255** (无符号!) | -- | 仅无符号 |
| DB2 | -- | -- | -- | 不支持 |
| Snowflake | `TINYINT` (别名) | NUMBER(3,0) | -- | 全部映射到 NUMBER |
| BigQuery | -- | -- | -- | 仅 INT64 |
| Redshift | -- | -- | -- | 不支持 |
| DuckDB | `TINYINT` | -128~127 | `UTINYINT` 0~255 | 0.3+ |
| ClickHouse | `Int8` | -128~127 | `UInt8` 0~255 | 全版本 |
| Trino | `TINYINT` | -128~127 | -- | 全版本 |
| Presto | `TINYINT` | -128~127 | -- | 全版本 |
| Spark SQL | `TINYINT` / `BYTE` | -128~127 | -- | 全版本 |
| Hive | `TINYINT` | -128~127 | -- | 0.11+ |
| Flink SQL | `TINYINT` | -128~127 | -- | 全版本 |
| Databricks | `TINYINT` | -128~127 | -- | 全版本 |
| Teradata | `BYTEINT` | -128~127 | -- | 专有名 |
| Greenplum | -- | -- | -- | 不支持 (继承 PG) |
| CockroachDB | -- | -- | -- | 不支持 (兼容 PG) |
| TiDB | `TINYINT` | -128~127 | `TINYINT UNSIGNED` | 兼容 MySQL |
| OceanBase | `TINYINT` | -128~127 | `TINYINT UNSIGNED` (MySQL 模式) | 双模式 |
| YugabyteDB | -- | -- | -- | 不支持 (兼容 PG) |
| SingleStore | `TINYINT` | -128~127 | `TINYINT UNSIGNED` | 兼容 MySQL |
| Vertica | `TINYINT` (别名) | INT (8B) 别名 | -- | 实际是 8 字节 |
| Impala | `TINYINT` | -128~127 | -- | 全版本 |
| StarRocks | `TINYINT` | -128~127 | -- | 全版本 |
| Doris | `TINYINT` | -128~127 | -- | 全版本 |
| MonetDB | `TINYINT` | -128~127 | -- | 全版本 |
| CrateDB | -- | -- | -- | 不支持 |
| TimescaleDB | -- | -- | -- | 不支持 (继承 PG) |
| QuestDB | `byte` | -128~127 | -- | 专有名 |
| Exasol | -- | -- | -- | 不支持 |
| SAP HANA | `TINYINT` | **0~255** (无符号!) | -- | 仅无符号 |
| Informix | -- | -- | -- | 不支持 |
| Firebird | -- | -- | -- | 不支持 |
| H2 | `TINYINT` | -128~127 | -- | 全版本 |
| HSQLDB | `TINYINT` | -128~127 | -- | 全版本 |
| Derby | -- | -- | -- | 不支持 |
| Amazon Athena | `TINYINT` | -128~127 | -- | 继承 Trino |
| Azure Synapse | `TINYINT` | **0~255** (无符号!) | -- | 继承 SQL Server |
| Google Spanner | -- | -- | -- | 仅 INT64 |
| Materialize | -- | -- | -- | 不支持 (兼容 PG) |
| RisingWave | -- | -- | -- | 不支持 (兼容 PG) |
| InfluxDB (SQL) | -- | -- | -- | 仅 i64/u64 |
| DatabendDB | `TINYINT` / `Int8` | -128~127 | `UInt8` 0~255 | 全版本 |
| Yellowbrick | -- | -- | -- | 不支持 |
| Firebolt | -- | -- | -- | 不支持 |

> **重要陷阱**：SQL Server / SAP HANA / Azure Synapse 的 `TINYINT` 是**无符号**类型（0~255），而 MySQL/ClickHouse/Hive/Spark 等的 `TINYINT` 是**有符号**类型（-128~127）。跨库迁移时这是最常见的"沉默错误"——SQL Server 的 `TINYINT 200` 迁移到 MySQL 后变成 `-56`。

### SMALLINT (2 字节)

| 引擎 | 关键字 | 有符号范围 | 无符号支持 | 版本说明 |
|------|--------|-----------|----------|---------|
| PostgreSQL | `SMALLINT` / `INT2` | -32768~32767 | -- | 全版本 |
| MySQL | `SMALLINT` | -32768~32767 | `SMALLINT UNSIGNED` 0~65535 | 全版本 |
| MariaDB | `SMALLINT` | -32768~32767 | `SMALLINT UNSIGNED` | 全版本 |
| SQLite | -- (映射 INTEGER) | 动态 | -- | 类型亲和性 |
| Oracle | `SMALLINT` (别名) | NUMBER(38) 别名 | -- | 实为 NUMBER |
| SQL Server | `SMALLINT` | -32768~32767 | -- | 全版本 |
| DB2 | `SMALLINT` | -32768~32767 | -- | 全版本 |
| Snowflake | `SMALLINT` (别名) | NUMBER(38,0) | -- | 全部映射到 NUMBER |
| BigQuery | -- | -- | -- | 仅 INT64 |
| Redshift | `SMALLINT` / `INT2` | -32768~32767 | -- | 最小整数类型 |
| DuckDB | `SMALLINT` / `INT2` | -32768~32767 | `USMALLINT` 0~65535 | 0.3+ |
| ClickHouse | `Int16` | -32768~32767 | `UInt16` 0~65535 | 全版本 |
| Trino | `SMALLINT` | -32768~32767 | -- | 全版本 |
| Presto | `SMALLINT` | -32768~32767 | -- | 全版本 |
| Spark SQL | `SMALLINT` / `SHORT` | -32768~32767 | -- | 全版本 |
| Hive | `SMALLINT` | -32768~32767 | -- | 全版本 |
| Flink SQL | `SMALLINT` | -32768~32767 | -- | 全版本 |
| Databricks | `SMALLINT` | -32768~32767 | -- | 全版本 |
| Teradata | `SMALLINT` | -32768~32767 | -- | 全版本 |
| Greenplum | `SMALLINT` / `INT2` | -32768~32767 | -- | 继承 PG |
| CockroachDB | `SMALLINT` / `INT2` | -32768~32767 | -- | 兼容 PG |
| TiDB | `SMALLINT` | -32768~32767 | `SMALLINT UNSIGNED` | 兼容 MySQL |
| OceanBase | `SMALLINT` | -32768~32767 | `SMALLINT UNSIGNED` (MySQL) | 双模式 |
| YugabyteDB | `SMALLINT` / `INT2` | -32768~32767 | -- | 兼容 PG |
| SingleStore | `SMALLINT` | -32768~32767 | `SMALLINT UNSIGNED` | 兼容 MySQL |
| Vertica | `SMALLINT` (别名) | INT (8B) 别名 | -- | 实际是 8 字节 |
| Impala | `SMALLINT` | -32768~32767 | -- | 全版本 |
| StarRocks | `SMALLINT` | -32768~32767 | -- | 全版本 |
| Doris | `SMALLINT` | -32768~32767 | -- | 全版本 |
| MonetDB | `SMALLINT` | -32768~32767 | -- | 全版本 |
| CrateDB | `SMALLINT` | -32768~32767 | -- | 全版本 |
| TimescaleDB | `SMALLINT` | -32768~32767 | -- | 继承 PG |
| QuestDB | `short` | -32768~32767 | -- | 专有名 |
| Exasol | `SMALLINT` (别名) | DECIMAL(36,0) 别名 | -- | 实为 DECIMAL |
| SAP HANA | `SMALLINT` | -32768~32767 | -- | 全版本 |
| Informix | `SMALLINT` | -32768~32767 | -- | 全版本 |
| Firebird | `SMALLINT` | -32768~32767 | -- | 全版本 |
| H2 | `SMALLINT` | -32768~32767 | -- | 全版本 |
| HSQLDB | `SMALLINT` | -32768~32767 | -- | 全版本 |
| Derby | `SMALLINT` | -32768~32767 | -- | 全版本 |
| Amazon Athena | `SMALLINT` | -32768~32767 | -- | 继承 Trino |
| Azure Synapse | `SMALLINT` | -32768~32767 | -- | 继承 SQL Server |
| Google Spanner | -- | -- | -- | 仅 INT64 |
| Materialize | `SMALLINT` / `INT2` | -32768~32767 | -- | 兼容 PG |
| RisingWave | `SMALLINT` / `INT2` | -32768~32767 | -- | 兼容 PG |
| InfluxDB (SQL) | -- | -- | -- | 仅 i64/u64 |
| DatabendDB | `SMALLINT` / `Int16` | -32768~32767 | `UInt16` 0~65535 | 全版本 |
| Yellowbrick | `SMALLINT` | -32768~32767 | -- | 全版本 |
| Firebolt | -- | -- | -- | 仅 INT/BIGINT |

> 几乎所有 SQL 引擎都支持 SQL:1992 标准的 `SMALLINT`，是兼容性最好的整数类型。BigQuery 与 Google Spanner 是显著例外——它们仅提供 `INT64` 一种整数类型，"小"整数也用 8 字节存储。

### INTEGER / INT (4 字节)

| 引擎 | 关键字 | 有符号范围 | 无符号支持 | 版本说明 |
|------|--------|-----------|----------|---------|
| PostgreSQL | `INTEGER` / `INT` / `INT4` | -2^31 ~ 2^31-1 | -- | 全版本 |
| MySQL | `INT` / `INTEGER` | -2^31 ~ 2^31-1 | `INT UNSIGNED` 0~2^32-1 | 全版本 |
| MariaDB | `INT` / `INTEGER` | -2^31 ~ 2^31-1 | `INT UNSIGNED` | 全版本 |
| SQLite | `INTEGER` (动态 1-8B) | 动态 | -- | 类型亲和性 |
| Oracle | `INTEGER` (别名) | NUMBER(38) 别名 | -- | 实为 NUMBER |
| SQL Server | `INT` / `INTEGER` | -2^31 ~ 2^31-1 | -- | 全版本 |
| DB2 | `INTEGER` / `INT` | -2^31 ~ 2^31-1 | -- | 全版本 |
| Snowflake | `INT` / `INTEGER` (别名) | NUMBER(38,0) | -- | 映射到 NUMBER |
| BigQuery | `INT64` (`INT` 别名) | -2^63 ~ 2^63-1 | -- | INT 实为 INT64 |
| Redshift | `INTEGER` / `INT` / `INT4` | -2^31 ~ 2^31-1 | -- | 全版本 |
| DuckDB | `INTEGER` / `INT` / `INT4` | -2^31 ~ 2^31-1 | `UINTEGER` 0~2^32-1 | 0.3+ |
| ClickHouse | `Int32` | -2^31 ~ 2^31-1 | `UInt32` 0~2^32-1 | 全版本 |
| Trino | `INTEGER` / `INT` | -2^31 ~ 2^31-1 | -- | 全版本 |
| Presto | `INTEGER` / `INT` | -2^31 ~ 2^31-1 | -- | 全版本 |
| Spark SQL | `INT` / `INTEGER` | -2^31 ~ 2^31-1 | -- | 全版本 |
| Hive | `INT` / `INTEGER` | -2^31 ~ 2^31-1 | -- | 全版本 |
| Flink SQL | `INT` / `INTEGER` | -2^31 ~ 2^31-1 | -- | 全版本 |
| Databricks | `INT` / `INTEGER` | -2^31 ~ 2^31-1 | -- | 全版本 |
| Teradata | `INTEGER` | -2^31 ~ 2^31-1 | -- | 全版本 |
| Greenplum | `INTEGER` / `INT4` | -2^31 ~ 2^31-1 | -- | 继承 PG |
| CockroachDB | `INTEGER` / `INT4` (注意默认!) | 详见下文 | -- | 兼容 PG (有差异) |
| TiDB | `INT` / `INTEGER` | -2^31 ~ 2^31-1 | `INT UNSIGNED` | 兼容 MySQL |
| OceanBase | `INT` / `INTEGER` | -2^31 ~ 2^31-1 | `INT UNSIGNED` (MySQL) | 双模式 |
| YugabyteDB | `INTEGER` / `INT4` | -2^31 ~ 2^31-1 | -- | 兼容 PG |
| SingleStore | `INT` / `INTEGER` | -2^31 ~ 2^31-1 | `INT UNSIGNED` | 兼容 MySQL |
| Vertica | `INT` / `INTEGER` | -2^63 ~ 2^63-1 (8B!) | -- | INT 实为 8B |
| Impala | `INT` / `INTEGER` | -2^31 ~ 2^31-1 | -- | 全版本 |
| StarRocks | `INT` / `INTEGER` | -2^31 ~ 2^31-1 | -- | 全版本 |
| Doris | `INT` / `INTEGER` | -2^31 ~ 2^31-1 | -- | 全版本 |
| MonetDB | `INTEGER` / `INT` | -2^31 ~ 2^31-1 | -- | 全版本 |
| CrateDB | `INTEGER` | -2^31 ~ 2^31-1 | -- | 全版本 |
| TimescaleDB | `INTEGER` | -2^31 ~ 2^31-1 | -- | 继承 PG |
| QuestDB | `int` | -2^31 ~ 2^31-1 | -- | 专有名 |
| Exasol | `INT` / `INTEGER` (别名) | DECIMAL(18,0) 别名 | -- | 实为 DECIMAL |
| SAP HANA | `INTEGER` / `INT` | -2^31 ~ 2^31-1 | -- | 全版本 |
| Informix | `INTEGER` / `INT` | -2^31 ~ 2^31-1 | -- | 全版本 |
| Firebird | `INTEGER` / `INT` | -2^31 ~ 2^31-1 | -- | 全版本 |
| H2 | `INTEGER` / `INT` | -2^31 ~ 2^31-1 | -- | 全版本 |
| HSQLDB | `INTEGER` / `INT` | -2^31 ~ 2^31-1 | -- | 全版本 |
| Derby | `INTEGER` / `INT` | -2^31 ~ 2^31-1 | -- | 全版本 |
| Amazon Athena | `INTEGER` / `INT` | -2^31 ~ 2^31-1 | -- | 继承 Trino |
| Azure Synapse | `INT` / `INTEGER` | -2^31 ~ 2^31-1 | -- | 继承 SQL Server |
| Google Spanner | `INT64` (无 INT 别名) | -2^63 ~ 2^63-1 | -- | 仅 INT64 |
| Materialize | `INTEGER` / `INT4` | -2^31 ~ 2^31-1 | -- | 兼容 PG |
| RisingWave | `INTEGER` / `INT4` | -2^31 ~ 2^31-1 | -- | 兼容 PG |
| InfluxDB (SQL) | -- | -- | -- | 仅 i64/u64 |
| DatabendDB | `INT` / `Int32` | -2^31 ~ 2^31-1 | `UInt32` 0~2^32-1 | 全版本 |
| Yellowbrick | `INTEGER` / `INT4` | -2^31 ~ 2^31-1 | -- | 全版本 |
| Firebolt | `INTEGER` / `INT` | -2^31 ~ 2^31-1 | -- | 全版本 |

> **CockroachDB 的 INT 默认陷阱**：CockroachDB 的 `INT` 默认是 8 字节（`INT8`），与 PostgreSQL 的 4 字节 `INT` 不同。可通过 `SET default_int_size = 4` 调整。
>
> **Vertica 的 INT 是 8 字节**：Vertica 没有真正的 4 字节整数，所有 `INT`/`INTEGER`/`SMALLINT` 都是 8 字节存储。
>
> **BigQuery / Spanner 的 INT 是 8 字节**：这两个 Google 引擎仅有 `INT64`，所有整数列都是 8 字节。

### BIGINT (8 字节)

| 引擎 | 关键字 | 有符号范围 | 无符号支持 | 版本说明 |
|------|--------|-----------|----------|---------|
| PostgreSQL | `BIGINT` / `INT8` | -2^63 ~ 2^63-1 | -- | 全版本 |
| MySQL | `BIGINT` | -2^63 ~ 2^63-1 | `BIGINT UNSIGNED` 0~2^64-1 | 全版本 |
| MariaDB | `BIGINT` | -2^63 ~ 2^63-1 | `BIGINT UNSIGNED` | 全版本 |
| SQLite | `INTEGER` (动态 1-8B) | 动态 | -- | 类型亲和性 |
| Oracle | -- (用 NUMBER(19)) | -- | -- | 仅 NUMBER 模拟 |
| SQL Server | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |
| DB2 | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |
| Snowflake | `BIGINT` (别名) | NUMBER(38,0) | -- | 映射到 NUMBER |
| BigQuery | `INT64` / `BIGINT` (别名) | -2^63 ~ 2^63-1 | -- | 默认整数类型 |
| Redshift | `BIGINT` / `INT8` | -2^63 ~ 2^63-1 | -- | 全版本 |
| DuckDB | `BIGINT` / `INT8` | -2^63 ~ 2^63-1 | `UBIGINT` 0~2^64-1 | 0.3+ |
| ClickHouse | `Int64` | -2^63 ~ 2^63-1 | `UInt64` 0~2^64-1 | 全版本 |
| Trino | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |
| Presto | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |
| Spark SQL | `BIGINT` / `LONG` | -2^63 ~ 2^63-1 | -- | 全版本 |
| Hive | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |
| Flink SQL | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |
| Databricks | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |
| Teradata | `BIGINT` | -2^63 ~ 2^63-1 | -- | V13.10+ |
| Greenplum | `BIGINT` / `INT8` | -2^63 ~ 2^63-1 | -- | 继承 PG |
| CockroachDB | `BIGINT` / `INT8` / `INT` (默认) | -2^63 ~ 2^63-1 | -- | INT 默认 8B |
| TiDB | `BIGINT` | -2^63 ~ 2^63-1 | `BIGINT UNSIGNED` | 兼容 MySQL |
| OceanBase | `BIGINT` | -2^63 ~ 2^63-1 | `BIGINT UNSIGNED` (MySQL) | 双模式 |
| YugabyteDB | `BIGINT` / `INT8` | -2^63 ~ 2^63-1 | -- | 兼容 PG |
| SingleStore | `BIGINT` | -2^63 ~ 2^63-1 | `BIGINT UNSIGNED` | 兼容 MySQL |
| Vertica | `BIGINT` / `INT` (= INT) | -2^63 ~ 2^63-1 | -- | 与 INT 等价 |
| Impala | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |
| StarRocks | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |
| Doris | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |
| MonetDB | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |
| CrateDB | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |
| TimescaleDB | `BIGINT` | -2^63 ~ 2^63-1 | -- | 继承 PG |
| QuestDB | `long` | -2^63 ~ 2^63-1 | -- | 专有名 |
| Exasol | `BIGINT` (别名) | DECIMAL(36,0) 别名 | -- | 实为 DECIMAL |
| SAP HANA | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |
| Informix | `BIGINT` / `INT8` | -2^63 ~ 2^63-1 | -- | INT8 是专有名 |
| Firebird | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |
| H2 | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |
| HSQLDB | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |
| Derby | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |
| Amazon Athena | `BIGINT` | -2^63 ~ 2^63-1 | -- | 继承 Trino |
| Azure Synapse | `BIGINT` | -2^63 ~ 2^63-1 | -- | 继承 SQL Server |
| Google Spanner | `INT64` | -2^63 ~ 2^63-1 | -- | 主要整数类型 |
| Materialize | `BIGINT` / `INT8` | -2^63 ~ 2^63-1 | -- | 兼容 PG |
| RisingWave | `BIGINT` / `INT8` | -2^63 ~ 2^63-1 | -- | 兼容 PG |
| InfluxDB (SQL) | `BIGINT` / `i64` | -2^63 ~ 2^63-1 | `UBIGINT` / `u64` | IOx 引擎 |
| DatabendDB | `BIGINT` / `Int64` | -2^63 ~ 2^63-1 | `UInt64` 0~2^64-1 | 全版本 |
| Yellowbrick | `BIGINT` / `INT8` | -2^63 ~ 2^63-1 | -- | 全版本 |
| Firebolt | `BIGINT` | -2^63 ~ 2^63-1 | -- | 全版本 |

> Oracle 没有原生的 `BIGINT` 类型，需用 `NUMBER(19, 0)` 等价表达。Snowflake 的 `BIGINT` 实际是 `NUMBER(38, 0)`，比 64 位更大。

### INT128 / 128 位整数与 DECIMAL128

| 引擎 | 关键字 | 字节 | 范围 | 无符号支持 | 引入版本 |
|------|--------|------|------|----------|---------|
| PostgreSQL | -- (`NUMERIC` 任意精度) | 变长 | 任意精度 | -- | -- |
| MySQL | -- (用 `DECIMAL(38)`) | 变长 | -- | -- | -- |
| MariaDB | -- (用 `DECIMAL(38)`) | 变长 | -- | -- | -- |
| SQLite | -- | -- | -- | -- | -- |
| Oracle | `NUMBER(38)` | 变长 | 38 位精度 | -- | -- |
| SQL Server | -- (用 `DECIMAL(38)`) | 17 字节 | -- | -- | -- |
| DB2 | -- (用 `DECFLOAT(34)` 或 `DECIMAL`) | 16 字节 | -- | -- | -- |
| Snowflake | `NUMBER(38,0)` (默认) | 变长 | 38 位精度 | -- | 全版本 |
| BigQuery | `BIGNUMERIC` (DECIMAL128) | -- | 76.76 位精度 | -- | 全版本 |
| Redshift | -- | -- | -- | -- | -- |
| DuckDB | `HUGEINT` | 16 | -2^127 ~ 2^127-1 | `UHUGEINT` (UBIGINT 后) | 0.x 早期 / UHUGEINT 0.10+ |
| ClickHouse | `Int128` | 16 | -2^127 ~ 2^127-1 | `UInt128` | 19.7 (2019) |
| ClickHouse | `Int256` | 32 | -2^255 ~ 2^255-1 | `UInt256` | 20.4 (2020) |
| Trino | -- (用 `DECIMAL(38)`) | 16 | -- | -- | -- |
| Presto | -- (用 `DECIMAL(38)`) | 16 | -- | -- | -- |
| Spark SQL | -- (用 `DECIMAL(38)`) | 变长 | -- | -- | -- |
| Hive | -- (用 `DECIMAL(38)`) | 变长 | -- | -- | -- |
| Flink SQL | -- (用 `DECIMAL(38)`) | 变长 | -- | -- | -- |
| Databricks | -- (用 `DECIMAL(38)`) | 变长 | -- | -- | -- |
| Teradata | -- (用 `NUMBER(38)`) | 变长 | -- | -- | -- |
| Greenplum | -- | -- | -- | -- | -- |
| CockroachDB | -- (DECIMAL 任意精度) | 变长 | -- | -- | -- (注：旧版 21.1 实验过 INT128，已合并到 DECIMAL) |
| TiDB | -- (用 `DECIMAL(38)`) | 变长 | -- | -- | -- |
| OceanBase | -- (用 `DECIMAL(38)`) | 变长 | -- | -- | -- |
| YugabyteDB | -- | -- | -- | -- | -- |
| SingleStore | -- (用 `DECIMAL(38)`) | 变长 | -- | -- | -- |
| Vertica | -- | -- | -- | -- | -- |
| Impala | -- (用 `DECIMAL(38)`) | 变长 | -- | -- | -- |
| StarRocks | `LARGEINT` | 16 | -2^127 ~ 2^127-1 | -- | 全版本 |
| Doris | `LARGEINT` | 16 | -2^127 ~ 2^127-1 | -- | 全版本 |
| MonetDB | `HUGEINT` | 16 | -2^127 ~ 2^127-1 | -- | Jul2015+ |
| CrateDB | -- | -- | -- | -- | -- |
| TimescaleDB | -- | -- | -- | -- | -- |
| QuestDB | -- | -- | -- | -- | -- |
| Exasol | -- | -- | -- | -- | -- |
| SAP HANA | -- | -- | -- | -- | -- |
| Informix | -- | -- | -- | -- | -- |
| Firebird | `INT128` | 16 | -2^127 ~ 2^127-1 | -- | 4.0+ (2021) |
| H2 | -- | -- | -- | -- | -- |
| HSQLDB | -- | -- | -- | -- | -- |
| Derby | -- | -- | -- | -- | -- |
| Amazon Athena | -- | -- | -- | -- | -- |
| Azure Synapse | -- | -- | -- | -- | -- |
| Google Spanner | -- | -- | -- | -- | -- |
| Materialize | -- | -- | -- | -- | -- |
| RisingWave | -- | -- | -- | -- | -- |
| InfluxDB (SQL) | -- | -- | -- | -- | -- |
| DatabendDB | -- (用 `DECIMAL(38)`) | -- | -- | -- | -- |
| Yellowbrick | -- | -- | -- | -- | -- |
| Firebolt | -- | -- | -- | -- | -- |

> **128 位整数的"伪 vs 真"**：
> - **真 128 位整数**：ClickHouse `Int128`、DuckDB `HUGEINT`、StarRocks/Doris `LARGEINT`、Firebird `INT128`、MonetDB `HUGEINT`——以原生 16 字节存储，硬件加速可用。
> - **DECIMAL 模拟**：MySQL/PG/SQL Server 等用 `DECIMAL(38)` 模拟，存储为变长十进制（17 字节左右），算术比原生 INT128 慢。
> - **任意精度**：PostgreSQL `NUMERIC` 无界、Oracle `NUMBER(38)`、Snowflake `NUMBER(38, 0)`——内部为变长十进制。
>
> **256 位整数**：仅 ClickHouse 提供 `Int256`/`UInt256`，主要用于区块链场景（以太坊地址、加密哈希）。

### UNSIGNED 变体支持矩阵

`UNSIGNED` 修饰可将正值范围翻倍（同时移除负数支持）：

| 引擎 | UNSIGNED 关键字 | TINYINT | SMALLINT | INT | BIGINT | INT128 | 备注 |
|------|----------------|---------|----------|-----|--------|--------|------|
| MySQL | `UNSIGNED` 修饰 | 是 | 是 | 是 | 是 | -- | 经典 MySQL 系语法 |
| MariaDB | `UNSIGNED` | 是 | 是 | 是 | 是 | -- | 同 MySQL |
| TiDB | `UNSIGNED` | 是 | 是 | 是 | 是 | -- | 兼容 MySQL |
| OceanBase (MySQL) | `UNSIGNED` | 是 | 是 | 是 | 是 | -- | MySQL 模式 |
| SingleStore | `UNSIGNED` | 是 | 是 | 是 | 是 | -- | 兼容 MySQL |
| ClickHouse | `UInt8`/`UInt16`/`UInt32`/`UInt64`/`UInt128`/`UInt256` | 是 | 是 | 是 | 是 | 是 | 独立类型而非修饰 |
| DuckDB | `UTINYINT`/`USMALLINT`/`UINTEGER`/`UBIGINT`/`UHUGEINT` | 是 | 是 | 是 | 是 | 是 | UHUGEINT 自 0.10+ |
| DatabendDB | `UInt8`/`UInt16`/`UInt32`/`UInt64` | 是 | 是 | 是 | 是 | -- | 类似 ClickHouse |
| InfluxDB (SQL) | `u64` / `UBIGINT` | -- | -- | -- | 是 | -- | 仅 64 位无符号 |
| PostgreSQL | -- | -- | -- | -- | -- | -- | 不支持 (用 CHECK 约束模拟) |
| SQL Server | -- | (内置无符号) | -- | -- | -- | -- | 仅 TINYINT 是无符号 |
| Oracle | -- | -- | -- | -- | -- | -- | 不支持 |
| BigQuery | -- | -- | -- | -- | -- | -- | 不支持 |
| Snowflake | -- | -- | -- | -- | -- | -- | 不支持 |
| Trino/Presto | -- | -- | -- | -- | -- | -- | 不支持 |
| Spark SQL | -- | -- | -- | -- | -- | -- | 不支持 |
| Hive | -- | -- | -- | -- | -- | -- | 不支持 |

> 通过 CHECK 约束模拟 UNSIGNED：
> ```sql
> -- PostgreSQL: 模拟 INT UNSIGNED
> CREATE TABLE t (
>     id INTEGER CHECK (id >= 0)  -- 强制非负
> );
> -- 但范围仍限于 INT 的 -2^31~2^31-1（即 0~2^31-1），不能利用 2^31~2^32-1 的高位空间
> ```

### SERIAL / 自增类型矩阵

`SERIAL` 是 PostgreSQL 等引擎为自增整数列提供的便捷语法。详见专题 `auto-increment-sequence-identity.md`。

| 引擎 | SERIAL 类型 | 等价语法 | 推荐替代 | 版本说明 |
|------|------------|---------|---------|---------|
| PostgreSQL | `SMALLSERIAL` (2B) | `SMALLINT NOT NULL DEFAULT nextval('seq')` | `GENERATED AS IDENTITY` | 9.2+ (SMALLSERIAL) |
| PostgreSQL | `SERIAL` (4B) | `INT NOT NULL DEFAULT nextval('seq')` | `GENERATED AS IDENTITY` | 全版本 |
| PostgreSQL | `BIGSERIAL` (8B) | `BIGINT NOT NULL DEFAULT nextval('seq')` | `GENERATED AS IDENTITY` | 全版本 |
| Greenplum | `SERIAL` / `BIGSERIAL` | 同 PG | 同 PG | 继承 PG |
| YugabyteDB | `SERIAL` / `BIGSERIAL` | 同 PG | `GENERATED AS IDENTITY` | 兼容 PG |
| CockroachDB | `SERIAL` (默认 INT8) | `INT8 NOT NULL DEFAULT unique_rowid()` | `GENERATED AS IDENTITY` | 兼容 PG |
| TimescaleDB | `SERIAL` / `BIGSERIAL` | 同 PG | 同 PG | 继承 PG |
| Materialize | `SERIAL` / `BIGSERIAL` | 同 PG | 同 PG | 兼容 PG |
| RisingWave | `SERIAL` (实验性) | -- | -- | 兼容 PG |
| MySQL | `SERIAL` (= `BIGINT UNSIGNED NOT NULL AUTO_INCREMENT UNIQUE KEY`) | 自增 | `AUTO_INCREMENT` | 全版本 |
| MariaDB | `SERIAL` (= MySQL) | -- | `AUTO_INCREMENT` | 全版本 |
| SingleStore | `SERIAL` | -- | -- | 兼容 MySQL |
| TiDB | `SERIAL` | -- | `AUTO_INCREMENT` / `AUTO_RANDOM` | 兼容 MySQL |
| Oracle | -- | -- | `GENERATED AS IDENTITY` (12c+) | -- |
| SQL Server | -- | -- | `IDENTITY(1,1)` | -- |
| DB2 | -- | -- | `GENERATED AS IDENTITY` | -- |
| Snowflake | -- | -- | `IDENTITY` / `AUTOINCREMENT` | -- |
| BigQuery | -- | -- | `GENERATE_UUID()` 或自定义序列 | -- |
| ClickHouse | -- | -- | `MaterializedView` 或 ReplacingMergeTree | -- |
| DuckDB | `SERIAL` (PG 兼容别名) | 自增序列 | `GENERATED AS IDENTITY` | 0.7+ |
| Trino/Presto | -- | -- | -- | 不支持 |
| Spark SQL | -- | -- | `monotonically_increasing_id()` (UDF) | -- |

> **PostgreSQL 官方建议**：自 PG 10 起官方推荐使用 SQL 标准的 `GENERATED AS IDENTITY` 替代 `SERIAL`，原因是 `SERIAL` 在权限管理（隐式创建的 sequence 权限独立）、`COPY FROM` 行为、Schema 复制等方面有诸多陷阱。`SERIAL` 仍可使用，但已被视为"半弃用"（quasi-deprecated）。

## MEDIUMINT (3 字节) — MySQL 独有

`MEDIUMINT` 是 MySQL 系列独有的 3 字节整数类型，提供 24 位整数支持：

| 引擎 | 关键字 | 有符号范围 | 无符号范围 | 节约空间 |
|------|--------|-----------|----------|---------|
| MySQL | `MEDIUMINT` | -8388608 ~ 8388607 | 0 ~ 16777215 | 比 INT 节约 1B (25%) |
| MariaDB | `MEDIUMINT` | -8388608 ~ 8388607 | 0 ~ 16777215 | 同 MySQL |
| TiDB | `MEDIUMINT` | 同上 | 同上 | 兼容 MySQL |
| SingleStore | `MEDIUMINT` | 同上 | 同上 | 兼容 MySQL |
| OceanBase (MySQL) | `MEDIUMINT` | 同上 | 同上 | 兼容 MySQL |
| 其他全部 45+ 引擎 | -- | -- | -- | -- |

```sql
-- MySQL: MEDIUMINT 用例
CREATE TABLE products (
    id MEDIUMINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,  -- 0 ~ 16M 商品
    sku MEDIUMINT,                                       -- 库存单位
    PRIMARY KEY (id)
);

-- 跨库迁移到 PostgreSQL: 必须升级到 INTEGER (4B)
-- 浪费 1 字节，但语义保留
CREATE TABLE products (
    id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    CHECK (id <= 16777215)  -- 可选：维持 MySQL 的范围语义
);
```

### MEDIUMINT 的设计意图

MEDIUMINT 的存在反映 MySQL 早期对存储成本的极致优化思维（1995 年 1 字节相当宝贵）。其典型使用场景：
- 商品/SKU/Category ID（不超过 1700 万的中小型实体）
- 楼盘房间号、酒店房间编号（24 位足够）
- IPv4 地址的高 24 位（子网压缩）

但在现代硬件（内存与磁盘 TB 级）下，`MEDIUMINT` 节省的 1 字节微不足道，反而带来对齐与跨库迁移成本。**新设计不推荐使用 MEDIUMINT**——直接用 INTEGER。

### 24 位整数在其他生态

`MEDIUMINT` 在标准库与其他语言中的对应：
- C/C++: 无原生 24 位类型，用 `int24_t` 第三方扩展或位域
- Rust: `i24`/`u24` 在 `bytemuck` 等库中定义
- Java/Python: 无原生 24 位
- 嵌入式系统：常见（如音频采样、24 位 ADC）

## 各引擎整数类型详解

### MySQL：全谱系整数类型

```sql
-- MySQL 整数类型（含 UNSIGNED 与 ZEROFILL）
CREATE TABLE int_demo (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    flag        TINYINT(1),                  -- 用作布尔
    age         TINYINT UNSIGNED,            -- 0 ~ 255
    year_built  SMALLINT UNSIGNED,           -- 0 ~ 65535
    sku         MEDIUMINT UNSIGNED,          -- 0 ~ 16,777,215
    user_id     INT UNSIGNED,                -- 0 ~ 4,294,967,295
    timestamp   BIGINT UNSIGNED,             -- 毫秒时间戳
    big_id      BIGINT UNSIGNED ZEROFILL     -- 显示宽度补零（已弃用）
);

-- TINYINT(1) 与 BOOLEAN
-- BOOLEAN 是 TINYINT(1) 的别名，TRUE = 1, FALSE = 0
INSERT INTO int_demo (flag) VALUES (TRUE);   -- 实际存 1
INSERT INTO int_demo (flag) VALUES (FALSE);  -- 实际存 0

-- 显示宽度（MySQL 8.0.17 起对所有整数类型弃用）
-- INT(11) 中的 11 不是范围，是显示宽度（与 ZEROFILL 配合）
-- INT(2) 仍能存 2147483647，不是限制为 2 位

-- UNSIGNED 减法陷阱（默认行为）
SELECT CAST(1 AS UNSIGNED) - CAST(2 AS UNSIGNED);
-- 结果: 18446744073709551615 (-1 的二进制补码)
-- 必须启用 NO_UNSIGNED_SUBTRACTION 模式才能返回 -1
SET sql_mode = 'NO_UNSIGNED_SUBTRACTION';
```

### PostgreSQL：标准三档 + 任意精度

```sql
-- PG 没有 TINYINT 和 UNSIGNED
CREATE TABLE int_demo (
    id BIGSERIAL PRIMARY KEY,                    -- 等价 BIGINT + sequence
    age SMALLINT,                                 -- -32768 ~ 32767
    user_id INTEGER,                              -- -2^31 ~ 2^31-1
    timestamp BIGINT,                             -- -2^63 ~ 2^63-1
    -- 大整数：使用 NUMERIC 任意精度
    huge_balance NUMERIC,                         -- 任意精度，最大 1000 位
    crypto_hash NUMERIC(38, 0)                    -- 等价 INT128 模拟
);

-- SERIAL 类型（自增）
CREATE TABLE small_table (id SMALLSERIAL PRIMARY KEY);  -- 9.2+
CREATE TABLE med_table (id SERIAL PRIMARY KEY);
CREATE TABLE big_table (id BIGSERIAL PRIMARY KEY);

-- 推荐：用 SQL 标准的 IDENTITY 替代 SERIAL（10+）
CREATE TABLE modern_table (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY
    -- 或 GENERATED BY DEFAULT AS IDENTITY 允许显式插入
);

-- PG 没有 UNSIGNED，用 CHECK 约束模拟
CREATE TABLE non_negative (
    score INTEGER NOT NULL CHECK (score >= 0)
);

-- 任意精度整数（无溢出）
SELECT (10::NUMERIC)^100;  -- 10^100，无问题
-- 但失去 INT 的硬件加速，性能慢 10-100 倍

-- INT2 / INT4 / INT8 是 SMALLINT / INTEGER / BIGINT 的别名
SELECT pg_typeof(1::INT2);   -- smallint
SELECT pg_typeof(1::INT8);   -- bigint
```

### Oracle：NUMBER(p) 一统天下

```sql
-- Oracle 没有原生硬件加速整数类型
-- 所有整数都是 NUMBER(p, 0) 或 NUMBER(*, 0) 的变长存储
CREATE TABLE int_demo (
    id            NUMBER(19, 0) PRIMARY KEY,  -- 等价 BIGINT
    age           NUMBER(3, 0),                -- 等价 TINYINT (0~999)
    year_built    NUMBER(5, 0),                -- 等价 SMALLINT
    user_id       NUMBER(10, 0),               -- 等价 INTEGER
    crypto_hash   NUMBER(38, 0),               -- 38 位精度，覆盖 INT128
    -- INTEGER / SMALLINT / INT 在 Oracle 中是 NUMBER(38) 的别名（不是 NUMBER(p, 0)）
    legacy_int    INTEGER                      -- 实际是 NUMBER(38, 0)
);

-- Oracle 12c+ 的 IDENTITY (替代序列触发器)
CREATE TABLE modern_table (
    id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR2(100)
);

-- Oracle 整数算术不会溢出（NUMBER 自动扩展精度，最多 38 位）
SELECT 9223372036854775807 + 9223372036854775807 FROM DUAL;
-- 结果: 18446744073709551614 (无错误)
```

### SQL Server：T-SQL 整数（仅有符号）

```sql
-- SQL Server 整数类型
CREATE TABLE int_demo (
    id          BIGINT IDENTITY(1, 1) PRIMARY KEY,
    flag        TINYINT,        -- 注意: 0 ~ 255 (无符号!)
    age         SMALLINT,        -- -32768 ~ 32767
    user_id     INT,             -- -2^31 ~ 2^31-1
    timestamp   BIGINT           -- -2^63 ~ 2^63-1
);

-- TINYINT 是 0~255 (无符号)，但其他类型都是有符号
-- SQL Server 没有 UNSIGNED 修饰符

-- IDENTITY 替代自增
CREATE TABLE products (
    id INT IDENTITY(1, 1) PRIMARY KEY,    -- 起始值 1，步长 1
    name NVARCHAR(100)
);

-- 整数溢出处理: SQL Server 抛出 Arithmetic Overflow 错误
SELECT CAST(2147483647 AS INT) + 1;  -- 错误: ERROR 220 Arithmetic overflow
SELECT TRY_CAST(2147483648 AS INT);   -- NULL (TRY_CAST 不抛错)

-- 无 INT128，使用 DECIMAL(38) 模拟
CREATE TABLE crypto (
    hash DECIMAL(38, 0)   -- 17 字节 packed decimal
);
```

### ClickHouse：Rust 风格命名 + 全幅 UInt + Int128/256

```sql
-- ClickHouse: 整数类型采用 C++/Rust 风格命名
CREATE TABLE events (
    event_id      UInt64,           -- 0 ~ 2^64-1
    user_id       UInt32,           -- 0 ~ 2^32-1
    session_byte  Int8,             -- -128 ~ 127
    flag          UInt8,            -- 0 ~ 255
    crypto_hash   UInt128,          -- 19.7+ (2019)
    eth_address   UInt256,          -- 20.4+ (2020), 区块链场景
    raw_balance   Int256            -- 20.4+, 大金额
) ENGINE = MergeTree()
ORDER BY event_id;

-- 类型别名 (全部都有)
-- TINYINT      = Int8
-- SMALLINT     = Int16
-- INT/INTEGER  = Int32
-- BIGINT       = Int64
-- TINYINT UNSIGNED = UInt8
-- 等等

-- ClickHouse 整数算术: 静默溢出（环绕）
SELECT toInt32(2147483647) + 1;
-- 结果: -2147483648 (二进制补码环绕，不抛错!)
SELECT toUInt32(0) - 1;
-- 结果: 4294967295

-- 类型自动提升: 较小整数运算自动提升到 Int64
SELECT toInt8(127) + toInt8(127);
-- 结果: 254 (Int16，不溢出)

-- Int256 区块链场景
CREATE TABLE transactions (
    tx_hash      UInt256,                          -- 256 位哈希
    from_addr    FixedString(20),                  -- 以太坊地址 160 位
    amount_wei   UInt256                           -- Wei 金额（10^-18 ETH）
) ENGINE = MergeTree()
ORDER BY tx_hash;

-- 性能: Int128/Int256 比原生 Int64 慢 2-4 倍（无原生 SIMD）
-- 但比 Decimal128 快 5-10 倍（Decimal 需要小数处理）
```

### DuckDB：HUGEINT (128 位) + 完整 UNSIGNED

```sql
-- DuckDB: 完整的整数家族
CREATE TABLE int_demo (
    id          BIGINT,           -- 8B 有符号
    flag        TINYINT,           -- 1B 有符号
    flag_u      UTINYINT,          -- 1B 无符号
    user_id     INTEGER,           -- 4B 有符号
    user_id_u   UINTEGER,          -- 4B 无符号
    big         BIGINT,            -- 8B
    big_u       UBIGINT,           -- 8B 无符号
    huge        HUGEINT,           -- 16B 有符号 (128 位)
    huge_u      UHUGEINT           -- 16B 无符号 (0.10+)
);

-- HUGEINT 字面量
SELECT 170141183460469231731687303715884105727::HUGEINT;  -- 2^127-1

-- HUGEINT 与 DECIMAL(38) 的差异
-- HUGEINT: 16 字节，硬件级 128 位整数运算
-- DECIMAL(38): 16 字节，但作为 packed decimal 处理，含小数点位

-- DuckDB 对溢出的处理: 抛错（自 0.7+）
SELECT CAST(127 AS TINYINT) + CAST(1 AS TINYINT);
-- 错误: Conversion Error: Overflow in addition of TINYINT (127 + 1)

-- USING SAMPLE 与 HUGEINT 配合
CREATE TABLE crypto_signatures (
    sig_id  BIGINT,
    r       HUGEINT,           -- ECDSA r 分量（256 位需要 INT256，DuckDB 还无）
    s       HUGEINT
);
```

### Snowflake：NUMBER(38, 0) 统一表示

```sql
-- Snowflake: 所有整数类型都是 NUMBER(38, 0) 的别名
CREATE TABLE int_demo (
    id          INTEGER,                        -- 等价 NUMBER(38, 0)
    age         TINYINT,                        -- 等价 NUMBER(38, 0)
    year_built  SMALLINT,                       -- 等价 NUMBER(38, 0)
    user_id     INT,                            -- 等价 NUMBER(38, 0)
    timestamp   BIGINT,                         -- 等价 NUMBER(38, 0)
    -- 显式精度
    crypto      NUMBER(38, 0),                  -- 38 位精度
    decimal_amt NUMBER(18, 4)                   -- 18 位整数 + 4 位小数
);

-- Snowflake 的整数运算永不溢出（38 位精度足够大）
SELECT 9223372036854775807 + 9223372036854775807;
-- 结果: 18446744073709551614 (无错误)

-- IDENTITY / AUTOINCREMENT
CREATE TABLE products (
    id INTEGER AUTOINCREMENT START 1 INCREMENT 1 PRIMARY KEY,
    -- 或 IDENTITY 等价
    name STRING
);

-- 物理存储: Snowflake 内部用变长存储优化（按实际值大小压缩）
-- TINYINT 列存放 1~127 时仅占 1-2 字节
-- 即使声明为 BIGINT，存储仍按需压缩
```

### BigQuery：仅 INT64 一种

```sql
-- BigQuery: 仅有 INT64（也叫 INT 或 INTEGER 别名）
CREATE TABLE dataset.int_demo (
    id          INT64,                          -- 唯一选择
    age         INT64,                          -- 没有 SMALLINT
    flag        INT64,                          -- 也没有 TINYINT
    timestamp   INT64,
    -- 大整数:
    crypto      BIGNUMERIC,                     -- 76.76 位精度（DECIMAL128）
    safe_int    NUMERIC                         -- 38.9 位精度
);

-- BigQuery 的 INT 是 INT64 的别名
-- 实际存储: 8 字节固定（无变长压缩）
-- 存储成本: 即使存储 0~127 的值也是 8 字节

-- BIGNUMERIC: 256 位精度，主要用于金融场景
SELECT BIGNUMERIC '12345678901234567890123456789012345678.12345678901234567890123456789012345678';
-- 76.76 位精度，远超 INT64

-- BigQuery 没有自增类型（也没有 IDENTITY）
-- 替代方案:
-- 1. GENERATE_UUID(): 字符串 UUID
-- 2. ROW_NUMBER() OVER ()
-- 3. 自定义 sequence (需要外部状态)
```

### CockroachDB：INT 默认 8 字节 + 历史 INT128

```sql
-- CockroachDB: INT 默认是 8 字节（与 PostgreSQL 不同！）
CREATE TABLE int_demo (
    id    INT PRIMARY KEY,            -- 默认 8B
    age   INT2,                        -- 显式 SMALLINT (2B)
    sku   INT4,                        -- 显式 INT (4B)
    big   INT8,                        -- 显式 BIGINT (8B)
    -- INT128: CockroachDB 21.1 引入实验性 INT128（用于内部 ID）
    -- 已合并到 DECIMAL，不作为公开类型
    big_dec  DECIMAL                   -- 任意精度
);

-- 设置默认 INT 大小
SET default_int_size = 4;             -- 切换到 4B 默认（PG 兼容）
-- 或
SET default_int_size = 8;             -- 默认 (CockroachDB 默认)

-- 兼容性: CockroachDB 的 SERIAL 与 PG 不同
-- CockroachDB SERIAL = INT8 + unique_rowid()（混合 ID 生成）
CREATE TABLE products (
    id SERIAL PRIMARY KEY,             -- 实际 INT8 + unique_rowid
    name TEXT
);

-- unique_rowid() 返回 64 位整数:
-- 高 48 位: 时间戳（精确到毫秒）
-- 低 16 位: 节点 ID + 序列计数器
-- 优势: 无需中央协调，分布式唯一，时间排序
-- 劣势: 不连续，不可预测
```

### Spark SQL / Hive：JVM 整数语义

```sql
-- Spark SQL: 与 Java 整数语义一致（默认静默溢出）
CREATE TABLE events (
    event_id    BIGINT,                          -- = Java long
    user_id     INT,                             -- = Java int
    flag        TINYINT,                          -- = Java byte (有符号 -128~127)
    age         SMALLINT,                         -- = Java short
    -- 没有 UNSIGNED
    -- 没有 INT128（用 DECIMAL(38) 替代）
    crypto      DECIMAL(38, 0)
);

-- Spark 整数溢出: 默认静默环绕（ANSI=off）
SELECT CAST(2147483647 AS INT) + 1;
-- ANSI=off (默认): -2147483648 (环绕)
-- ANSI=on: 抛错

-- Spark 3.0+ 启用 ANSI 严格模式
SET spark.sql.ansi.enabled = true;
SELECT CAST(2147483647 AS INT) + 1;
-- 错误: ArithmeticException: integer overflow

-- try_add() 等安全函数 (Spark 3.0+)
SELECT try_add(2147483647, 1);  -- NULL（不抛错）
SELECT try_subtract(0, 9223372036854775808);  -- NULL

-- Hive 0.11+ 整数类型与 Spark 一致
-- 但 Hive 默认始终是静默环绕（无 ANSI 模式）
```

### Vertica：所有整数 = 8 字节

```sql
-- Vertica: 所有整数类型实际都是 INT (8B)
CREATE TABLE int_demo (
    id          INT,                            -- 8B 有符号
    age         TINYINT,                         -- 实际 8B (TINYINT 是别名)
    year_built  SMALLINT,                        -- 实际 8B
    user_id     INTEGER,                         -- 实际 8B
    timestamp   BIGINT                           -- 实际 8B
);

-- Vertica 的设计哲学: 列存压缩自动优化存储
-- 即使声明 INT，存储 0~127 的值时按 1 字节压缩存储
-- 但 SQL 表达式中所有运算按 8 字节进行

-- 这种设计的优劣：
-- 优势: 简单（一种类型够用）+ 自动压缩
-- 劣势: 不能利用窄类型的 SIMD 指令（AVX-512 对 Int8 一次处理 64 个）
```

### Firebird：INT128 自 4.0+ 引入

```sql
-- Firebird 4.0+ (2021) 引入 INT128
CREATE TABLE int_demo (
    id           BIGINT NOT NULL,
    crypto_hash  INT128,                        -- 4.0+ 新增
    very_big     NUMERIC(38, 0)                  -- 等价 INT128 但 packed decimal
);

-- INT128 字面量
SELECT CAST('170141183460469231731687303715884105727' AS INT128) FROM RDB$DATABASE;
-- 2^127-1

-- 内部表示: 16 字节小端序整数（与 ClickHouse Int128 兼容）
-- 算术: 全 128 位硬件加速（在支持的 CPU 上）
-- 比 NUMERIC(38) 快 3-5 倍
```

### StarRocks / Doris：LARGEINT (16 字节)

```sql
-- StarRocks / Doris: LARGEINT 是 128 位整数
CREATE TABLE events (
    user_id     BIGINT,
    crypto_id   LARGEINT,                       -- 16 字节有符号
    -- 没有 ULARGEINT（不支持无符号 128 位）
    metric_val  LARGEINT
) ENGINE = OLAP
DUPLICATE KEY (user_id);

-- LARGEINT 字面量: 字符串形式（无原生 128 位字面量）
INSERT INTO events VALUES (
    1, '170141183460469231731687303715884105727', '999999999999999999'
);

-- 性能: 比 BIGINT 慢 3-5 倍（无 SIMD 加速）
-- 用例: 当 BIGINT (2^63) 不够大时
```

### MonetDB：HUGEINT (128 位)

```sql
-- MonetDB Jul2015+: HUGEINT 是 128 位有符号整数
CREATE TABLE int_demo (
    id      BIGINT,
    huge    HUGEINT
);

INSERT INTO int_demo VALUES (1, 170141183460469231731687303715884105727);

-- MonetDB HUGEINT 是真正的 128 位（不是 DECIMAL 模拟）
-- 但需要编译时启用（默认开启）
```

### SQLite：动态类型 + 类型亲和性

```sql
-- SQLite: INTEGER 是动态 1-8 字节
CREATE TABLE int_demo (
    id INTEGER PRIMARY KEY AUTOINCREMENT,    -- ROWID 别名
    age INT,                                  -- TYPE AFFINITY: INTEGER
    flag TINYINT,                             -- 也是 INTEGER 亲和（不是真 1B）
    big BIGINT                                -- 也是 INTEGER 亲和
);

-- SQLite 实际存储: 根据值大小动态选择 1, 2, 3, 4, 6, 或 8 字节
INSERT INTO int_demo (age) VALUES (100);     -- 存为 1 字节
INSERT INTO int_demo (age) VALUES (1000000);  -- 存为 4 字节
INSERT INTO int_demo (age) VALUES (10000000000); -- 存为 8 字节

-- INTEGER PRIMARY KEY 是特殊的（ROWID 别名）
-- 自增使用 AUTOINCREMENT 关键字（避免 ROWID 重用）

-- SQLite 整数最大: 2^63-1 (8 字节)
-- 没有 INT128 / HUGEINT / LARGEINT
```

## UNSIGNED 详解：MySQL vs ClickHouse vs DuckDB

### MySQL UNSIGNED：修饰符语法

```sql
-- MySQL: UNSIGNED 是类型修饰符
CREATE TABLE mysql_demo (
    a TINYINT UNSIGNED,        -- 0 ~ 255
    b SMALLINT UNSIGNED,       -- 0 ~ 65535
    c MEDIUMINT UNSIGNED,      -- 0 ~ 16777215
    d INT UNSIGNED,            -- 0 ~ 4294967295
    e BIGINT UNSIGNED          -- 0 ~ 18446744073709551615
);

-- 陷阱 1: UNSIGNED - UNSIGNED 默认环绕
SELECT CAST(1 AS UNSIGNED) - CAST(2 AS UNSIGNED);
-- 默认结果: 18446744073709551615 (= 2^64 - 1, -1 的二进制补码)
-- 修复: SET sql_mode = 'NO_UNSIGNED_SUBTRACTION';
-- 修复后: -1 (但变 SIGNED 类型)

-- 陷阱 2: UNSIGNED 与 SIGNED 比较
SELECT -1 < CAST(0 AS UNSIGNED);
-- 结果: 0 (false!) — -1 被隐式转为 UNSIGNED 18446744073709551615
-- 此值不小于 0

-- 陷阱 3: JOIN 类型不匹配
CREATE TABLE a (id INT UNSIGNED);
CREATE TABLE b (id INT SIGNED);
SELECT * FROM a JOIN b ON a.id = b.id;
-- 警告: 索引可能不被使用（类型转换阻止索引利用）
```

### ClickHouse UInt：独立类型

```sql
-- ClickHouse: UInt8/16/32/64/128/256 是独立类型（不是修饰符）
CREATE TABLE ch_demo (
    a UInt8,           -- 0 ~ 255
    b UInt16,          -- 0 ~ 65535
    c UInt32,          -- 0 ~ 4294967295
    d UInt64,          -- 0 ~ 2^64-1
    e UInt128,         -- 0 ~ 2^128-1 (19.7+)
    f UInt256          -- 0 ~ 2^256-1 (20.4+)
) ENGINE = MergeTree() ORDER BY a;

-- ClickHouse UInt 算术: 静默环绕（无错误）
SELECT toUInt32(0) - 1;
-- 结果: 4294967295 (环绕)

-- 类型自动提升: 较小类型运算自动提升避免溢出
SELECT toUInt8(255) + toUInt8(1);
-- 结果: 256 (UInt16，不溢出)

-- IP 地址优化: 用 UInt32 存 IPv4
CREATE TABLE access_log (
    user_ip UInt32,                              -- IPv4 整数化
    user_ipv6 UInt128                            -- IPv6 整数化
) ENGINE = MergeTree();

INSERT INTO access_log VALUES (
    toUInt32(IPv4StringToNum('192.168.1.1')),
    toUInt128(IPv6StringToNum('2001:db8::1'))
);
```

### DuckDB UTINYINT：完整整数家族

```sql
-- DuckDB: U 前缀的无符号家族
CREATE TABLE duck_demo (
    a UTINYINT,         -- 0 ~ 255
    b USMALLINT,        -- 0 ~ 65535
    c UINTEGER,         -- 0 ~ 4294967295
    d UBIGINT,          -- 0 ~ 2^64-1
    e UHUGEINT          -- 0 ~ 2^128-1 (0.10+)
);

-- DuckDB 溢出: 抛错（自 0.7+）
SELECT CAST(255 AS UTINYINT) + CAST(1 AS UTINYINT);
-- 错误: Conversion Error: Type UTINYINT with value 256 can't be cast to UTINYINT

-- 安全转换
SELECT TRY_CAST(256 AS UTINYINT);  -- NULL
```

## 128 位整数使用场景

### 1. 加密哈希存储

```sql
-- ClickHouse: 高效存储 MD5 / SHA-128
CREATE TABLE file_hashes (
    file_id UInt64,
    md5_hash UInt128,                            -- 128 位 MD5
    sha256_truncated UInt256                     -- 完整 SHA-256
) ENGINE = MergeTree() ORDER BY file_id;

INSERT INTO file_hashes VALUES (
    1,
    reinterpretAsUInt128(unhex('5d41402abc4b2a76b9719d911017c592')),
    toUInt256(0x...)
);

-- 比较 16 字节哈希: UInt128 比较 = 单条 SSE 指令
-- 比 String 比较快 10-100 倍
```

### 2. 金融高精度计算

```sql
-- DuckDB: HUGEINT 用于以分计金额（避免 DOUBLE 精度损失）
CREATE TABLE transactions (
    txn_id BIGINT,
    -- 金额以 10^-18 单位存储（如以太坊 Wei）
    amount_wei HUGEINT
);

INSERT INTO transactions VALUES
    (1, 1000000000000000000),                   -- 1 ETH = 10^18 Wei
    (2, 500000000000000000);                    -- 0.5 ETH

-- 总和不会溢出（HUGEINT 范围 ±2^127）
SELECT SUM(amount_wei) FROM transactions;

-- 与 DECIMAL(38, 18) 相比，HUGEINT 算术快 5-10 倍
```

### 3. UUID 整数化

```sql
-- ClickHouse: 将 UUID 存储为 UInt128 节省空间
CREATE TABLE entities (
    entity_id UInt128,                          -- 16 字节
    name String
) ENGINE = MergeTree() ORDER BY entity_id;

-- 比起 String 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' (37 字节)
-- UInt128 节省 21 字节/行 + 比较速度快 10x

-- DuckDB 也有原生 UUID 类型 (16 字节，但有专门的字符串解析)
CREATE TABLE entities (
    entity_id UUID,                              -- DuckDB 原生
    name VARCHAR
);
```

### 4. 区块链场景

```sql
-- ClickHouse: 区块链数据
CREATE TABLE blockchain (
    block_height UInt64,
    tx_hash UInt256,                             -- 256 位交易哈希
    from_address FixedString(20),                -- 160 位以太坊地址（20 字节）
    to_address FixedString(20),
    amount_wei UInt256,                          -- 大额交易（超出 BIGINT）
    gas_price UInt256
) ENGINE = MergeTree()
ORDER BY (block_height, tx_hash);

-- 以太坊地址用 UInt160 不够 (ClickHouse 没有 UInt160)
-- 解决方案: FixedString(20) (20 字节固定)
-- 或填充到 UInt256
```

### 5. 分布式雪花 ID

```sql
-- 雪花算法 ID = 64 位（普通 BIGINT 足够）
-- 但若需要更大 ID 空间（多数据中心 + 长时间）:
-- 128 位雪花 ID = 64 位时间戳 + 32 位机器 + 32 位序列
CREATE TABLE distributed_snowflake (
    snowflake_id UInt128,                        -- ClickHouse
    payload String
) ENGINE = MergeTree() ORDER BY snowflake_id;
```

## 各引擎整数类型对比矩阵

| 引擎 | 整数家族特点 | UNSIGNED | INT128 | INT256 | SERIAL |
|------|------------|----------|--------|--------|--------|
| MySQL | TINYINT/SMALLINT/MEDIUMINT/INT/BIGINT | 是 (修饰) | -- | -- | 是 |
| MariaDB | 同 MySQL | 是 (修饰) | -- | -- | 是 |
| PostgreSQL | SMALLINT/INT/BIGINT + 任意精度 NUMERIC | -- | NUMERIC | NUMERIC | 是 (SMALLSERIAL/SERIAL/BIGSERIAL) |
| Oracle | NUMBER(p) 一统 | -- | NUMBER(38) | -- | -- |
| SQL Server | TINYINT(无符号)/SMALLINT/INT/BIGINT | -- | DECIMAL | -- | -- |
| Snowflake | 全部 NUMBER(38, 0) | -- | NUMBER(38) | -- | AUTOINCREMENT |
| BigQuery | 仅 INT64 | -- | BIGNUMERIC | -- | -- |
| ClickHouse | Int8~256 + UInt8~256 完整 | 是 (独立类型) | 是 (19.7+) | 是 (20.4+) | -- |
| DuckDB | TINYINT~BIGINT + HUGEINT + UHUGEINT | 是 (U 前缀) | 是 (HUGEINT) | -- | 是 |
| StarRocks/Doris | TINYINT~BIGINT + LARGEINT | -- | 是 (LARGEINT) | -- | -- |
| MonetDB | TINYINT~BIGINT + HUGEINT | -- | 是 (HUGEINT) | -- | -- |
| Firebird | SMALLINT~BIGINT + INT128 | -- | 是 (4.0+) | -- | -- |
| CockroachDB | INT2/4/8 (默认 INT8) | -- | -- (内部) | -- | 是 (PG 兼容) |
| Vertica | 全部 8 字节 (INT 别名) | -- | -- | -- | -- |
| SQL Server | T-SQL 整数 | (TINYINT 内置) | -- | -- | IDENTITY |

## 关键发现

### 1. SQL Server 的 TINYINT 是无符号 (0~255)，与多数引擎相反

SQL Server / SAP HANA / Azure Synapse 的 `TINYINT` 是 0~255 无符号，而 MySQL / ClickHouse / Hive / Spark / DuckDB 的 `TINYINT` 是 -128~127 有符号。这是跨库迁移最常见的"沉默错误"——值在两种系统间转换时不会报错，但会得到完全不同的结果。

### 2. CockroachDB INT 默认是 8 字节（与 PG 不兼容）

PostgreSQL `INT` = 4 字节，但 CockroachDB `INT` 默认 = 8 字节（`INT8`）。从 PG 迁移到 CockroachDB 时，列定义可能"自动放大"。可通过 `SET default_int_size = 4` 切换。

### 3. Vertica 的所有整数都是 8 字节

Vertica 的 `TINYINT`/`SMALLINT`/`INT`/`INTEGER`/`BIGINT` 都是 `INT` (8 字节) 的别名。列存压缩自动按值大小压缩存储，但内存中和 SQL 运算时都按 8 字节处理。

### 4. BigQuery / Spanner / Snowflake 整数类型扁平化

- BigQuery: 仅 `INT64`（8 字节）
- Spanner: 仅 `INT64`
- Snowflake: 所有整数类型都是 `NUMBER(38, 0)` 别名

这种设计简化用户体验，但对引擎开发者是双刃剑：失去了利用窄类型 SIMD 加速的机会，但避免了类型转换 bug。

### 5. 128 位整数在 2019-2024 间大规模兴起

- 2019: ClickHouse Int128/UInt128 (19.7)
- 2020: ClickHouse Int256/UInt256 (20.4)
- 2021: CockroachDB INT128 (实验性)；Firebird INT128 (4.0)
- 早期: DuckDB HUGEINT；StarRocks/Doris LARGEINT；MonetDB HUGEINT

驱动力: 加密货币、区块链、金融高精度计算、大规模分布式 ID。

### 6. UNSIGNED 是 MySQL 系 + 列存引擎的特性

支持 UNSIGNED 的引擎：
- MySQL 系（MySQL/MariaDB/TiDB/SingleStore/OceanBase MySQL）
- 列存引擎（ClickHouse、DuckDB、DatabendDB、InfluxDB）

不支持 UNSIGNED 的引擎（普遍）：
- 所有 PG 派生（PG/Greenplum/CockroachDB/YugabyteDB/Materialize/RisingWave）
- 所有大型商业数据库（Oracle/SQL Server/DB2）
- 所有云数仓（BigQuery/Snowflake/Redshift）
- 所有 Trino/Presto/Spark 系
- 所有 Java 生态（H2/HSQLDB/Derby）

PG 不支持 UNSIGNED 的设计原因: SQL 标准未定义无符号；与算术运算交互复杂（隐式类型提升规则不明确）；CHECK 约束可以模拟。

### 7. SERIAL 在 PG 中已"半弃用"

PostgreSQL 10+ 推荐用 SQL 标准的 `GENERATED AS IDENTITY` 替代 `SERIAL`/`BIGSERIAL`。原因：
- 权限管理：sequence 权限独立于表，容易遗漏 `GRANT USAGE ON SEQUENCE`
- COPY FROM：插入显式 ID 后 sequence 不更新，导致后续插入冲突
- Schema 复制：sequence 名字与表名耦合，重命名时容易遗漏
- 跨库迁移：`IDENTITY` 是 SQL 标准，跨 PG/Oracle/DB2 兼容

```sql
-- 旧风格 (仍可工作)
CREATE TABLE t (id SERIAL PRIMARY KEY);

-- 新风格 (推荐)
CREATE TABLE t (id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY);
```

### 8. 整数溢出处理三大流派

| 流派 | 行为 | 代表引擎 |
|------|------|---------|
| **抛错** (严格) | 溢出立即报错 | PostgreSQL, SQL Server, Oracle, DuckDB, BigQuery, Trino, MySQL (严格模式) |
| **静默环绕** (宽松) | 二进制补码环绕 | ClickHouse, Hive, Spark (ANSI=off), Vertica |
| **自动提升** (避溢出) | NUMBER 扩展精度 | Oracle (NUMBER(38)), Snowflake (NUMBER(38, 0)) |

详见 `arithmetic-overflow-division.md`。

### 9. MEDIUMINT 是 MySQL 独有的"历史遗产"

24 位 (3 字节) `MEDIUMINT` 仅在 MySQL 系（MySQL/MariaDB/TiDB/SingleStore/OceanBase MySQL）支持。设计意图是 1995 年节省存储，但现代硬件下意义不大。跨库迁移时直接用 `INTEGER` 替换（浪费 1 字节）。

### 10. SQLite 的"动态整数"是独特设计

SQLite 的 `INTEGER` 不是固定字节数，而是**根据值大小动态使用 1, 2, 3, 4, 6, 或 8 字节**。这是类型亲和性 (type affinity) 的体现：
- 声明 `TINYINT`/`SMALLINT`/`BIGINT` 列时，实际都是 INTEGER 亲和
- 物理存储按值大小压缩
- 单列内可以有不同字节宽度的整数（值 100 占 1B，值 10^9 占 4B）

这种设计与列存引擎的"值压缩"有相似之处，但 SQLite 是行存引擎下的独特优化。

## 对引擎开发者的实现建议

### 1. 选择基准类型

```
最小兼容矩阵 (覆盖 95% SQL 使用):
  ✅ INTEGER (4B 有符号)
  ✅ BIGINT (8B 有符号)
  ✅ SMALLINT (2B 有符号)
  ✅ DECIMAL/NUMERIC (任意精度模拟大整数)
  ⚠️ TINYINT (1B 有符号 — 决定符号性时参考目标用户)
  ❌ MEDIUMINT (3B — 不要新增，复杂度不值)

UNSIGNED 决策:
  - 若目标是 MySQL 兼容: 必须支持 UNSIGNED 修饰
  - 若目标是 PG 兼容: 不支持 UNSIGNED，用 CHECK 约束
  - 若是新设计: 建议参考 ClickHouse/DuckDB 的独立类型方案，避免 MySQL 的修饰符复杂性

INT128 决策:
  - 行存 OLTP: 通常不需要 INT128，DECIMAL(38) 已够
  - 列存 OLAP: 推荐原生 INT128（加密哈希、UUID、金融）
  - 区块链: 必须 INT256
```

### 2. 类型提升规则

```
表达式类型推断 (避免溢出):
  TINYINT + TINYINT     -> SMALLINT (避免 1B 溢出)
  SMALLINT + SMALLINT   -> INTEGER  (避免 2B 溢出)
  INTEGER + INTEGER     -> BIGINT   (避免 4B 溢出)  -- 严格模式
  BIGINT + BIGINT       -> 抛错或环绕 (无更大类型)
  BIGINT + DECIMAL      -> DECIMAL  (扩展精度)

或者 PostgreSQL/SQL Server 风格:
  T + T -> T (相同类型，溢出抛错)
```

### 3. 溢出处理策略

```
严格模式 (推荐 OLTP):
  - 算术溢出抛错 (ERROR: integer out of range)
  - 提供 try_add() / try_subtract() 等安全函数返回 NULL

宽松模式 (兼容 MySQL/ClickHouse):
  - 算术溢出静默环绕（二进制补码）
  - 提供 ANSI 开关切换严格模式 (Spark 风格)

自动扩展 (兼容 Oracle/Snowflake):
  - INTEGER + INTEGER -> NUMBER(38)
  - 永不溢出，但失去硬件加速
```

### 4. SIMD 加速实现

```
向量化整数运算建议:
  - INT8: 一条 AVX-512 指令可处理 64 个值
  - INT16: 一条 AVX-512 指令可处理 32 个值
  - INT32: 一条 AVX-512 指令可处理 16 个值
  - INT64: 一条 AVX-512 指令可处理 8 个值
  - INT128: 通常无 SIMD，2-4 倍慢于 INT64
  - INT256: 通常无 SIMD，4-8 倍慢于 INT64

设计建议:
  - 优先优化 INT32/INT64 路径（覆盖 80% 用例）
  - INT128 用通用编译器内联（__int128 in C++）
  - INT256 用结构化拆分（4x INT64）
```

### 5. 存储压缩

```
列存压缩策略:
  - 字典编码: 低基数 INT 列（如 status_code）
  - RLE: 连续相同值（如时间排序的 INT）
  - 帧编码 (Frame-of-reference): 范围窄的 INT 列
  - 位打包 (Bit-packing): 实际值远小于声明类型

行存压缩 (SQLite 风格):
  - 变长存储: 0~127 用 1B，128~32767 用 2B，等等
  - 优势: 简单透明
  - 劣势: 解码开销，无 SIMD 加速

混合方案 (推荐):
  - 声明 INT64，但存储自动按值范围压缩
  - 元数据记录最小/最大值，触发压缩选择
```

### 6. 跨语言绑定

```
JDBC 整数映射建议:
  - INT -> int (32 位)
  - INT UNSIGNED -> long (避免负数溢出)
  - BIGINT -> long
  - BIGINT UNSIGNED -> BigInteger (避免负数溢出)
  - INT128 -> BigInteger

ODBC: 类似 JDBC，但 SQL_TYPE_BIGINT 即 8 字节有符号
Python (psycopg2 / mysqlclient): int (任意精度，无溢出)
Go (database/sql): int64 / uint64
Rust (sqlx): i32 / i64 / u32 / u64
```

### 7. 测试要点

```
必测场景:
  ✓ 边界值: T_MIN, T_MIN+1, -1, 0, 1, T_MAX-1, T_MAX
  ✓ 溢出: T_MAX + 1, T_MIN - 1
  ✓ UNSIGNED 边界: 0, 0-1, T_MAX_UNSIGNED, T_MAX_UNSIGNED+1
  ✓ 类型转换: TINYINT 与 BIGINT 比较 (隐式提升)
  ✓ NULL 与整数运算: NULL + 1 = NULL
  ✓ DIV0: 整数除以零 (各方言行为不同)
  ✓ 模运算: T_MIN % -1 (某些 CPU 抛错)
  ✓ 移位: 1 << 63 (符号位边界)
```

## 参考资料

- SQL:1992 标准: ISO/IEC 9075-2:1992, Section 4.3.1 (Numeric Types)
- SQL:2003 标准: ISO/IEC 9075-2:2003 (BIGINT 引入)
- MySQL: [Integer Types](https://dev.mysql.com/doc/refman/8.0/en/integer-types.html)
- MySQL: [TINYINT(1) and BOOLEAN](https://dev.mysql.com/doc/refman/8.0/en/numeric-types.html)
- PostgreSQL: [Numeric Types](https://www.postgresql.org/docs/current/datatype-numeric.html)
- PostgreSQL: [SERIAL deprecation note (10+)](https://wiki.postgresql.org/wiki/Don%27t_Do_This)
- Oracle: [NUMBER Data Type](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Data-Types.html)
- SQL Server: [int, bigint, smallint, tinyint](https://learn.microsoft.com/en-us/sql/t-sql/data-types/int-bigint-smallint-and-tinyint-transact-sql)
- ClickHouse: [Int8, Int16, ..., Int256](https://clickhouse.com/docs/en/sql-reference/data-types/int-uint)
- DuckDB: [Numeric Types](https://duckdb.org/docs/sql/data_types/numeric)
- Snowflake: [Numeric Data Types](https://docs.snowflake.com/en/sql-reference/data-types-numeric)
- BigQuery: [Numeric Types](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#numeric_types)
- CockroachDB: [INT default size](https://www.cockroachlabs.com/docs/stable/int.html)
- Firebird: [INT128 data type (4.0)](https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rnfb40-numbers.html)
- StarRocks: [LARGEINT](https://docs.starrocks.io/docs/sql-reference/data-types/numeric/LARGEINT/)
- 相关文档: `data-type-mapping.md`、`arithmetic-overflow-division.md`、`auto-increment-sequence-identity.md`
