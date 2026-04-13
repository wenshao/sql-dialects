# 锁机制与死锁检测 (Locks and Deadlock Detection)

数据库的并发模型由两根支柱撑起——多版本并发控制 (MVCC) 决定读取看到什么，锁机制决定写入如何排队。前者已在 [mvcc-implementation.md](./mvcc-implementation.md) 中详细讨论；本文聚焦后者：行锁、表锁、意向锁、咨询锁，以及当锁形成环路时的死锁检测算法。理解 45+ 引擎在锁模型上的差异，是排查生产环境锁等待、死锁回滚、热点行竞争的前提。

锁机制设计有三个根本权衡：**粒度**（细锁并发高但元数据开销大），**等待策略**（阻塞 vs 立即失败 vs 跳过），以及**死锁处理**（主动检测 vs 超时放弃）。一些云原生 OLAP 引擎（Snowflake、BigQuery、ClickHouse）干脆抛弃传统锁模型，用乐观并发或异步 mutation 替代——这条分歧线本身就是过去十年数据库设计哲学最显著的分裂之一。

## SQL 标准定义

### SQL:1992 SELECT FOR UPDATE

SQL:1992 标准在游标定义中引入了悲观锁的雏形：

```sql
DECLARE cursor_name CURSOR FOR
    SELECT ... FROM ...
    FOR UPDATE [ OF column_list ]
```

`FOR UPDATE` 表示游标读取的行将被后续 UPDATE/DELETE 修改，要求数据库在读取时即获取行的排他锁，避免在游标推进过程中被其他事务修改。

### SQL:2008 FOR UPDATE / FOR SHARE 扩展

SQL:2008 将锁子句从游标扩展到普通 SELECT 语句，并引入 `FOR SHARE` 表示共享意图：

```sql
SELECT ... FROM ...
[ FOR { UPDATE | SHARE | NO KEY UPDATE | KEY SHARE }
  [ OF table_name [, ...] ]
  [ NOWAIT | SKIP LOCKED ] ]
```

- `FOR UPDATE`：对返回行加排他锁
- `FOR SHARE`：对返回行加共享锁（允许其他 FOR SHARE，阻止 FOR UPDATE 与写入）
- `NOWAIT`：行被锁定时立即报错
- `SKIP LOCKED`：跳过被锁定的行（典型场景：消息队列消费）

标准本身**不规定**锁的实现方式（行锁/页锁/表锁）、不规定死锁如何检测、不规定锁等待超时——这些都留给具体引擎，因此各家差异巨大。

## 支持矩阵

### 锁粒度支持

| 引擎 | 行锁 | 页锁 | 表锁 | 意向锁 (IS/IX/SIX) | 锁升级 |
|------|------|------|------|-------------------|--------|
| PostgreSQL | 是 | -- | 是 | -- (使用 RowShare/RowExclusive 表级锁模拟) | 否 |
| MySQL InnoDB | 是 | -- | 是 | 是 | 否 |
| MariaDB (InnoDB) | 是 | -- | 是 | 是 | 否 |
| MariaDB (Aria) | -- | 是 | 是 | -- | -- |
| SQLite | -- | -- | 是 (整库) | -- | -- |
| Oracle | 是 | -- | 是 | 是 (RS/RX/SRX) | **从不升级** |
| SQL Server | 是 | 是 | 是 | 是 | 是 (~5000 锁) |
| DB2 | 是 | -- | 是 | 是 | 是 (LOCKLIST 满) |
| Snowflake | -- | -- | 表级 (隐式) | -- | -- |
| BigQuery | -- | -- | -- | -- | -- |
| Redshift | -- | -- | 是 | -- | -- |
| DuckDB | -- | -- | 是 | -- | -- |
| ClickHouse | -- | -- | 部分元数据锁 | -- | -- |
| Trino | -- | -- | -- | -- | -- |
| Presto | -- | -- | -- | -- | -- |
| Spark SQL | -- | -- | -- | -- | -- |
| Hive | -- | -- | 是 (ZooKeeper) | 是 | -- |
| Flink SQL | -- | -- | -- | -- | -- |
| Databricks | -- | -- | 表级 (Delta) | -- | -- |
| Teradata | 是 | -- | 是 | 是 | -- |
| Greenplum | -- | -- | 是 | -- | -- |
| CockroachDB | 是 | -- | -- | -- | 否 |
| TiDB | 是 | -- | 是 | -- | 否 |
| OceanBase | 是 | -- | 是 | 是 | 否 |
| YugabyteDB | 是 | -- | 是 | 是 | 否 |
| SingleStore | 是 | -- | 是 | -- | -- |
| Vertica | -- | -- | 是 | 是 | -- |
| Impala | -- | -- | -- | -- | -- |
| StarRocks | -- | -- | 表级 (元数据) | -- | -- |
| Doris | -- | -- | 表级 (元数据) | -- | -- |
| MonetDB | -- | -- | 是 | -- | -- |
| CrateDB | -- | -- | -- | -- | -- |
| TimescaleDB | 是 (继承 PG) | -- | 是 | -- | 否 |
| QuestDB | -- | -- | 是 (writer) | -- | -- |
| Exasol | -- | -- | 是 | -- | -- |
| SAP HANA | 是 | -- | 是 | 是 | -- |
| Informix | 是 | 是 | 是 | -- | 是 |
| Firebird | 是 | -- | 是 | -- | -- |
| H2 | 是 | -- | 是 | -- | -- |
| HSQLDB | 是 | -- | 是 | -- | -- |
| Derby | 是 | -- | 是 | 是 | 是 |
| Amazon Athena | -- | -- | -- | -- | -- |
| Azure Synapse | -- | -- | 是 | -- | -- |
| Google Spanner | 是 | -- | -- | -- | 否 |
| Materialize | -- | -- | -- | -- | -- |
| RisingWave | -- | -- | -- | -- | -- |
| InfluxDB (SQL) | -- | -- | -- | -- | -- |
| DatabendDB | -- | -- | 表级 (元数据) | -- | -- |
| Yellowbrick | -- | -- | 是 | -- | -- |
| Firebolt | -- | -- | -- | -- | -- |

