# 区间缺失检测 (GAP DETECTION)

各数据库区间缺失检测最佳实践，包括连续序列断点、时间间隔检测等。

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
