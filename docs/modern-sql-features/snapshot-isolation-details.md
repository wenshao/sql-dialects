# 快照隔离的实现细节 (Snapshot Isolation Deep Dive)

一个事务只看到"开始那一刻"的数据库、另一个事务的并发修改对它完全不可见——这就是 Snapshot Isolation (SI)，它让读写不互相阻塞，是 PostgreSQL、Oracle、SQL Server (RCSI/SI)、MySQL InnoDB 一致性读、Snowflake、CockroachDB、SAP HANA、YugabyteDB 等几乎所有现代 OLTP/HTAP 引擎的并发核心。但 SI 不等于可串行化：它允许 **写偏斜 (Write Skew)**、**只读事务异常 (Read-Only Anomaly)**、**串行化幻读变种**等微妙的异常。本文深入剖析 SI、Read Committed Snapshot (RC-SI)、Serializable Snapshot Isolation (SSI) 三种变体的理论基础与各引擎的实现差异，以及 Cahill/PostgreSQL 的 SIREAD 锁与 rw-antidependency 检测。

本文聚焦 SI 的"为什么"与"怎么做"。隔离级别语义横向对比见 `transaction-isolation-comparison.md`；版本链、Read View、undo log、GC 等底层机制见 `mvcc-implementation.md`。

## SI vs Serializable：一字之差，差之千里

```
Snapshot Isolation (SI) 的直观定义:
  1. 事务 T 开始时记录一个"开始时间戳" start_ts(T)
  2. T 的所有读取看到的是 start_ts(T) 那一刻的已提交数据库状态
  3. T 的写入对其他事务不可见, 直到 T 提交
  4. 提交时做 First-Committer-Wins (FCW) 或 First-Updater-Wins (FUW) 冲突检测:
     如果 T 修改过的任何行在 [start_ts(T), commit_ts(T)] 期间
     被其他已提交事务修改过, T 被中止。

SI 的"不"保证:
  - SI 不等于 Serializable
  - SI 只防止了写-写冲突, 未防止 rw 依赖形成的环
  - 具体允许的异常: Write Skew (写偏斜), Read-Only Transaction Anomaly

Serializable 的定义:
  所有并发事务的执行结果, 必须等价于某种串行执行顺序。
  即在并发事务的冲突图 (conflict graph) 中不存在环。
```

SI 最早由 Berenson 等人 1995 年在 *A Critique of ANSI SQL Isolation Levels* 中系统定义并指出其与标准隔离级别的差异。Adya 1999 年博士论文 *Weak Consistency: A Generalized Theory and Optimistic Implementations for Distributed Transactions* 进一步形式化了基于依赖图的隔离级别定义。Cahill 等人 2008 年在 SIGMOD 论文 *Serializable Isolation for Snapshot Databases* 中提出了 SSI：在 SI 之上通过检测 rw-antidependency 的"危险结构"实现真正的可串行化——这是 PostgreSQL 9.1 (2011) 将 SERIALIZABLE 升级为真正可串行化的理论基础。

## 理论基础：从 Berenson 1995 到 Cahill 2008

### Berenson et al. 1995：A Critique of ANSI SQL Isolation Levels

ANSI SQL-92 用三种异常 (dirty read, non-repeatable read, phantom) 定义四个隔离级别。Berenson 等人指出：

```
ANSI 定义的问题:
  1. 用"不允许哪些异常"来定义隔离级别, 但异常清单不完整
  2. Phantom 的形式化定义歧义, 实际上包含更广的异常族
  3. 不考虑多版本, 偏向锁实现
  4. 忽略了 Write Skew, Lost Update 等实际会发生的异常

论文新增的异常分类:
  A5A: Read Skew
    T1 读 X, 然后读 Y; 两次读之间 T2 修改 X 和 Y 并提交
    T1 看到的 X 和 Y 来自不同时刻, 违反 X+Y 的应用层约束

  A5B: Write Skew
    T1 读 {X, Y}, 基于聚合值修改 X
    T2 读 {X, Y}, 基于聚合值修改 Y
    两个事务各自读到的聚合值都满足约束, 合起来违反约束

  Cursor Stability:
    居于 RC 和 RR 之间, 对游标当前行加共享锁, 防止 Lost Update

  Snapshot Isolation:
    介于 RR 和 Serializable 之间
    防止: Dirty Read, Non-repeatable Read, Phantom (快照中看不到新插入), Lost Update (FCW)
    允许: Write Skew, Read-Only Anomaly
```

Berenson 论文奠定了现代隔离级别讨论的基础，"Snapshot Isolation 不防 Write Skew"自此成为数据库从业者的常识。

### Adya 1999 博士论文：依赖图形式化

Adya 用事务间的依赖图 (DSG, Direct Serialization Graph) 重新定义隔离级别。依赖边分三种：

```
ww (write-write): T1 写 x 后 T2 写 x, 边 T1 -> T2
wr (write-read):  T1 写 x 后 T2 读 x, 边 T1 -> T2
rw (read-write):  T1 读 x 旧版本, T2 之后写 x (T2 不看 T1 写的版本), 边 T1 -> T2

Adya 隔离级别 (依赖图视角):
  PL-1 (= RU): 禁止 G0 (ww 环)
  PL-2 (= RC): 禁止 G1 (ww 环 + 中间回滚的 wr 边 + 传递闭包)
  PL-SI (= SI): 禁止 G-SI (起始 rw 边 + 回到 T1 形成环, 前提是 T1 commit 后 T2 start)
  PL-3 (= Serializable): 禁止任何含 rw 边形成环的 G2
```

SI 允许的"危险结构"：两条 rw 边首尾相连形成环 (Cahill 将其称为 **dangerous structure**)。这正是 SSI 算法要动态检测并中止的目标。

### Cahill 2008：Serializable Snapshot Isolation

Cahill 等人证明：若并发事务的冲突图中存在环，则该环必然包含两条相邻的 rw-antidependency 边 (即存在三个事务 T1 -rw-> T2 -rw-> T3，且 T2 commit 优先于 T1, T3 之一)。基于此定理，SSI 算法：

