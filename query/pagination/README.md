# 分页 (PAGINATION)

各数据库分页语法对比，包括 LIMIT/OFFSET、FETCH FIRST、ROWNUM 等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | LIMIT offset, count 语法 |
| [PostgreSQL](postgres.sql) | LIMIT/OFFSET + FETCH FIRST(SQL:2008) |
| [SQLite](sqlite.sql) | LIMIT/OFFSET 语法 |
| [Oracle](oracle.sql) | FETCH FIRST(12c+)，ROWNUM 旧方案 |
| [SQL Server](sqlserver.sql) | OFFSET FETCH(2012+)，TOP 旧方案 |
| [MariaDB](mariadb.sql) | LIMIT/OFFSET 兼容 MySQL |
| [Firebird](firebird.sql) | FIRST/SKIP + OFFSET FETCH(3.0+) |
| [IBM Db2](db2.sql) | FETCH FIRST + OFFSET(9.7+) |
| [SAP HANA](saphana.sql) | LIMIT/OFFSET 支持 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | LIMIT/OFFSET 支持 |
| [Snowflake](snowflake.sql) | LIMIT/OFFSET + FETCH FIRST |
| [ClickHouse](clickhouse.sql) | LIMIT n OFFSET m 语法 |
| [Hive](hive.sql) | LIMIT 支持，无 OFFSET |
| [Spark SQL](spark.sql) | LIMIT 支持，无 OFFSET(用窗口函数) |
| [Flink SQL](flink.sql) | LIMIT 支持(批模式) |
| [StarRocks](starrocks.sql) | LIMIT/OFFSET 支持 |
| [Doris](doris.sql) | LIMIT/OFFSET 支持 |
| [Trino](trino.sql) | LIMIT/OFFSET + FETCH FIRST |
| [DuckDB](duckdb.sql) | LIMIT/OFFSET + FETCH FIRST |
| [MaxCompute](maxcompute.sql) | LIMIT/OFFSET 支持 |
| [Hologres](hologres.sql) | LIMIT/OFFSET(PG 兼容) |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | LIMIT/OFFSET(PG 兼容) |
| [Azure Synapse](synapse.sql) | OFFSET FETCH(T-SQL 风格) |
| [Databricks SQL](databricks.sql) | LIMIT/OFFSET 支持 |
| [Greenplum](greenplum.sql) | PG 兼容 LIMIT/OFFSET |
| [Impala](impala.sql) | LIMIT/OFFSET 支持 |
| [Vertica](vertica.sql) | LIMIT/OFFSET + FETCH FIRST |
| [Teradata](teradata.sql) | TOP/SAMPLE + QUALIFY ROW_NUMBER |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 LIMIT/OFFSET |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式分页 |
| [CockroachDB](cockroachdb.sql) | PG 兼容 LIMIT/OFFSET |
| [Spanner](spanner.sql) | LIMIT/OFFSET 支持 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 LIMIT/OFFSET |
| [PolarDB](polardb.sql) | MySQL 兼容 LIMIT/OFFSET |
| [openGauss](opengauss.sql) | PG 兼容 LIMIT/OFFSET |
| [TDSQL](tdsql.sql) | MySQL 兼容 LIMIT/OFFSET |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | ROWNUM + OFFSET FETCH |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 分页 |
| [TDengine](tdengine.sql) | LIMIT/OFFSET 支持 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | LIMIT 支持(Pull Query) |
| [Materialize](materialize.sql) | PG 兼容 LIMIT/OFFSET |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | LIMIT/OFFSET + FETCH FIRST |
| [Derby](derby.sql) | FETCH FIRST + OFFSET(10.6+) |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2008 FETCH FIRST / OFFSET |

## 核心差异

