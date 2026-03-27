# 聚合函数 (AGGREGATE FUNCTIONS)

各数据库聚合函数对比，包括 COUNT、SUM、AVG、MIN、MAX、GROUP_CONCAT 等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | GROUP_CONCAT，JSON_ARRAYAGG(5.7+)，基础聚合 |
| [PostgreSQL](postgres.sql) | ARRAY_AGG/STRING_AGG/FILTER/WITHIN GROUP，最丰富 |
| [SQLite](sqlite.sql) | GROUP_CONCAT，3.44+ JSON 聚合 |
| [Oracle](oracle.sql) | LISTAGG(11gR2+)，PERCENTILE_CONT/DISC |
| [SQL Server](sqlserver.sql) | STRING_AGG(2017+)，GROUPING SETS 完整 |
| [MariaDB](mariadb.sql) | GROUP_CONCAT，兼容 MySQL 聚合 |
| [Firebird](firebird.sql) | LIST() 聚合，标准聚合函数 |
| [IBM Db2](db2.sql) | LISTAGG，GROUPING SETS/CUBE/ROLLUP |
| [SAP HANA](saphana.sql) | STRING_AGG，聚合下推到列存 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | ARRAY_AGG/STRING_AGG/APPROX_ 近似族 |
| [Snowflake](snowflake.sql) | LISTAGG/ARRAY_AGG/APPROX_ 近似族 |
| [ClickHouse](clickhouse.sql) | groupArray/-If/-State 组合器，近似聚合丰富 |
| [Hive](hive.sql) | COLLECT_LIST/COLLECT_SET，UDAF 可扩展 |
| [Spark SQL](spark.sql) | COLLECT_LIST/COLLECT_SET，内建+UDF |
| [Flink SQL](flink.sql) | LISTAGG，增量聚合优化 |
| [StarRocks](starrocks.sql) | GROUP_CONCAT/PERCENTILE，Bitmap 聚合 |
| [Doris](doris.sql) | GROUP_CONCAT/BITMAP/HLL 聚合 |
| [Trino](trino.sql) | ARRAY_AGG/APPROX_ 近似族 |
| [DuckDB](duckdb.sql) | LIST_AGG/STRING_AGG，统计聚合丰富 |
| [MaxCompute](maxcompute.sql) | WM_CONCAT/COLLECT_LIST，UDAF 扩展 |
| [Hologres](hologres.sql) | PG 兼容聚合函数 |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | LISTAGG/APPROXIMATE COUNT(PG 兼容) |
| [Azure Synapse](synapse.sql) | STRING_AGG(T-SQL)，分布式聚合 |
| [Databricks SQL](databricks.sql) | COLLECT_LIST/COLLECT_SET + 近似聚合 |
| [Greenplum](greenplum.sql) | PG 兼容聚合，并行优化 |
| [Impala](impala.sql) | GROUP_CONCAT/APPX_MEDIAN 近似聚合 |
| [Vertica](vertica.sql) | LISTAGG，投影预聚合 |
| [Teradata](teradata.sql) | 标准聚合 + TD_ANALYZE 统计 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 GROUP_CONCAT |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式聚合 |
| [CockroachDB](cockroachdb.sql) | PG 兼容 ARRAY_AGG/STRING_AGG |
| [Spanner](spanner.sql) | ARRAY_AGG/STRING_AGG，标准聚合 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容聚合函数 |
| [PolarDB](polardb.sql) | MySQL 兼容聚合函数 |
| [openGauss](opengauss.sql) | PG 兼容聚合函数 |
| [TDSQL](tdsql.sql) | MySQL 兼容聚合函数 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | LISTAGG(Oracle 兼容) |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 聚合 + time_bucket 配合 |
| [TDengine](tdengine.sql) | 内建 APERTURE/SPREAD/TWA 等时序聚合 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | COLLECT_LIST/TOPK，流式增量聚合 |
| [Materialize](materialize.sql) | PG 兼容聚合，增量维护 |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | LISTAGG/ARRAY_AGG 支持 |
| [Derby](derby.sql) | 基础聚合函数(COUNT/SUM/AVG/MIN/MAX) |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 聚合 / SQL:2003 FILTER |

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