```
SSI 算法核心:
  1. 事务运行时, 记录每次读取到 "SIREAD" 锁 (非阻塞共享标记, 非传统锁)
  2. 当另一事务对该行执行写操作, 形成一条 rw-antidependency 边
  3. 追踪每个事务的 inConflict (入向 rw 边) 和 outConflict (出向 rw 边) 标志
  4. 若某事务同时有入向和出向 rw 边, 形成 "危险结构"
  5. 在三者中选一个中止 (PostgreSQL 通常选最晚提交者或当前事务)

特性:
  - 无需物化依赖图, 只需两个 bit per transaction
  - SIREAD "锁" 不阻塞任何事务 (纯检测用)
  - 在 SI 之上增加的开销是追踪读集合 + 冲突检测
  - PostgreSQL 9.1 (2011) 首次在主流 OLTP 中实现
```

Cahill 算法的优雅在于：既保留了 SI 的读不阻塞写、写不阻塞读的高并发优势，又通过中止部分事务实现了真正的可串行化，无需传统 S2PL 的读锁。

## 支持矩阵：SI / RC-SI / SSI

### 主流引擎默认隔离 + SI / SSI 支持 (45 引擎)

| 引擎 | MVCC | 默认级别 | SI 可用 | RC-SI | SSI (真可串行化) | 冲突检测 | 首次支持 |
|------|------|---------|---------|-------|------------------|----------|----------|
| PostgreSQL | 是 | RC | 是 (RR/SERIALIZABLE) | 否 | 是 (SERIALIZABLE, SIREAD) | FUW + SSI | 9.1 (2011) |
| MySQL (InnoDB) | 是 | RR | RR 基于 SI | 否 | 否 (SERIALIZABLE 用锁) | FCW (只对 UPDATE 行) | 5.0+ |
| MariaDB (InnoDB) | 是 | RR | RR 基于 SI | 否 | 否 | FCW | 5.0+ |
| Oracle | 是 | RC | 是 (SERIALIZABLE = SI) | 是 (默认 RC = RC-SI) | 否 | FUW | 7+ (早于 SI 命名) |
| SQL Server | 是 (行版本) | RC | 是 (SNAPSHOT 级别) | 是 (RCSI, 数据库选项) | 否 | FUW | 2005 |
| SQLite | WAL 模式 | SERIALIZABLE | WAL 下近似 SI | -- | 锁实现 | 写锁 | 3.7 (WAL) |
| DB2 | 是 | CS | 是 (CS 基于 SI) | 是 | 否 | -- | 9.7+ |
| TiDB | 是 | RR | 是 (RR = SI) | 是 (v4.0+) | 否 (映射到 RR) | FCW (Percolator) | 1.0+ |
| CockroachDB | 是 | SERIALIZABLE | 是 | 是 (v23.1+) | 是 (SSI 变体, 无 SIREAD) | 时间戳推进 + 不确定区间 | v1.0 |
| OceanBase | 是 | RC | RR 模式支持 SI | 是 (默认) | 否 | FUW | 全版本 |
| YugabyteDB | 是 | RR | 是 (RR = SI) | 是 | 是 (SERIALIZABLE) | 冲突时间戳 + PG SSI | 2.0+ |
| GaussDB | 是 | RC | 是 | 是 | 是 (继承 PG 能力) | 继承 PG | 继承 PG |
| Greenplum | 是 | RC | 是 | 否 | 是 (继承 PG 6.x+) | 继承 PG | 继承 PG |
| Snowflake | 是 | RC | 基于 SI | -- | 否 | FCW (自动中止冲突事务) | GA |
| BigQuery | 是 | SERIALIZABLE | 多语句事务用 SI | -- | 提交时冲突检测 | OCC, 乐观并发控制 | GA (多语句事务) |
| Redshift | 是 | SERIALIZABLE | 是 | -- | 是 (真正 SSI) | SSI | GA |
| Databricks (Delta) | 是 (log) | WriteSerializable | 乐观 SI | -- | WriteSerializable (近 SSI) | OCC | GA |
| Spark SQL (Iceberg/Delta) | 是 (log) | 表级 | 乐观 SI | -- | 依赖 Delta/Iceberg | OCC | GA |
| Hive (ACID) | 是 (版本文件) | SI | 是 | -- | 否 | 锁 + 事务 ID | 3.0+ |
| DuckDB | 是 | SERIALIZABLE | 单写者下等价 SI | -- | 无冲突 (单写) | 单写者序列化 | 0.3+ |
| ClickHouse | 否 (单语句原子) | N/A | -- | -- | -- | -- | -- |
| MonetDB | 是 | SERIALIZABLE | 是 (OCC SI) | -- | 乐观 SI | OCC + 提交冲突检测 | 全版本 |
| Vertica | 是 | SERIALIZABLE | 是 | -- | -- | -- | GA |
| Trino / Presto | 否 | -- | -- | -- | -- | -- | -- |
| Flink SQL | 流 | N/A | -- | -- | -- | -- | -- |
| Teradata | 锁 | SERIALIZABLE | 否 (纯锁) | -- | -- | 锁 | 全版本 |
| SingleStore (MemSQL) | 是 | RC | RC 基于 SI | 是 | 否 | -- | GA |
| SAP HANA | 是 | RC | 是 | 是 (默认) | 是 (可选 STATEMENT/REPEATABLE/SERIALIZABLE) | FCW + MVCC + 冲突检查 | 2.0+ |
| Informix | 是 / 锁 | CR | 否 (纯锁) | -- | -- | -- | -- |
| Firebird | 是 (版本) | SNAPSHOT | 是 (NOWAIT/WAIT) | -- | 否 | FCW | 1.0+ |
| H2 | 是 (MVStore) | RC | 是 (MVCC=TRUE) | -- | 否 | -- | 1.4+ |
| HSQLDB | 是 (MVCC) | RR | 是 (MVCC 下) | -- | 否 | -- | 2.0+ |
| Derby | 锁 | RC | 否 | -- | -- | -- | -- |
| Amazon Aurora (PG) | 是 | RC | 继承 PG | -- | 继承 PG | 继承 PG | 继承 PG |
| Amazon Aurora (MySQL) | 是 | RR | 继承 MySQL | -- | 否 | 继承 MySQL | 继承 MySQL |
| Azure Synapse | 是 | RC | -- | -- | -- | -- | -- |
| Google Spanner | 是 (Paxos + TrueTime) | SERIALIZABLE | 只读事务用 SI | -- | 外部一致性 (严格可串行) | 时间戳序 + 锁 | GA |
| CrateDB | 最终一致 | -- | -- | -- | -- | -- | -- |
| TimescaleDB | 是 | RC | 继承 PG | -- | 继承 PG (9.1+) | 继承 PG | 继承 PG |
| QuestDB | 单写者 | -- | -- | -- | -- | 单写者 | -- |
| Exasol | 是 | SERIALIZABLE | 是 | -- | 乐观 | 提交时冲突检测 | GA |
| StarRocks | 是 (版本) | 表级 | 版本化读 | -- | -- | -- | GA |
| Doris | 是 (版本) | 表级 | 版本化读 | -- | -- | -- | GA |
| Impala | Kudu/Iceberg | 表级 | 依赖底层 | -- | -- | -- | -- |
| Materialize | 是 (timely) | SERIALIZABLE | 是 | -- | 严格可串行 | timely dataflow | GA |