> 关键观察：完整支持行锁 + 意向锁体系的引擎主要是传统 OLTP 数据库（Oracle、MySQL InnoDB、SQL Server、DB2、SAP HANA、Derby）。云数据仓库 (Snowflake、BigQuery、Redshift) 与计算引擎 (Trino、Spark) 普遍只在表级别协调，依赖 MVCC 或乐观并发处理冲突。

### FOR UPDATE / FOR SHARE 子句支持

| 引擎 | FOR UPDATE | FOR SHARE | NOWAIT | SKIP LOCKED | WAIT N |
|------|-----------|-----------|--------|-------------|--------|
| PostgreSQL | 是 (8.x+) | 是 (8.x+) | 是 | 是 (9.5+) | -- |
| MySQL InnoDB | 是 | `LOCK IN SHARE MODE` / `FOR SHARE` (8.0+) | 是 (8.0+) | 是 (8.0+) | -- |
| MariaDB | 是 | `LOCK IN SHARE MODE` | 是 (10.3+) | 是 (10.6+) | 是 (10.3+ via SET) |
| SQLite | -- | -- | -- | -- | -- |
| Oracle | 是 | -- (废弃) | 是 | 是 (11g+) | 是 (`WAIT n`) |
| SQL Server | -- (用 hints) | -- (用 hints) | `READPAST` / `NOWAIT` hint | `READPAST` | `LOCK_TIMEOUT` |
| DB2 | 是 (`FOR UPDATE`) | `FOR READ ONLY` | -- | `SKIP LOCKED DATA` | -- |
| Snowflake | -- | -- | -- | -- | -- |
| BigQuery | -- | -- | -- | -- | -- |
| Redshift | -- | -- | -- | -- | -- |
| DuckDB | -- | -- | -- | -- | -- |
| ClickHouse | -- | -- | -- | -- | -- |
| Trino | -- | -- | -- | -- | -- |
| Presto | -- | -- | -- | -- | -- |
| Spark SQL | -- | -- | -- | -- | -- |
| Hive | -- | -- | -- | -- | -- |
| Flink SQL | -- | -- | -- | -- | -- |
| Databricks | -- | -- | -- | -- | -- |
| Teradata | -- (使用 LOCKING modifier) | -- | `NOWAIT` | -- | -- |
| Greenplum | 是 (继承 PG) | 是 | 是 | 是 | -- |
| CockroachDB | 是 (20.1+) | 是 | 是 | 是 (22.2+) | -- |
| TiDB | 是 (悲观模式 3.0+) | 是 | 是 | -- | 是 |
| OceanBase | 是 | 是 | 是 | 是 | 是 |
| YugabyteDB | 是 | 是 | 是 | 是 (2.15+) | -- |
| SingleStore | 是 | -- | -- | -- | -- |
| Vertica | -- | -- | -- | -- | -- |
| Impala | -- | -- | -- | -- | -- |
| StarRocks | -- | -- | -- | -- | -- |
| Doris | -- | -- | -- | -- | -- |
| MonetDB | -- | -- | -- | -- | -- |
| CrateDB | -- | -- | -- | -- | -- |
| TimescaleDB | 是 (继承 PG) | 是 | 是 | 是 | -- |
| QuestDB | -- | -- | -- | -- | -- |
| Exasol | -- | -- | -- | -- | -- |
| SAP HANA | 是 | -- | 是 | 是 | 是 (`WAIT n`) |
| Informix | 是 | -- | -- | -- | 是 (`SET LOCK MODE TO WAIT n`) |
| Firebird | `WITH LOCK` | -- | -- | -- | -- |
| H2 | 是 | -- | -- | -- | -- |
| HSQLDB | 是 | -- | -- | -- | -- |
| Derby | 是 | -- | -- | -- | -- |
| Amazon Athena | -- | -- | -- | -- | -- |
| Azure Synapse | -- | -- | -- | -- | -- |
| Google Spanner | 是 (Read-Write 事务) | -- | -- | -- | -- |
| Materialize | -- | -- | -- | -- | -- |
| RisingWave | -- | -- | -- | -- | -- |
| InfluxDB (SQL) | -- | -- | -- | -- | -- |
| DatabendDB | -- | -- | -- | -- | -- |
| Yellowbrick | -- | -- | -- | -- | -- |
| Firebolt | -- | -- | -- | -- | -- |

