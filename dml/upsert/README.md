# 插入或更新 (UPSERT)

各数据库 UPSERT / MERGE 语法对比，包括 ON CONFLICT、ON DUPLICATE KEY 等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | INSERT ON DUPLICATE KEY UPDATE，REPLACE INTO |
| [PostgreSQL](postgres.sql) | INSERT ON CONFLICT(DO UPDATE/NOTHING) |
| [SQLite](sqlite.sql) | INSERT OR REPLACE，ON CONFLICT(3.24+) |
| [Oracle](oracle.sql) | MERGE INTO(9i+)，功能最丰富 |
| [SQL Server](sqlserver.sql) | MERGE INTO，OUTPUT 子句 |
| [MariaDB](mariadb.sql) | 兼容 MySQL，INSERT ON DUPLICATE |
| [Firebird](firebird.sql) | UPDATE OR INSERT，MERGE INTO(3.0+) |
| [IBM Db2](db2.sql) | MERGE INTO 标准 SQL 风格 |
| [SAP HANA](saphana.sql) | UPSERT/REPLACE/MERGE 三种语法 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | MERGE INTO，DML 配额限制 |
| [Snowflake](snowflake.sql) | MERGE INTO 标准，多条件匹配 |
| [ClickHouse](clickhouse.sql) | ReplacingMergeTree 引擎级去重 |
| [Hive](hive.sql) | MERGE INTO(3.0+ ACID 表) |
| [Spark SQL](spark.sql) | Delta Lake MERGE INTO |
| [Flink SQL](flink.sql) | PRIMARY KEY 自动 Upsert 模式 |
| [StarRocks](starrocks.sql) | Primary Key 模型 Upsert |
| [Doris](doris.sql) | Unique 模型自动覆盖，MERGE(未来) |
| [Trino](trino.sql) | MERGE INTO(401+) |
| [DuckDB](duckdb.sql) | INSERT OR REPLACE/ON CONFLICT |
| [MaxCompute](maxcompute.sql) | 不支持 UPSERT |
| [Hologres](hologres.sql) | INSERT ON CONFLICT 支持 |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | MERGE INTO(2023+)，DELETE+INSERT 传统方案 |
| [Azure Synapse](synapse.sql) | 无 MERGE，用 DELETE+INSERT 模拟 |
| [Databricks SQL](databricks.sql) | Delta Lake MERGE INTO，CDC 友好 |
| [Greenplum](greenplum.sql) | PG 兼容 ON CONFLICT |
| [Impala](impala.sql) | 仅 Kudu 表支持 UPSERT |
| [Vertica](vertica.sql) | MERGE INTO 标准支持 |
| [Teradata](teradata.sql) | MERGE INTO + UPDATE/INSERT 组合 |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 ON DUPLICATE KEY UPDATE |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式 MERGE/REPLACE |
| [CockroachDB](cockroachdb.sql) | PG 兼容 ON CONFLICT |
| [Spanner](spanner.sql) | INSERT OR UPDATE/REPLACE |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 ON CONFLICT |
| [PolarDB](polardb.sql) | MySQL 兼容 ON DUPLICATE |
| [openGauss](opengauss.sql) | PG 兼容 ON CONFLICT |
| [TDSQL](tdsql.sql) | MySQL 兼容，分布式 UPSERT |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | MERGE INTO(Oracle 兼容) |
| [KingbaseES](kingbase.sql) | PG 兼容 ON CONFLICT |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG ON CONFLICT |
| [TDengine](tdengine.sql) | 新记录覆盖旧记录(相同时间戳) |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | 相同 KEY 自动覆盖(Kafka 语义) |
| [Materialize](materialize.sql) | 不支持(流式源驱动) |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | MERGE INTO 标准支持 |
| [Derby](derby.sql) | MERGE INTO 标准支持(10.11+) |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 MERGE INTO 规范 |

## 核心差异

