# 锁机制 (Locking) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| 行锁 (FOR UPDATE) | ✅ InnoDB | ✅ | ❌ 文件锁 | ✅ | ⚠️ UPDLOCK 提示 | ✅ InnoDB | ✅ | ✅ | ✅ |
| 表锁 (LOCK TABLE) | ✅ | ✅ 8 级 | ⚠️ 文件锁 | ✅ 5 级 | ✅ TABLOCK/TABLOCKX | ✅ | ✅ | ✅ | ✅ |
| 乐观锁 (版本号) | ✅ 应用层 | ✅ xmin | ⚠️ 应用层 | ✅ ORA_ROWSCN | ✅ 应用层 | ✅ 应用层 | ✅ 应用层 | ✅ 应用层 | ✅ 应用层 |
| 悲观锁 (FOR UPDATE) | ✅ | ✅ | ❌ | ✅ | ⚠️ UPDLOCK 提示 | ✅ | ✅ | ✅ | ✅ |
| SELECT FOR UPDATE | ✅ | ✅ | ❌ | ✅ | ❌ 用 WITH (UPDLOCK) | ✅ | ✅ | ✅ | ✅ |
| FOR SHARE | ✅ 8.0+ | ✅ 4 级 | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| NOWAIT | ✅ 8.0.1+ | ✅ | ❌ | ✅ | ✅ WITH (NOWAIT) | ✅ 10.6+ | ✅ | ✅ | ✅ |
| SKIP LOCKED | ✅ 8.0+ | ✅ 9.5+ | ❌ | ✅ 11g+ | ⚠️ READPAST | ✅ 10.6+ | ❌ | ✅ | ⚠️ |
| 死锁检测 | ✅ InnoDB 自动 | ✅ 自动 | ⚠️ SQLITE_BUSY | ✅ 自动 | ✅ 自动 | ✅ 自动 | ✅ 自动 | ✅ 自动 | ✅ 自动 |
| 锁超时 | ✅ innodb_lock_wait_timeout | ✅ lock_timeout | ⚠️ busy_timeout | ✅ WAIT n | ✅ LOCK_TIMEOUT | ✅ | ✅ | ✅ | ✅ |
| Advisory 锁 | ✅ GET_LOCK | ✅ pg_advisory_lock | ❌ | ✅ DBMS_LOCK | ✅ sp_getapplock | ⚠️ GET_LOCK | ❌ | ⚠️ | ❌ |
| 锁升级 | ❌ | ❌ | ❌ | ❌ | ✅ 自动升级 | ❌ | ❌ | ⚠️ | ⚠️ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 行锁 | ❌ | ❌ | ❌ | ❌ | ❌ | ⚠️ 有限 | ❌ | ⚠️ | ⚠️ | ❌ | ❌ | ❌ |
| 表锁 | ⚠️ 元数据锁 | ⚠️ 乐观锁 | ❌ | ❌ | ⚠️ 元数据锁 | ⚠️ | ❌ | ⚠️ | ⚠️ | ❌ | ❌ | ❌ |
| 乐观锁 | ✅ OCC | ✅ OCC | ⚠️ | ❌ | ❌ | ✅ | ❌ | ✅ MVCC | ✅ | ✅ MVCC | ❌ | ❌ |
| 悲观锁 | ❌ | ❌ | ❌ | ❌ | ❌ | ⚠️ | ❌ | ⚠️ | ⚠️ | ❌ | ❌ | ❌ |
| SELECT FOR UPDATE | ❌ | ❌ | ❌ | ❌ | ❌ | ⚠️ | ❌ | ✅ | ⚠️ | ❌ | ❌ | ❌ |
| 死锁检测 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 锁超时 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ⚠️ | ⚠️ | ❌ | ❌ | ❌ |
| Advisory 锁 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| 行锁 | ✅ | ⚠️ | ❌ | ✅ | ❌ | ✅ | ✅ |
| 表锁 | ✅ | ✅ | ❌ | ✅ | ⚠️ | ✅ | ✅ |
| 乐观锁 | ✅ | ⚠️ | ✅ OCC | ✅ | ❌ | ✅ | ✅ |
| 悲观锁 | ✅ | ⚠️ | ❌ | ✅ | ❌ | ✅ | ✅ |
| SELECT FOR UPDATE | ✅ | ⚠️ | ❌ | ✅ | ❌ | ✅ | ✅ |
| 死锁检测 | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| 锁超时 | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| Advisory 锁 | ❌ | ⚠️ sp_getapplock | ❌ | ✅ | ❌ | ❌ | ⚠️ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| 行锁 | ✅ 悲观模式 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 表锁 | ⚠️ 有限 | ✅ | ⚠️ | ❌ | ⚠️ | ✅ | ✅ | ⚠️ | ✅ | ✅ |
| 乐观锁 | ✅ 乐观模式 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 悲观锁 | ✅ 悲观模式 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| SELECT FOR UPDATE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| NOWAIT | ✅ 5.0+ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| SKIP LOCKED | ✅ 8.0+ | ✅ | ✅ | ❌ | ✅ | ⚠️ | ✅ | ⚠️ | ⚠️ | ✅ |
| 死锁检测 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 锁超时 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Advisory 锁 | ❌ | ⚠️ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ⚠️ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| 行锁 | ✅ PostgreSQL | ❌ | ❌ | ❌ | ✅ | ⚠️ |
| 表锁 | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| 乐观锁 | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| 悲观锁 | ✅ | ❌ | ❌ | ❌ | ✅ | ⚠️ |
| SELECT FOR UPDATE | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| 死锁检测 | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| 锁超时 | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| Advisory 锁 | ✅ pg_advisory_lock | ❌ | ❌ | ❌ | ❌ | ❌ |

## 关键差异

- **SQL Server** 不支持标准 `SELECT ... FOR UPDATE`，使用 `WITH (UPDLOCK, ROWLOCK)` 锁提示替代，是唯一不支持该语法的主流数据库
- **PostgreSQL** 拥有最精细的行锁粒度（4 级：FOR UPDATE / FOR NO KEY UPDATE / FOR SHARE / FOR KEY SHARE），其他数据库通常只有 2 级
- **PostgreSQL** 的 Advisory Lock（`pg_advisory_lock`）功能最完整，支持会话级/事务级/共享/排他；MySQL 的 `GET_LOCK` 仅支持会话级排他锁
- **SQLite** 使用文件级锁（5 级状态机），WAL 模式实现读写并发但仍然是单写；没有行级锁概念
- **Oracle** 不支持 `FOR SHARE`（读不阻塞写的设计哲学，通过 MVCC Undo 段实现读一致性）
- **ClickHouse / BigQuery / Flink** 等分析引擎几乎不支持传统锁机制，ClickHouse 依赖不可变 data part，BigQuery 使用乐观并发控制
- **SQL Server** 独有锁升级机制（约 5000 个行锁自动升级为表锁），其他数据库无此机制
- **TiDB** 同时支持乐观和悲观事务模式（4.0+ 默认悲观），可在会话级别切换
- **SKIP LOCKED** 是实现数据库级工作队列的关键特性，PostgreSQL 9.5+ / MySQL 8.0+ / Oracle 11g+ 支持，SQL Server 使用 `READPAST` 提示实现类似语义
- **Flink / ksqlDB / TDengine** 完全不支持传统锁机制，流处理引擎通过检查点和 exactly-once 语义保证一致性
