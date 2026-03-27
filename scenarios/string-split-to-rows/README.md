# 字符串拆分 (STRING SPLIT TO ROWS)

各数据库字符串拆分为多行的最佳实践，包括分隔符分割、正则拆分等。

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