### LOCK TABLE 显式锁定

| 引擎 | LOCK TABLE 语法 | 模式数量 |
|------|-----------------|---------|
| PostgreSQL | `LOCK TABLE name IN <mode>` | 8 种 (ACCESS SHARE … ACCESS EXCLUSIVE) |
| MySQL InnoDB | `LOCK TABLES name {READ|WRITE}` | 2 种 |
| MariaDB | `LOCK TABLES` | 2 种 |
| Oracle | `LOCK TABLE name IN <mode>` | 5 种 (RS/RX/S/SRX/X) |
| SQL Server | -- (使用 `WITH (TABLOCK)` hint) | 多种 hint |
| DB2 | `LOCK TABLE name IN {SHARE|EXCLUSIVE} MODE` | 2 种 |
| Greenplum | `LOCK TABLE` (继承 PG) | 8 种 |
| CockroachDB | -- | -- |
| TiDB | `LOCK TABLES` (兼容 MySQL) | 2 种 |
| Snowflake | -- (隐式) | -- |
| Teradata | `LOCKING TABLE name FOR <mode>` | 4 种 |
| Vertica | `LOCK TABLE` | 多种 |
| SAP HANA | `LOCK TABLE` | 2 种 |
| H2 / HSQLDB / Derby | `LOCK TABLE` | 2 种 |
| Firebird | `RESERVING ... FOR ...` (事务级声明) | 多种 |

### 咨询锁 / 应用锁

| 引擎 | API | 键类型 | 作用域 |
|------|-----|--------|--------|
| PostgreSQL | `pg_advisory_lock(key)`, `pg_try_advisory_lock`, `pg_advisory_unlock` | bigint 或两个 int | 会话级 / 事务级 |
| MySQL | `GET_LOCK(name, timeout)`, `RELEASE_LOCK`, `IS_FREE_LOCK` | 字符串 | 会话级 (5.7.5+ 实例级) |
| MariaDB | `GET_LOCK`, `RELEASE_LOCK` | 字符串 | 会话级 |
| Oracle | `DBMS_LOCK.REQUEST` (需 EXECUTE 权限) | 用户分配 ID | 会话/事务 |
| SQL Server | `sp_getapplock`, `sp_releaseapplock` | 字符串 | 会话/事务 |
| DB2 | -- (使用 LOCK TABLE 模拟) | -- | -- |
| CockroachDB | -- | -- | -- |
| TiDB | -- | -- | -- |
| Greenplum | `pg_advisory_lock` (继承 PG) | bigint | 会话/事务 |
| YugabyteDB | -- (PG 兼容但未实现) | -- | -- |

### 死锁检测机制

| 引擎 | 检测方式 | 默认超时 | 受害者选择 |
|------|---------|---------|-----------|
| PostgreSQL | wait-for graph (deferred) | `deadlock_timeout` 1s | 触发检测的事务被中止 |
| MySQL InnoDB | wait-for graph (即时) | `lock_wait_timeout` 50s (兜底) | 修改行数最少的事务回滚 |
| MariaDB InnoDB | wait-for graph | 50s | 同 InnoDB |
| Oracle | wait-for graph (定期 ~3s) | 不适用 | 检测发起方语句被回滚 (ORA-00060) |
| SQL Server | wait-for graph (默认 5s) | `LOCK_TIMEOUT` -1 | DEADLOCK_PRIORITY + 日志最少者 |
| DB2 | wait-for graph (异步 deadlock detector) | `DLCHKTIME` 10s | 成本最低事务 |
| SQLite | -- (整库写锁，无死锁) | `busy_timeout` | -- |
| CockroachDB | 优先级 (priority queue) + push txn | -- | 低优先级事务 abort/restart |
| TiDB | 分布式 wait-for graph (悲观锁) | -- | DDL 选择 |
| OceanBase | 分布式 wait-for graph | -- | -- |
| YugabyteDB | wait-for graph (2.15+) | -- | -- |
| Google Spanner | wound-wait | -- | 较新事务被 wound（中止重试） |
| Snowflake | -- (无传统锁) | -- | -- |
| BigQuery | -- (无事务锁) | -- | -- |
| Trino / Presto / Spark / Flink | -- (无事务) | -- | -- |
| ClickHouse | -- (mutation 异步) | -- | -- |
| Teradata | wait-for graph | -- | -- |
| Vertica | wait-for graph | -- | -- |
| SAP HANA | wait-for graph | -- | -- |
| Informix | wait-for graph | `DEADLOCK_TIMEOUT` 60s | -- |
| Firebird | -- (乐观 + 冲突错误) | -- | 第一个写入者获胜 |
| H2 | wait-for graph | 默认 1s lock timeout | -- |
| HSQLDB | -- (MVCC 模式无死锁；锁模式有简单超时) | -- | -- |
| Derby | wait-for graph | `derby.locks.deadlockTimeout` 20s | 持锁最少者 |
| SingleStore | wait-for graph | -- | -- |

### 锁等待超时配置

