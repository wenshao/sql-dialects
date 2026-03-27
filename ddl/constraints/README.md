# 约束 (CONSTRAINTS)

各数据库约束管理语法对比，包括主键、外键、唯一、检查、非空约束。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | InnoDB 外键，CHECK(8.0.16+)，NDB 特殊限制 |
| [PostgreSQL](postgres.sql) | 最完整约束支持，EXCLUDE/DEFERRABLE |
| [SQLite](sqlite.sql) | 外键需手动开启 PRAGMA foreign_keys |
| [Oracle](oracle.sql) | DEFERRABLE 约束，虚拟列 CHECK |
| [SQL Server](sqlserver.sql) | WITH NOCHECK 延迟校验，级联操作 |
| [MariaDB](mariadb.sql) | CHECK(10.2.1+)真正生效，与 MySQL 差异 |
| [Firebird](firebird.sql) | 完整约束支持，含 DEFERRABLE |
| [IBM Db2](db2.sql) | 信息性约束(NOT ENFORCED)，分区键约束 |
| [SAP HANA](saphana.sql) | PK/UNIQUE 强制，FK/CHECK 默认不强制 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | PK/FK 仅信息性，不强制执行 |
| [Snowflake](snowflake.sql) | NOT NULL 外均不强制，仅做优化提示 |
| [ClickHouse](clickhouse.sql) | 无传统约束，CONSTRAINT 仅 CHECK 表达式 |
| [Hive](hive.sql) | 不支持 PK/FK/CHECK(仅信息性) |
| [Spark SQL](spark.sql) | NOT NULL 支持，其余不强制 |
| [Flink SQL](flink.sql) | PK 仅声明性，用于优化 |
| [StarRocks](starrocks.sql) | PK 模型用于去重，非传统约束 |
| [Doris](doris.sql) | Unique 模型保证唯一，约束有限 |
| [Trino](trino.sql) | 依赖底层连接器约束 |
| [DuckDB](duckdb.sql) | PK/FK/CHECK/UNIQUE 完整支持 |
| [MaxCompute](maxcompute.sql) | 不支持约束 |
| [Hologres](hologres.sql) | PK 支持，FK 不支持 |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | PK/FK 信息性，不强制执行 |
| [Azure Synapse](synapse.sql) | NOT ENFORCED 约束，用于优化 |
| [Databricks SQL](databricks.sql) | Delta Lake PK/FK 信息性(Unity Catalog) |
| [Greenplum](greenplum.sql) | 分布键必须包含在 PK/UNIQUE 中 |
| [Impala](impala.sql) | 不支持约束 |
| [Vertica](vertica.sql) | PK/FK/UNIQUE 信息性，不强制 |
| [Teradata](teradata.sql) | 完整约束支持，PPI 与 PK 交互 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容，外键(6.6+)，CHECK 不强制 |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 模式约束差异 |
| [CockroachDB](cockroachdb.sql) | PG 兼容，分布式 UNIQUE 约束 |
| [Spanner](spanner.sql) | PK 必须指定，INTERLEAVE 层级外键 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容约束，分布式执行 |
| [PolarDB](polardb.sql) | MySQL 兼容，完整约束 |
| [openGauss](opengauss.sql) | PG 兼容，支持 DEFERRABLE |
| [TDSQL](tdsql.sql) | MySQL 兼容，分布式约束限制 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | Oracle 兼容约束语法 |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG 约束，超表 UNIQUE 须含时间列 |
| [TDengine](tdengine.sql) | 无传统约束，时间列为隐式 PK |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | KEY 仅用于分区，无约束 |
| [Materialize](materialize.sql) | 无约束支持 |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 标准约束支持，含 DEFERRABLE |
| [Derby](derby.sql) | 完整约束支持 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 完整约束定义 |

## 核心差异

