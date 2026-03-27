# 日期序列填充 (DATE SERIES FILL)

各数据库日期序列填充最佳实践，包括生成连续日期并填充缺失数据。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | 递归 CTE(8.0+) 或变量生成日期序列 |
| [PostgreSQL](postgres.sql) | generate_series() 原生日期序列 |
| [SQLite](sqlite.sql) | 递归 CTE 生成，3.8.3+ 支持 |
| [Oracle](oracle.sql) | CONNECT BY LEVEL 或递归 CTE 生成 |
| [SQL Server](sqlserver.sql) | 递归 CTE 或数字表交叉连接 |
| [MariaDB](mariadb.sql) | seq_1_to_N 序列引擎(10.0+) |
| [Firebird](firebird.sql) | 递归 CTE 生成日期范围 |
| [IBM Db2](db2.sql) | 递归 CTE 生成日期序列 |
| [SAP HANA](saphana.sql) | SERIES_GENERATE_DATE() 原生序列 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | GENERATE_DATE_ARRAY() 原生函数 |
| [Snowflake](snowflake.sql) | GENERATOR() + ROW_NUMBER 生成 |
| [ClickHouse](clickhouse.sql) | range() + arrayJoin() 或数字表 |
| [Hive](hive.sql) | posexplode(split()) 模拟序列 |
| [Spark SQL](spark.sql) | sequence() + explode() 生成 |
| [Flink SQL](flink.sql) | 无原生序列，用 UDTF 或 Lookup |
| [StarRocks](starrocks.sql) | 无 generate_series，递归 CTE 或表 |
| [Doris](doris.sql) | 无 generate_series，递归 CTE 或表 |
| [Trino](trino.sql) | sequence() + UNNEST 生成 |
| [DuckDB](duckdb.sql) | generate_series() 原生支持 |
| [MaxCompute](maxcompute.sql) | UDTF 或日期维表补齐 |
| [Hologres](hologres.sql) | generate_series()(PG 兼容) |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | 递归 CTE 或日期维表 |
| [Azure Synapse](synapse.sql) | 递归 CTE 生成 |
| [Databricks SQL](databricks.sql) | sequence() + explode() 生成 |
| [Greenplum](greenplum.sql) | generate_series()(PG 兼容) |
| [Impala](impala.sql) | 无原生序列，日期维表补齐 |
| [Vertica](vertica.sql) | TIMESERIES 子句原生支持 |
| [Teradata](teradata.sql) | sys_calendar.calendar 系统日历表 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | 递归 CTE(5.1+) 或日期维表 |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 模式递归 CTE |
| [CockroachDB](cockroachdb.sql) | generate_series()(PG 兼容) |
| [Spanner](spanner.sql) | GENERATE_DATE_ARRAY() 原生函数 |
| [YugabyteDB](yugabytedb.sql) | generate_series()(PG 兼容) |
| [PolarDB](polardb.sql) | MySQL 兼容递归 CTE |
| [openGauss](opengauss.sql) | generate_series()(PG 兼容) |
| [TDSQL](tdsql.sql) | MySQL 兼容递归 CTE |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容 CONNECT BY 或递归 CTE |
| [KingbaseES](kingbase.sql) | PG 兼容 generate_series() |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | time_bucket_gapfill() 原生补齐 |
| [TDengine](tdengine.sql) | FILL() 原生时序补齐(PREV/LINEAR/NULL) |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 不适用(流式处理) |
| [Materialize](materialize.sql) | generate_series()(PG 兼容) |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | SYSTEM_RANGE() 生成序列 |
| [Derby](derby.sql) | 递归 CTE(10.14+) |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 递归 CTE 可模拟序列 |

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **序列生成** | 递归 CTE 生成日期序列（3.8.3+） | numbers() 函数 + toDate() 生成日期序列 | GENERATE_DATE_ARRAY + UNNEST 生成（最简洁） | PG generate_series 最优雅 / MySQL 递归 CTE / Oracle CONNECT BY |
| **日期类型** | 无原生 DATE，日期存为 TEXT | Date/DateTime 原生类型 | DATE 原生类型 | 各方言有原生日期类型 |
| **LEFT JOIN 填充** | 标准 LEFT JOIN 方案 | 标准 LEFT JOIN | 标准 LEFT JOIN | 标准方案 |
| **COALESCE 填 0** | COALESCE(val, 0) 填充缺失值 | COALESCE 或 ifNull() | COALESCE 或 IFNULL() | 各方言均支持 COALESCE |

## 引擎开发者视角

**核心设计决策**：日期序列生成是时序分析的基础操作。引擎是否提供内置的序列生成函数（如 generate_series）直接影响此场景的用户体验。

**实现建议**：
- 表值函数 generate_series(start, end, step) 是最优雅的日期序列生成方案（PostgreSQL）。实现为流式迭代器而非物化全部值——避免大范围序列的内存消耗
- ClickHouse 的 numbers() 函数 + toDate() 组合是列式引擎的优秀替代方案——numbers(N) 生成 0 到 N-1 的整数序列，结合日期函数转换
- 如果不提供内置序列生成器，递归 CTE 是用户的后备方案。引擎应确保递归 CTE 能高效处理数万次迭代（日期序列通常有数千到数万行）
- GENERATE_DATE_ARRAY + UNNEST（BigQuery）模式将序列生成和展开分离——这种函数式设计在列式引擎中更自然
- LEFT JOIN + COALESCE 填充缺失值的模式应被优化器高效处理——这是日期填充的标准 SQL 模式
- 常见错误：日期序列生成未考虑时区和夏令时——跨越夏令时切换的日期序列在加减小时时可能产生意外结果。引擎的 INTERVAL 运算应正确处理时区转换
