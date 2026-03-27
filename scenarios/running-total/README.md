# 累计求和 (RUNNING TOTAL)

各数据库累计求和最佳实践，包括窗口函数 SUM() OVER() 等方案。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | SUM() OVER(8.0+) 或变量累加(旧版) |
| [PostgreSQL](postgres.sql) | SUM() OVER 完整窗口帧控制 |
| [SQLite](sqlite.sql) | SUM() OVER(3.25+) 窗口函数 |
| [Oracle](oracle.sql) | SUM() OVER 最早支持，分析函数 |
| [SQL Server](sqlserver.sql) | SUM() OVER(2012+ ROWS 帧优化) |
| [MariaDB](mariadb.sql) | SUM() OVER(10.2+)，兼容 MySQL |
| [Firebird](firebird.sql) | SUM() OVER(3.0+) 窗口函数 |
| [IBM Db2](db2.sql) | SUM() OVER 完整支持 |
| [SAP HANA](saphana.sql) | SUM() OVER 内存加速 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | SUM() OVER 完整窗口帧 |
| [Snowflake](snowflake.sql) | SUM() OVER 完整窗口帧 |
| [ClickHouse](clickhouse.sql) | runningAccumulate()/SUM() OVER 支持 |
| [Hive](hive.sql) | SUM() OVER(0.11+) 窗口函数 |
| [Spark SQL](spark.sql) | SUM() OVER 完整支持 |
| [Flink SQL](flink.sql) | SUM() OVER 流式累计(Over Window) |
| [StarRocks](starrocks.sql) | SUM() OVER 完整支持 |
| [Doris](doris.sql) | SUM() OVER 完整支持 |
| [Trino](trino.sql) | SUM() OVER 完整支持 |
| [DuckDB](duckdb.sql) | SUM() OVER 完整支持 |
| [MaxCompute](maxcompute.sql) | SUM() OVER 完整支持 |
| [Hologres](hologres.sql) | SUM() OVER(PG 兼容) |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | SUM() OVER 完整支持 |
| [Azure Synapse](synapse.sql) | SUM() OVER(T-SQL 兼容) |
| [Databricks SQL](databricks.sql) | SUM() OVER 完整支持 |
| [Greenplum](greenplum.sql) | PG 兼容 SUM() OVER |
| [Impala](impala.sql) | SUM() OVER 完整支持 |
| [Vertica](vertica.sql) | SUM() OVER 分析优化 |
| [Teradata](teradata.sql) | SUM() OVER + QUALIFY 过滤 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 SUM() OVER |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 模式 SUM() OVER |
| [CockroachDB](cockroachdb.sql) | PG 兼容 SUM() OVER |
| [Spanner](spanner.sql) | SUM() OVER 完整支持 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 SUM() OVER |
| [PolarDB](polardb.sql) | MySQL 兼容 SUM() OVER |
| [openGauss](opengauss.sql) | PG 兼容 SUM() OVER |
| [TDSQL](tdsql.sql) | MySQL 兼容 SUM() OVER |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容 SUM() OVER |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG SUM() OVER，时序累计 |
| [TDengine](tdengine.sql) | CSUM() 内建累计函数 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 不支持(流式用状态存储累计) |
| [Materialize](materialize.sql) | SUM() OVER(PG 兼容) |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | SUM() OVER 支持 |
| [Derby](derby.sql) | 有限窗口函数，自连接模拟 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 窗口聚合 SUM() OVER 规范 |

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