> 说明:
> - `SI` 列指 "基础的 Snapshot Isolation"；`RC-SI` 指 Read Committed 级别基于行版本实现 (非加锁) ；`SSI` 指真正可串行化、在 SI 之上增加冲突检测。
> - PostgreSQL 的 REPEATABLE READ 实际语义就是 SI；SERIALIZABLE 才是 SSI。
> - Oracle 的 SERIALIZABLE 即 SI, 不防 Write Skew (历来如此)。
> - CockroachDB 的 SERIALIZABLE 用了 SSI 变体 (时间戳 + 不确定区间) 而非 Cahill SIREAD。
> - 统计: 约 30 个引擎有 SI 基础支持, 其中约 8 个提供真正 SSI (PostgreSQL、CockroachDB、YugabyteDB、Redshift、SAP HANA 可选、Greenplum 6.x、GaussDB、Spanner 严格可串行)。

### First-Committer-Wins vs First-Updater-Wins

两种冲突检测策略是 SI 实现的经典分岔。

```
First-Committer-Wins (FCW):
  谁先提交谁赢
  冲突检测推迟到提交阶段
  后提交的事务看到读集合/写集合冲突 -> 中止

  优点: 乐观, 读阶段无锁
  缺点: 事务可能跑了很久才在提交点被中止, 浪费资源

  采用: Snowflake, MonetDB, BigQuery, CockroachDB (时间戳推进)

First-Updater-Wins (FUW):
  谁先对冲突行执行写操作谁赢
  UPDATE/DELETE 时若发现该行版本已被其他未提交事务修改, 立即等待或冲突
  若对方已提交, 当前事务中止 (SI) 或重读 (RCSI)

  优点: 冲突早发现, 不浪费计算资源
  缺点: 需要写锁或版本锁

  采用: Oracle, SQL Server SNAPSHOT, SAP HANA, MySQL InnoDB, PostgreSQL (REPEATABLE READ)
```

PostgreSQL REPEATABLE READ 实际采用 FUW 语义：UPDATE/DELETE 时若发现行版本已被并发事务修改且已提交，当前事务以 `could not serialize access` 报错中止；若并发事务未提交则等待。SSI (SERIALIZABLE) 在此基础上叠加 SIREAD 谓词锁与读写依赖图检测。FUW 让并发写冲突尽早显现，FCW 则让只读工作负载完全不受影响。

### Predicate Lock / 谓词锁

Write Skew 的根本原因是事务 T1 依赖的"集合"被 T2 通过 INSERT/UPDATE 修改。真正防止幻读/写偏斜需要**谓词锁 (Predicate Lock)**：对 `WHERE age > 60` 这样的条件加锁，而不是对特定行加锁。

```
三种谓词锁实现:
  1. 真谓词锁 (Database Systems 教科书版):
     代价巨大: 必须检查每个新 INSERT 是否匹配某个活跃事务的谓词
     实际引擎几乎不用

  2. 索引范围锁 / Next-Key Locking (MySQL InnoDB RR):
     对索引区间加锁 (锁定 key 本身 + 前一个 key 之间的 gap)
     覆盖: 索引能覆盖到的 WHERE 条件
     局限: 无索引列的 WHERE 退化为表锁或失效

  3. SIREAD 锁 (PostgreSQL SSI):
     "影子锁", 不阻塞读写, 仅用于追踪依赖
     粒度: page / tuple / relation (自适应)
     检测到危险结构时中止事务
```

InnoDB 的 Next-Key Lock 是 RR 级别防幻读的核心：`SELECT * FROM t WHERE age > 60 FOR UPDATE` 会对 age 索引 (60, +∞) 加 gap lock，阻止 INSERT age=70 的行进入。但没有索引的条件 (如 `WHERE UPPER(name) = 'ALICE'`) 退化为锁整个索引，并发极差。

PostgreSQL 的 SIREAD 锁是另一种路线：**不阻塞任何操作**，仅记录"T1 读过满足这个条件的页/元组，若后续 T2 写入满足该条件的行，形成 rw-antidependency"。代价是追踪内存 + 冲突中止，但并发度显著高于真谓词锁或 S2PL。

## 各引擎 SI 实现详解

### PostgreSQL：SI + SSI (9.1, 2011)

PostgreSQL 是主流 OLTP 中最早、最完整实现 SSI 的引擎。核心设计：

```
隔离级别映射:
  READ UNCOMMITTED -> 实际 READ COMMITTED (不允许脏读)
  READ COMMITTED   -> 默认, 每条语句新快照
  REPEATABLE READ  -> SI, 事务开始时取快照, 防脏读/不可重复读/幻读, 允许 write skew
  SERIALIZABLE     -> SSI (9.1+), 在 SI 之上用 SIREAD 锁检测 rw 依赖环

快照的数据结构 (PGPROC / pg_snapshot):
  xmin: 活跃事务中最小的 xid (小于 xmin 的 xid 都已提交或中止)
  xmax: 下一个将分配的 xid (大于等于 xmax 的修改都不可见)
  xip:  活跃事务的 xid 列表 (在 [xmin, xmax) 之间但未提交)

可见性判断 (每个元组的 xmin/xmax):
  插入该元组的 xid 必须小于快照的 xmax 且不在 xip 中 (即插入事务已提交)
  且 xid != 当前事务 -> 看到插入 (若是自己插入总是可见)
  xmax (删除/更新) 必须不可见 -> 行未被已提交事务删除
```