| 引擎 | 参数名 | 默认 | 单位 |
|------|--------|------|------|
| PostgreSQL | `lock_timeout` (语句级) / `deadlock_timeout` | 0 (无限) / 1000 | ms |
| MySQL InnoDB | `innodb_lock_wait_timeout` | 50 | s |
| Oracle | (会话级 `FOR UPDATE WAIT n`) | 无限 | s |
| SQL Server | `SET LOCK_TIMEOUT n` | -1 (无限) | ms |
| DB2 | `LOCKTIMEOUT` | -1 (无限) | s |
| CockroachDB | `lock_timeout` | 0 | ms |
| TiDB | `innodb_lock_wait_timeout` | 50 | s |
| SAP HANA | `lock_wait_timeout` | 1800000 | ms |
| Informix | `SET LOCK MODE TO WAIT n` | 0 (NOT WAIT) | s |
| H2 | `LOCK_TIMEOUT` | 10000 | ms |

## 各引擎详解

### PostgreSQL：行锁 + 8 种表锁 + bigint 咨询锁

PostgreSQL 的锁体系建立在 8 种表级锁模式上，行级锁通过 tuple 头部的 xmax/xmin 字段隐式记录（不消耗共享内存）：

```sql
-- 表锁的 8 种模式（从弱到强）
LOCK TABLE accounts IN ACCESS SHARE MODE;        -- SELECT
LOCK TABLE accounts IN ROW SHARE MODE;           -- SELECT FOR UPDATE/SHARE
LOCK TABLE accounts IN ROW EXCLUSIVE MODE;       -- INSERT/UPDATE/DELETE
LOCK TABLE accounts IN SHARE UPDATE EXCLUSIVE;   -- VACUUM, ANALYZE, CREATE INDEX CONCURRENTLY
LOCK TABLE accounts IN SHARE MODE;               -- CREATE INDEX
LOCK TABLE accounts IN SHARE ROW EXCLUSIVE;      -- 较少使用
LOCK TABLE accounts IN EXCLUSIVE MODE;           -- 阻塞所有读写（除 ACCESS SHARE）
LOCK TABLE accounts IN ACCESS EXCLUSIVE MODE;    -- DROP/TRUNCATE/ALTER

-- FOR UPDATE 的四个变体
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;          -- 完整行锁
SELECT * FROM accounts WHERE id = 1 FOR NO KEY UPDATE;   -- 不锁主键，允许外键检查
SELECT * FROM accounts WHERE id = 1 FOR SHARE;           -- 共享锁
SELECT * FROM accounts WHERE id = 1 FOR KEY SHARE;       -- 仅锁主键

-- NOWAIT / SKIP LOCKED (9.5+)
SELECT * FROM jobs WHERE status='pending'
    FOR UPDATE SKIP LOCKED LIMIT 10;   -- 队列消费典型模式

SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;  -- 立即报错 55P03

-- 咨询锁（bigint 键，与表/行无关）
SELECT pg_advisory_lock(12345);              -- 阻塞获取
SELECT pg_try_advisory_lock(12345);          -- 非阻塞，返回 boolean
SELECT pg_advisory_xact_lock(12345);         -- 事务结束自动释放
SELECT pg_advisory_lock(1, 2);               -- 两个 int32 组成 bigint
SELECT pg_advisory_unlock(12345);

-- 监控视图
SELECT * FROM pg_locks;                       -- 所有锁
SELECT pid, query, wait_event_type, wait_event
  FROM pg_stat_activity WHERE wait_event_type='Lock';
```

死锁检测：PostgreSQL 采用**延迟检测**——事务进入等待后，先睡眠 `deadlock_timeout`（默认 1 秒），到期后才构建 wait-for graph 检查环路。这避免了为每次短暂等待都付出图遍历开销。错误码 `40P01`，`SQLSTATE deadlock_detected`，触发检测的事务被回滚。

### Oracle：TM/TX 队列锁，从不升级

Oracle 的锁分两类：**TX (事务锁)** 标记某个事务持有某行，存储在数据块 ITL (Interested Transaction List) 中；**TM (DML 表级锁)** 防止 DDL 与 DML 冲突。Oracle 的杀手锏特性是：**永远不会从行锁升级到表锁**，无论一个事务锁了多少行。

```sql
-- 标准 FOR UPDATE
SELECT * FROM employees WHERE department_id = 10 FOR UPDATE;

-- WAIT n（等待 n 秒后失败 ORA-30006）
SELECT * FROM employees WHERE id = 100 FOR UPDATE WAIT 5;

-- NOWAIT（立即失败 ORA-00054）
SELECT * FROM employees WHERE id = 100 FOR UPDATE NOWAIT;

-- SKIP LOCKED (11g+)
SELECT * FROM job_queue WHERE status='READY'
    FOR UPDATE SKIP LOCKED;

-- 显式表锁
LOCK TABLE employees IN EXCLUSIVE MODE NOWAIT;

-- DBMS_LOCK 应用锁
DECLARE
  lockhandle VARCHAR2(128);
  status     INTEGER;
BEGIN
  DBMS_LOCK.ALLOCATE_UNIQUE('mylock', lockhandle);
  status := DBMS_LOCK.REQUEST(lockhandle, DBMS_LOCK.X_MODE, 60, TRUE);
  -- ...
  status := DBMS_LOCK.RELEASE(lockhandle);
END;

-- 监控
SELECT * FROM v$lock;
SELECT * FROM dba_blockers;
SELECT * FROM dba_waiters;
```

