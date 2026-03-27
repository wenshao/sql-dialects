# 日期函数 (DATE FUNCTIONS)

各数据库日期函数对比，包括日期加减、格式化、提取、差值计算等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 链接 |
|---|---|
| MySQL | [mysql.sql](mysql.sql) |
| PostgreSQL | [postgres.sql](postgres.sql) |
| SQLite | [sqlite.sql](sqlite.sql) |
| Oracle | [oracle.sql](oracle.sql) |
| SQL Server | [sqlserver.sql](sqlserver.sql) |
| MariaDB | [mariadb.sql](mariadb.sql) |
| Firebird | [firebird.sql](firebird.sql) |
| IBM Db2 | [db2.sql](db2.sql) |
| SAP HANA | [saphana.sql](saphana.sql) |

### 大数据 / 分析型引擎
| 方言 | 链接 |
|---|---|
| BigQuery | [bigquery.sql](bigquery.sql) |
| Snowflake | [snowflake.sql](snowflake.sql) |
| ClickHouse | [clickhouse.sql](clickhouse.sql) |
| Hive | [hive.sql](hive.sql) |
| Spark SQL | [spark.sql](spark.sql) |
| Flink SQL | [flink.sql](flink.sql) |
| StarRocks | [starrocks.sql](starrocks.sql) |
| Doris | [doris.sql](doris.sql) |
| Trino | [trino.sql](trino.sql) |
| DuckDB | [duckdb.sql](duckdb.sql) |
| MaxCompute | [maxcompute.sql](maxcompute.sql) |
| Hologres | [hologres.sql](hologres.sql) |

### 云数仓
| 方言 | 链接 |
|---|---|
| Redshift | [redshift.sql](redshift.sql) |
| Azure Synapse | [synapse.sql](synapse.sql) |
| Databricks SQL | [databricks.sql](databricks.sql) |
| Greenplum | [greenplum.sql](greenplum.sql) |
| Impala | [impala.sql](impala.sql) |
| Vertica | [vertica.sql](vertica.sql) |
| Teradata | [teradata.sql](teradata.sql) |

### 分布式 / NewSQL
| 方言 | 链接 |
|---|---|
| TiDB | [tidb.sql](tidb.sql) |
| OceanBase | [oceanbase.sql](oceanbase.sql) |
| CockroachDB | [cockroachdb.sql](cockroachdb.sql) |
| Spanner | [spanner.sql](spanner.sql) |
| YugabyteDB | [yugabytedb.sql](yugabytedb.sql) |
| PolarDB | [polardb.sql](polardb.sql) |
| openGauss | [opengauss.sql](opengauss.sql) |
| TDSQL | [tdsql.sql](tdsql.sql) |

### 国产数据库
| 方言 | 链接 |
|---|---|
| DamengDB | [dameng.sql](dameng.sql) |
| KingbaseES | [kingbase.sql](kingbase.sql) |

### 时序数据库
| 方言 | 链接 |
|---|---|
| TimescaleDB | [timescaledb.sql](timescaledb.sql) |
| TDengine | [tdengine.sql](tdengine.sql) |

### 流处理
| 方言 | 链接 |
|---|---|
| ksqlDB | [ksqldb.sql](ksqldb.sql) |
| Materialize | [materialize.sql](materialize.sql) |

### 嵌入式 / 轻量
| 方言 | 链接 |
|---|---|
| H2 | [h2.sql](h2.sql) |
| Derby | [derby.sql](derby.sql) |

### SQL 标准
| 方言 | 链接 |
|---|---|
| SQL Standard | [sql-standard.sql](sql-standard.sql) |

## 核心差异

