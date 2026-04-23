# 分布式事务 (Distributed Transactions: XA and 2PC)

两阶段提交 (Two-Phase Commit, 2PC) 是分布式数据一致性的基石，也是分布式系统的梦魇——它让多个独立的资源管理器就一个事务达成共识，又在任何一个参与者崩溃时让整个事务陷入"不确定"状态。三十多年来，从 X/Open XA 到 Google Percolator，从 Oracle RAC 到 Spanner TrueTime，每一代分布式数据库都在重写 2PC 的答卷。

## X/Open XA 规范 (1991)

X/Open (现 The Open Group) 在 1991 年发布 **XA 规范** (Distributed Transaction Processing: The XA Specification, 1991 年 10 月)，后来被 **ISO/IEC 14834:1996**（Information technology — Distributed Transaction Processing — The XA Specification）正式采纳为国际标准。XA 定义了 **事务管理器 (Transaction Manager, TM)** 与 **资源管理器 (Resource Manager, RM)** 之间的接口。

```
 ┌──────────────┐    xa_start / xa_end      ┌────────────────┐
 │              │ ◄───────────────────────► │                │
 │ Transaction  │    xa_prepare             │ Resource       │
 │ Manager (TM) │ ◄───────────────────────► │ Manager (RM)   │
 │              │    xa_commit / xa_rollback│ (Database)     │
 │              │ ◄───────────────────────► │                │
 └──────────────┘    xa_recover             └────────────────┘
```

XA 协议的两阶段提交核心接口：

```c
int xa_start(XID *xid, int rmid, long flags);    // 开启分支事务
int xa_end(XID *xid, int rmid, long flags);      // 结束数据操作
int xa_prepare(XID *xid, int rmid, long flags);  // 阶段 1: 准备
int xa_commit(XID *xid, int rmid, long flags);   // 阶段 2: 提交
int xa_rollback(XID *xid, int rmid, long flags); // 阶段 2: 回滚
int xa_recover(XID *xids[], long count, int rmid, long flags); // 恢复悬挂事务
int xa_forget(XID *xid, int rmid, long flags);   // 遗忘
```

标准 SQL 中映射为 `XA` 语句族 (MySQL/MariaDB/Oracle)：

```sql
-- 阶段 0: 开启 XA 事务
XA START 'global_txn_id';
INSERT INTO orders(id, amount) VALUES (1001, 99.99);
UPDATE inventory SET qty = qty - 1 WHERE sku = 'A';
XA END 'global_txn_id';

-- 阶段 1: 准备 (所有 RM 投票)
XA PREPARE 'global_txn_id';

-- 阶段 2: 协调者决定
XA COMMIT 'global_txn_id';
-- 或
XA ROLLBACK 'global_txn_id';

-- 恢复: 列出所有已 PREPARE 但未完成的事务
XA RECOVER;
```

## 支持矩阵（综合）

### XA / 2PC 基础支持

| 引擎 | XA SQL 语法 | JTA/XAResource | MSDTC | PREPARE TRANSACTION | 悬挂恢复 | 集群内部 2PC | 外部协调者 | 版本 |
|------|------------|----------------|-------|---------------------|---------|-------------|-----------|------|
| Oracle | 是 (DBMS_XA) | 是 (OCI XA) | 是 | -- | 是 | RAC 内部 | 支持 | 7+ |
| SQL Server | 是 (BEGIN DISTRIBUTED TRAN) | 是 | 原生集成 | -- | 是 | AlwaysOn | 需 MSDTC | 7.0+ |
| MySQL (InnoDB) | 是 | 是 (Connector/J) | 部分 | -- | 是 | Group Replication | 支持 | 5.0+ (2005) |
| MariaDB | 是 | 是 | 部分 | -- | 是 | Galera (非 XA) | 支持 | 5.1+ |
| PostgreSQL | -- | 是 (pgjdbc) | -- | 是 (8.1+) | 是 | -- | 支持 | 8.1+ (2005) |
| DB2 | 是 | 是 (全面) | 是 | -- | 是 | pureScale | 支持 | V5+ |
| SQLite | -- | -- | -- | -- | -- | -- | -- | 不支持 |
| Snowflake | -- | -- | -- | -- | -- | 内部 | -- | 不支持 |
| BigQuery | -- | -- | -- | -- | -- | 内部 | -- | 不支持 |
| Redshift | -- | -- | -- | -- | -- | 分布式提交 | -- | 不支持 |
| DuckDB | -- | -- | -- | -- | -- | -- | -- | 不支持 |
| ClickHouse | -- | -- | -- | -- | -- | 分布式协调 | -- | 不支持 |
| Trino | -- | -- | -- | -- | -- | -- | -- | 不支持 |
| Presto | -- | -- | -- | -- | -- | -- | -- | 不支持 |
| Spark SQL | -- | -- | -- | -- | -- | -- | -- | 不支持 |
| Hive | -- | -- | -- | -- | -- | -- | -- | 不支持 |
| Flink SQL | -- | 2PC sink | -- | -- | 是 (checkpoint) | 2PC sink | -- | 1.4+ |
| Databricks | -- | -- | -- | -- | -- | Delta 内部 | -- | 不支持 |
| Teradata | 是 | 是 | 是 | -- | 是 | 内部 | 支持 | V2R6+ |
| Greenplum | -- | 是 (pgjdbc) | -- | 是 (PG 继承) | 是 | 分布式 2PC | 支持 | 继承 PG |
| CockroachDB | -- | -- | -- | -- | -- | Parallel Commits | -- | 2.1+ (2018) |
| TiDB | 是 (6.2+ 测试版) | 部分 | -- | -- | 是 | Percolator 2PC | 有限 | 6.2+ |
| OceanBase | 是 | 是 | -- | -- | 是 | 内部 2PC | 支持 | 3.x+ |
| YugabyteDB | -- | -- | -- | 是 | 是 | DocDB 2PC | 支持 | 2.x+ |
| SingleStore | 是 (两阶段) | 部分 | -- | -- | 是 | 内部 2PC | 有限 | 7.0+ |
| Vertica | -- | -- | -- | -- | -- | 内部提交 | -- | 不支持 |
| Impala | -- | -- | -- | -- | -- | -- | -- | 不支持 |
| StarRocks | -- | -- | -- | -- | -- | 内部 2PC | -- | 不支持 |
| Doris | -- | -- | -- | -- | -- | 内部 2PC | -- | 不支持 |
| MonetDB | -- | -- | -- | -- | -- | -- | -- | 不支持 |
| CrateDB | -- | -- | -- | -- | -- | -- | -- | 不支持 |
| TimescaleDB | -- | 是 (pgjdbc) | -- | 是 (继承 PG) | 是 | -- | 支持 | 继承 PG |
| QuestDB | -- | -- | -- | -- | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | -- | -- | 内部 | -- | 不支持 |
| SAP HANA | 是 | 是 | 是 | -- | 是 | 内部 | 支持 | 1.0+ |
| Informix | 是 | 是 | 是 | -- | 是 | HDR/ER | 支持 | 7+ |
| Firebird | -- | 是 (Jaybird) | -- | -- | 部分 | -- | 支持 | 2.x+ |
| H2 | -- | 是 | -- | -- | 部分 | -- | 支持 | 1.x+ |
| HSQLDB | -- | 是 | -- | -- | 部分 | -- | 支持 | 2.x+ |
| Derby | -- | 是 | -- | -- | 是 | -- | 支持 | 10.x+ |
| Amazon Athena | -- | -- | -- | -- | -- | -- | -- | 不支持 |
| Azure Synapse | 是 (Dedicated SQL) | 是 | 是 | -- | 是 | MPP 内部 | 支持 | GA |
| Google Spanner | -- | -- | -- | -- | -- | TrueTime + 2PC | -- | 不支持 |
| Materialize | -- | -- | -- | -- | -- | -- | -- | 不支持 |
| RisingWave | -- | -- | -- | -- | -- | -- | -- | 不支持 |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | -- | -- | 不支持 |
| DatabendDB | -- | -- | -- | -- | -- | 内部 | -- | 不支持 |
| Yellowbrick | -- | -- | -- | -- | -- | 内部 | -- | 不支持 |
| Firebolt | -- | -- | -- | -- | -- | -- | -- | 不支持 |