PostgreSQL 的 SSI 实现细节：

```c
// 伪代码, 实际在 src/backend/storage/lmgr/predicate.c

struct SERIALIZABLEXACT {
    VirtualTransactionId   vxid;
    SerCommitSeqNo         prepareSeqNo;
    SerCommitSeqNo         commitSeqNo;
    bool                   inConflict;   // 有入向 rw 边
    bool                   outConflict;  // 有出向 rw 边
    List*                  predicateLocks; // 当前持有的 SIREAD 锁
};

// 读操作
on_read(tuple):
    take_SIREAD_lock(tuple.page);  // 或 tuple 级, 自适应

// 写操作
on_write(tuple):
    for each T' holding SIREAD lock on tuple.page:
        add_rw_edge(T', self);  // T' 读过, 现在 self 写
        T'.outConflict = true;
        self.inConflict = true;
        if T'.inConflict && self.outConflict:
            abort_one_of(T', self, other);  // 危险结构!

// 提交
on_commit():
    // SSI 可能在提交前中止当前事务
    // 也可能让已标记 inConflict 的只读事务安全提交 (见 "只读优化")
```

关键特性：
- **SIREAD 锁不阻塞任何操作**：它只是内存中的标记
- **锁粒度自适应**：元组级 → 页级 → 关系级，当锁数量超过阈值时升级
- **中止选择**：PostgreSQL 通常中止"容易重试"的事务 (仍在运行、未提交的)
- **错误码**：SSI 中止的事务收到 `SQLSTATE 40001 serialization_failure`，应用层应重试

```sql
-- 应用层典型重试模板
DO $$
DECLARE
  retries INT := 0;
BEGIN
  LOOP
    BEGIN
      -- 业务事务
      ROLLBACK;  -- 或 COMMIT
      EXIT;
    EXCEPTION WHEN serialization_failure THEN
      retries := retries + 1;
      IF retries > 5 THEN RAISE; END IF;
      PERFORM pg_sleep(random() * 0.1);
    END;
  END LOOP;
END $$;
```

### Oracle：SI 先驱，SERIALIZABLE 实为 SI

Oracle 早在 1990 年代就实现了基于 undo segment 的多版本一致性读，是工业界 MVCC 的开山鼻祖之一。其 SERIALIZABLE 级别实际上是 SI，不防 Write Skew。

```
Oracle 隔离级别:
  READ COMMITTED (默认):
    语句级快照, 每条 SQL 开始时取 SCN (System Change Number)
    读一致性: 单条语句看到一致视图 (可能用 undo 回滚到 SCN)
    写操作: 读取行的最新已提交版本, 等待未提交事务

  SERIALIZABLE:
    事务级快照, 事务开始时取 SCN
    整个事务看到该 SCN 的数据库状态
    提交时, FUW 检测写集合冲突:
      若事务修改的行在 SCN 之后被其他事务提交过, 报 ORA-08177
      不防 Write Skew
```

Oracle 读一致性的核心：**SCN + Undo Segment**。每个查询记录自己的 snapshot SCN，读到一个块时检查块头的 SCN；若比自己新，用 undo segment 回滚到正确版本。长事务会导致"snapshot too old" (ORA-01555)，因为 undo 已被覆盖。

### SQL Server：RCSI (2005) + SNAPSHOT 隔离级别

SQL Server 2005 引入了两种基于行版本的级别：

```sql
-- 1. READ COMMITTED SNAPSHOT (RCSI)
--    数据库级选项, 改变 READ COMMITTED 的实现
ALTER DATABASE MyDB SET READ_COMMITTED_SNAPSHOT ON;
-- 启用后, READ COMMITTED 从加锁变为基于行版本
-- 每条语句读取最新已提交版本, 不再加共享锁

-- 2. SNAPSHOT 隔离级别 (事务级)
ALTER DATABASE MyDB SET ALLOW_SNAPSHOT_ISOLATION ON;
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRAN;
-- 事务开始时取快照, 整个事务看到同一版本
-- 提交时 FUW 检测, 冲突报错 3960
```

SQL Server 的行版本存储在 **tempdb** 的 version store 中，这是它与 PostgreSQL (tuple 内元组) 和 Oracle (undo segment) 的关键差异。启用 RCSI/SI 后 tempdb 压力上升，需要监控 `sys.dm_tran_version_store`。

SQL Server 没有实现 SSI。SERIALIZABLE 级别仍是传统 S2PL + 范围锁。

### MySQL InnoDB：一致性读 = SI

InnoDB 的"一致性非锁定读" (consistent nonlocking read) 在 RR / RC 下基于 MVCC，语义上等同于 SI：

```
InnoDB MVCC (详细见 mvcc-implementation.md):
  每行隐藏列: DB_TRX_ID (最后修改者事务 ID), DB_ROLL_PTR (指向 undo log)
  Read View: 事务开始时 (RR) 或每条语句 (RC) 记录活跃事务集合

  可见性规则:
    DB_TRX_ID < Read View.min_trx_id        -> 可见 (已提交)
    DB_TRX_ID >= Read View.max_trx_id       -> 不可见 (新事务)
    DB_TRX_ID 在活跃列表中                  -> 不可见 (未提交)
    DB_TRX_ID == 自己                       -> 可见

InnoDB RR vs 标准 SI:
  标准 SI: 不防写偏斜
  InnoDB RR: SELECT 一致读 (纯 SI), SELECT ... FOR UPDATE / UPDATE / DELETE 走当前读 + Gap Lock
  "当前读 + Gap Lock" 使 RR 实际上部分防写偏斜 (如果能通过索引锁定读集合)
```

MySQL 的 RR 因此比 PostgreSQL 的 RR (纯 SI) 更强——代价是 Gap Lock 带来的死锁和并发下降。

