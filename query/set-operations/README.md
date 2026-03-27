# 集合操作 (SET OPERATIONS)

各数据库集合操作语法对比，包括 UNION、INTERSECT、EXCEPT。

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

1. **EXCEPT vs MINUS**：SQL 标准用 EXCEPT，Oracle 用 MINUS（语义相同），MySQL 8.0.31+ 才支持 EXCEPT/INTERSECT
2. **UNION ALL vs UNION**：UNION 去重排序开销大，90% 场景应使用 UNION ALL（已知无重复或不需要去重时）
3. **列匹配规则**：所有集合操作要求 SELECT 列表数量相同，但类型兼容性规则各方言不同（MySQL 隐式转换较宽松）
4. **排序限制**：ORDER BY 只能出现在最后一个 SELECT 之后（应用于整个结果集），不能在中间的 SELECT 中使用

## 选型建议

UNION ALL 是性能最好的集合操作，优先使用。INTERSECT 可以用 INNER JOIN 替代，EXCEPT 可以用 LEFT JOIN ... WHERE ... IS NULL 替代（在不支持集合操作的老版本中）。大数据场景下 UNION ALL 常用于合并多个分区的查询结果。

## 版本演进

- MySQL 8.0.31+：首次支持 INTERSECT 和 EXCEPT（之前只支持 UNION/UNION ALL）
- MariaDB 10.3+：支持 INTERSECT 和 EXCEPT
- PostgreSQL：一直完整支持所有集合操作，包括 INTERSECT ALL 和 EXCEPT ALL

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **UNION/UNION ALL** | 完整支持 | 完整支持 | 完整支持 | 均支持 |
| **INTERSECT/EXCEPT** | 完整支持 | 支持 INTERSECT，EXCEPT 用 NOT IN 替代 | 完整支持 INTERSECT/EXCEPT | PG 完整支持，MySQL 8.0.31+ 才支持 |
| **EXCEPT vs MINUS** | 使用 EXCEPT | 使用 EXCEPT | 使用 EXCEPT | Oracle 用 MINUS（语义相同） |
| **类型匹配** | 动态类型，列匹配宽松（不严格检查类型） | 严格类型匹配 | 严格类型匹配 | PG 严格 / MySQL 宽松隐式转换 |
| **性能考量** | 单文件操作，小数据集高效 | 分布式执行，UNION ALL 常用于合并分片结果 | 按扫描量计费，UNION ALL 扫描两倍数据 | 优化器选择合并策略 |