1. **日期加减**：MySQL 用 DATE_ADD()/DATE_SUB()/INTERVAL 关键字，PostgreSQL 用 `+ INTERVAL '1 day'` 运算符，Oracle 用 ADD_MONTHS()/date ± number，SQL Server 用 DATEADD()
2. **日期差值**：MySQL 用 DATEDIFF()（只返回天数），PostgreSQL 直接相减（date1 - date2 返回整数天），Oracle 直接相减返回小数天，SQL Server DATEDIFF() 可指定单位
3. **日期截断**：MySQL 没有原生 DATE_TRUNC（用 DATE_FORMAT 模拟），PostgreSQL/Snowflake/BigQuery 用 DATE_TRUNC()，Oracle 用 TRUNC()
4. **格式化字符串**：MySQL 用 `%Y-%m-%d`，Oracle 用 `YYYY-MM-DD`，PostgreSQL 的 TO_CHAR 用 `YYYY-MM-DD`，SQL Server 用格式代码数字
5. **一周的第一天**：MySQL 取决于 @@default_week_format，PostgreSQL 一周从周一开始（ISO 标准），Oracle 取决于 NLS_TERRITORY

## 选型建议

日期函数是跨方言迁移时工作量最大的领域之一。建议在应用层封装日期操作逻辑，或使用 ORM 的日期函数抽象。关键日期操作（月末、工作日计算）建议写单元测试验证跨方言行为一致性。

## 版本演进

- MySQL 8.0：引入更多窗口函数与日期结合的能力，但仍无 DATE_TRUNC
- PostgreSQL 14+：增强 EXTRACT 和 date_bin() 函数（按任意间隔截断时间）
- BigQuery：日期函数设计最一致（DATE_ADD/DATE_SUB/DATE_DIFF/DATE_TRUNC 命名统一）

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **日期存储** | 无原生日期类型，日期存为 TEXT/REAL/INTEGER | 有 Date/Date32/DateTime/DateTime64 原生类型 | DATE/DATETIME/TIMESTAMP 原生类型 | 各方言有原生日期时间类型 |
| **日期函数** | 有限函数集：date()/time()/datetime()/strftime() | 极其丰富：toDate/toDateTime/addDays/dateDiff 等 | 统一命名：DATE_ADD/DATE_SUB/DATE_DIFF/DATE_TRUNC | MySQL DATE_ADD / PG interval 运算 / Oracle ADD_MONTHS |
| **DATE_TRUNC** | 无原生 DATE_TRUNC（用 strftime 模拟） | toStartOfMonth/toStartOfDay 等专用函数 | DATE_TRUNC（设计最一致） | PG 有 DATE_TRUNC，MySQL 无原生支持 |
| **时区处理** | 无时区概念（存储什么就是什么） | DateTime 可指定时区（'Asia/Shanghai'） | TIMESTAMP 自动 UTC 处理 | PG TIMESTAMPTZ 最佳 / MySQL TIMESTAMP 自动转 UTC |
| **动态类型影响** | 日期存为字符串时，比较和排序可能不符预期 | 严格类型确保日期计算正确 | 严格类型 | 严格类型 |

## 引擎开发者视角

**核心设计决策**：日期函数是方言差异最大的领域，引擎在函数命名和行为上的选择直接决定了与现有生态的兼容程度。

**实现建议**：
- 推荐采用统一命名模式：DATE_ADD/DATE_SUB/DATE_DIFF/DATE_TRUNC/DATE_PART——BigQuery 的设计最一致，用户学习成本低。避免 MySQL 的多套等价函数（DATE_ADD = ADDDATE, DATE_SUB = SUBDATE）
- DATE_TRUNC（按指定粒度截断时间戳）是分析查询的核心函数，MySQL 至今不支持是重大缺失。新引擎必须从第一天就支持
- INTERVAL 类型是否作为一等公民存储：PostgreSQL 的做法（INTERVAL 可以存储为列类型）更灵活但实现复杂，MySQL 的做法（INTERVAL 仅用于函数参数）更简单
- 时区处理是最容易出错的领域：推荐内部统一使用 UTC 存储，输入输出时根据会话时区转换。PostgreSQL 的 TIMESTAMPTZ 模型是黄金标准——存储 UTC，显示时自动转换
- date_bin()（PostgreSQL 14+，按任意间隔对齐时间戳）是新兴的高价值函数——比 DATE_TRUNC 更灵活（可以按 15 分钟、6 小时等任意间隔对齐），时序分析场景价值极大
- 常见错误：一周的第一天不可配置。ISO 标准定义周一为一周的第一天，但美国用户期望周日是第一天——引擎应提供会话级配置参数