### CockroachDB：默认 SSI，无 SIREAD

CockroachDB 一上来就选择 SERIALIZABLE 作为默认，实现方式与 PostgreSQL 截然不同：

```
CockroachDB SSI:
  基于时间戳排序 (MVCC) + 不确定区间 (uncertainty interval)
  每个节点有 HLC (Hybrid Logical Clock), 时间戳全局近似单调

  事务 T 的时间戳 commit_ts:
    初始 = 事务开始时的本地 HLC
    读到 commit_ts 之后提交的行 -> 不在快照内
    读到 commit_ts - uncertainty 到 commit_ts 之间提交的行 -> "不确定":
      自动推进 commit_ts 到该行提交时间 (读重启, read refresh)

  冲突检测:
    写-写: 时间戳冲突, 后写者 restart
    读-写: 如果读过 key 的事务发现 key 被更晚写入, 要么推进时间戳 (可刷新 read set) 要么 abort
    rw-antidependency 环: 通过时间戳推进 + priority queue 打破
```

CockroachDB 的 SSI 没有 SIREAD 锁，改为"时间戳推进"：冲突发生时尝试把自己的提交时间戳往后推到冲突点之外，若读集合仍然有效 (re-read 一致)，事务继续；否则重启。代价是频繁重启 (通过 `retry savepoint` 机制在客户端处理)，好处是分布式下更自然 (无需全局锁管理器)。

v23.1 起 CockroachDB 也支持 READ COMMITTED 作为可选默认，与 PostgreSQL RCSI 近似。

### YugabyteDB：PG 兼容的 SSI

YugabyteDB 用 DocDB (基于 RocksDB 的分布式 KV) 实现 PG 兼容层：

```
YB 隔离级别:
  READ COMMITTED: RC-SI, 每条语句新快照
  REPEATABLE READ (默认): SI, 事务开始取 hybrid_ts
  SERIALIZABLE: 基于 lockmanager + SSI (借鉴 PG 但分布式实现)

特色:
  - 冲突检测基于 intent writes (双阶段写入)
  - 分布式下 SIREAD 锁成本高, 采用 intent + conflict timestamp
  - 默认 RR 而非 RC, 与 TiDB 一致 (兼容 MySQL 习惯)
```

### SAP HANA：MVCC + 可选 SSI

HANA 作为内存列存引擎也实现了基于 MVCC 的 SI。它支持 STATEMENT (RC) / REPEATABLE READ / SERIALIZABLE 多级，默认 RC-SI。SERIALIZABLE 使用类似 PG 的依赖检测但实现细节是专有。

### Snowflake：自动 SI，无用户旋钮

Snowflake 不暴露隔离级别旋钮，单语句/事务一律 SI (基于 FDN 存储的时间旅行特性)。写冲突由提交时自动检测，失败事务应用层重试。其存储层已按时间戳组织微分区 (micropartition)，天然适合 SI。

### MySQL vs PostgreSQL vs Oracle：RR 的三种语义

```
同样是 "REPEATABLE READ", 三家语义迥异:

MySQL InnoDB RR (默认):
  一致读 = 标准 SI
  当前读 (FOR UPDATE / DML) + Next-Key Lock -> 防幻读
  实际: 接近 Serializable 但允许 Write Skew (一致读部分)
  常见陷阱: 一致读和当前读混用导致行为怪异

PostgreSQL RR:
  纯 SI, 无 Gap Lock
  允许 Write Skew 和所有 rw-antidependency 异常
  若需真可串行, 用 SERIALIZABLE (SSI)

Oracle:
  没有 REPEATABLE READ, 跳过 SQL 标准的此级别
  SERIALIZABLE 实际是 SI
  等价行为需用 SERIALIZABLE 或应用层 SELECT ... FOR UPDATE
```

## SSI 深度剖析：Cahill/PostgreSQL 视角

### 危险结构 (Dangerous Structures)

Cahill 的核心定理：

```
定理 (Cahill 2008, 原论文 Theorem 2.1):
  如果并发事务的依赖图中存在环, 则该环必然包含一个"有害三元组":
    T_pivot 满足:
      存在 T_in -rw-> T_pivot 且
      存在 T_pivot -rw-> T_out 且
      T_out 在 T_in 之前或同时提交

  (等价: 两条相邻的 rw 边, 且中间节点 T_pivot 的入边来源比出边去向更晚提交)

推论:
  只需监控每个事务是否同时有入向 rw 边和出向 rw 边
  若有, 形成"危险结构", 立即或最终中止其中之一

空间开销:
  每事务 2 bit (inConflict, outConflict)
  外加 SIREAD 锁集合 (读集合)
```

这意味着 SSI 的增量状态极小，是 SI 实现上最省资源的"可串行化增强"。

### rw-antidependency 的产生

```
rw-antidependency: T1 读 x 的某个版本, T2 之后写 x 的新版本 (T2 不是基于 T1 读的版本写的)

产生场景:
  T1: BEGIN; SELECT * FROM t WHERE c = 'A';           -- 读 x_v1
  T2: BEGIN; UPDATE t SET c = 'B' WHERE id = 1; COMMIT; -- 写 x_v2
  T1: COMMIT;                                          -- T1 的读没包含 T2 的修改

依赖图视角:
  T1 -rw-> T2 (T1 的读在前, T2 的写在后, T1 看不到 T2 的写)

孤立此边没问题 (串行化顺序 = T1, T2)
危险在于形成环:
  T1 -rw-> T2 -rw-> T3 -?-> T1  (三角形)
  或 T1 -rw-> T2 -rw-> T1 (write skew, 两事务相互读对方未写值)
```

### SIREAD 锁的工作机制

```
SIREAD (Serializable Isolation READ) 锁:
  不是传统意义的锁, 不阻塞任何操作
  本质: 对某个页/元组记录 "事务 T 读过这里"
  存储: 共享内存哈希表, key = (relation, page/tuple), value = set<xid>

  锁粒度自适应 (PostgreSQL):
    初始: tuple 级 (最细粒度)
    超过阈值: 升级到 page 级
    再超: 升级到 relation 级
    参数: max_pred_locks_per_transaction (默认 64)
         max_pred_locks_per_page
         max_pred_locks_per_relation

  获取时机:
    SELECT 读每个元组时获取元组级或页级 SIREAD 锁
    Seq Scan: 获取 relation 级
    Index Scan: 获取索引叶子页级

  释放时机:
    事务提交后, 若其他活跃事务依然持有冲突边, 锁保留为 "committed"
    直到所有可能与之冲突的事务完成
```

