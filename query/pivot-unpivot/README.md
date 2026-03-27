# 行列转换 (PIVOT / UNPIVOT)

各数据库行列转换语法对比，包括 PIVOT、UNPIVOT 和条件聚合实现。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | 无 PIVOT，用 CASE+聚合模拟 |
| [PostgreSQL](postgres.sql) | tablefunc 扩展 crosstab()，无原生 PIVOT |
| [SQLite](sqlite.sql) | 无 PIVOT，CASE+聚合模拟 |
| [Oracle](oracle.sql) | PIVOT/UNPIVOT(11g+)原生支持 |
| [SQL Server](sqlserver.sql) | PIVOT/UNPIVOT(2005+)原生支持 |
| [MariaDB](mariadb.sql) | 无 PIVOT，CASE+聚合模拟 |
| [Firebird](firebird.sql) | 无 PIVOT，CASE+聚合模拟 |
| [IBM Db2](db2.sql) | DECODE+聚合，无原生 PIVOT |
| [SAP HANA](saphana.sql) | 无原生 PIVOT，用 MAP_MERGE 等函数 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | PIVOT/UNPIVOT(2021+)原生支持 |
| [Snowflake](snowflake.sql) | PIVOT/UNPIVOT 原生支持 |
| [ClickHouse](clickhouse.sql) | 无 PIVOT，用 CASE+聚合或 Map |
| [Hive](hive.sql) | 无 PIVOT，CASE+聚合模拟 |
| [Spark SQL](spark.sql) | DataFrame pivot()，SQL PIVOT(3.4+) |
| [Flink SQL](flink.sql) | 无 PIVOT 语法 |
| [StarRocks](starrocks.sql) | 无 PIVOT，CASE+聚合模拟 |
| [Doris](doris.sql) | 无 PIVOT，CASE+聚合模拟 |
| [Trino](trino.sql) | 无 PIVOT，CASE+聚合模拟 |
| [DuckDB](duckdb.sql) | PIVOT/UNPIVOT 原生支持 |
| [MaxCompute](maxcompute.sql) | 无 PIVOT，CASE+聚合模拟 |
| [Hologres](hologres.sql) | 无 PIVOT，CASE+聚合模拟 |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | 无 PIVOT，CASE+聚合模拟 |
| [Azure Synapse](synapse.sql) | 无原生 PIVOT(T-SQL PIVOT 有限) |
| [Databricks SQL](databricks.sql) | PIVOT 原生支持 |
| [Greenplum](greenplum.sql) | crosstab()(PG tablefunc) |
| [Impala](impala.sql) | 无 PIVOT，CASE+聚合模拟 |
| [Vertica](vertica.sql) | 无 PIVOT，CASE+聚合模拟 |
| [Teradata](teradata.sql) | 无原生 PIVOT，用 CASE+聚合 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | 无 PIVOT，CASE+聚合模拟 |
| [OceanBase](oceanbase.sql) | Oracle 模式 PIVOT 支持 |
| [CockroachDB](cockroachdb.sql) | 无 PIVOT，CASE+聚合模拟 |
| [Spanner](spanner.sql) | 无 PIVOT，CASE+聚合模拟 |
| [YugabyteDB](yugabytedb.sql) | 无 PIVOT，tablefunc 扩展 |
| [PolarDB](polardb.sql) | 无 PIVOT，CASE+聚合模拟 |
| [openGauss](opengauss.sql) | tablefunc 扩展 |
| [TDSQL](tdsql.sql) | 无 PIVOT，CASE+聚合模拟 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容 PIVOT/UNPIVOT |
| [KingbaseES](kingbase.sql) | PG 兼容 tablefunc |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG tablefunc |
| [TDengine](tdengine.sql) | 不支持 PIVOT |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 不支持 PIVOT |
| [Materialize](materialize.sql) | 无 PIVOT 支持 |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 无 PIVOT，CASE+聚合模拟 |
| [Derby](derby.sql) | 无 PIVOT，CASE+聚合模拟 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 无 PIVOT 标准(厂商扩展) |

