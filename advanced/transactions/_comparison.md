# 事务 (Transactions) — 方言对比

## 语法支持对比

### 传统 RDBMS

| 特性 | MySQL | PostgreSQL | SQLite | Oracle | SQL Server | MariaDB | Firebird | Db2 | SAP HANA |
|---|---|---|---|---|---|---|---|---|---|
| BEGIN/START | ✅ START TRANSACTION | ✅ BEGIN | ✅ BEGIN | ⚠️ 隐式 | ✅ BEGIN TRAN | ✅ START TRANSACTION | ⚠️ 自动开始 | ⚠️ 隐式 | ⚠️ AUTOCOMMIT OFF |
| COMMIT | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| ROLLBACK | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| SAVEPOINT | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ 2.0+ | ✅ | ✅ |
| READ UNCOMMITTED | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| READ COMMITTED | ✅ | ✅ 默认 | ❌ | ✅ 默认 | ✅ 默认 | ✅ | ✅ | ✅ 默认 | ✅ 默认 |
| REPEATABLE READ | ✅ 默认 | ✅ | ❌ | ❌ | ✅ | ✅ 默认 | ✅ | ❌ | ❌ |
| SERIALIZABLE | ✅ | ✅ | ✅ 默认 | ✅ | ✅ | ✅ | ✅ 默认 | ❌ | ✅ |
| SNAPSHOT | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ |
| XA 事务 | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |

### 大数据 / 分析引擎

| 特性 | BigQuery | Snowflake | MaxCompute | Hive | ClickHouse | StarRocks | Trino | Hologres | Doris | DuckDB | Spark | Flink |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 多语句事务 | ✅ | ✅ | ⚠️ 事务表 | ❌ | ⚠️ 有限 | ✅ 3.0+ | ❌ | ✅ | ✅ 2.1+ | ✅ | ❌ | ❌ |
| SAVEPOINT | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 隔离级别 | Snapshot | READ COMMITTED | Snapshot | Snapshot | ❌ | ❌ | ❌ | READ COMMITTED | ❌ | Snapshot | Snapshot/Serial. | ❌ |
| MVCC | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ Checkpoint |
| Exactly-Once | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

### 云数据仓库

| 特性 | Redshift | Synapse | Databricks | Greenplum | Impala | Vertica | Teradata |
|---|---|---|---|---|---|---|---|
| 多语句事务 | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ | ✅ |
| 隔离级别 | SERIALIZABLE | READ UNCOMMITTED | Snapshot/Serial. | READ COMMITTED | ❌ | READ COMMITTED | READ UNCOMMITTED |
| SAVEPOINT | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ |

### 分布式 / NewSQL

| 特性 | TiDB | OceanBase | CockroachDB | Spanner | YugabyteDB | PolarDB | openGauss | TDSQL | DamengDB | KingbaseES |
|---|---|---|---|---|---|---|---|---|---|---|
| 多语句事务 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 默认隔离 | Snapshot | READ COMMITTED | SERIALIZABLE | External Consist. | Snapshot | REPEATABLE READ | READ COMMITTED | REPEATABLE READ | READ COMMITTED | READ COMMITTED |
| SAVEPOINT | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 分布式事务 | ✅ Percolator | ✅ 2PC | ✅ | ✅ TrueTime | ✅ 2PC | ✅ | ✅ | ✅ | ✅ | ✅ |

### 特殊用途

| 特性 | TimescaleDB | TDengine | ksqlDB | Materialize | H2 | Derby |
|---|---|---|---|---|---|---|
| 多语句事务 | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| SAVEPOINT | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| 默认隔离 | READ COMMITTED | ❌ | ❌ | SERIALIZABLE | READ COMMITTED | READ COMMITTED |

## 关键差异

- **Oracle/Db2** 事务隐式开始（每条 DML 自动开启），无 BEGIN 语句
- **Flink** 不支持传统事务，通过 Checkpoint + 2PC 实现 Exactly-Once
- **TDengine/ksqlDB** 完全不支持多语句事务
- **CockroachDB** 默认 SERIALIZABLE（最强），大多数数据库默认 READ COMMITTED
- **Spanner** 使用 TrueTime 实现 External Consistency（比 SERIALIZABLE 更强）
- **Redshift** 仅支持 SERIALIZABLE 隔离级别（不可更改）
- **Synapse** 仅支持 READ UNCOMMITTED（最弱）
- **Databricks** 不支持显式 BEGIN/COMMIT，每条 DML 是独立的 ACID 操作
- **大数据引擎** SAVEPOINT 支持极少，仅传统 RDBMS 和分布式 NewSQL 支持