### Read-Only Optimization

SSI 有一个重要优化：**只读事务通常可以安全提交而不中止**。

```
定理 (Cahill 2008, Theorem 4.1):
  如果一个只读事务 T_RO 处于危险结构中,
  但其所有入向 rw 边的源事务都已在 T_RO 启动前提交,
  那么将 T_RO 以其启动时的快照排序到依赖图中, 不会形成环。

推论:
  只读事务可以 "safe snapshot" 优化:
  若启动时不存在任何未提交的读写事务, 该只读事务可跳过 SSI 追踪
  PostgreSQL: DEFERRABLE 只读事务会等到 safe snapshot 再开始

等效效果:
  真正 HTAP 场景下, 分析型只读事务不会打扰 OLTP 事务
  也不会被 OLTP 中止 (只要选对了启动时机)
```

```sql
-- PostgreSQL 的 DEFERRABLE 只读事务
BEGIN ISOLATION LEVEL SERIALIZABLE READ ONLY DEFERRABLE;
-- 等待 safe snapshot (无未提交的读写事务), 然后开始
-- 保证永不被 SSI 中止, 也不影响其他事务
SELECT ... ;
COMMIT;
```

## Write Skew 的经典例子：值班医生

这是 Cahill 论文中反复出现的示例，也是理解 SI 不等于 Serializable 的最佳教材。

```
业务约束:
  急诊科至少 1 名医生在岗 (on_call = true)

表:
  CREATE TABLE doctors (id INT, name TEXT, on_call BOOLEAN);
  INSERT INTO doctors VALUES (1, 'Alice', TRUE), (2, 'Bob', TRUE);

场景 (两位医生同时申请休假):

Session 1 (Alice 申请下班):
  BEGIN ISOLATION LEVEL REPEATABLE READ;
  SELECT COUNT(*) FROM doctors WHERE on_call = TRUE;   -- 返回 2, OK
  -- 应用层判断: count >= 2, 可以让 Alice 下班
  UPDATE doctors SET on_call = FALSE WHERE id = 1;
  -- 尚未提交...

Session 2 (Bob 申请下班, 并发执行):
  BEGIN ISOLATION LEVEL REPEATABLE READ;
  SELECT COUNT(*) FROM doctors WHERE on_call = TRUE;   -- 仍返回 2 (看不到 Session 1 的修改)
  -- 应用层判断: count >= 2, 可以让 Bob 下班
  UPDATE doctors SET on_call = FALSE WHERE id = 2;
  COMMIT;

Session 1:
  COMMIT;

结果:
  Alice 和 Bob 都 on_call = FALSE
  业务约束被违反: 无人在岗!

  依赖图:
    S1 -rw-> S2 (S1 读 doctors, S2 写 doctor id=2)
    S2 -rw-> S1 (S2 读 doctors, S1 写 doctor id=1)
    形成环 -> 非可串行化
```

### 各引擎对此例的处理

| 引擎 | RR / SI | 处理方式 | 结果 |
|------|---------|---------|------|
| PostgreSQL RR | SI | 不检测 | 两个都 COMMIT 成功, 约束被破坏 |
| PostgreSQL SERIALIZABLE (SSI) | SSI | 检测到 rw 环 | 其中一个 ROLLBACK, SQLSTATE 40001 |
| MySQL RR | SI + Gap Lock | SELECT 不加锁 | 两个都 COMMIT 成功, 约束被破坏 |
| MySQL RR + SELECT FOR UPDATE | S2PL | 第二个 SELECT 等锁 | 串行执行, 约束保持 |
| Oracle SERIALIZABLE | SI | 不检测 (SI 语义) | 两个都 COMMIT 成功, 约束被破坏 |
| SQL Server SNAPSHOT | SI | 不检测 | 两个都 COMMIT 成功, 约束被破坏 |
| SQL Server SERIALIZABLE | S2PL + range lock | 谓词锁保护集合 | 串行执行, 约束保持 |
| CockroachDB (默认 SERIALIZABLE) | SSI | 时间戳 + 冲突检测 | 其中一个 restart |
| YugabyteDB SERIALIZABLE | SSI | 类似 PG | 其中一个 ROLLBACK |

### 修复方案

```sql
-- 方案 1: 升级到 SERIALIZABLE (需要引擎真正支持)
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- 方案 2: SELECT ... FOR UPDATE (普遍兼容)
SELECT * FROM doctors WHERE on_call = TRUE FOR UPDATE;
-- 持有 S2PL 写锁, 第二个事务等待

-- 方案 3: 提升到物化写 (通过更新"占位"行强制 rw 变 ww)
UPDATE doctors_constraint_row SET v = v + 1;  -- 先更新一个约束锚行
-- 之后的逻辑检查 + UPDATE 会序列化

-- 方案 4: 应用层显式加锁 (Redis / ZooKeeper 分布式锁)
```

## Read-Only Transaction Anomaly

Fekete et al. 2004 指出另一个 SI 异常：即使是**只读事务**也可能看到不一致的状态。

```
场景:
  银行账户 X, Y, 初始 X=70, Y=80
  规则: 单账户余额不得低于 0; 但 X+Y 透支时收透支费

  T1 (存款):
    BEGIN;
    -- 读 X=70, Y=80
    UPDATE X SET bal = bal + 20 WHERE id = 'X';  -- X=90
    COMMIT;

  T2 (取款 + 可能收费):
    BEGIN;
    -- 看到的 X, Y 取决于启动时刻
    -- 情况 A: T2 先开始, 看 X=70, Y=80, 合计 150 足够
    --         UPDATE Y SET bal = bal - 100;  -- Y = -20
    --         由于读 X=70 + Y - 100 = -30 < 0, 不收费? 但 Y 现在 = -20!
    -- 实际: 读的 X+Y=150-100=50 > 0, 所以不收费
    COMMIT;

  T3 (只读报表):
    BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
    -- 启动时机关键: 若 T3 在 T1 提交后、T2 提交前启动
    -- 看到 X=90 (来自 T1), Y=80 (尚未看到 T2)
    SELECT X.bal, Y.bal;  -- (90, 80)
    -- 最终 T2 提交后, 数据库状态 X=90, Y=-20
    -- 按串行顺序 T2 -> T1 -> T3 解读, 应收透支费但未收
    -- T3 的报表反映了一个从未真正存在的状态
    COMMIT;
```