## 核心差异

1. **原生 PIVOT/UNPIVOT**：Oracle 11g+/SQL Server 2005+ 原生支持，BigQuery/Snowflake/Databricks 也支持，MySQL/PostgreSQL 不支持（需要用条件聚合模拟）
2. **条件聚合模拟**：`SUM(CASE WHEN category = 'A' THEN value END) AS A` 是通用的 PIVOT 替代方案，所有方言都支持
3. **动态列**：原生 PIVOT 需要硬编码列名（编译时确定），动态列需要用动态 SQL（存储过程中拼接 SQL 字符串）
4. **UNPIVOT 替代**：可以用 UNION ALL 或 CROSS JOIN + LATERAL/VALUES 模拟 UNPIVOT

## 选型建议

列值已知且固定时，条件聚合（CASE WHEN + GROUP BY）是最通用的跨方言 PIVOT 方案。列值动态变化时，建议在应用层（Python/Java）做行列转换。原生 PIVOT 语法更简洁但可移植性差。

## 版本演进

- Oracle 11g+：引入原生 PIVOT/UNPIVOT 关键字
- SQL Server 2005+：支持 PIVOT/UNPIVOT
- BigQuery/Snowflake：近年引入 PIVOT/UNPIVOT 语法支持
- PostgreSQL：通过 tablefunc 扩展的 crosstab() 函数提供有限的 PIVOT 能力

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **原生 PIVOT** | 不支持，用 CASE WHEN + GROUP BY 模拟 | 不支持原生 PIVOT，用条件聚合模拟 | 支持 PIVOT/UNPIVOT 语法 | Oracle 11g+/SQL Server 2005+ 支持原生 PIVOT |
| **UNPIVOT** | 不支持，用 UNION ALL 模拟 | 不支持原生 UNPIVOT，用 arrayJoin 等替代 | 支持 UNPIVOT 语法 | Oracle/SQL Server 支持原生 UNPIVOT |
| **条件聚合** | 支持 SUM(CASE WHEN...) 通用方案 | 支持且高效（列式存储利于条件聚合） | 支持 | 所有方言通用方案 |
| **动态列** | 不支持（无存储过程做动态 SQL） | 可用客户端生成动态查询 | 可用 EXECUTE IMMEDIATE 动态生成 | 需要存储过程中动态 SQL |

## 引擎开发者视角

**核心设计决策**：PIVOT/UNPIVOT 是报表查询的核心需求。是实现原生 PIVOT 语法还是依赖条件聚合（CASE WHEN + GROUP BY）模拟，取决于引擎的目标用户群。

**实现建议**：
- 条件聚合（`SUM(CASE WHEN category='A' THEN value END) AS A`）在任何支持 CASE WHEN 和聚合函数的引擎中天然可用，不需要额外实现。这是 MySQL/PostgreSQL 至今未实现原生 PIVOT 的原因之一
- 原生 PIVOT 语法的核心优势是简洁性——对 BI 工具和报表场景用户友好。但有一个根本性限制：列名必须在编译时确定，不能动态生成
- 动态 PIVOT（运行时确定列名）是真正的难题——需要运行时修改查询的输出 schema。PostgreSQL 的 crosstab() 使用 text 参数绕过了编译时限制，但类型安全性差
- UNPIVOT 的实现更简单——本质是 CROSS JOIN 加 VALUES 表达式或 UNION ALL。原生 UNPIVOT 语法只是语法糖
- 对于列式引擎，PIVOT 操作涉及行列转换——这与列式存储的组织方式天然冲突。实现时需要注意内存使用（PIVOT 结果的列数可能很大）
- 常见错误：PIVOT 的 NULL 处理不一致。对于源数据中不存在的分类值，结果列应该是 NULL 还是省略？需要明确定义