死锁检测：Oracle 的死锁检测器**每 3 秒**扫描 enqueue wait list，构建 wait-for graph。检测到环路后，**触发检测的会话**所执行的语句被回滚（仅该语句，不是整个事务），返回 `ORA-00060: deadlock detected while waiting for resource`，并自动写入 trace 文件至 `user_dump_dest`。OEM (Oracle Enterprise Manager) 提供死锁告警与历史。

### SQL Server：5000 行升级阈值

SQL Server 是少数实现完整锁升级的引擎：当单个语句对一个对象持有的行/页锁数量超过阈值（默认约 **5000**），数据库引擎会尝试升级为表锁，以减少锁管理器内存占用。

```sql
-- 通过 hint 控制锁
SELECT * FROM Orders WITH (UPDLOCK, ROWLOCK)
    WHERE OrderID = 100;

SELECT * FROM Orders WITH (READPAST)        -- 跳过被锁定的行
    WHERE Status = 'Pending';

SELECT * FROM Orders WITH (NOLOCK)          -- 脏读
    WHERE Status = 'Pending';

SELECT * FROM Orders WITH (TABLOCKX);       -- 强制表级排他

-- 锁升级控制（表级别）
ALTER TABLE Orders SET (LOCK_ESCALATION = TABLE);     -- 默认
ALTER TABLE Orders SET (LOCK_ESCALATION = AUTO);      -- 分区表升级到分区
ALTER TABLE Orders SET (LOCK_ESCALATION = DISABLE);

-- 锁超时
SET LOCK_TIMEOUT 5000;   -- 5 秒后失败 1222
SELECT * FROM Orders WHERE OrderID = 100;

-- 死锁优先级
SET DEADLOCK_PRIORITY HIGH;        -- LOW / NORMAL / HIGH / -10..10

-- 应用锁
EXEC sp_getapplock @Resource='myresource', @LockMode='Exclusive',
                   @LockOwner='Session', @LockTimeout=5000;
EXEC sp_releaseapplock @Resource='myresource';

-- 监控
SELECT * FROM sys.dm_tran_locks;
EXEC sp_who2;
SELECT * FROM sys.dm_os_waiting_tasks WHERE wait_type LIKE 'LCK%';
```

死锁检测：SQL Server 的 lock monitor 后台线程**每 5 秒**唤醒一次构建 wait-for graph；如检测到死锁则缩短间隔加快后续扫描。受害者选择基于 `DEADLOCK_PRIORITY` 设置 + 回滚成本（事务日志字节数最少者）。死锁图可通过扩展事件或 trace flag 1222 输出为 XML（`deadlock-list/deadlock/process-list/resource-list`）。

### MySQL InnoDB：行锁 + Gap Lock + Next-Key Lock

InnoDB 是 OLTP 引擎中锁模型最复杂的之一，因为它必须在 REPEATABLE READ 隔离级别下用锁（而非 MVCC）防止幻读：

```sql
-- 标准 FOR UPDATE
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;

-- 共享锁
SELECT * FROM accounts WHERE id = 1 LOCK IN SHARE MODE;  -- 旧语法
SELECT * FROM accounts WHERE id = 1 FOR SHARE;            -- 8.0+

-- NOWAIT / SKIP LOCKED (8.0+)
SELECT * FROM jobs WHERE status='pending'
    FOR UPDATE SKIP LOCKED LIMIT 10;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;

-- 显式表锁
LOCK TABLES accounts WRITE, customers READ;
UNLOCK TABLES;

-- 配置
SET innodb_lock_wait_timeout = 30;
SET GLOBAL innodb_deadlock_detect = ON;   -- 5.7+ 默认 ON

-- 应用锁（5.7.5+ 实例级，之前会话级）
SELECT GET_LOCK('mylock', 5);
SELECT IS_USED_LOCK('mylock');
SELECT RELEASE_LOCK('mylock');

-- 监控
SHOW ENGINE INNODB STATUS;        -- LATEST DETECTED DEADLOCK 段
SELECT * FROM performance_schema.data_locks;
SELECT * FROM performance_schema.data_lock_waits;
```

InnoDB 的锁模型在 REPEATABLE READ 下扩展为三类：

- **Record Lock**：仅锁定索引记录本身
- **Gap Lock**：锁定索引记录之间的间隙，阻止其他事务在间隙中插入
- **Next-Key Lock**：Record Lock + Gap Lock 的组合，是 REPEATABLE READ 下的默认行为，**用于防止幻读**

```sql
-- REPEATABLE READ 下的 next-key 行为
START TRANSACTION;
SELECT * FROM users WHERE age BETWEEN 20 AND 30 FOR UPDATE;
-- 此时不仅锁定 age 在 [20,30] 的现有行，还锁定 (20,30] 范围的间隙
-- 其他事务无法 INSERT age=25 的行（直到事务提交）
```

