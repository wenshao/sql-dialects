# 连接查询 (JOIN)

各数据库 JOIN 语法对比，包括 INNER、LEFT、RIGHT、FULL、CROSS、LATERAL JOIN 等。

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

1. **FULL OUTER JOIN**：MySQL/MariaDB 不支持，需要用 LEFT JOIN UNION RIGHT JOIN 模拟
2. **LATERAL JOIN**：PostgreSQL 9.3+ 和 MySQL 8.0.14+ 支持，Oracle 12c+ 用 CROSS APPLY/OUTER APPLY，SQL Server 用 CROSS/OUTER APPLY
3. **NATURAL JOIN**：所有方言语法相同但生产环境不推荐使用（列名变化会悄悄改变语义）
4. **旧式 JOIN 语法**：Oracle 的 `(+)` 语法和 WHERE 中的隐式 JOIN 仍在旧代码中常见，新代码应使用显式 JOIN ... ON
5. **分布式 JOIN 性能**：大数据引擎中 JOIN 可能触发数据 shuffle，Hive/Spark 的 Map-side JOIN（broadcast）和 Sort-Merge JOIN 对性能影响巨大

## 选型建议

优先使用 INNER JOIN 和 LEFT JOIN，覆盖 90% 以上的业务场景。CROSS JOIN 用于生成笛卡尔积（如日期序列 x 维度）。大数据场景下 JOIN 小表时使用 broadcast hint 避免 shuffle。LATERAL JOIN 适合"每行对应 Top-N"的需求。

## 版本演进

- MySQL 8.0.14+：支持 LATERAL 派生表
- PostgreSQL 9.3+：引入 LATERAL JOIN
- Hive 0.13+：支持隐式 JOIN 语法的 CROSS JOIN
- ClickHouse：引入多种 JOIN 算法（hash/partial_merge/parallel_hash）可通过设置调优

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **JOIN 类型** | INNER/LEFT/CROSS JOIN 完整支持，3.39.0+ 支持 RIGHT/FULL OUTER JOIN | 支持所有 JOIN 类型，有独特的 JOIN 算法选择（hash/partial_merge 等） | 完整支持所有 JOIN 类型 | 均支持（MySQL 不支持 FULL OUTER JOIN） |
| **LATERAL JOIN** | 不支持 | 不支持传统 LATERAL，但有 arrayJoin 等替代 | 支持 | PG 9.3+/MySQL 8.0.14+ 支持 |
| **JOIN 性能** | 嵌套循环为主，适合小数据集 | JOIN 可能触发数据 shuffle，提供 JOIN 算法提示优化 | Serverless 自动优化，大表 JOIN 按扫描量计费 | 优化器选择 nested loop/hash/merge join |
| **JOIN 哲学** | 传统关系型 JOIN | 列式存储偏好宽表，JOIN 代价较高，推荐预 JOIN 写入 | 按扫描数据量计费，JOIN 大表成本高 | JOIN 是核心操作，优化器高度成熟 |
| **存储模型影响** | 行存储，JOIN 操作自然 | 列存储 + 分布式，JOIN 需要网络传输和内存 | 列存储 + Serverless，按扫描量计费影响 JOIN 策略 | 行存储，JOIN 依赖索引高效执行 |