> 统计：约 18 个引擎支持某种形式的 XA / 2PC 外部语法，约 12 个引擎在集群内部实现 2PC 但不暴露外部接口，约 20 个引擎完全拒绝分布式事务。

### 2PC 技术分类

| 类别 | 代表引擎 | 协议 | 协调者 | 延迟影响 |
|------|---------|------|--------|---------|
| 经典 XA (外部协调) | Oracle, MySQL, SQL Server, DB2, PostgreSQL | X/Open XA | 外部 TM | 2-3× 单机 |
| MPP 内部 2PC | Greenplum, Azure Synapse, Teradata | 内部 | QD/主节点 | 同步阻塞 |
| Percolator 2PC | TiDB, (部分 YugabyteDB) | Google Percolator (OSDI 2010) | 去中心化 | 2 RTT |
| Parallel Commits | CockroachDB (2.1+) | 优化 2PC + 并行 | Gateway 节点 | 1 RTT |
| TrueTime 2PC | Google Spanner | Paxos + 2PC + TrueTime | Paxos Leader | 2 RTT + 等待不确定 |
| Checkpoint 2PC | Flink | 两阶段 sink | JobManager | 检查点周期 |
| 拒绝 2PC | Snowflake, BigQuery, DuckDB | N/A | N/A | 无分布式事务 |

### 编程接口支持

| 接口标准 | 引擎支持 | 典型库 |
|---------|---------|-------|
| X/Open XA C API | Oracle OCI, DB2, SQL Server, Informix, HANA | `xa_switch_t` |
| Java JTA (JSR 907) | 大部分主流引擎 | `javax.transaction.xa.XAResource` |
| Jakarta JTA 2.0 | 现代 JDBC 驱动 | `jakarta.transaction.xa.XAResource` |
| .NET System.Transactions | SQL Server 原生 | `TransactionScope` + MSDTC |
| MSDTC (COM) | SQL Server, Oracle (with OraMTS) | `ITransactionCoordinator` |
| Tuxedo ATMI | Oracle Tuxedo + 多数据库 | 早期企业中间件 |

## 经典 XA 协议生命周期深入

### 两阶段提交的完整时序

```
           Client          Coordinator          RM1              RM2
             │                 │                 │                 │
             │─ begin() ──────►│                 │                 │
             │                 │─ xa_start(xid) ►│                 │
             │                 │─ xa_start(xid) ──────────────────►│
             │◄── OK ──────────│                 │                 │
             │                 │                 │                 │
             │─ do_work() ────►│                 │                 │
             │                 │─ SQL ope ──────►│                 │
             │                 │─ SQL ope ──────────────────────── ►│
             │                 │                 │                 │
             │─ commit() ─────►│                 │                 │
             │                 │─ xa_end(xid) ──►│                 │
             │                 │─ xa_end(xid) ──────────────────── ►│
             │                 │                                   │
   Phase 1:  │                 │─ xa_prepare ──► (write PREPARE    │
             │                 │                  record to WAL,   │
             │                 │                  acquire locks)   │
             │                 │◄── VOTE YES ────│                 │
             │                 │─ xa_prepare ─────────────────────►│
             │                 │◄── VOTE YES ──────────────────────│
             │                 │                                   │
             │   (Coordinator writes COMMIT decision to log)       │
             │                                                     │
   Phase 2:  │                 │─ xa_commit ────►(write COMMIT)    │
             │                 │─ xa_commit ──────────────────────►│
             │                 │◄── OK ──────────│                 │
             │                 │◄── OK ────────────────────────────│
             │◄── OK ──────────│                                   │
```

### 关键不变量

1. **持久化先于投票**：RM 返回 VOTE YES 之前，必须将 UNDO/REDO 日志落盘，保证崩溃后可重新提交。
2. **决定点单一**：协调者写入 COMMIT 决定的瞬间就是事务的"提交点"，此后无法回滚。
3. **阻塞性**：RM 在 PREPARE 和决定到达之间持有锁，如果协调者崩溃，RM 进入"不确定 (in-doubt)"状态。
4. **幂等性**：xa_commit / xa_rollback 必须可重复调用，应对消息重传。
5. **可恢复**：重启后协调者从日志恢复决定，RM 通过 xa_recover 报告悬挂事务。

### 悬挂事务恢复

```sql
-- MySQL 重启后，管理员可查看所有悬挂 XA 事务
XA RECOVER CONVERT XID;
-- 输出 formatID, gtrid_length, bqual_length, data
-- 管理员必须决定: XA COMMIT 还是 XA ROLLBACK

-- Oracle: 查询悬挂事务
SELECT LOCAL_TRAN_ID, GLOBAL_TRAN_ID, STATE
FROM DBA_2PC_PENDING
WHERE STATE IN ('prepared', 'collecting');

-- PostgreSQL: 查询已 PREPARE 事务
SELECT * FROM pg_prepared_xacts;
COMMIT PREPARED 'some_global_txn_id';  -- 或 ROLLBACK PREPARED
```

## 各引擎 XA / 2PC 详解

### Oracle — 企业级 XA 标杆