死锁检测：InnoDB 维护**实时** wait-for graph，每次锁等待发生时即时检测环路。受害者选择算法寻找**修改行数最少**的事务回滚（`undo log` 长度最短），返回错误 `1213 ER_LOCK_DEADLOCK`。`innodb_deadlock_detect` 自 5.7 起默认 ON；在高并发热点场景下也可关闭，依靠 `innodb_lock_wait_timeout` 兜底（避免 O(n²) 图构建开销）。

### DB2：LOCKLIST 内存池 + 锁升级

DB2 的所有锁都存储在共享内存的 **lock list** 中，由 `LOCKLIST` 数据库参数限制大小（pages × 4KB）。当某事务持有的锁占用超过 `MAXLOCKS` 百分比，DB2 会触发**锁升级**：将多个行锁合并为单个表锁。

```sql
LOCK TABLE employees IN SHARE MODE;
LOCK TABLE employees IN EXCLUSIVE MODE;

-- FOR UPDATE
SELECT * FROM employees WHERE id = 100 FOR UPDATE;

-- SKIP LOCKED (跳过未提交行)
SELECT * FROM job_queue
    WHERE status='ready'
    FOR UPDATE SKIP LOCKED DATA;

-- 注册表变量启用乐观读取
db2set DB2_EVALUNCOMMITTED=YES         -- 评估未提交但锁持有的行
db2set DB2_SKIPINSERTED=YES            -- 跳过其他事务未提交的插入
db2set DB2_SKIPDELETED=YES             -- 跳过其他事务未提交的删除

-- 配置
UPDATE DB CFG FOR mydb USING LOCKLIST 50000;
UPDATE DB CFG FOR mydb USING MAXLOCKS 22;
UPDATE DB CFG FOR mydb USING DLCHKTIME 10000;
UPDATE DB CFG FOR mydb USING LOCKTIMEOUT 30;

-- 监控
SELECT * FROM SYSIBMADM.SNAPLOCKWAIT;
SELECT * FROM TABLE(MON_GET_LOCKS(NULL,-2)) AS L;
```

死锁检测：DB2 的 deadlock detector 后台进程按 `DLCHKTIME`（默认 10 秒）周期性扫描 wait-for graph。受害者基于成本模型选择，错误码 `SQL0911N reason code 2`。

### Snowflake：无传统锁，乐观并发 + 微分区重写

Snowflake 完全抛弃了行级锁。其架构基于**不可变微分区** (immutable micro-partitions)：DML 操作不修改原数据，而是生成新的微分区版本。冲突在事务提交时检测——若两个事务并发更新同一组微分区，**后提交者失败重试**。

```sql
-- DML 语句获取的是表级写锁（防止两个事务同时修改元数据）
UPDATE orders SET status='shipped' WHERE id IN (1,2,3);

-- 长时间运行的 UPDATE 会阻塞同表的其他 UPDATE/DELETE
-- SELECT 永远不阻塞（读取上一个已提交快照）

-- 监控
SHOW LOCKS;
SHOW TRANSACTIONS;
SELECT SYSTEM$ABORT_TRANSACTION(<txn_id>);
```

无 FOR UPDATE，无 NOWAIT，无 SKIP LOCKED，无死锁——因为根本不存在传统意义上的锁等待。这是云数仓为 OLAP 优化做出的根本设计取舍：放弃精细并发控制，换取存储/计算分离与无限弹性。

### BigQuery：无事务锁

BigQuery 同样无行/页/表锁。多语句事务在 2021 年才推出 (preview)，使用快照隔离 + 提交时冲突检测。DML 语句串行化在表级别（同一张表的并发 UPDATE 排队执行），但不暴露任何锁 API。

```sql
BEGIN TRANSACTION;
UPDATE dataset.t SET v = v + 1 WHERE k = 1;
COMMIT TRANSACTION;
-- 若另一事务并发修改同行：6017005 错误，必须应用层重试
```

### ClickHouse：mutation 异步，无行锁

ClickHouse 是分析型列存，不支持点更新。`ALTER TABLE ... UPDATE/DELETE` 语句被称为 **mutation**，是异步的——它生成一个 mutation 任务，后台线程通过重写整个数据 part 来应用变更。

```sql
ALTER TABLE events UPDATE status='archived' WHERE ts < '2024-01-01';
-- 立即返回，但不保证立即生效
SELECT * FROM system.mutations WHERE table = 'events';

-- 同步等待
ALTER TABLE events UPDATE ... SETTINGS mutations_sync = 2;
```

无锁，无 FOR UPDATE，无死锁。表级有少量元数据锁用于保护 schema 变更，但用户事务模型几乎不存在。

### CockroachDB：优先级队列 + Push Transaction

CockroachDB 是分布式 SQL，采用 Serializable 隔离级别，使用**事务优先级**而非传统死锁检测：

```sql
-- FOR UPDATE 在 20.1+ 支持
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE SKIP LOCKED;  -- 22.2+

-- 设置事务优先级
SET TRANSACTION PRIORITY HIGH;       -- LOW / NORMAL / HIGH
```

冲突解决采用 **push transaction** 机制：事务 A 遇到事务 B 持有的锁时，比较优先级；若 A 优先级更高且 B 仍在运行，A 强制 B 重启 (abort + retry)；否则 A 等待 B。CockroachDB 不显式构建全局 wait-for graph（在分布式环境中代价高昂），而是依靠优先级单调收敛保证最终某个事务能进展。