1. **CHECK 约束**：MySQL 8.0.16+ 才真正执行 CHECK 约束（之前只解析不执行），PostgreSQL/Oracle/SQL Server 一直支持
2. **外键支持**：分析型引擎（BigQuery/Snowflake/ClickHouse/Hive）的外键是信息性的不强制执行，TiDB 6.6 之前不支持外键
3. **DEFERRABLE 约束**：PostgreSQL/Oracle 支持延迟约束检查（事务提交时检查），MySQL/SQL Server 不支持
4. **UNIQUE 约束与 NULL**：SQL 标准允许 UNIQUE 列有多个 NULL，PostgreSQL/Oracle 遵循标准，SQL Server 默认只允许一个 NULL
5. **约束命名**：PostgreSQL/Oracle 严格管理约束名，MySQL 约束名可选但推荐命名以便后续管理

## 选型建议

OLTP 数据库应充分利用约束保证数据完整性，外键约束对数据一致性非常有价值但会影响写入性能。OLAP/大数据场景通常在应用层或 ETL 管道中保证数据质量，数据库层的约束往往是信息性的。

## 版本演进

- MySQL 8.0.16：CHECK 约束从"仅解析"变为真正强制执行
- TiDB 6.6：首次支持外键约束
- PostgreSQL 15+：支持 NULLS NOT DISTINCT 使 UNIQUE 约束完全排除 NULL 重复

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **主键约束** | 支持且强制执行，INTEGER PRIMARY KEY 特殊处理为 ROWID | 定义 PRIMARY KEY 影响排序键（ORDER BY），但不强制唯一性 | 支持声明但不强制执行（NOT ENFORCED） | 完整支持且强制执行 |
| **外键约束** | 支持但默认关闭（PRAGMA foreign_keys=ON 启用） | 不支持外键 | 支持声明但不强制执行（信息性约束） | 完整支持且强制执行，影响写入性能 |
| **CHECK 约束** | 完整支持 | 不支持 CHECK 约束 | 不支持 | MySQL 8.0.16+ 才真正执行，PG/Oracle 一直支持 |
| **UNIQUE 约束** | 支持且强制执行 | 不强制执行唯一性（MergeTree 最终合并可能去重） | 不强制执行 | 完整支持且强制执行 |
| **约束命名** | 支持但通常省略 | 无约束命名概念 | 约束名可选 | PG/Oracle 严格管理约束名 |
| **事务保证** | 单写场景下约束检查在事务内即时生效 | 无传统事务，约束不在写入时检查 | DML 有配额限制，约束仅用于查询优化器提示 | 约束在事务中即时检查（可 DEFERRABLE 延迟到提交） |

## 引擎开发者视角

**核心设计决策**：约束的实现深度是 OLTP 和 OLAP 引擎的分水岭。强制执行约束保证数据质量但有写入性能开销，信息性约束可以辅助查询优化器但不保证数据正确性。

**实现建议**：
- PRIMARY KEY 和 NOT NULL 是最低要求——任何引擎都应该支持并强制执行。UNIQUE 约束的实现依赖唯一索引，通常一起实现
- CHECK 约束要么强制执行要么不接受语法——MySQL 在 8.0.16 之前"解析但不执行"CHECK 是业界公认的设计失误。用户会误以为约束在工作
- 外键约束的实现成本最高：需要在 INSERT/UPDATE/DELETE 时检查引用完整性，涉及跨表锁定和级联操作（CASCADE/SET NULL/RESTRICT）。分布式引擎中跨分片外键几乎不可能高效实现
- DEFERRABLE 约束（事务提交时检查而非语句执行时检查）对某些业务场景至关重要（如互相引用的行），PostgreSQL 的实现可做参考
- 分析型引擎推荐走信息性约束路线（如 BigQuery 的 NOT ENFORCED）——约束元数据可以帮助查询优化器做更好的优化（如利用主键信息消除不必要的 DISTINCT）
- 常见错误：约束名称的自动生成策略不一致导致迁移困难。应该在约束未命名时用确定性算法生成名称（如 `tablename_columnname_pkey`）
