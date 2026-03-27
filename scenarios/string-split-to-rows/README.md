# 字符串拆分 (STRING SPLIT TO ROWS)

各数据库字符串拆分为多行的最佳实践，包括分隔符分割、正则拆分等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | JSON_TABLE 展开(8.0+)，递归 CTE 拆分 |
| [PostgreSQL](postgres.sql) | STRING_TO_TABLE(14+)/regexp_split_to_table |
| [SQLite](sqlite.sql) | json_each + JSON 数组 或递归 CTE |
| [Oracle](oracle.sql) | CONNECT BY + REGEXP_SUBSTR 或 JSON_TABLE |
| [SQL Server](sqlserver.sql) | STRING_SPLIT(2016+)/CROSS APPLY 展开 |
| [MariaDB](mariadb.sql) | 递归 CTE 或 JSON_TABLE(10.6+) |
| [Firebird](firebird.sql) | 递归 CTE 手动拆分 |
| [IBM Db2](db2.sql) | XMLTABLE + 递归 CTE 方案 |
| [SAP HANA](saphana.sql) | SERIES_GENERATE + SUBSTRING 方案 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | SPLIT() + UNNEST 一步展开 |
| [Snowflake](snowflake.sql) | SPLIT_TO_TABLE()/LATERAL FLATTEN |
| [ClickHouse](clickhouse.sql) | splitByChar/splitByString + arrayJoin |
| [Hive](hive.sql) | explode(split()) + LATERAL VIEW |
| [Spark SQL](spark.sql) | explode(split()) 展开 |
| [Flink SQL](flink.sql) | UNNEST + STRING_TO_ARRAY 展开 |
| [StarRocks](starrocks.sql) | explode(split()) + LATERAL |
| [Doris](doris.sql) | explode_split() + LATERAL VIEW |
| [Trino](trino.sql) | split() + UNNEST 展开 |
| [DuckDB](duckdb.sql) | string_split() + UNNEST 展开 |
| [MaxCompute](maxcompute.sql) | explode(split()) + LATERAL VIEW |
| [Hologres](hologres.sql) | regexp_split_to_table(PG 兼容) |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | SPLIT_TO_ARRAY + 行号展开 |
| [Azure Synapse](synapse.sql) | STRING_SPLIT(T-SQL 兼容) |
| [Databricks SQL](databricks.sql) | explode(split()) 展开 |
| [Greenplum](greenplum.sql) | regexp_split_to_table(PG 兼容) |
| [Impala](impala.sql) | explode(split()) + LATERAL VIEW |
| [Vertica](vertica.sql) | SPLIT_PART + 生成行方案 |
| [Teradata](teradata.sql) | STRTOK_SPLIT_TO_TABLE 原生函数 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | 递归 CTE + SUBSTRING_INDEX |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 模式拆分方案 |
| [CockroachDB](cockroachdb.sql) | regexp_split_to_table(PG 兼容) |
| [Spanner](spanner.sql) | SPLIT() + UNNEST 展开 |
| [YugabyteDB](yugabytedb.sql) | regexp_split_to_table(PG 兼容) |
| [PolarDB](polardb.sql) | MySQL 兼容 JSON_TABLE 或递归 CTE |
| [openGauss](opengauss.sql) | regexp_split_to_table(PG 兼容) |
| [TDSQL](tdsql.sql) | MySQL 兼容递归 CTE 方案 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | CONNECT BY 或递归 CTE |
| [KingbaseES](kingbase.sql) | PG 兼容 regexp_split_to_table |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 字符串拆分函数 |
| [TDengine](tdengine.sql) | 不支持字符串拆行 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 不支持字符串拆行 |
| [Materialize](materialize.sql) | regexp_split_to_table(PG 兼容) |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 无 STRING_SPLIT，递归 CTE 模拟 |
| [Derby](derby.sql) | 无 STRING_SPLIT，Java 过程模拟 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 无标准拆分(厂商扩展) |

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **拆分函数** | 无内置拆分函数（递归 CTE + substr 模拟） | splitByChar/splitByString 返回 Array + arrayJoin 展开 | SPLIT() 返回 ARRAY + UNNEST() 展开 | PG STRING_TO_TABLE()/unnest / MySQL JSON_TABLE 模拟 / Oracle REGEXP_SUBSTR |
| **ARRAY 支持** | 无原生 ARRAY 类型 | 原生 Array 类型，拆分天然高效 | 原生 ARRAY + UNNEST | PG 原生 ARRAY / MySQL 无原生 ARRAY |
| **性能** | 递归 CTE 拆分效率低 | 列式 Array 操作高效 | Serverless 弹性处理 | 取决于方法和数据量 |

## 引擎开发者视角

**核心设计决策**：字符串拆分为多行涉及两个子问题——拆分函数（split string -> array）和展开操作（array -> rows）。引擎是否有原生 ARRAY 类型直接决定实现方案。

**实现建议**：
- 最优方案是 SPLIT + UNNEST 组合：先将字符串拆分为数组，再将数组展开为多行。PostgreSQL 的 STRING_TO_TABLE() 函数直接一步完成是最优雅的实现
- 如果引擎有原生 ARRAY 类型，SPLIT(string, delimiter) -> ARRAY 是自然的实现。ClickHouse 的 splitByChar/splitByString -> arrayJoin 组合紧凑高效
- 没有 ARRAY 类型的引擎需要用递归 CTE + SUBSTRING 模拟拆分——性能差且代码冗长。这是 MySQL 长期的痛点（直到 JSON_TABLE 才有了可用的替代方案）
- UNNEST/展开操作的关键决策：展开空数组时是否保留原始行（LEFT JOIN 语义 vs INNER JOIN 语义）。PostgreSQL 的 unnest 默认是 INNER 语义（空数组丢失行），CROSS JOIN LATERAL 可以用 LEFT JOIN LATERAL 保留
- 正则拆分（按正则表达式模式拆分）是高级需求——PostgreSQL 的 regexp_split_to_table() 直接支持，值得借鉴
- 常见错误：拆分结果中的空字符串处理。`'a,,b'` 按逗号拆分应该产生 `['a', '', 'b']` 三个元素还是 `['a', 'b']` 两个元素？应遵循标准的拆分语义保留空字符串，并让用户自行过滤