### TiDB：乐观锁 + 悲观锁双模式

TiDB 早期只有乐观事务，自 3.0 起引入**悲观锁模式**（默认从 3.0.8 起），并实现分布式死锁检测：

```sql
-- 显式启用悲观事务
BEGIN PESSIMISTIC;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;

-- 配置
SET GLOBAL tidb_txn_mode = 'pessimistic';
SET GLOBAL innodb_lock_wait_timeout = 50;
```

死锁检测：TiDB 在 PD (Placement Driver) 中维护全局**分布式 wait-for graph**：每个 TiKV region leader 上的锁等待信息上报到 deadlock detector leader 节点，集中构建图。检测到环路后，由协调器选择 start_ts 最小（最老）的事务作为受害者回滚，错误码 `8022 Deadlock`。

### Google Spanner：Wound-Wait

Spanner 使用经典的 **wound-wait** 死锁避免算法（而非检测）：

- 当事务 T1 请求被 T2 持有的锁时，比较时间戳
- 若 T1 比 T2 **老**（start_ts 更小），T1 "wound" T2：T2 被中止，T1 继续
- 若 T1 比 T2 **新**，T1 等待 T2

由于 wound-wait 保证只有老事务能等待新事务，wait-for graph 永远是 DAG，**不可能形成环路**——因此根本不需要死锁检测。代价是新事务可能因冲突被反复中止（但因为它们重启后会带着原始时间戳，最终也会变成"老"事务）。

## NOWAIT / SKIP LOCKED 语义深入

`NOWAIT` 与 `SKIP LOCKED` 看起来相似，但语义截然不同：

| 行为 | 普通 FOR UPDATE | NOWAIT | SKIP LOCKED |
|------|----------------|--------|-------------|
| 遇到锁定行 | 等待至超时 | 立即返回错误 | 跳过该行，继续返回其他行 |
| 适用场景 | 一致性读取后修改 | 实时性要求高的失败快速 | 工作队列 (worker pool) |
| 错误码 (PG) | -- | 55P03 lock_not_available | 不报错 |

### PostgreSQL 9.5+ 实现

```sql
-- 经典工作队列消费模式
WITH next_job AS (
    SELECT id FROM job_queue
    WHERE status = 'pending'
    ORDER BY created_at
    FOR UPDATE SKIP LOCKED
    LIMIT 1
)
UPDATE job_queue
SET status='processing', worker_id = pg_backend_pid()
FROM next_job
WHERE job_queue.id = next_job.id
RETURNING job_queue.*;
```

10 个 worker 同时运行此查询，每个会取到不同的 job——`SKIP LOCKED` 自动绕开其他 worker 已锁定的行，无需任何额外协调。

### Oracle 11g+

```sql
-- Oracle 的 SKIP LOCKED 同样是工作队列首选
SELECT * FROM job_queue
WHERE status='READY'
ORDER BY priority
FOR UPDATE SKIP LOCKED;

-- WAIT n 是中间路线：不立即放弃，但有上限
SELECT * FROM accounts WHERE id = 1 FOR UPDATE WAIT 5;
```

### SQL Server READPAST

SQL Server 没有原生 SKIP LOCKED 关键字，但 `READPAST` table hint 提供等价语义：

```sql
SELECT TOP 1 * FROM job_queue WITH (UPDLOCK, READPAST)
WHERE Status = 'Pending'
ORDER BY CreatedAt;

-- 注意：READPAST 仅跳过行锁/页锁，不能跳过表锁
-- 必须配合 ROWLOCK 或允许细粒度锁
```

## 死锁检测算法：Wait-For Graph vs Timeout

### Wait-For Graph (WFG) 方法

**节点**：活动事务；**边**：T1 → T2 表示 T1 正在等待 T2 释放某把锁。死锁存在当且仅当 WFG 中存在环路。

实现可分两类：

- **即时检测** (eager)：每次锁等待发生时立即更新图并 DFS 查环。优点是发现快、延迟低；缺点是开销 O(n) 每次锁请求。代表：MySQL InnoDB。
- **延迟检测** (lazy)：等待 T 时间后才构图，默认假设大部分等待会自然解除。代表：PostgreSQL（`deadlock_timeout` 1s）、Oracle（每 3s 扫描）、SQL Server（每 5s 扫描）。

### Timeout-Only 方法

不显式检测死锁，仅设置锁等待超时，到期则失败。优点是实现极简，无需维护 WFG；缺点是无法区分"长时间等待"和"真死锁"，且超时时间难调（设短了误杀，设长了死锁恢复慢）。代表：早期 SQLite、HSQLDB MVCC 模式、部分嵌入式数据库。

### 分布式死锁检测的难题

在分布式数据库中，全局 WFG 构建代价高昂——节点之间需要交换锁等待信息。三种解法：

1. **集中式**：选举一个协调节点收集全局信息（TiDB 的 PD 模式）
2. **基于时间戳的避免**：用 wound-wait 或 wait-die 保证 WFG 无环（Spanner）
3. **优先级 + push txn**：放弃全局视图，依靠优先级单调推进（CockroachDB）

## 关键发现

