# 连接查询 (JOIN)

各数据库 JOIN 语法对比，包括 INNER、LEFT、RIGHT、FULL、CROSS、LATERAL JOIN 等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | INNER/LEFT/RIGHT/CROSS JOIN，8.0 无 FULL JOIN |
| [PostgreSQL](postgres.sql) | 全 JOIN 类型 + LATERAL JOIN，完整支持 |
| [SQLite](sqlite.sql) | INNER/LEFT/CROSS JOIN，无 RIGHT/FULL |
| [Oracle](oracle.sql) | 全 JOIN 类型，(+) 旧语法，LATERAL(12c+) |
| [SQL Server](sqlserver.sql) | 全 JOIN 类型，CROSS/OUTER APPLY |
| [MariaDB](mariadb.sql) | 兼容 MySQL JOIN，10.3+ 部分增强 |
| [Firebird](firebird.sql) | 全 JOIN 类型，标准 SQL 风格 |
| [IBM Db2](db2.sql) | 全 JOIN 类型 + LATERAL 支持 |
| [SAP HANA](saphana.sql) | 全 JOIN 类型，列存优化 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | 全 JOIN 类型 + UNNEST 数组展开 JOIN |
| [Snowflake](snowflake.sql) | 全 JOIN 类型 + LATERAL FLATTEN |
| [ClickHouse](clickhouse.sql) | 全 JOIN 类型，分布式 JOIN 需注意内存 |
| [Hive](hive.sql) | 支持 FULL JOIN，MapReduce 实现 |
| [Spark SQL](spark.sql) | 全 JOIN 类型，Broadcast/Sort-Merge/Shuffle |
| [Flink SQL](flink.sql) | 流式 JOIN(Regular/Temporal/Interval/Lookup) |
| [StarRocks](starrocks.sql) | 全 JOIN 类型，Broadcast/Shuffle 策略 |
| [Doris](doris.sql) | 全 JOIN 类型，Broadcast/Shuffle 策略 |
| [Trino](trino.sql) | 全 JOIN 类型 + UNNEST 支持 |
| [DuckDB](duckdb.sql) | 全 JOIN 类型 + LATERAL/ASOF JOIN |
| [MaxCompute](maxcompute.sql) | 全 JOIN 类型，MapJoin 提示 |
| [Hologres](hologres.sql) | PG 兼容 JOIN |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | 全 JOIN 类型，分布键优化 |
| [Azure Synapse](synapse.sql) | 全 JOIN 类型，分布式执行 |
| [Databricks SQL](databricks.sql) | 全 JOIN 类型，自适应执行 |
| [Greenplum](greenplum.sql) | PG 兼容 JOIN，分布键 co-locate |
| [Impala](impala.sql) | 全 JOIN 类型，Broadcast/Shuffle |
| [Vertica](vertica.sql) | 全 JOIN 类型，投影优化 |
| [Teradata](teradata.sql) | 全 JOIN 类型，Hash/Merge/Product Join |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 JOIN，Index/Hash Join |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式 JOIN |
| [CockroachDB](cockroachdb.sql) | PG 兼容 JOIN，分布式执行 |
| [Spanner](spanner.sql) | 全 JOIN 类型，分布式 JOIN |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 JOIN |
| [PolarDB](polardb.sql) | MySQL 兼容 JOIN，并行执行 |
| [openGauss](opengauss.sql) | PG 兼容 JOIN |
| [TDSQL](tdsql.sql) | MySQL 兼容，跨分片 JOIN |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容 JOIN |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG JOIN，超表透明 |
| [TDengine](tdengine.sql) | 有限 JOIN，仅子表间 JOIN |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 流-流/流-表 JOIN，时间窗口约束 |
| [Materialize](materialize.sql) | PG 兼容 JOIN，增量维护 |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 全 JOIN 类型支持 |
| [Derby](derby.sql) | 全 JOIN 类型支持 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:1992 JOIN / SQL:2003 LATERAL |

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

## 引擎开发者视角

**核心设计决策**：JOIN 是查询处理最复杂的部分。实现哪些 JOIN 算法、优化器如何选择 JOIN 顺序和算法，直接决定了引擎处理复杂查询的能力。

**实现建议**：
- 三大 JOIN 算法必须全部实现：Nested Loop（小表/有索引时最优）、Hash Join（等值 JOIN 的通用选择）、Sort-Merge Join（已排序数据或不等值 JOIN）。只实现 Nested Loop 的引擎在大表 JOIN 时完全不可用
- JOIN 顺序优化是 NP-hard 问题：小于 10 个表时可以穷举，超过时需要启发式算法（如 PostgreSQL 的 GEQO——遗传算法）或动态规划剪枝。这是查询优化器中最复杂的模块之一
- FULL OUTER JOIN 的实现比 LEFT/RIGHT JOIN 复杂得多——MySQL/MariaDB 至今不支持证明了这一点。推荐实现方式：LEFT JOIN + ANTI JOIN（找出右表中未匹配的行）
- LATERAL JOIN 是现代 SQL 的重要特性——允许子查询引用同级 FROM 子句中的列。实现上相当于对外层每一行执行一次参数化子查询
- 分布式 JOIN 的数据移动策略至关重要：Broadcast（小表广播到所有节点）vs Shuffle（按 JOIN 键重新分布两个表）vs Co-located（数据已按 JOIN 键分布时无需移动）。优化器必须根据表大小自动选择策略
- 常见错误：JOIN 条件中的隐式类型转换导致无法使用索引。如果 JOIN 列类型不同（如 INT JOIN VARCHAR），引擎应发出警告而非静默做类型转换
