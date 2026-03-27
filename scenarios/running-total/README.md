# 累计求和 (RUNNING TOTAL)

各数据库累计求和最佳实践，包括窗口函数 SUM() OVER() 等方案。

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
| **窗口函数方案** | 3.25.0+ 支持 SUM() OVER (ORDER BY ...) | 支持 SUM() OVER 累计窗口 | 完整支持 | PG 8.4+/MySQL 8.0+/Oracle 8i+ |
| **无窗口替代** | 旧版本需自连接或子查询模拟 | 通常有窗口函数 | 通常有窗口函数 | MySQL 5.7 需变量累加 |
| **窗口帧控制** | 支持 ROWS/RANGE BETWEEN | 支持基本窗口帧 | 支持完整窗口帧 | PG 11+ 支持 GROUPS 帧 |
| **性能** | 小数据量足够 | 列式存储大数据聚合高效 | Serverless 弹性处理 | 索引有序可加速 |

## 引擎开发者视角

**核心设计决策**：累计求和（running total）是窗口函数的经典应用。引擎对窗口帧（ROWS vs RANGE）的实现正确性和性能直接影响此场景。

**实现建议**：
- SUM() OVER (ORDER BY date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) 是累计求和的标准写法。引擎必须支持流式计算——逐行累加而非对每行都重新计算从起始到当前的总和
- RANGE 帧与 ROWS 帧的区别在累计求和场景中尤其重要：RANGE 帧下，ORDER BY 值相同的行会得到相同的累计值（因为它们在逻辑上属于同一个"位置"）。这常常不是用户期望的行为——引擎应在文档中明确说明
- 移动平均（`AVG() OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)`——7 日移动平均）是累计求和的变体。窗口帧的边界计算必须正确处理窗口开头不足 N 行的情况
- 分组累计（PARTITION BY group ORDER BY date）的实现需要在分组边界重置累加器——确保切换到新分组时状态正确归零
- 对于列式引擎，窗口函数的排序是主要开销。如果数据已按排序键有序（如 ClickHouse 的 ORDER BY 表属性），应跳过额外排序
- 常见错误：浮点数累计求和的精度损失。大量浮点数相加会累积舍入误差——对金融数据应使用 DECIMAL 类型而非 FLOAT/DOUBLE。引擎的窗口聚合中间结果也应使用高精度类型