这类 read-only anomaly 即使在 RR (SI) 下也会发生。PostgreSQL SSI 检测并在必要时中止或重排只读事务；但大多数 SI 实现 (Oracle, MySQL InnoDB RR, SQL Server SNAPSHOT) 不防。

## SI 冲突检测的内部实现

### PostgreSQL FCW + SSI 提交阶段

```c
// 伪代码 (实际见 src/backend/storage/lmgr/predicate.c)

pre_commit_check_SSI(xact):
    if xact.isolation_level != SERIALIZABLE:
        return OK

    // 1. 检查是否存在 "危险结构"
    for each rw_edge (other -> xact):
        if xact.outConflict && other.inConflict:
            // 形成环, 中止本事务
            ereport(ERROR, SQLSTATE 40001)

    // 2. SIREAD 锁在事务结束后延迟释放
    //    因为其他活跃事务仍可能与此事务形成依赖边
    move_SIREAD_locks_to_committed_list(xact)

    return OK
```

### Oracle FUW on UPDATE

```
UPDATE 操作内部:
  1. 获取行的最新版本 (忽略快照, 总是看最新)
  2. 比较最新版本的 SCN 与本事务的 snapshot SCN:
     - 若最新版本 SCN <= snapshot: 无冲突, 继续修改
     - 若最新版本 SCN > snapshot 且对方已提交:
         RR 下: ORA-08177, 事务中止
         RC 下: 重读该行最新版本, 在新快照上重试 (stmt-level retry)
     - 若对方未提交: 等待
  3. 生成 undo + 修改行 + 标记 SCN = 当前事务 SCN
```

### SQL Server SNAPSHOT FUW

```
UPDATE 操作内部:
  1. 检查行版本链, 找到本事务快照能看到的版本 (V_snap)
  2. 检查当前行的最新版本 (V_latest)
  3. 若 V_snap 的时间戳 < V_latest 的时间戳 (即有人在我快照后修改过):
     抛 Error 3960 "Snapshot isolation transaction aborted"
  4. 否则, 创建新版本并写入
```

## 常见坑与设计建议

### 坑 1：用 SI 做银行转账 (经典 Write Skew)

```sql
-- 错误做法 (允许总额违约)
BEGIN ISOLATION LEVEL REPEATABLE READ;  -- PG RR = SI, Oracle SERIALIZABLE = SI
SELECT SUM(balance) FROM accounts WHERE user_id = 1;   -- 读总余额
-- 应用层决定转出额度
UPDATE accounts SET balance = balance - 100 WHERE user_id = 1 AND id = 5;
COMMIT;

-- 并发的两个事务各自看到同样的余额, 都认为 100 可转
-- 结果: 总额透支
```

**正确做法**：用 `SELECT ... FOR UPDATE` 或 `SERIALIZABLE` (真 SSI)；不要依赖 SI 的"RR"隔离级别保证业务约束。

### 坑 2：长事务与版本链膨胀

SI 实现依赖保留旧版本。长事务会卡住 GC：

```
PostgreSQL: 长事务 -> xmin horizon 推不进 -> VACUUM 无法清理旧版本 -> 表膨胀
MySQL InnoDB: 长事务 -> undo tablespace 膨胀 -> 查询变慢 (版本链更长)
Oracle: 长事务 -> undo 覆盖 -> ORA-01555 snapshot too old

监控指标:
  PG: pg_stat_activity 中最老 backend_start + state='active/idle in transaction'
  MySQL: information_schema.INNODB_TRX 按 trx_started 排序
  Oracle: V$TRANSACTION 按 START_TIME
```

### 坑 3：跨 HTAP 负载的 SSI 中止

分析型长查询在 SSI 下容易被中止：

```
常见模式: OLAP 长查询扫表 + OLTP 高频写入
-> OLAP 形成大量 SIREAD 锁
-> OLTP 写入与 OLAP 频繁形成 rw 边
-> 概率上 OLAP 被中止

解决方案:
  - PG: 用 DEFERRABLE 只读事务 (safe snapshot, 永不中止)
  - Oracle: 用 flashback 查询 (历史快照, 不参与冲突检测)
  - 分流到从库: OLAP 查询走 replica, 只读不参与 SSI
  - CockroachDB: AS OF SYSTEM TIME 历史读 (bounded staleness)
```

### 坑 4：跨事务约束需要约束锚行

SI 下常用技巧：用一个"约束锚行"强制 rw 变 ww。

```sql
-- 值班医生例子的修复 (不升级到 SERIALIZABLE):
CREATE TABLE on_call_count (dept_id INT PRIMARY KEY, cnt INT);

-- 每次修改 on_call 时同步更新 cnt
-- Alice 下班事务:
BEGIN;
UPDATE on_call_count SET cnt = cnt - 1 WHERE dept_id = 1;  -- 物理写, 后续事务会等锁
SELECT cnt FROM on_call_count WHERE dept_id = 1;           -- 读到最新值 (自己的写可见)
-- 应用层判断 cnt >= 1 才继续
UPDATE doctors SET on_call = FALSE WHERE id = 1;
COMMIT;

-- Bob 的并发事务会因 UPDATE on_call_count 等锁 (ww 冲突), 串行化
```

这是工业界用 SI 做约束检查的标准模式：把 rw 依赖转成 ww 依赖，让 FCW/FUW 检测机制发挥作用。

### 坑 5：自增主键 / 序列不受事务保护