1. **语法分裂**：MySQL 用 `ON DUPLICATE KEY UPDATE`，PostgreSQL 用 `ON CONFLICT ... DO UPDATE`，SQL 标准用 `MERGE ... WHEN MATCHED/NOT MATCHED`
2. **MERGE 支持**：Oracle/SQL Server/Db2 完整支持 MERGE，PostgreSQL 15+ 支持 MERGE，MySQL 至今不支持 MERGE
3. **冲突目标**：PostgreSQL 的 ON CONFLICT 必须指定冲突列或约束名，MySQL 自动基于 UNIQUE/PRIMARY KEY 判断
4. **REPLACE INTO**：MySQL/SQLite 的 REPLACE INTO 实际是 DELETE + INSERT，会重置自增 ID 和触发 DELETE 触发器，应谨慎使用
5. **分析型引擎**：ClickHouse 用 ReplacingMergeTree 引擎实现最终去重，BigQuery/Snowflake 用 MERGE 语法

## 选型建议

优先使用 SQL 标准 MERGE 语法（如果方言支持），可移植性最好。MySQL 场景使用 ON DUPLICATE KEY UPDATE（比 REPLACE INTO 更安全）。高并发场景注意 UPSERT 的死锁风险，MySQL 的 ON DUPLICATE KEY UPDATE 在并发下可能死锁。

## 版本演进

- PostgreSQL 9.5+：引入 ON CONFLICT（INSERT ... ON CONFLICT DO UPDATE/NOTHING）
- PostgreSQL 15+：引入 SQL 标准 MERGE 语法
- SQLite 3.24.0+：引入 ON CONFLICT（UPSERT）语法
- MySQL 8.0：ON DUPLICATE KEY UPDATE 支持 VALUES() 的别名替代（推荐用 AS 新行别名）

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **UPSERT 机制** | ON CONFLICT DO UPDATE/NOTHING（3.24.0+），REPLACE INTO | 无原生 UPSERT；ReplacingMergeTree 引擎实现最终去重 | MERGE 语法（SQL 标准） | MySQL ON DUPLICATE KEY / PG ON CONFLICT / Oracle MERGE |
| **去重时机** | INSERT 时即时检查冲突并处理 | ReplacingMergeTree 在后台合并时去重（最终一致，非即时） | MERGE 即时执行但消耗 DML 配额 | 即时在 INSERT 时处理 |
| **MERGE 支持** | 不支持 SQL 标准 MERGE | 不支持 MERGE | 完整支持 MERGE（推荐方式） | Oracle/SQL Server 完整支持，PG 15+ 支持，MySQL 不支持 |
| **并发安全** | 单写模型天然无并发冲突 | 并发 INSERT 后由后台合并保证最终一致 | 同一表并发 MERGE 有限制 | 行级锁保证并发安全，但可能死锁 |
| **REPLACE INTO** | 支持（DELETE + INSERT） | 不支持 | 不支持 | MySQL 支持（DELETE + INSERT，会重置自增） |

## 引擎开发者视角

**核心设计决策**：UPSERT 的语法选择直接影响并发安全性。MERGE（SQL 标准）vs ON CONFLICT（PostgreSQL）vs ON DUPLICATE KEY（MySQL）各有利弊。

**实现建议**：
- ON CONFLICT 语义更清晰（显式指定冲突目标列或约束名），推荐新引擎优先实现。PostgreSQL 9.5 的 ON CONFLICT DO UPDATE/DO NOTHING 设计优雅且并发安全
- MERGE 是 SQL 标准但实现复杂（需要支持 WHEN MATCHED/NOT MATCHED/NOT MATCHED BY SOURCE 多个分支），SQL Server 的 MERGE 实现有已知的并发 bug——新引擎实现 MERGE 时要特别注意锁策略
- UPSERT 的原子性是核心难点：CHECK-THEN-INSERT 的朴素实现在并发下会失败（TOCTOU 竞态）。正确的实现需要在索引层面加排他锁或使用 INSERT-ON-CONFLICT 的原子操作
- REPLACE INTO（MySQL/SQLite）的 DELETE+INSERT 语义有严重副作用：重置自增 ID、触发 DELETE 触发器、破坏外键引用。新引擎不推荐实现此语法
- 分析型引擎如果使用 MergeTree 类架构，可以在引擎级实现去重（ReplacingMergeTree）而非 SQL 级——这是更自然的列式引擎方案
- 常见错误：UPSERT 的死锁风险。并发 UPSERT 操作如果以不同顺序访问同一组行会导致死锁，引擎应提供 gap lock 或按主键排序的写入策略来缓解
