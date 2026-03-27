# 日期函数 (Date Functions) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| 当前日期 | NOW()/CURDATE() | NOW()/CURRENT_DATE | datetime('now') | SYSDATE | GETDATE()/SYSDATETIME() | NOW() | CURRENT_TIMESTAMP | CURRENT TIMESTAMP | CURRENT_TIMESTAMP |
| 日期加减 | DATE_ADD/INTERVAL | + INTERVAL | datetime('+N days') | ADD_MONTHS/+INTERVAL | DATEADD | DATE_ADD/INTERVAL | DATEADD | + N DAYS | ADD_DAYS/ADD_MONTHS |
| 日期差 | DATEDIFF/TIMESTAMPDIFF | AGE()/DATE_PART | julianday 差 | MONTHS_BETWEEN | DATEDIFF | DATEDIFF/TIMESTAMPDIFF | DATEDIFF | TIMESTAMPDIFF | DAYS_BETWEEN |
| 提取部分 | EXTRACT/YEAR() | EXTRACT/DATE_PART | strftime | EXTRACT/TO_CHAR | DATEPART/YEAR() | EXTRACT/YEAR() | EXTRACT | EXTRACT | EXTRACT/YEAR() |
| 格式化 | DATE_FORMAT | TO_CHAR | strftime | TO_CHAR | FORMAT/CONVERT | DATE_FORMAT | ❌ | TO_CHAR/VARCHAR_FORMAT | TO_VARCHAR |
| 解析 | STR_TO_DATE | TO_TIMESTAMP | datetime() | TO_DATE | CONVERT/PARSE | STR_TO_DATE | ❌ | TO_TIMESTAMP | TO_TIMESTAMP |
| 截断 | DATE() | DATE_TRUNC | date() | TRUNC | ❌ | DATE() | ❌ | TRUNC/TRUNCATE | ❌ |
| 时区转换 | CONVERT_TZ | AT TIME ZONE | ❌ | FROM_TZ/AT TIME ZONE | AT TIME ZONE | CONVERT_TZ | ❌ | AT TIME ZONE | ❌ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 日期加减 | DATE_ADD | DATEADD | DATEADD | DATE_ADD | addDays/addMonths | DATE_ADD | date_add | + INTERVAL | DATE_ADD | + INTERVAL | DATE_ADD | TIMESTAMPADD |
| 日期差 | DATE_DIFF | DATEDIFF | DATEDIFF | DATEDIFF | dateDiff | DATEDIFF | date_diff | AGE/DATE_PART | DATEDIFF | - / date_diff | DATEDIFF | TIMESTAMPDIFF |
| 格式化 | FORMAT_TIMESTAMP | TO_CHAR | DATE_FORMAT | DATE_FORMAT | formatDateTime | DATE_FORMAT | date_format | TO_CHAR | DATE_FORMAT | strftime | DATE_FORMAT | DATE_FORMAT |
| 截断 | DATE_TRUNC | DATE_TRUNC | ❌ | TRUNC | toStartOfDay/Month | DATE_TRUNC | date_trunc | DATE_TRUNC | DATE_TRUNC | date_trunc | DATE_TRUNC | ❌ |
| 时区转换 | TIMESTAMP(tz) | CONVERT_TIMEZONE | ❌ | FROM_UTC_TIMESTAMP | toTimezone | CONVERT_TZ | AT TIME ZONE | AT TIME ZONE | CONVERT_TZ | timezone | FROM_UTC_TIMESTAMP | CONVERT_TZ |
| UNIX 时间戳 | UNIX_SECONDS | DATE_PART(epoch) | ✅ | ❌ | toUnixTimestamp | UNIX_TIMESTAMP | to_unixtime | EXTRACT(epoch) | UNIX_TIMESTAMP | epoch | UNIX_TIMESTAMP | UNIX_TIMESTAMP |

## 关键差异

- **函数命名差异极大**，同一功能在不同方言中名称完全不同
- **BigQuery** 区分 DATE_ADD/DATETIME_ADD/TIMESTAMP_ADD，按类型选择函数
- **ClickHouse** 使用 camelCase 函数名（addDays, toStartOfMonth 等）
- **SQLite** 使用 strftime 和 datetime 函数处理日期，功能有限
- **Oracle** 使用 TO_CHAR/TO_DATE 格式化和解析，格式串与其他方言不兼容
- **SQL Server** 不支持 DATE_TRUNC，需用 DATEADD/DATEDIFF 模拟
- **PostgreSQL/DuckDB** 支持日期直接运算（+ INTERVAL）
- **SAP HANA** 使用独特的 ADD_DAYS/DAYS_BETWEEN 系列函数