Oracle 自 v7 起完整支持 X/Open XA，是唯一在所有平台、所有中间件上都被验证过的 XA 实现。OCI XA 库 (`oraxa.h`) 是 Tuxedo、WebLogic、WebSphere 等中间件的标准后端。

```sql
-- PL/SQL 包 DBMS_XA 提供编程接口
DECLARE
    xid_val DBMS_XA_XID := DBMS_XA_XID(101, HEXTORAW('01020304'), HEXTORAW('05060708'));
    rc PLS_INTEGER;
BEGIN
    rc := DBMS_XA.XA_START(xid_val, DBMS_XA.TMNOFLAGS);

    UPDATE accounts SET balance = balance - 100 WHERE id = 1;

    rc := DBMS_XA.XA_END(xid_val, DBMS_XA.TMSUCCESS);
    rc := DBMS_XA.XA_PREPARE(xid_val);
    rc := DBMS_XA.XA_COMMIT(xid_val, FALSE);
END;
/

-- 悬挂事务恢复
SELECT * FROM DBA_2PC_PENDING;
ROLLBACK FORCE 'transaction_id';
-- 或
COMMIT FORCE 'transaction_id';
```

Oracle RAC 在集群内使用 **Cache Fusion + 内部分布式提交协议**，RAC 实例之间不需要走外部 XA。多 Oracle 实例之间或 Oracle-DB2 之间才需要 XA。

### SQL Server — MSDTC 原生集成

SQL Server 是 Windows 生态里唯一与 MSDTC (Microsoft Distributed Transaction Coordinator) 深度集成的 RDBMS。在 .NET 中使用 `TransactionScope` 自动晋升为分布式事务：

```sql
-- T-SQL 语法
BEGIN DISTRIBUTED TRANSACTION;
    INSERT INTO LocalDB.dbo.orders VALUES (1, 100);
    INSERT INTO LINKED_SERVER.RemoteDB.dbo.inventory VALUES (1, 100);
COMMIT TRANSACTION;
```

```csharp
// .NET 代码
using (var scope = new TransactionScope())
{
    conn1.ExecuteNonQuery("INSERT INTO db1.orders ...");
    conn2.ExecuteNonQuery("INSERT INTO db2.inventory ...");
    scope.Complete();  // 触发 MSDTC 2PC
}
```

**集群 DTC (Cluster DTC)**: SQL Server AlwaysOn 集群中，DTC 资源被集群化，协调者的故障切换依赖 Windows Failover Cluster。MSDTC 的日志存储在共享磁盘上。

### MySQL InnoDB — 迟来的 XA 支持

