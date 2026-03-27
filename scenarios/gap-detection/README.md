# 区间缺失检测 (GAP DETECTION)

各数据库区间缺失检测最佳实践，包括连续序列断点、时间间隔检测等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | LAG/LEAD(8.0+) 或自连接检测间隙 |
| [PostgreSQL](postgres.sql) | generate_series + LEFT JOIN 或窗口函数 |
| [SQLite](sqlite.sql) | 窗口函数(3.25+) 或自连接 |
| [Oracle](oracle.sql) | LAG/LEAD/CONNECT BY 检测间隙 |
| [SQL Server](sqlserver.sql) | LAG/LEAD + CTE 检测间隙 |
| [MariaDB](mariadb.sql) | seq 引擎 + LEFT JOIN(10.0+) |
| [Firebird](firebird.sql) | 窗口函数(3.0+) 检测间隙 |
| [IBM Db2](db2.sql) | LAG/LEAD 窗口函数检测 |
| [SAP HANA](saphana.sql) | LAG/LEAD 窗口函数检测 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | LAG/LEAD + GENERATE_ARRAY |
| [Snowflake](snowflake.sql) | LAG/LEAD + GENERATOR 序列 |
| [ClickHouse](clickhouse.sql) | neighbor() 函数替代 LAG/LEAD |
| [Hive](hive.sql) | LAG/LEAD 窗口函数检测 |
| [Spark SQL](spark.sql) | LAG/LEAD + sequence/explode |
| [Flink SQL](flink.sql) | LAG/LEAD 流式间隙检测 |
| [StarRocks](starrocks.sql) | LAG/LEAD 窗口函数检测 |
| [Doris](doris.sql) | LAG/LEAD 窗口函数检测 |
| [Trino](trino.sql) | LAG/LEAD + sequence/UNNEST |
| [DuckDB](duckdb.sql) | LAG/LEAD + generate_series |
| [MaxCompute](maxcompute.sql) | LAG/LEAD 窗口函数检测 |
| [Hologres](hologres.sql) | LAG/LEAD(PG 兼容) |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | LAG/LEAD 窗口函数检测 |
| [Azure Synapse](synapse.sql) | LAG/LEAD 窗口函数检测 |
| [Databricks SQL](databricks.sql) | LAG/LEAD + sequence 检测 |
| [Greenplum](greenplum.sql) | PG 兼容 generate_series + JOIN |
| [Impala](impala.sql) | LAG/LEAD 窗口函数检测 |
| [Vertica](vertica.sql) | TIMESERIES 原生间隙填充 |
| [Teradata](teradata.sql) | QUALIFY + LAG/LEAD 检测 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 LAG/LEAD |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 模式窗口函数 |
| [CockroachDB](cockroachdb.sql) | PG 兼容 generate_series + JOIN |
| [Spanner](spanner.sql) | LAG/LEAD + GENERATE_DATE_ARRAY |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 generate_series |
| [PolarDB](polardb.sql) | MySQL 兼容 LAG/LEAD |
| [openGauss](opengauss.sql) | PG 兼容 generate_series + JOIN |
| [TDSQL](tdsql.sql) | MySQL 兼容 LAG/LEAD |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容 LAG/LEAD |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | time_bucket_gapfill() 直接检测 |
| [TDengine](tdengine.sql) | FILL() 自动检测并填充间隙 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 不适用(流式连续处理) |
| [Materialize](materialize.sql) | LAG/LEAD(PG 兼容) |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | LAG/LEAD 窗口函数检测 |
| [Derby](derby.sql) | 自连接检测(窗口函数有限) |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 LAG/LEAD 规范 |

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **LAG/LEAD 方案** | 3.25.0+ 支持 LAG/LEAD 窗口函数 | 支持 LAG/LEAD | 完整支持 LAG/LEAD | PG/Oracle/MySQL 8.0+ 支持 |
| **序列生成** | 递归 CTE 生成连续序列 | numbers() 函数生成数字序列 | GENERATE_ARRAY + UNNEST | PG generate_series / MySQL 递归 CTE |
| **LEFT JOIN 检测** | 标准 LEFT JOIN 方案 | 支持但 JOIN 可能触发 shuffle | 支持，按扫描量计费 | 标准方案 |
| **性能** | 小数据集足够 | 列式存储大范围扫描高效 | 大范围扫描成本需关注 | 索引辅助提升效率 |

## 引擎开发者视角

**核心设计决策**：区间缺失检测依赖窗口函数（LAG/LEAD）或序列生成+LEFT JOIN 两种方案。引擎对这两种模式的优化能力决定了检测效率。

**实现建议**：
- LAG/LEAD 方案（比较相邻行的差值）是最高效的——只需一次排序遍历即可发现所有断点。引擎应确保 LAG/LEAD 的流式执行（逐行计算，不物化整个窗口）
- 序列生成+LEFT JOIN 方案（生成完整序列再与实际数据 JOIN 找缺失值）更直观但内存消耗大。对于数值范围很大但实际数据稀疏的场景，这种方案不可行
- 优化器应能识别 `WHERE next_val - current_val > 1` 这种窗口函数结果上的过滤模式，并在窗口计算阶段就进行过滤而非先物化全部窗口结果再过滤
- 对于时序数据库，间隔检测是核心需求——可以考虑提供内置函数（如 TimescaleDB 的 time_bucket_gapfill）直接处理时间间隔填充
- generate_series 类函数对数值范围的 gap detection 非常有用——引擎应同时支持整数序列和日期序列生成
- 常见错误：LAG/LEAD 的默认值处理。第一行的 LAG 和最后一行的 LEAD 返回 NULL——间隔检测算法需要正确处理这些边界情况，引擎可以通过 LAG(val, 1, default_val) 的第三个参数简化用户代码