1. **行锁体系是 OLTP 数据库的标志**。完整的行锁 + 意向锁 + 多模式表锁体系几乎只存在于传统 OLTP 引擎（PostgreSQL、Oracle、SQL Server、DB2、MySQL InnoDB、SAP HANA）。云数仓与计算引擎普遍只在表级粗粒度协调，依靠 MVCC 或乐观并发处理冲突。

2. **Oracle 永不升级行锁，是独一无二的设计选择**。SQL Server 在 ~5000 行处升级，DB2 根据 LOCKLIST 内存触发，PostgreSQL 完全不升级行锁（但因行锁存于行头部不消耗共享内存，无需升级）。Oracle 是唯一将"无升级"作为正式承诺的商业引擎，代价是行锁元数据存于数据块 ITL 中，每个数据块的 ITL 槽位有限。

3. **PostgreSQL 的 `deadlock_timeout` 是延迟检测的代表**。1 秒延迟表示：等待不到 1 秒的事务永远不会触发死锁检测（避免了大部分短锁竞争场景的开销）。InnoDB 走相反路线——即时检测，低延迟但高 CPU。

4. **SQL Server 的锁升级阈值约 5000 行**。这个数字是经过权衡的：低于该值时锁元数据开销可接受，超过则升级以保护内存。通过 `ALTER TABLE ... SET (LOCK_ESCALATION = DISABLE)` 可禁用，但会增加锁内存压力。

5. **InnoDB 的 next-key lock 是为 REPEATABLE READ 防幻读而生**。它不是单纯的行锁，而是 "record + gap" 组合锁，会锁定索引区间。这也是为什么 MySQL 的 REPEATABLE READ 在等价测试中比 PostgreSQL 更"严格"——它阻止了其他事务的插入，而 PostgreSQL 在 REPEATABLE READ（其实是快照隔离）下允许并发写入但通过快照屏蔽。

6. **SKIP LOCKED 把数据库变成消息队列**。PostgreSQL 9.5、Oracle 11g、SQL Server (READPAST)、MySQL 8.0 全部支持这一语义。在云原生时代以前，SKIP LOCKED + UPDATE...RETURNING 是无 Kafka/RabbitMQ 部署下最简的工作分发方式，至今在中等规模任务调度中仍是首选。

7. **CockroachDB 用优先级队列代替了 wait-for graph**。这是分布式场景的妥协：构建全局 WFG 需跨节点同步锁状态，代价过高。优先级 + push txn 不需要全局视图，只需局部决策即可单调收敛。代价是低优先级事务可能反复被中止。

8. **TiDB 的悲观锁是 MySQL 兼容的关键**。原生乐观事务模型在大量 UPDATE 冲突场景下重试率高，难以承载 OLTP 工作负载。3.0 引入悲观锁后，TiDB 才真正具备 MySQL 替代品的能力，且实现了集中式分布式死锁检测器。

9. **Google Spanner 的 wound-wait 让死锁检测变得不必要**。算法保证 WFG 永远无环——这是用静态规则替代动态检测的典范。代价是新事务可能被反复 wound，但因为重启后保留原始时间戳，最终能成为"最老"事务获得通过。

10. **Snowflake、BigQuery、ClickHouse 等代表"无锁哲学"**。它们用不可变存储 + MVCC + 乐观重试替代了所有传统锁机制。在 OLAP 场景下这是合理的——读多写少、批量更新、追加为主。但代价是无法支持点更新热点（同一行高频并发写入），这也是为什么这些引擎都不适合 OLTP。

11. **PostgreSQL 咨询锁是被低估的应用层工具**。bigint 键空间允许任意 hash 字符串成键，`pg_try_advisory_lock` 是非阻塞的，事务级版本自动释放——是分布式定时任务、单实例 leader 选举、限流器的优雅实现。MySQL 的 `GET_LOCK` 自 5.7.5 起升级为实例级（之前是会话级），但仍只支持字符串键。

12. **`lock_timeout` 与 `deadlock_timeout` 是不同的事**。前者限制单次锁等待的最大时长（防止业务 hang 死），后者控制何时触发死锁检测（性能调优旋钮）。生产环境通常都会把 `lock_timeout` 设为几秒到几十秒——0（无限等待）虽是默认，但在线上几乎总会引发问题。

13. **SQLite 的"无死锁"是因为整库一把写锁**。任意写事务都需要先获取数据库级 RESERVED 锁，最多升级为 EXCLUSIVE 锁。同时只有一个写事务能进行——根本没机会形成环路。代价是写并发为 1，这也是 SQLite 不适合多写场景的根本原因。WAL 模式略有改善，但写仍是串行化的。

14. **流处理引擎 (Flink、Materialize、RisingWave) 完全不参与锁讨论**。它们的状态由检查点 (checkpoint) + 状态后端管理，输入是不可变事件流，没有"事务读后写"的概念，因此无锁。这是数据库与流处理在并发模型上的根本鸿沟。

15. **DB2 的 LOCKLIST + MAXLOCKS 是显式锁内存预算**。这是少数将锁内存作为可配置资源直接暴露的数据库——DBA 必须按工作负载调整 LOCKLIST 大小（DB2 9.5+ 支持 `AUTOMATIC` 自调），否则锁升级会频繁触发，导致性能不可预期。