```
CREATE SEQUENCE s; 或 AUTO_INCREMENT 列
-> 无论何种隔离级别, sequence 分配跨事务立即可见, 不可回滚

PG: nextval() 永远分配新值, 事务回滚也不回收
Oracle: SEQUENCE 默认 NOCACHE 外仍有 gap
MySQL: AUTO_INCREMENT 在事务回滚后不回收

对 SI 的影响: 依赖 ID 连续性的应用逻辑永远不要基于 ID 计算范围
```

## 关键发现

### 发现 1：SERIALIZABLE 不等于真串行化

Oracle、MySQL RR、SQL Server SNAPSHOT、Snowflake、许多 NewSQL 引擎的 "SERIALIZABLE" 或 "最高隔离" 实际上是 SI 或 SI 变体。只有 PostgreSQL SERIALIZABLE (9.1+)、CockroachDB、YugabyteDB、Redshift、Spanner 等少数引擎提供真正可串行化。

### 发现 2：SI 的性能魅力无法抗拒

为什么几乎所有现代引擎默认选 SI 或 SI 变体？**读不阻塞写，写不阻塞读**这一核心特性让数据库并发能力提升一个数量级。代价是 Write Skew 必须由应用层通过 FOR UPDATE / 约束锚行 / 应用锁等方式防护。

### 发现 3：Cahill SSI 的开销比预想小

Cahill/PostgreSQL 的 SSI 只增加两个 bit per transaction + SIREAD 锁追踪。在 TPCC 等典型负载下开销 < 10%，这让 PG 9.1 有信心将 SSI 做成"免费升级"。但在高并发分析负载下，SIREAD 锁可能升级到关系级，引发假阳性中止，需要参数调优。

### 发现 4：RC-SI 是现实最好的默认

Oracle RC (自 1990 年代就是 RC-SI)、SQL Server RCSI (2005+)、PostgreSQL 的 RC (自 PG 早期版本即基于 MVCC 行版本)、许多 NewSQL 引擎的默认——这一级别是现实中平衡正确性与性能的最佳点。每条语句一次快照，避免长事务的版本链问题，又保证了"不见脏数据 + 不阻塞写"。MySQL RR 的"一致读 + 当前读 + Gap Lock"虽然语义复杂但也源于类似考量。

### 发现 5：谓词锁的代价促生多种创新

真正的谓词锁代价过高，各引擎给出不同近似：
- MySQL InnoDB: Next-Key Lock (索引范围锁) —— 锁实现
- PostgreSQL SSI: SIREAD (影子锁, 自适应粒度) —— MVCC 实现
- CockroachDB: 时间戳推进 + 不确定区间 —— 分布式无锁
- SQL Server SERIALIZABLE: range lock —— 锁实现
- Spanner: TrueTime + 锁 —— 外部一致性

这组对比展示了 "SI 加固到 Serializable" 这一问题的算法多样性。

### 发现 6：SI 的未来是分布式 + MVCC + 时间戳

Spanner、CockroachDB、YugabyteDB 证明 SI/SSI 可以在分布式环境下以合理代价实现。全局时间戳 (TrueTime / HLC) + MVCC + 时间戳推进 / 冲突检测的组合，正在成为 NewSQL 默认选择。传统 S2PL + 分布式锁管理器的路线 (Spanner 早期、Google F1、TiDB 悲观锁) 逐步被 MVCC + 乐观 / 时间戳排序替代。

### 发现 7：应用开发者的心智模型

对应用层开发者而言，三条准则足以覆盖 95% 的场景：

1. **写任何需要读-判断-写的逻辑，默认用 `SELECT ... FOR UPDATE`**，不要依赖隔离级别名字。
2. **RC-SI 足够大多数业务**，只在真正需要事务内多次读一致的场景才升级到 SI/RR。
3. **若必须在 SI 下写 "防写偏斜" 代码**，用约束锚行把 rw 依赖转成 ww 依赖。

## 参考资料

- Berenson, H., Bernstein, P., Gray, J., Melton, J., O'Neil, E., O'Neil, P. *A Critique of ANSI SQL Isolation Levels*, SIGMOD 1995. [Microsoft Research tech report](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/tr-95-51.pdf)
- Adya, A. *Weak Consistency: A Generalized Theory and Optimistic Implementations for Distributed Transactions*, PhD Thesis, MIT, 1999.
- Cahill, M., Röhm, U., Fekete, A. *Serializable Isolation for Snapshot Databases*, SIGMOD 2008.
- Fekete, A., Liarokapis, D., O'Neil, E., O'Neil, P., Shasha, D. *Making Snapshot Isolation Serializable*, ACM TODS 2005.
- Fekete, A., O'Neil, E., O'Neil, P. *A Read-Only Transaction Anomaly Under Snapshot Isolation*, SIGMOD Record 2004.
- PostgreSQL: [Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html)
- PostgreSQL: [Serializable Snapshot Isolation (SSI) Wiki](https://wiki.postgresql.org/wiki/SSI)
- Oracle: [Data Concurrency and Consistency](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/data-concurrency-and-consistency.html)
- SQL Server: [SET TRANSACTION ISOLATION LEVEL](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-transaction-isolation-level-transact-sql)
- SQL Server: [Snapshot Isolation in SQL Server](https://learn.microsoft.com/en-us/dotnet/framework/data/adonet/sql/snapshot-isolation-in-sql-server)
- MySQL: [InnoDB Multi-Versioning](https://dev.mysql.com/doc/refman/8.0/en/innodb-multi-versioning.html)
- CockroachDB: [Serializable Isolation](https://www.cockroachlabs.com/docs/stable/demo-serializable.html)
- CockroachDB: [Read Committed Transactions (v23.1+)](https://www.cockroachlabs.com/docs/stable/read-committed.html)
- YugabyteDB: [Transaction Isolation Levels](https://docs.yugabyte.com/preview/architecture/transactions/isolation-levels/)
- Snowflake: [Transactions](https://docs.snowflake.com/en/sql-reference/transactions)
- Spanner: [TrueTime and External Consistency](https://cloud.google.com/spanner/docs/true-time-external-consistency)
- Martin Kleppmann, *Designing Data-Intensive Applications*, Chapter 7 (Transactions), O'Reilly 2017.
- Ports, D. R. K., Grittner, K. *Serializable Snapshot Isolation in PostgreSQL*, VLDB 2012.