MySQL 5.0 (2005 年) 引入 XA 支持，但有一个**严重的历史 bug** (MySQL Bug#12161): XA PREPARE 后，若主库崩溃，binlog 与 InnoDB redo log 会不一致，导致从库复制出错。

```sql
-- MySQL XA 语法
XA START 'xid1';
INSERT INTO t1 VALUES(1);
XA END 'xid1';
XA PREPARE 'xid1';
XA COMMIT 'xid1';

-- 5.7 之前的 bug:
-- PREPARE 的事务写入 binlog 但未 COMMIT 时主库崩溃
-- 重启后事务不在 binlog 中，但从库可能已经收到
-- 导致主从数据不一致
```

**5.7.7 (2015) 修复**：引入"两阶段 binlog"机制，XA PREPARE 时先写 binlog 作为 PREPARE 事件，XA COMMIT 时再写 COMMIT 事件，保证主从一致。

**Group Replication** (5.7.17+) 内部使用 Paxos 变种 (XCom) 达成共识，不依赖外部 XA。

### MariaDB — 分叉的演进

MariaDB 继承 MySQL 的 XA 语法，但演进路径分叉：

- MariaDB 10.3+ 修复了 MySQL 5.7 同样的 binlog bug
- Galera Cluster 使用 **基于认证的复制 (certification-based replication)**，**不使用** 2PC
- 跨 MariaDB 实例仍需外部 XA 协调者

### PostgreSQL — PREPARE TRANSACTION

PostgreSQL 8.1 (2005 年) 引入 `PREPARE TRANSACTION` 语法，不提供 `XA` 关键字但功能等价：

```sql
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
PREPARE TRANSACTION 'xact_foo_42';
-- 此时事务已持久化但未提交，连接可断开

-- 稍后由协调者决定
COMMIT PREPARED 'xact_foo_42';
-- 或
ROLLBACK PREPARED 'xact_foo_42';

-- 查询悬挂
SELECT * FROM pg_prepared_xacts;
```

**注意事项**：
- `max_prepared_transactions` 参数必须 > 0 (默认 0, 即禁用)
- 悬挂事务长时间不清理会占用 WAL 和锁资源
- pgjdbc 驱动完整实现 JTA `XAResource`

**Greenplum / Citus** 等基于 PG 的 MPP 系统在分布式 COMMIT 时内部使用 PREPARE TRANSACTION 实现跨节点一致性。

### DB2 — 企业 XA 全面支持

DB2 是 XA 规范的早期合作者之一。支持：

- XA C API (`db2xa_switch` structure)
- JDBC Type 4 `XADataSource`
- WebSphere MQ、CICS、IMS 原生集成
- TPF (Transaction Processing Facility) 主机级事务

```sql
-- DB2 XA 恢复
LIST INDOUBT TRANSACTIONS WITH PROMPTING;
COMMIT INDOUBT TRANSACTION 'xid_hex';
FORGET INDOUBT TRANSACTION 'xid_hex';
```

### TiDB — Percolator 2PC

TiDB 内部实现 Google **Percolator 协议** (OSDI 2010 论文)，这是 Spanner 之前 Google 用于更新搜索索引的分布式事务协议。

**核心设计**：基于底层 KV (TiKV) 的 **MVCC + 两阶段写入**，协调者去中心化 (分布在 gateway 节点)：

```
Phase 1 - Prewrite:
  1. Client 选择一个 key 作为 Primary Key
  2. 对所有涉及的 key 写入 "lock" 列，指向 primary
  3. 对所有涉及的 key 写入 "data" 列，但未提交

Phase 2 - Commit:
  1. Commit primary key: 写入 "write" 列 (commit_ts)，清除 lock
  2. 对其他 key 异步 commit
  3. 任何读操作若遇到未完成的 lock，可追溯 primary 的状态自行决定提交或回滚
```

TiDB 从 6.2 开始在实验层面提供 `XA` 语法，但其内部事务仍基于 Percolator，对 Java 应用通过 Connector/J 有限支持 JTA。

### CockroachDB — Parallel Commits (2018)

CockroachDB 2.1 (2018) 引入 **Parallel Commits** 协议，将提交延迟从 2 RTT 降到 1 RTT：

```
传统 2PC:            Parallel Commits:
  1. Prepare (RTT 1)    1. 并行写所有 intent + transaction record (RTT 1)
  2. Commit   (RTT 2)    2. 客户端立即确认 (后台异步 resolve intents)
```

关键创新：事务记录以 **STAGING** 状态写入，包含所有参与 range 的 ID。后续读到 intent 的事务可以根据 STAGING 记录自行 "隐式提交" 判定。CockroachDB **不暴露 XA 接口**——团队明确认为外部 XA 协调者与其分布式模型冲突。

### Google Spanner — TrueTime + 2PC

Spanner (OSDI 2012 论文) 使用 **TrueTime API** 结合 **Paxos 复制 + 2PC**：

```
跨 Paxos Group 事务:
  1. Coordinator Paxos Leader 收到 2PC 请求
  2. 每个 Participant Paxos Group 内部: Paxos commit
  3. 2PC Prepare: 每个 participant 报告 prepare timestamp
  4. Coordinator 选择 commit_ts = max(prepare_ts) + ε
  5. Wait out uncertainty: 必须等到 TT.after(commit_ts) = true
  6. 2PC Commit: 广播给所有 participants

TrueTime: TT.now() 返回 [earliest, latest] 区间
  由 GPS + 原子钟保证 |latest - earliest| < 7ms
  等待不确定性确保全局事务外部一致性 (external consistency)
```

Spanner **不支持外部 XA**，所有事务都是内部分布式事务，对 SQL 用户透明。

### YugabyteDB — DocDB + 2PC

YugabyteDB 架构：PostgreSQL API (YSQL) 层 + DocDB 分布式 KV 层。事务协议借鉴 Spanner 和 Percolator：

- **Single-shard transactions**: 单 shard 内部用 Raft
- **Distributed transactions**: 跨 shard 用 **Hybrid Logical Clock (HLC)** + 2PC
- 继承 PostgreSQL 的 `PREPARE TRANSACTION` 语法
- 有 **Transaction Status Table** 作为去中心化协调状态

### Snowflake / BigQuery — 明确拒绝 XA

云原生 OLAP 引擎明确不支持 XA：

- **Snowflake**: 文档明确说明不支持分布式事务协调，只保证单仓库内事务原子性
- **BigQuery**: 多语句事务 (2021 年 GA) 仅限单项目，无跨服务 XA
- **Redshift**: 集群内部有分布式提交，但不暴露 XA 语法

**为何拒绝**？详见后文专题。

### Flink SQL — 2PC Sink

Flink 的 "2PC" 指 **Two-Phase Commit Sink**，配合 checkpoint 机制实现 exactly-once 语义：

```java
public class MyTwoPhaseCommitSink extends TwoPhaseCommitSinkFunction<T, TXN, CTX> {
    protected void invoke(TXN transaction, T value, Context ctx) { ... }
    protected TXN beginTransaction() { ... }
    protected void preCommit(TXN tx) { /* phase 1 */ }
    protected void commit(TXN tx) { /* phase 2, at checkpoint complete */ }
    protected void abort(TXN tx) { ... }
}
```

Kafka Sink (事务型 Producer)、JDBC Sink (XA) 都走这个框架。**协调者是 Flink JobManager**，checkpoint 完成等同于 2PC 决定点。

## Percolator 2PC 深度剖析

Google Percolator (2010) 是第一个在 **无中心协调者** 的前提下实现跨行 ACID 事务的协议。TiDB、一些 YugabyteDB 场景、CockroachDB (部分借鉴) 都采用其思想。

### 三列模型

底层 KV 中，每个 key 存储三个列：

```
Lock Column:   lock information (primary pointer, timestamp)
Write Column:  commit timestamp → data version
Data Column:   data values indexed by start timestamp
```

### 乐观事务全过程

```
初始状态:
  row1: lock=<empty>, write=(ts=10→v1), data=(ts=10→v1)
  row2: lock=<empty>, write=(ts=10→u1), data=(ts=10→u1)

事务 T 开始: start_ts = 15

Phase 1 - Prewrite:
  1. 选 row1 为 primary
  2. 对 row1:
     读 write 列最新版本 = 10 < 15, OK
     写 lock=(primary=row1, ts=15)
     写 data(ts=15, v2)
  3. 对 row2:
     写 lock=(primary=row1, ts=15)  ← 指向 primary
     写 data(ts=15, u2)

中间状态:
  row1: lock=(primary, 15), write=(10→v1), data=(10→v1, 15→v2)
  row2: lock=(→row1, 15),   write=(10→u1), data=(10→u1, 15→u2)

Phase 2 - Commit: commit_ts = 16
  1. 先 commit primary (row1):
     写 write=(ts=16→v2 @ start_ts=15)
     删除 lock
  2. 再 commit secondary (row2):
     写 write=(ts=16→u2 @ 15)
     删除 lock

最终状态:
  row1: lock=empty, write=(10→v1, 16→v2), data=(10→v1, 15→v2)
  row2: lock=empty, write=(10→u1, 16→u2), data=(10→u1, 15→u2)
```

### 故障恢复的精妙之处

如果事务 T 在 primary commit 后、secondary commit 前崩溃：

```
row1: 已提交 (write 列有 ts=16)
row2: 仍处于 locked 状态, 指向 primary row1

事务 T' 读到 row2 时:
  发现 lock, 检查 primary = row1
  发现 row1.write 有 ts=16 → T 已提交
  T' 帮助 T 完成: 写 row2.write=16, 删除 row2.lock
  (任何读者都能推动恢复, 无需专门协调者)
```

如果 T 在 primary commit 前崩溃：

```
row1 和 row2 都处于 locked 状态

事务 T' 读到 row2.lock 后:
  检查 primary = row1
  row1.lock 仍然存在, write 无 ts=16
  判断 T 已失败 (超时或主动清理)
  T' 回滚: 删除 row2.lock, 丢弃 data(ts=15)
```

### TiDB 对 Percolator 的改进

1. **Parallel Commit** (3.0+): 减少一个 RTT，类似 CockroachDB
2. **Large Transaction**: 支持百万行级事务
3. **Async Commit** (5.0+): commit_ts 由 primary 动态计算，降低延迟
4. **Pessimistic Mode**: 悲观锁模式，避免热点 write-write 冲突

## Spanner TrueTime 深度剖析

Spanner 的核心创新是 **解决全球分布式 ACID 的时钟问题**。传统的逻辑时钟 (Lamport, Vector) 只能提供事件因果序，无法提供跨节点的"外部一致性"。

### 外部一致性 (External Consistency) 的定义

"如果事务 T1 的 commit 在现实世界时间上早于 T2 的 begin，那么 T1 的 commit_ts < T2 的 commit_ts。"

这比线性一致性更强——它要求 **系统的逻辑时序与物理时序一致**。

### TrueTime API

```
TT.now() → [earliest, latest]
  保证: 真实的当前时间 ∈ [earliest, latest]
  区间长度 ε 由底层基础设施保证 < 7ms

TT.after(t)  → bool (真实时间是否已经过了 t)
TT.before(t) → bool
```

实现：每个数据中心部署 GPS 时钟 + 原子钟。Time master 与所有服务器同步，每 30s 回应 UDP 探测，计算漂移上界。

### 2PC with TrueTime

```
Commit Wait 协议:

1. 协调者收到 prepare votes, 选择 commit_ts:
   s = max(TT.now().latest, max(prepare_ts_i))

2. 协调者写入 COMMIT record (Paxos 复制)

3. Wait: 执行 commit_wait = 等待直到 TT.after(s) = true
         (即 s < 现实时间下界), 典型等待 2ε ≈ 14ms

4. 释放锁, 回应客户端

关键: commit_wait 保证任何 later-started 事务的 start_ts > s
      → 因果序 = 时间序 = 全局序
```

### 为什么别的系统不能抄

TrueTime 的精度 (<7ms) 依赖专用硬件 (GPS + 原子钟)。一般云环境下的 NTP 精度仅 10-100ms。为解决这个问题：

- **CockroachDB HLC (Hybrid Logical Clock)**: 组合物理时钟和逻辑计数器，但有 500ms 最大时钟偏差假设，在偏差超出时需要"重启"事务
- **YugabyteDB HLC**: 同上
- **Amazon Aurora**: 使用集中式 "redo log service" 绕过 TrueTime 问题
- **TiDB TSO**: PD 集群提供单调递增时间戳，是中心化的单点

## 为什么云原生 OLAP 拒绝 XA？

Snowflake、BigQuery、Redshift、Databricks 等云原生分析引擎明确不支持 XA。这不是功能缺失，而是架构选择。

### 1. XA 与云弹性冲突

XA 协议要求 RM 在 PREPARE 后持有锁直到 COMMIT。在自动伸缩的无服务器架构中，一个持锁的事务可能阻止节点回收：

```
传统数据库: 节点生命周期 = 服务器生命周期 (长期)
云原生引擎: 节点生命周期 = 查询周期 (秒-分钟)

XA 事务可能跨越多个节点重启, 悬挂锁污染持久层
```

### 2. 分析负载不需要 ACID 写协调

OLAP 的典型工作负载是 **批量写 + 海量读**。ETL 作业的"事务"是 **整个 ETL 流水线级** 的，不是 SQL 语句级的。失败后重跑整个作业远比协调 XA 悬挂事务简单。

### 3. Storage-Compute 分离改变了游戏规则

```
传统 RDBMS:       共享磁盘 + 紧耦合节点 → XA 有意义
Snowflake:       共享 S3/ADLS + 无状态计算 → 事务 = 对象存储的版本化
Databricks:      Delta Lake + ACID via file rename + MVCC
BigQuery:        Colossus + snapshot isolation via metadata
```

元数据层面的**版本化 + 快照隔离** 天然实现了 ACID，不需要 XA。

### 4. 现代微服务偏好替代方案

| 方案 | 原理 | 适用场景 |
|------|------|---------|
| **Saga** | 一系列本地事务 + 补偿动作 | 长流程业务 (订单、支付) |
| **Outbox Pattern** | 业务写 + outbox 写在同库, 异步投递消息 | 事件驱动架构 |
| **TCC (Try-Confirm-Cancel)** | 资源预留 + 二次确认 | 金融、电商 |
| **Event Sourcing + CQRS** | 事件日志作为事实, 物化视图作为状态 | 审计、时间旅行 |
| **Best-Effort 1PC** | 只让"危险资源"做最后一步 | 消息 + 数据库 |

```
Saga 示例 (订单创建):
  1. CreateOrder (Order Service) → 成功
  2. ReserveInventory (Inventory Service) → 成功
  3. ChargePayment (Payment Service) → 失败
  →  Compensate: ReleaseInventory, CancelOrder (反向执行)

相比 XA:
  + 无阻塞锁, 无悬挂事务
  + 各服务可独立演进
  - 不保证隔离性 (中间状态可见)
  - 补偿逻辑复杂度高
```

## XA 的根本性缺陷

### 阻塞问题

2PC 在协调者崩溃 + 某 RM PREPARE 完成但未收到决定时，RM 必须持锁等待人工介入或协调者恢复。**FLP 不可能性定理** 证明了异步网络中不存在非阻塞的共识协议。

### 协调者单点

传统 XA 的协调者是单点。现代方案 (如 Paxos Commit, Flexible Paxos) 用共识算法复制协调者日志，但复杂度剧增。

### 性能损耗

```
对比实验 (同等硬件, TPC-C):
  单机事务:        10,000 TPS, P99 延迟 5ms
  单数据中心 XA:   2,500 TPS,  P99 延迟 25ms  (2 额外 RTT + 同步落盘)
  跨可用区 XA:     800 TPS,    P99 延迟 80ms  (网络延迟主导)
  跨地域 XA:       100 TPS,    P99 延迟 500ms (不建议)
```

### 异构 RM 兼容性

XA 规范描述的接口简单，但不同数据库对 `xa_prepare` 的隔离级别、锁持有时机、超时处理语义有差异。在 Oracle + DB2 + MQ 混合场景下，调优 XA 成了传说级任务。

## 各引擎的隔离级别与 XA 的交互

XA PREPARE 阶段对不同引擎的隔离级别有差异化要求。RM 必须在 PREPARE 与决定之间持有至少 serializable 级别的锁，否则会破坏全局一致性。

| 引擎 | PREPARE 锁级别 | 可见性规则 | PREPARE 超时默认 |
|------|--------------|-----------|----------------|
| Oracle | Row + TX lock (SS2PL) | 其他事务看旧版本 (MVCC) | 无默认, 依赖 TM |
| SQL Server | Row / Page / Table | 默认 READ COMMITTED, 可 SNAPSHOT | 60 秒 (可配) |
| MySQL InnoDB | Row + Next-key lock | MVCC + 读视图保留到提交 | 无默认 |
| PostgreSQL | Row + predicate (SSI) | MVCC, 2PC 事务持有 snapshot | max_prepared_transactions 配额 |
| DB2 | Row / Page / Table | MVCC (CS, CS+MVCC) | TM 控制 |
| SAP HANA | Row + MVCC | MVCC | 由 TM 控制 |

### SSI 与 XA 的兼容性

PostgreSQL 9.1+ 引入的 Serializable Snapshot Isolation (SSI) 与 XA PREPARE 的交互：

```
PREPARE TRANSACTION 会暂存 predicate lock (SIREAD 锁)
直到 COMMIT PREPARED / ROLLBACK PREPARED
→ 长悬挂事务可能导致 SIREAD 锁表膨胀
→ 生产建议: 设置 PREPARE 事务的应用侧超时
```

## 中间件协调者生态

企业级 Java 应用中，外部 TM 中间件承担实际的 XA 协调：

### Atomikos (开源)

```java
// Spring Boot + Atomikos XA 配置示例
@Bean
public UserTransactionManager atomikosTransactionManager() {
    var mgr = new UserTransactionManager();
    mgr.setForceShutdown(false);
    return mgr;
}

@Bean(initMethod = "init", destroyMethod = "close")
public AtomikosDataSourceBean mysqlXaDataSource() {
    var ds = new AtomikosDataSourceBean();
    ds.setXaDataSourceClassName("com.mysql.cj.jdbc.MysqlXADataSource");
    ds.setUniqueResourceName("mysql-xa");
    // ...
    return ds;
}
```

### Narayana (JBoss / WildFly 内置)

- 完整 JTA 1.2 + JTS 实现
- 支持 XA 恢复、日志压缩、分布式故障注入
- 被 Spring Boot `spring-boot-starter-jta-narayana` 集成

### Bitronix (已不活跃，但曾广泛使用)

### 商业 TM

- **Oracle Tuxedo** (从 BEA 收购): 企业级 TP 监视器，跨平台 XA
- **IBM CICS / IMS**: 主机级 TP 监视器
- **Microsoft DTC**: Windows 原生
- **Seata** (Alibaba 开源): 针对微服务的 AT / TCC / Saga 模式

### Seata — 中国互联网的 XA 替代方案

Seata (Simple Extensible Autonomous Transaction Architecture) 是阿里巴巴在 2019 年开源的分布式事务框架，支持多种模式：

```
AT (自动补偿型): 解析 SQL 生成反向补偿 SQL, 默认隔离级别 RC
TCC (Try-Confirm-Cancel): 手写三阶段补偿
Saga: 长流程事务的状态机编排
XA: 标准 X/Open XA 协议 (1.4+ 原生支持)
```

Seata 的 **TC (Transaction Coordinator)** 是独立服务，通过 Nacos / Eureka 注册发现。相比传统 XA：

- TC 可水平扩展 (基于 Raft 或外部存储)
- 分支事务 (Branch Transaction) 与全局事务 (Global Transaction) 解耦
- 支持异构 RM (关系数据库、消息队列、缓存)

## 跨数据中心 2PC 实战

### 典型场景：同城双活架构

```
数据中心 A (Beijing):         数据中心 B (Shanghai):
  RDBMS A1 + RDBMS A2            RDBMS B1 + RDBMS B2
          ↑                              ↑
          └─────── XA Coordinator ───────┘
                   (浮动在 A / B 之间)
```

**延迟放大**：同城专线 2-3ms 延迟，2PC 至少 2 RTT → 4-6ms 延迟增加。对 TPS 高的 OLTP 系统意味着吞吐至少下降一半。

**脑裂处理**：协调者所在 DC 与另一 DC 网络隔离时：
- 协调者端：所有事务可正常决定，但对侧 RM 进入悬挂
- 对侧 RM：PREPARED 事务无法推进，必须人工恢复

**生产经验**：
- 银行系统典型采用"**最后一站**"策略：最后一个写入的资源不做 PREPARE，直接 COMMIT (Best-Effort 1PC)
- 电信 BOSS 系统：事务按业务域拆分，避免跨 DC XA
- 证券交易所：核心撮合用内存 + 事务日志 + 订阅复制，完全绕过 XA

### 跨地域 (Multi-Region) 的 XA 困境

```
US-East-1 ←→ EU-West-1 (AWS): ping ~80ms
US-East-1 ←→ AP-Northeast-1 (AWS): ping ~140ms

XA 事务 2 RTT:
  2 × 80ms = 160ms (基础)
  + fsync: 10ms × 2 = 20ms
  + 应用处理: 20ms
  = 200ms 最小延迟

TPS 上限:
  单连接: 5 TPS
  100 并发连接: 500 TPS (受锁冲突限制)
```

Spanner 和 CockroachDB 在这个场景下胜出，因为它们用 **Paxos + 2PC** 替代了经典 2PC，将协调者的共识日志复制与 2PC 协议融合，网络往返次数减少。

## XA 与现代复制机制的交互

### XA + MySQL 复制 (Binlog)

MySQL XA 的两阶段必须与 binlog 两阶段协调：

```
XA PREPARE 时:
  1. InnoDB redo log 写入 PREPARE 状态 (fsync)
  2. Binlog 写入 XA PREPARE 事件 (fsync)
  → 崩溃恢复时可通过 binlog 决定事务结局

XA COMMIT 时:
  1. InnoDB redo log 写入 COMMIT
  2. Binlog 写入 XA COMMIT 事件
  → 从库收到 XA COMMIT 事件时才应用变更

XA ROLLBACK:
  1. InnoDB 回滚
  2. Binlog 写入 XA ROLLBACK
```

从库 SQL 线程在应用 XA PREPARE 时同样需要持有锁，这会导致**从库复制延迟累积**。8.0+ 引入 `slave_parallel_type = LOGICAL_CLOCK` 以并行应用非冲突 XA 事务。

### XA + PostgreSQL Streaming Replication

PG 的 WAL-based 复制对 PREPARE TRANSACTION 更友好：

```
PREPARE TRANSACTION 在 WAL 写入 PREPARE 记录 (与 COMMIT 记录不同)
从库 replay 到 PREPARE 记录: 将事务状态设为 PREPARED
从库 replay 到 COMMIT PREPARED 记录: 实际提交
```

从库可以以 Hot Standby 模式服务读，但对处于 PREPARED 状态的行仍然看不到 (等同于主库的行为)。

### XA + Kafka Transactional Producer

Kafka 0.11+ 引入 **事务型 Producer**，可与数据库 XA 通过 "Chained Transactions" 模式配合：

```java
// 简化的 Flink Kafka Sink 使用模式:
producer.beginTransaction();
for (Record r : batch) producer.send(r);
producer.flush();
producer.commitTransaction();  // Kafka 内部 2PC

// 若配合 JDBC Sink, Flink Checkpoint 起协调作用:
//   Phase 1: 所有 sink preCommit (Kafka flush, JDBC XA PREPARE)
//   Phase 2 (checkpoint complete): 所有 sink commit
```

## 锁升级与死锁

XA 事务对锁的持有期长于本地事务 (从首次访问到 COMMIT PREPARED)。这放大了死锁概率。

### 典型死锁模式

```
事务 T1 (XA):                 事务 T2 (XA):
  UPDATE account A              UPDATE account B
  XA PREPARE                    XA PREPARE

Time 1: T1 写 A, 获得 A 的锁
Time 2: T2 写 B, 获得 B 的锁
Time 3: T1 试图写 B, 等待 B 锁
Time 4: T2 试图写 A, 等待 A 锁
Time 5: 死锁

若 T1, T2 是本地事务: 数据库检测死锁, kill 一个
若 T1, T2 是 XA 事务 + 协调者在远端:
  数据库可能检测到死锁, 但如何通知协调者?
  协调者超时机制通常很保守 (分钟级)
  → 死锁导致大量连接阻塞
```

### 缓解策略

1. **统一访问顺序**：所有事务按相同顺序访问资源 (但应用层难以强制)
2. **超时 + 重试**：XA 事务设置较短的锁等待超时 (innodb_lock_wait_timeout)
3. **悲观锁预先声明**：使用 `SELECT ... FOR UPDATE NOWAIT` 尽早失败
4. **分库分表避免跨分片**：将热点数据路由到同一分片，避免 XA

## 灾难恢复与 XA

### 备份 XA 悬挂事务的处理

全量备份时若存在 PREPARED 但未 COMMIT 的事务：

```
Oracle RMAN: 备份时快照一致, 恢复后 PREPARED 事务仍在悬挂状态
             管理员必须根据原 TM 日志决定提交/回滚

PostgreSQL pg_basebackup:
  - 在线备份包含 PREPARED 事务的 WAL 记录
  - 恢复到 PIT (Point-in-Time) 时, 需要 PITR 点前的所有 WAL
  - 超过 recovery_target 的 COMMIT PREPARED 不会被应用

MySQL 物理备份 (XtraBackup):
  - 备份时记录 LSN, PREPARED 事务在其中
  - 恢复时跳过 CRASH_RECOVERY 的 XA 事务处理
  - 需要管理员手动 XA COMMIT / XA ROLLBACK
```

### 跨数据库版本升级的 XA

从旧版本升级到新版本时，如果存在悬挂 XA 事务：

- Oracle: DBMS_XA 接口稳定，可跨版本
- MySQL 5.6 → 5.7: XA 事务需先清理再升级 (binlog 格式变化)
- PostgreSQL: `pg_prepared_xacts` 格式稳定，兼容性好

## 可观察性与调试

### 关键指标

```
xa.prepare.count                # PREPARE 调用次数
xa.prepare.duration.p99         # PREPARE 延迟 P99
xa.commit.count                 # COMMIT 调用次数
xa.rollback.count               # ROLLBACK 调用次数
xa.in_doubt.count               # 当前悬挂事务数 (关键!)
xa.recover.count                # xa_recover 调用次数
xa.lock_wait.duration.p99       # PREPARE 到 COMMIT 间锁持有时间
```

### 诊断 SQL (各引擎)

```sql
-- MySQL
XA RECOVER CONVERT XID;

-- PostgreSQL
SELECT
    gid,
    prepared,
    owner,
    database,
    EXTRACT(EPOCH FROM (NOW() - prepared)) AS held_seconds
FROM pg_prepared_xacts
ORDER BY prepared;

-- Oracle
SELECT *
FROM DBA_2PC_PENDING
WHERE STATE IN ('prepared', 'collecting', 'committed', 'forced commit', 'forced abort');

-- SQL Server (查看 DTC 协调的事务)
SELECT * FROM sys.dm_tran_active_transactions
WHERE transaction_type = 2;  -- 分布式事务
```

### 长悬挂事务告警

生产环境建议：任何 PREPARED 但持续 > 30 秒的事务触发告警。通常意味着：

- 协调者崩溃但未恢复
- 网络分区
- TM 日志损坏
- 应用 bug (忘了 commit/rollback)

## 关键发现

1. **XA 是 1991 年的标准，但至今仍是跨异构数据库事务的唯一通用方案。** Oracle、SQL Server、DB2 是三大企业级 XA 实现，都有数十年生产验证。

2. **PostgreSQL 选了不同的路线**：`PREPARE TRANSACTION` (8.1, 2005) 语法不叫 XA，但语义等价，且集成更干净。Greenplum / Citus 等基于 PG 的 MPP 系统都依赖它做分布式提交。

3. **MySQL XA 的历史 bug (Bug#12161) 直到 5.7.7 (2015) 才修复。** 这是 MySQL 在分布式事务领域落后的主要原因之一。MariaDB Galera Cluster 完全放弃 XA，走认证复制路线。

4. **Google 在 Percolator (2010) 和 Spanner (2012) 中重新定义了 2PC。** Percolator 的去中心化 2PC 被 TiDB 采用；Spanner 的 TrueTime 2PC 至今仍是跨地域强一致的金标准。

5. **CockroachDB 的 Parallel Commits (2018) 将分布式事务延迟从 2 RTT 降到 1 RTT。** 代价是 "STAGING" 状态的隐式提交语义，增加了读路径复杂度。

6. **云原生 OLAP 明确拒绝 XA。** Snowflake、BigQuery、Redshift 认为 storage-compute 分离 + MVCC 已足以解决分析场景的 ACID 需求。XA 与弹性伸缩架构冲突。

7. **微服务时代，Saga / Outbox / TCC 正在取代 XA。** 尽管它们牺牲了隔离性和即时一致性，但在服务自治、可独立演进、无阻塞锁等方面胜过 XA。

8. **分布式事务的代价 (CAP 定理的现实表现)**：
   - 单机 → 分布式：延迟至少 2×
   - 同可用区 → 跨可用区：延迟至少 5×
   - 跨可用区 → 跨地域：延迟至少 20×
   - 每增加一个 RM，协调失败概率指数增长

9. **内部 2PC (集群内) 比外部 XA (跨引擎) 普及得多。** 几乎所有分布式数据库集群内部都有 2PC 或其变种，但只有少数暴露外部 XA 接口。原因：集群内可优化网络、复用共识日志、统一故障模型。

10. **XA 的真正战场已从"通用事务协议"转向"遗留系统集成"。** 新系统用 Saga，老系统用 XA。在金融、电信、航空等既有大量 XA 中间件投资的领域，XA 还将长期存在。

## 对引擎开发者的实现建议

### 1. 2PC 协调者设计

```
核心组件:
  - Transaction Log: 持久化所有事务状态 (PREPARING / PREPARED / COMMITTED / ABORTED)
  - Participant Registry: 追踪每个事务涉及的 RM
  - Timeout Manager: 检测 PREPARE 超时, 触发全局回滚
  - Recovery Manager: 重启后扫描日志, 重发决定

关键不变量:
  1. 决定 (COMMIT / ABORT) 写入日志并 fsync 后才能发送
  2. 对所有 participants 重试直到 ACK (幂等性)
  3. 日志截断仅在所有 participants 都 forget 后
```

### 2. RM PREPARE 实现

```
PREPARE 必须原子地:
  1. 持久化所有修改到 UNDO/REDO 日志
  2. 保留所有锁 (不释放)
  3. 将 transaction state 标记为 "in-doubt"
  4. 在故障恢复时, 扫描 WAL 重建 in-doubt 事务

禁忌:
  - PREPARE 后释放任何锁 → 违反隔离性
  - 投 YES 前未 fsync → 可能导致崩溃后数据丢失
  - COMMIT 时报错 → 必须只返回成功 (已在 PREPARE 投票阶段检查过)
```

### 3. 悬挂恢复协议

```
重启序列:
  1. 读 WAL, 恢复所有已 PREPARE 但未完成的事务到 in-doubt 列表
  2. 对每个 in-doubt 事务, 尝试联系协调者查询决定
  3. 若协调者不可达, 保持 in-doubt, 提供管理员命令 (XA RECOVER)
  4. xa_forget 应仅在确认协调者已知晓决定后执行

常见 bug:
  - xa_recover 列表未去重
  - xa_rollback 悬挂事务时未清理二级索引
  - 两阶段提交与 binlog/WAL 的顺序问题
```

### 4. Percolator-style 2PC 实现要点

```
核心数据结构 (每个 key 三列):
  - data: [start_ts] → value
  - lock: [start_ts] → lock_info (primary_ptr, ttl)
  - write: [commit_ts] → start_ts  (指向 data 列的具体版本)

Prewrite 检查:
  for each key:
    - write 列最新版本 ts < start_ts (否则 write-write 冲突)
    - lock 列无其他事务 (否则冲突)
    - 写 lock, 写 data

Commit:
  - 先 commit primary (写 write, 清 lock)
  - 异步 commit secondaries

读路径冲突处理:
  - 遇到 lock.ts < read_ts:
      检查 primary, 判断 T 已提交 / 失败 / 未决
      已提交: 帮助 T 完成 (rollforward)
      失败:   清理 lock (rollback)
      未决:   超时等待或冲突报错
```

### 5. 与优化器的交互

```
1. 计划选择时需要知道是否启用 XA
   启用时: 避免优化器做跨 RM 的运行时行重排
2. 并行度: XA 事务内的并行查询共享 XID, 需保证并发控制
3. 连接池: XA 连接不能随意归还到池 (必须在事务完成后)
4. 分布式执行: 各节点独立 PREPARE, 需要全局屏障
```

### 6. 测试要点

```
正确性测试:
  - 两 RM 环境 + 故障注入: coordinator crash, RM crash, 网络分区
  - 悬挂事务恢复: 重启后 xa_recover 能列出所有未完成事务
  - 幂等性: 重复 xa_commit / xa_rollback 不应报错
  - 隔离性: PREPARE 后其他事务不能读/改对应行

性能测试:
  - XA 事务 vs 本地事务: 延迟、吞吐
  - PREPARE 阶段锁持有时长分布
  - 异常路径: 超时、网络抖动下的 P99

混沌测试:
  - 协调者崩溃后 RM 自恢复
  - RM PREPARE 成功但 COMMIT 阶段断网
  - 多 RM 间时钟漂移
```

### 7. 性能优化技巧

```
1. Presumed Abort: 协调者对 aborted 事务无需记录日志, 省一次 fsync
2. Read-Only Optimization: 只读 RM 在 PREPARE 时直接回 "read-only done"
3. 1PC Optimization: 只有一个 RM 时退化为单阶段提交
4. Group Commit: 批量 fsync 多个事务日志
5. Parallel Commits (CockroachDB 风格): 并行写 intent 和 txn record
6. Async Commit (TiDB 5.0+): 不等所有 secondaries 确认
```

### 8. 协议变体的取舍

| 变体 | 延迟 | 可靠性 | 复杂度 | 适用场景 |
|------|------|--------|--------|---------|
| 经典 2PC | 高 (2 RTT) | 阻塞 | 低 | 异构系统集成 |
| 3PC | 更高 (3 RTT) | 非阻塞 (同步网络) | 中 | 学术, 实际很少用 |
| Paxos Commit | 中 (1 RTT + Paxos) | 非阻塞 | 高 | Spanner, 跨地域 |
| Percolator 2PC | 中 (2 RTT) | 自恢复 | 中 | TiDB |
| Parallel Commits | 低 (1 RTT) | 自恢复 | 中高 | CockroachDB |
| Saga | N/A (非 ACID) | 最终一致 | 高 (业务层) | 微服务 |

## 参考资料

- X/Open XA 规范 (1991): [Distributed Transaction Processing: The XA Specification](https://pubs.opengroup.org/onlinepubs/009680699/toc.pdf)
- ISO/IEC 14834:1996 — XA 国际标准化版本（Information technology — Distributed Transaction Processing — The XA Specification）
- Java JTA: [JSR 907 - Java Transaction API](https://www.oracle.com/java/technologies/jta.html)
- Oracle: [DBMS_XA Package](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_XA.html)
- SQL Server: [Distributed Transactions](https://learn.microsoft.com/en-us/sql/relational-databases/native-client-ole-db-transactions/)
- MySQL: [XA Transactions](https://dev.mysql.com/doc/refman/8.0/en/xa.html)
- MySQL Bug#12161: XA recovery binlog inconsistency (MySQL bug tracker)
- PostgreSQL: [PREPARE TRANSACTION](https://www.postgresql.org/docs/current/sql-prepare-transaction.html)
- DB2: [XA transaction support](https://www.ibm.com/docs/en/db2/11.5?topic=managers-xa-transactions)
- Peng, Dabek, "Large-scale Incremental Processing Using Distributed Transactions and Notifications" (Percolator), OSDI 2010
- Corbett et al., "Spanner: Google's Globally-Distributed Database", OSDI 2012
- TiDB: [Percolator Optimization](https://en.pingcap.com/blog/async-commit-the-accelerator-for-transaction-commit-in-tidb-5-0/)
- CockroachDB: [Parallel Commits](https://www.cockroachlabs.com/blog/parallel-commits/)
- Garcia-Molina, Salem "Sagas", ACM SIGMOD 1987
- Gray, Lamport "Consensus on Transaction Commit" (Paxos Commit), ACM TODS 2006
- Bernstein, Hadzilacos, Goodman "Concurrency Control and Recovery in Database Systems", 1987
- Helland "Life beyond Distributed Transactions: an Apostate's Opinion" (2007)
- Flink: [Exactly-Once Two-Phase Commit](https://flink.apache.org/2018/02/28/an-overview-of-end-to-end-exactly-once-processing-in-apache-flink/)
- Spanner TrueTime: [Spanner, TrueTime and the CAP Theorem](https://research.google/pubs/pub45855/)
