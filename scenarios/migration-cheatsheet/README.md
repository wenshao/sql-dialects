# 迁移速查 (MIGRATION CHEATSHEET)

各数据库之间迁移的语法速查表与注意事项。

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
| **迁入难点** | 动态类型接受任何数据，迁入容易但类型信息丢失 | 需要设计排序键/引擎/分区策略，与 RDBMS 建表差异大 | 无索引/无 GRANT 需重新思考数据建模和安全策略 | 各方言间 SQL 语法和类型映射是主要工作 |
| **迁出难点** | 动态类型数据可能包含混合类型值，迁出时需类型清洗 | INSERT-only 数据可能有未合并的重复行 | IAM 权限无法直接映射到 SQL GRANT | 函数名/日期格式/事务行为是迁移高频问题 |
| **权限迁移** | 无权限系统，迁移时需从零建立权限 | GRANT/REVOKE 可映射到目标系统 | IAM 角色需转换为 SQL 权限或目标系统的权限模型 | GRANT/REVOKE 可跨方言映射（语法差异小） |
| **约束迁移** | 约束语法简单，迁移到其他 DB 需增加约束 | 无约束可迁移（目标系统需新建约束） | 信息性约束迁出时需在目标系统设为强制执行 | 约束定义可跨方言迁移（语法有差异） |

## 引擎开发者视角

**核心设计决策**：方言兼容性是新引擎获取用户的最快路径。选择兼容哪个方言（MySQL/PostgreSQL/SQL 标准）决定了可以争取的用户群体和迁移成本。

**实现建议**：
- 方言兼容性推荐分层实现：核心层遵循 SQL 标准，兼容层提供方言特有语法的映射。TiDB（兼容 MySQL）和 CockroachDB（兼容 PostgreSQL）的策略都证明了方言兼容的价值
- 类型映射是迁移的第一道坎：建立完整的类型对照表（如 MySQL TINYINT -> INT8，Oracle NUMBER(10,2) -> DECIMAL(10,2)），并提供自动迁移工具
- 函数兼容的优先级：日期函数 > 字符串函数 > 类型转换 > 聚合函数。日期函数是差异最大的领域（DATE_ADD vs INTERVAL vs DATEADD），也是迁移工作量最大的部分
- 隐式行为差异是最危险的迁移风险——整数除法（5/2 返回 2 还是 2.5）、NULL 排序（NULLS FIRST 还是 NULLS LAST）、空字符串与 NULL 的关系等。引擎应提供兼容模式参数来切换这些行为
- 提供 SQL 方言检查工具（lint/validator）帮助用户发现迁移中的不兼容语法——比运行时报错更友好
- 常见错误：只兼容了语法但忽略了语义差异。例如 GROUP BY 中引用 SELECT 别名（MySQL 允许，PostgreSQL 不允许）——语法层面都能解析但语义不同时最容易被忽略