1. **LIMIT/OFFSET**：MySQL/PostgreSQL/SQLite/MariaDB 使用，最直观但 OFFSET 大时性能差
2. **FETCH FIRST**：SQL 标准语法 `FETCH FIRST n ROWS ONLY`，Oracle 12c+/SQL Server 2012+/Db2/PostgreSQL 都支持
3. **ROWNUM**：Oracle 12c 之前的经典分页方式（三层嵌套 SELECT），代码冗长但无替代方案
4. **TOP**：SQL Server 特有的 `SELECT TOP n`，不支持 OFFSET（需要配合 OFFSET FETCH 或 ROW_NUMBER）
5. **Teradata 独特语法**：`SELECT TOP n` 或 `QUALIFY ROW_NUMBER() OVER (...) BETWEEN m AND n`

## 选型建议

前几页用 LIMIT/OFFSET 即可，深分页（OFFSET > 10000）必须用键集分页（WHERE id > last_id ORDER BY id LIMIT n）。API 分页推荐用游标分页（cursor-based），比 OFFSET 更稳定且性能一致。报表场景的分页通常在应用层处理。

## 版本演进

- Oracle 12c+：引入 `OFFSET n ROWS FETCH FIRST m ROWS ONLY`，告别 ROWNUM 三层嵌套
- SQL Server 2012+：引入 `OFFSET ... FETCH NEXT ...` 语法
- MySQL 8.0：引入窗口函数，可用 ROW_NUMBER() 实现更灵活的分页逻辑

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **分页语法** | LIMIT/OFFSET（与 MySQL/PG 相同） | LIMIT/OFFSET | LIMIT/OFFSET | MySQL/PG LIMIT / Oracle FETCH FIRST / SQL Server TOP+OFFSET |
| **OFFSET 性能** | 大 OFFSET 性能差（需跳过行），但单文件操作开销有限 | 大 OFFSET 分布式扫描成本高 | 大 OFFSET 按扫描量计费，成本高 | 大 OFFSET 普遍性能差 |
| **键集分页** | 支持 WHERE id > last_id 键集分页 | 支持且推荐，避免大 OFFSET | 支持但更推荐利用分区裁剪 | 均支持且推荐 |
| **FETCH FIRST** | 不支持 SQL 标准 FETCH FIRST 语法 | 不支持 | 不支持 | PG/Oracle 12c+/SQL Server 2012+ 支持 |
| **计费影响** | 无计费概念 | 无直接计费影响 | OFFSET 不减少扫描量，分页仍按全量扫描计费 | 无计费概念 |

## 引擎开发者视角

**核心设计决策**：分页是 Web 应用最常见的查询模式。LIMIT/OFFSET 的性能特性和 SQL 标准 FETCH FIRST 的支持程度直接影响用户体验。

**实现建议**：
- LIMIT/OFFSET 是最直观的分页语法，必须支持。但引擎应在内部将 OFFSET 优化为跳过操作而非物化前 N 行——对于 `LIMIT 10 OFFSET 1000000`，不应真正构造一百万行的中间结果
- SQL 标准的 FETCH FIRST n ROWS ONLY / OFFSET n ROWS 语法推荐同时支持（PostgreSQL 已同时支持两种）——标准语法对企业用户迁移有价值
- 键集分页（keyset pagination，`WHERE id > last_id ORDER BY id LIMIT n`）的优化对引擎来说更自然——可以直接利用索引定位起始位置，O(1) 而非 O(offset)。引擎应确保这种模式能触发 Index Scan
- WITH TIES 选项（FETCH FIRST 10 ROWS WITH TIES，返回排序值相同的所有行）实现简单但语义有用——排行榜场景中并列排名应全部返回
- 对于分布式引擎，LIMIT 的实现需要注意：各节点先取 LIMIT+OFFSET 行，协调节点再做全局 LIMIT——如果 OFFSET 很大会导致各节点传输大量数据
- 常见错误：没有 ORDER BY 的 LIMIT 返回不确定的结果集——引擎应对此发出警告（结果随执行计划变化而变化，用户可能以为结果是稳定的）
