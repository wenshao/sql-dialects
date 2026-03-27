# 视图 (VIEWS)

各数据库视图语法对比，包括普通视图和物化视图的创建与管理。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | 普通视图 + 算法(MERGE/TEMPTABLE)，无物化视图 |
| [PostgreSQL](postgres.sql) | 普通/物化视图，REFRESH CONCURRENTLY |
| [SQLite](sqlite.sql) | 只读视图，无物化视图 |
| [Oracle](oracle.sql) | 普通/物化视图，FAST REFRESH，ON COMMIT |
| [SQL Server](sqlserver.sql) | 普通/索引视图(物化)，SCHEMABINDING |
| [MariaDB](mariadb.sql) | 兼容 MySQL 视图，无物化视图 |
| [Firebird](firebird.sql) | 普通视图，无物化视图 |
| [IBM Db2](db2.sql) | MQT(物化查询表)，自动/手动刷新 |
| [SAP HANA](saphana.sql) | 普通/JOIN/OLAP Calculation View |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | 普通/物化视图，自动刷新 |
| [Snowflake](snowflake.sql) | 普通/物化/安全视图(Secure View) |
| [ClickHouse](clickhouse.sql) | 普通视图 + MATERIALIZED VIEW(实时增量) |
| [Hive](hive.sql) | 普通视图 + 物化视图(3.0+) |
| [Spark SQL](spark.sql) | 临时/全局临时视图，无物化视图 |
| [Flink SQL](flink.sql) | 临时视图，无物化视图 |
| [StarRocks](starrocks.sql) | 异步物化视图，自动查询改写 |
| [Doris](doris.sql) | 同步/异步物化视图，自动改写 |
| [Trino](trino.sql) | 普通视图，物化视图依赖 Connector |
| [DuckDB](duckdb.sql) | 普通视图，无物化视图 |
| [MaxCompute](maxcompute.sql) | 普通视图 + 物化视图 |
| [Hologres](hologres.sql) | 无物化视图，外部表视图 |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | 普通/物化视图(自动刷新) |
| [Azure Synapse](synapse.sql) | 普通/物化视图，自动维护 |
| [Databricks SQL](databricks.sql) | Streaming 物化视图(DLT) |
| [Greenplum](greenplum.sql) | PG 兼容视图 |
| [Impala](impala.sql) | 普通视图，无物化视图 |
| [Vertica](vertica.sql) | Live Aggregate Projection 替代物化视图 |
| [Teradata](teradata.sql) | JOIN INDEX 实现物化视图 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容视图，无物化视图 |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式视图 |
| [CockroachDB](cockroachdb.sql) | PG 兼容视图，物化视图(23.1+) |
| [Spanner](spanner.sql) | 普通视图，无物化视图 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容，物化视图支持 |
| [PolarDB](polardb.sql) | MySQL 兼容视图 |
| [openGauss](opengauss.sql) | PG 兼容，物化视图支持 |
| [TDSQL](tdsql.sql) | MySQL 兼容视图 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容，物化视图支持 |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 连续聚合(Continuous Aggregate)自动刷新 |
| [TDengine](tdengine.sql) | 不支持视图 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 持久化查询 = 物化视图 |
| [Materialize](materialize.sql) | 核心即增量物化视图，毫秒级刷新 |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 标准视图支持 |
| [Derby](derby.sql) | 标准视图支持 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 VIEW + SQL:2008 物化视图参考 |

## 核心差异

1. **物化视图**：PostgreSQL/Oracle/SQL Server 支持完整的物化视图，MySQL 不原生支持（需要手动维护），BigQuery/Snowflake 支持自动刷新的物化视图
2. **可更新视图**：MySQL/PostgreSQL/Oracle 支持对简单视图执行 INSERT/UPDATE/DELETE，但条件严格（不能有 JOIN、GROUP BY 等）
3. **WITH CHECK OPTION**：防止通过视图插入不满足视图 WHERE 条件的数据，多数 RDBMS 支持但语义有细微差异
4. **递归视图**：SQL 标准定义了 `CREATE RECURSIVE VIEW`，但大多数方言用视图 + 递归 CTE 实现
5. **物化视图刷新**：Oracle 支持增量刷新（FAST REFRESH），PostgreSQL 只支持全量刷新（REFRESH MATERIALIZED VIEW），BigQuery 自动增量刷新

## 选型建议

普通视图适合封装复杂查询、实现权限隔离。物化视图适合加速慢查询，但需要考虑数据新鲜度和刷新成本。在 MySQL 中可以用定时任务 + 物理表模拟物化视图。在分析型引擎中物化视图常用于预聚合加速。

## 版本演进

- PostgreSQL 9.3+：引入物化视图，9.4+ 支持 CONCURRENTLY 刷新不阻塞查询
- MySQL 8.0：视图功能与 5.7 基本一致，仍无原生物化视图
- ClickHouse：物化视图是触发式的，INSERT 时自动增量更新到目标表

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **普通视图** | 支持 CREATE VIEW | 支持 CREATE VIEW | 支持 CREATE VIEW | 均支持 |
| **物化视图** | 不支持 | 支持且独特：INSERT 触发式增量更新到目标表 | 支持自动增量刷新的物化视图 | PG/Oracle 支持，MySQL 不原生支持 |
| **可更新视图** | 简单视图支持 INSERT/UPDATE/DELETE | 视图只读 | 视图只读 | MySQL/PG/Oracle 简单视图可更新 |
| **WITH CHECK OPTION** | 不支持 | 不支持 | 不支持 | MySQL/PG/Oracle/SQL Server 支持 |
| **视图性能** | 视图展开为子查询执行，无额外优化 | 物化视图用于预聚合加速，普通视图无特殊优化 | 物化视图可显著降低查询成本和延迟 | PG 物化视图可手动 REFRESH |
| **权限控制** | 无权限系统，视图不提供安全隔离 | 可通过 GRANT 控制视图访问 | 通过 IAM 控制视图的 dataset 级访问 | 视图是实现列级/行级安全的常用手段 |

## 引擎开发者视角

**核心设计决策**：视图的实现深度从简单的查询替换到复杂的物化视图增量刷新，跨越巨大的复杂度范围。需要决定：是否支持可更新视图、是否实现物化视图、物化视图的刷新策略。

**实现建议**：
- 普通视图的最低实现是查询替换（view expansion）——在解析阶段将视图引用替换为其定义查询。这很简单但要注意：视图展开后的优化应与直接写子查询等价，不能因为视图边界阻碍优化器
- 物化视图是高价值特性，有三种刷新策略：全量刷新（REFRESH MATERIALIZED VIEW，最简单）、增量刷新（只处理变更数据，Oracle 的 FAST REFRESH）、触发式刷新（ClickHouse 的方式，INSERT 时自动更新目标表）。新引擎推荐先实现全量刷新，再逐步支持增量
- CONCURRENTLY 刷新（PostgreSQL 9.4+）允许在刷新期间查询旧版本数据，对高可用场景至关重要——实现方式是维护两份数据然后原子切换
- 可更新视图的规则复杂：只有满足特定条件（单表、无聚合、无 DISTINCT 等）的简单视图才能更新。WITH CHECK OPTION 增加了额外的检查逻辑
- CREATE OR REPLACE VIEW 应从第一天就支持——修改视图定义不应该需要先 DROP 再 CREATE（会丢失依赖和权限）
- 常见错误：视图的列数量或类型在基表修改后不自动更新（PostgreSQL 的行为），或自动更新但破坏了依赖视图（级联失效）。两种策略各有利弊，需要明确文档化
