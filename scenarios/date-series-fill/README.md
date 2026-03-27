# 日期序列填充 (DATE SERIES FILL)

各数据库日期序列填充最佳实践，包括生成连续日期并填充缺失数据。

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
