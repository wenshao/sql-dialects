# 聚合函数 (AGGREGATE FUNCTIONS)

各数据库聚合函数对比，包括 COUNT、SUM、AVG、MIN、MAX、GROUP_CONCAT 等。

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

1. **字符串聚合**：MySQL 用 GROUP_CONCAT()，PostgreSQL 用 STRING_AGG()（9.0+），Oracle 用 LISTAGG()，SQL Server 用 STRING_AGG()（2017+），分隔符参数位置和默认行为各不相同
2. **COUNT(DISTINCT) 多列**：MySQL 支持 `COUNT(DISTINCT a, b)`，PostgreSQL/Oracle/SQL Server 不支持（需要子查询或 CONCAT 模拟）
3. **NULL 处理**：所有标准聚合函数（SUM/AVG/MIN/MAX）跳过 NULL 值，`COUNT(*)` 计所有行但 `COUNT(column)` 跳过 NULL
4. **FILTER 子句**：PostgreSQL 9.4+ 支持 `SUM(x) FILTER (WHERE condition)`，其他方言需要用 `SUM(CASE WHEN condition THEN x END)` 模拟
5. **近似聚合**：BigQuery/ClickHouse/Snowflake 提供 APPROX_COUNT_DISTINCT 等近似聚合函数，大数据量下性能远优于精确计算

## 选型建议

COUNT(DISTINCT) 在大基数列上性能差，大数据场景考虑使用 HyperLogLog 等近似算法。GROUP_CONCAT/STRING_AGG 的结果长度可能受限（MySQL 默认 1024 字节限制，需调整 group_concat_max_len）。FILTER 子句是 PostgreSQL 的杀手级特性，比 CASE WHEN 更简洁。

## 版本演进

- PostgreSQL 9.4+：引入聚合函数的 FILTER 子句
- SQL Server 2017+：引入 STRING_AGG()（替代 FOR XML PATH 拼接字符串的复杂写法）
- MySQL 8.0：GROUP_CONCAT 仍是主要的字符串聚合方式，无 STRING_AGG

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **基本聚合** | 支持 COUNT/SUM/AVG/MIN/MAX/GROUP_CONCAT | 支持全部标准聚合 + 大量扩展函数 | 完整支持 + APPROX 近似函数 | 完整支持 |
| **字符串聚合** | GROUP_CONCAT（与 MySQL 类似） | groupArray + arrayStringConcat 组合 | STRING_AGG | MySQL GROUP_CONCAT / PG STRING_AGG / Oracle LISTAGG |
| **近似聚合** | 不支持 | 丰富：uniq/uniqExact/uniqHLL12/uniqCombined | APPROX_COUNT_DISTINCT 等 | PG/MySQL 不内置，Oracle 有 APPROX_COUNT_DISTINCT |
| **FILTER 子句** | 不支持（用 CASE WHEN 替代） | 支持 -If 后缀聚合函数（countIf/sumIf 等） | 不支持（用 CASE WHEN 或 COUNTIF） | PG 9.4+ 支持 FILTER (WHERE ...) |
| **列式优势** | 行存储，聚合需全行读取 | 列式存储使聚合极其高效（只读目标列） | 列式存储 + 按扫描列计费，SELECT 特定列可降低成本 | 行存储，聚合需读取完整行 |

## 引擎开发者视角

**核心设计决策**：聚合函数的实现直接影响分析查询的性能。需要决定：支持哪些聚合函数、是否支持用户自定义聚合（UDAF）、是否提供近似聚合函数。

**实现建议**：
- 最低实现：COUNT/SUM/AVG/MIN/MAX + GROUP BY。聚合算子的内存管理是关键——GROUP BY 高基数列时的哈希表可能超出内存，必须有溢出到磁盘的机制（hash-based aggregation with spilling）
- STRING_AGG/LISTAGG（字符串聚合）是高频需求，实现优先级应高于一般认知。MySQL 的 GROUP_CONCAT 有默认 1024 字节限制是设计缺陷——新引擎应默认不限制或设足够大的上限
- FILTER 子句（PostgreSQL 9.4+ 的 `SUM(x) FILTER (WHERE cond)`）对优化器很友好——可以生成更高效的执行计划。比 CASE WHEN 的等价改写优化空间更大
- 近似聚合函数（APPROX_COUNT_DISTINCT/HyperLogLog）对大数据引擎几乎是必选——精确的 COUNT DISTINCT 在十亿行级别不实际。ClickHouse 的 uniq/uniqHLL12/uniqCombined 系列函数是优秀参考
- 用户自定义聚合函数（UDAF）应使用 init/accumulate/merge/finalize 四步接口——merge 步骤对分布式引擎的并行聚合至关重要
- 常见错误：AVG 的整数除法问题（SUM/COUNT 都是整数时 AVG 可能丢失精度）。聚合函数内部应使用高精度中间类型进行计算
