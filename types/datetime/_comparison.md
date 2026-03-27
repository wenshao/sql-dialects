# 日期时间类型 (DateTime Types) — 方言对比

## 类型支持对比

### 传统 RDBMS

| 类型 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| DATE | ✅ | ✅ | ⚠️ TEXT | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| TIME | ✅ | ✅ | ⚠️ TEXT | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| DATETIME | ✅ | ❌ | ⚠️ TEXT | ❌ | ✅ DATETIME2 | ✅ | ❌ | ❌ | ❌ |
| TIMESTAMP | ✅ 特殊 | ✅ | ⚠️ TEXT | ✅ | ❌ | ✅ 特殊 | ✅ | ✅ | ✅ SECONDDATE |
| TIMESTAMP WITH TZ | ❌ | ✅ TIMESTAMPTZ | ❌ | ✅ | ✅ DATETIMEOFFSET | ❌ | ❌ | ❌ | ✅ |
| INTERVAL | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 精度 | 微秒 6 | 微秒 6 | ❌ | 纳秒 9 | 100纳秒 7 | 微秒 6 | 100微秒 4 | 微秒 6 | 纳秒 7 |

### 大数据 / 分析引擎

| 类型 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| DATE | ✅ | ✅ | ✅ | ✅ | ✅ Date/Date32 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| TIME | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| DATETIME | ✅ | ❌ | ✅ | ❌ | ✅ DateTime/DateTime64 | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| TIMESTAMP | ✅ | ✅ TIMESTAMP_NTZ/LTZ/TZ | ✅ | ✅ | ✅ DateTime64 | ✅ | ✅ | ✅ TIMESTAMPTZ | ✅ | ✅ | ✅ | ✅ |
| INTERVAL | ⚠️ 运算用 | ✅ | ❌ | ❌ | ✅ IntervalDay 等 | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
| 精度 | 微秒 6 | 纳秒 9 | 毫秒 3 | 纳秒 9 | 可配置 0-9 | 微秒 6 | 皮秒 12 | 微秒 6 | 微秒 6 | 微秒 6 | 微秒 6 | 毫秒 3 |

### 特殊说明

| 数据库 | 特点 |
|---|---|
| SQLite | 无专用日期类型，以 TEXT/REAL/INTEGER 存储 |
| Snowflake | 区分 TIMESTAMP_NTZ / TIMESTAMP_LTZ / TIMESTAMP_TZ 三种时间戳 |
| BigQuery | 区分 DATETIME（无时区）和 TIMESTAMP（UTC 微秒） |
| TDengine | 时间戳是每行的必需首列，精度可选毫秒/微秒/纳秒 |
| ClickHouse | DateTime 秒级，DateTime64 可配置 0-18 精度 |

## 关键差异

- **SQLite** 无原生日期类型，一切存为 TEXT/REAL/INTEGER
- **MySQL TIMESTAMP** 有特殊行为（自动更新、UTC 存储、2038 年限制）
- **Snowflake** 三种 TIMESTAMP 变体是独有设计
- **Oracle** 没有 TIME 类型，没有 DATETIME 类型
- **SQL Server** 使用 DATETIME2 替代 DATETIME（精度更高）
- **PostgreSQL** INTERVAL 类型最完善，支持复杂间隔运算
- **Trino** 精度最高达 12 位（皮秒）
- **TDengine** 时间戳是数据模型核心，精度可配置到纳秒
