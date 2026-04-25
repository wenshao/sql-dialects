# 事务 ID 内部结构 (Transaction ID Internals)

事务 ID 是 MVCC 的心跳。每一笔 INSERT/UPDATE/DELETE 在被持久化之前都会被打上一个 txid（或者 xid、SCN、LSN、HLC、TSO，名字五花八门），数据库依赖它判断"这一行对当前快照是否可见"、"两笔并发事务谁先谁后"、"WAL 中的这条记录是否需要重放"。

txid 看起来只是一个整数，但它的位宽、结构、生成方式决定了引擎的可扩展性边界：32 位会撞上 wraparound，必须周期性 freeze；64 位看似无穷却限制了集群的事务吞吐率；混合逻辑时钟（HLC）放弃了"严格单调"换来跨节点协调；TrueTime 用 GPS + 原子钟提供"外部一致性"代价是几毫秒的不确定窗口。本文系统对比 45+ 数据库引擎的事务 ID 设计、生成机制、wraparound 策略与跨节点协调方案。

## 没有 SQL 标准

ANSI/ISO SQL 标准定义了 ACID 的语义、隔离级别（READ UNCOMMITTED、READ COMMITTED、REPEATABLE READ、SERIALIZABLE），但完全没有规定事务标识的内部结构：

- 是 32 位还是 64 位？标准未定义。
- 单调递增还是混合时钟？标准未定义。
- 是否暴露给用户？标准未定义（PG 暴露 `txid_current()`、Oracle 暴露 `DBMS_FLASHBACK.GET_SYSTEM_CHANGE_NUMBER`，多数引擎不暴露）。
- wraparound 时如何处理？标准未定义。

这种"标准沉默"造成了几乎完全的实现分化：

- **PostgreSQL** 长期使用 32 位 XID，配合循环可比较的环形语义，必须 vacuum freeze；13 引入 64 位 `xid8`/`FullTransactionId`。
- **Oracle** 使用 6 字节 SCN（48 位 base + 16 位 wrap），约 2^48 = 280 万亿，几个世纪用不完。
- **MySQL InnoDB** trx_id 是 6 字节（48 位），比 PG 老路线宽，但仍未完全 64 位化。
- **SQL Server** 用 LSN 而非显式事务 ID，LSN 是 96 位（VLF# + offset + slot）。
- **CockroachDB / YugabyteDB** 使用 HLC（Hybrid Logical Clock，物理时间 + 逻辑计数器）。
- **Spanner / AlloyDB Omni（部分）** 使用 TrueTime，提交时间戳带不确定窗口。
- **TiDB / TiKV** 使用 PD 集中分配的 TSO（Timestamp Oracle，物理 + 逻辑）。
- **OceanBase** 使用 GTS（Global Timestamp Service），与 TSO 类似。
- **ClickHouse** 经典模型下没有事务概念；新版本 24.x 引入实验性事务，使用 CSN（Commit Sequence Number）。
- **Snowflake / BigQuery** 完全托管，事务 ID 内部不暴露。
- **Materialize / RisingWave** 流计算引擎使用 timeline timestamp（基于源数据时间）。

下面用 5 张支持矩阵覆盖 45+ 引擎的核心维度。

## 支持矩阵

### 1. 事务 ID 位宽与基本结构

| 引擎 | 名称 | 位宽 | 结构 | 用户可见 | 备注 |
|------|------|------|------|---------|------|
| PostgreSQL | XID / FullTransactionId | 32 / 64 | epoch + xid | `txid_current()`、`xid8` | 13+ 才有 64 位 xid8 |
| MySQL InnoDB | trx_id | 48 | 平坦计数器 | `INFORMATION_SCHEMA.INNODB_TRX` | 6 字节，存储在行隐藏列 |
| MariaDB | trx_id | 48 | 同 InnoDB | 同 InnoDB | 继承自 InnoDB |
| Oracle | SCN | 48 | base(48) [+ wrap(16)] | `CURRENT_SCN`、`SCN_TO_TIMESTAMP` | 6 字节核心 + 16 位 wrap |
| SQL Server | LSN | 96 | VLF#(32) + offset(32) + slot(16) | `sys.fn_dblog`、`%%LOCKRES%%` | 实际 10 字节，常见 "10:00000045:0001" |
| DB2 | LSN | 64 | offset in log stream | `db2pd -logs` | LSO (Log Sequence Offset) |
| SQLite | rowid + change counter | 64 | 平坦 | -- | 没有真正的 txid，rollback journal 跟踪页 |
| SAP HANA | TID | 64 | 平坦 | M_TRANSACTIONS | 单调递增 |
| Informix | logical log position | 64 | LSN | onstat -l | 类似 DB2 |
| Firebird | TIP (Transaction Inventory) | 32 | 平坦计数器 | `RDB$TRANSACTIONS` | 限制约 20 亿，需 sweep |
| H2 | tx id | 64 | 平坦 | `INFORMATION_SCHEMA.SESSIONS` | 内存数据库 |
| HSQLDB | tx id | 64 | 平坦 | -- | 内存优先 |
| Derby | tx id | 64 | 平坦 | -- | -- |
| CockroachDB | HLC timestamp | 128 (96 物理 + 32 逻辑) | physical(64ns) + logical(32) | `cluster_logical_timestamp()` | HLC 论文 2014 |
| Spanner | commit timestamp | 64 + uncertainty | 物理时间 + ε（TrueTime） | `READ_TIMESTAMP` | TrueTime SOSP 2012 |
| TiDB | TSO | 64 | physical(46ms) + logical(18) | `tidb_current_ts` | PD 集中分配 |
| YugabyteDB | HLC | 64 | physical(52μs) + logical(12) | -- | 借鉴 Spanner + HLC |
| OceanBase | GTS | 64 | physical(μs) + logical | -- | 类 TSO，租户级 GTS |
| TDengine | tx id | 64 | 平坦 | -- | 时序数据库 |
| Snowflake | commit timestamp + queryId | 64 | 物理时间 | `CURRENT_TIMESTAMP`、`QUERY_ID` | 内部，不暴露 txid |
| BigQuery | session/job id | 字符串 | UUID | `SESSION_USER` | 不暴露 txid |
| Redshift | XID | 32 | 继承 PG 8.0 | `pg_locks.transaction` | 同 PG，但有自动 vacuum |
| Greenplum | XID | 32 / 64 | 继承 PG | `pg_locks.transaction` | 6.x 后引入 xid8 |
| DuckDB | tx id | 64 | 平坦 | -- | 0.5+ 持久化 |
| ClickHouse | CSN | 64 | commit sequence number | system.transactions（24.x+） | 经典模型无事务 |
| Trino / Presto | query id + transaction id | 字符串 | UUID-ish | `current_transaction_id` | 计算引擎 |
| Spark SQL | query id | 字符串 | -- | -- | 无传统事务 |
| Flink SQL | checkpoint id | 64 | 平坦 | -- | 用 checkpoint 代替 txid |
| Hive | writeId | 64 | 平坦递增 | `SHOW TRANSACTIONS` | ACID v2，HiveMetaStore 分配 |
| Impala | writeId | 64 | 同 Hive | -- | 复用 Hive ACID |
| Databricks | Delta version | 64 | 单调递增 | `DESCRIBE HISTORY` | Delta Log version |
| Iceberg | snapshot id | 64 | 单调或哈希 | `snapshots` 表 | 表格式标识 |
| Materialize | timestamp | 64 | timeline + ms 时间戳 | `mz_now()` | 流式时间线 |
| RisingWave | epoch | 64 | physical + logical | -- | 借鉴 Flink barrier |
| Kafka KSQL | offset | 64 | 平坦 | -- | 流处理偏移 |
| InfluxDB (SQL) | -- | -- | -- | -- | 无传统事务 |
| QuestDB | tx id | 64 | 平坦 | -- | 时序 |
| MonetDB | tx id | 64 | 平坦 | -- | -- |
| Crate DB | tx id | 64 | 平坦 | -- | 基于 Lucene |
| Vertica | epoch | 64 | LCS/CCS/AHM | `EPOCHS` 系统表 | 多种 epoch（current/checkpoint/AHM） |
| Teradata | TJ ID | 64 | TJ row id | DBC.TransactionAbortMsg | TJ = Transient Journal |
| Yellowbrick | XID | 32 / 64 | 继承 PG | -- | PG fork |
| Firebolt | -- | -- | 不暴露 | -- | 完全托管 |
| Aurora MySQL | trx_id | 48 | 同 InnoDB | -- | 共享存储但 ID 同 InnoDB |
| Aurora PostgreSQL | XID / xid8 | 32 / 64 | 同 PG | 同 PG | 同 PG |
| Azure Synapse | XID | 32 | 继承 PDW（基于 SQL Server PDW） | -- | -- |
| Amazon Athena | query id | 字符串 | UUID | -- | 计算引擎 |
| TimescaleDB | XID / xid8 | 32 / 64 | 继承 PG | 同 PG | -- |
| SingleStore | snapshot version | 64 | 平坦递增 | -- | -- |
| StarRocks | transaction id | 64 | 平坦 | -- | FE 集中分配 |
| Doris | transaction id | 64 | 平坦 | `SHOW TRANSACTION` | FE 集中分配 |
| Tarantool | LSN | 64 | per-instance | box.info.lsn | 主从复制基础 |

> 统计（位宽）：32 位 XID 5 个（PG 经典、Redshift、Greenplum 经典、Firebird、Synapse），48 位 3 个（InnoDB/MariaDB/Oracle SCN），64 位 25+ 个，96+ 位 2 个（SQL Server LSN、CockroachDB HLC 128 位）。
>
> 统计（结构）：平坦计数器 25+ 个；epoch + counter 模式 PG 后期、Oracle、ClickHouse；HLC 模式 CockroachDB、YugabyteDB；TrueTime 模式 Spanner；TSO 模式 TiDB、OceanBase（GTS）。

### 2. 单调性与时钟模型

| 引擎 | 严格单调 | 时钟来源 | 跨节点协调 | 备注 |
|------|---------|---------|-----------|------|
| PostgreSQL | 是（单实例内） | 内部计数器 | 流复制时主控 | XidGenLock 串行化 |
| MySQL InnoDB | 是 | 内部计数器 | 主从单点 | trx_sys mutex 保护 |
| MariaDB | 是 | 同 InnoDB | -- | -- |
| Oracle | 是 | SCN broker | RAC 多节点协调 | RAC 用 LMS 进程同步 SCN |
| Oracle RAC | 是（全局） | LMS + SCN | Lamport 时钟 + IPC | DLM 维护 |
| SQL Server | 是（单实例） | 内部 | AG 组 lazy redo | LSN 全局唯一 |
| SQL Server AG | 是（主副本） | 主副本 | 异步/同步复制 | secondary LSN 重放 |
| DB2 | 是 | LSN 单调 | pureScale GLM 协调 | -- |
| SQLite | 单文件单进程 | 内部 | -- | 无并发节点 |
| SAP HANA | 是 | 内部 | scale-out 协调 | -- |
| Firebird | 是 | TIP | -- | -- |
| CockroachDB | HLC 半单调 | NTP + 内部 logical | 全集群 HLC | 时钟漂移 250ms 容忍 |
| Spanner | 全局严格单调 | TrueTime（GPS+原子钟） | 跨数据中心 | commit-wait 保证外部一致性 |
| TiDB | 全局严格单调 | PD TSO | 单 PD 节点 | PD leader 瓶颈 |
| YugabyteDB | HLC 半单调 | NTP + logical | tablet leader | -- |
| OceanBase | 全局严格单调 | GTS | 租户级 GTS leader | -- |
| Snowflake | 是 | 内部 | 单点 metadata | FoundationDB |
| BigQuery | 是（per dataset） | Spanner timestamp | -- | 借助 Spanner |
| Redshift | 是 | 同 PG | leader node | 单 leader |
| Greenplum | 是 | master coordinator | master 单点 | 类 PG |
| DuckDB | 是 | 内部 | -- | 单进程 |
| ClickHouse (24.x+) | 是（实验） | 内部 | ZooKeeper/Keeper 协调 | -- |
| Hive ACID | 是 | HiveMetaStore | HMS 单点 | writeId 由 HMS 分配 |
| Databricks Delta | 是 | Delta Log | OCC + 文件原子重命名 | version 由 commit 时确定 |
| Materialize | 是 | timeline 物理时钟 | -- | 流式时间 |
| RisingWave | epoch 单调 | barrier injection | barrier 协调 | -- |
| Vertica | epoch 单调 | initiator | -- | -- |
| StarRocks | 是 | FE leader | FE 单点 | -- |
| Doris | 是 | FE leader | FE 单点 | -- |
| SingleStore | 是 | per partition | partition leader | -- |
| Tarantool | 是 | per instance | replication 协调 | LSN per instance |

### 3. wraparound（回卷）防御策略

| 引擎 | 是否有 wraparound 风险 | 触发阈值 | 防御机制 |
|------|--------------------|---------|---------|
| PostgreSQL（经典 XID） | 是 | 2^31 ≈ 21 亿 | autovacuum freeze、`vacuum_freeze_min_age`、`vacuum_freeze_table_age`、`autovacuum_freeze_max_age` |
| PostgreSQL（xid8/FullTransactionId） | 几乎不（2^64） | -- | 用 xid8 即可避免 |
| MySQL InnoDB | 几乎不（2^48 ≈ 280 万亿） | 280 万亿 | 实际不会触及 |
| MariaDB | 同 InnoDB | -- | -- |
| Oracle | 几乎不（2^48） | 280 万亿 | 几个世纪 |
| Oracle SCN headroom | 是（隐性） | 当前 SCN > 软上限 | "SCN headroom" 警告，可补丁修复 |
| SQL Server | 几乎不（VLF# 32 位 + offset 32 位） | -- | VLF 循环复用，LSN 不复用 |
| DB2 | 几乎不 | 2^64 | -- |
| Firebird | 是 | 2^31（OID 32 位） | sweep / backup-restore，gbak 重置 |
| SAP HANA | 几乎不 | 2^64 | -- |
| CockroachDB | 几乎不（HLC 物理时间 + 逻辑） | 物理时间永不回卷（除非 NTP 错误） | HLC 容忍最大 clock skew |
| Spanner | 不 | -- | TrueTime 严格单调 |
| TiDB | 不 | -- | TSO 64 位 |
| YugabyteDB | 不 | -- | -- |
| Greenplum | 是（继承 PG 经典） | 21 亿 per segment | 每 segment vacuum freeze |
| Redshift | 是（继承 PG 8.0） | 21 亿 | 自动 vacuum，但仍可发生（历史故障） |
| TimescaleDB | 是（继承 PG） | 21 亿 | hypertable 多分区可缓解 |
| Yellowbrick | 是（继承 PG） | 21 亿 | -- |
| 其他 64 位平坦 | 几乎不 | 2^64 | -- |

### 4. 暴露给用户的接口

| 引擎 | 当前 txid | 历史 txid → 时间 | 时间 → txid | 备注 |
|------|----------|----------------|------------|------|
| PostgreSQL | `txid_current()`、`pg_current_xact_id()`（13+） | `pg_xact_commit_timestamp(xid)` 需 `track_commit_timestamp=on` | -- | 13+ 推荐使用 `pg_current_xact_id` |
| MySQL InnoDB | `INFORMATION_SCHEMA.INNODB_TRX.trx_id` | -- | -- | -- |
| Oracle | `CURRENT_SCN`、`DBMS_FLASHBACK.GET_SYSTEM_CHANGE_NUMBER` | `SCN_TO_TIMESTAMP(scn)` | `TIMESTAMP_TO_SCN(ts)` | flashback 查询基础 |
| SQL Server | `sys.fn_dblog`（DBCC LOG） | `LOG_BLOCK_GENERATION` | -- | LSN 多用于复制和恢复 |
| DB2 | `db2pd -logs` | -- | -- | -- |
| SAP HANA | `M_TRANSACTIONS` | -- | -- | -- |
| CockroachDB | `cluster_logical_timestamp()`、`SHOW TRANSACTION TIMESTAMP` | HLC 内含物理时间 | -- | AS OF SYSTEM TIME 接受 HLC |
| Spanner | `READ_TIMESTAMP`、`COMMIT_TIMESTAMP` 列 | TrueTime 内含 | -- | -- |
| TiDB | `tidb_current_ts`（session）、`SHOW MASTER STATUS` | TSO 内含物理 | -- | snapshot read 接受 TSO |
| YugabyteDB | -- | -- | -- | -- |
| OceanBase | `OB_GTS()` | -- | -- | -- |
| Snowflake | `CURRENT_TIMESTAMP`、`SYSTEM$STREAM_HAS_DATA`、`QUERY_ID` | Time Travel 用时间或 query id | -- | TIME TRAVEL（90 天内） |
| BigQuery | `SESSION_USER`、`@@query_id` | TIME TRAVEL（FOR SYSTEM_TIME AS OF） | -- | 7 天 TT 默认 |
| Hive ACID | `SHOW TRANSACTIONS`、`SHOW LOCKS` | -- | -- | -- |
| Databricks Delta | `DESCRIBE HISTORY` | version → ts | `TIMESTAMP AS OF` | 表级 |
| Materialize | `mz_now()`、`SELECT * FROM mz_now()` | timeline 内含 | `AS OF` | 流式查询基础 |
| Vertica | `CURRENT_EPOCH`、`MARKER_EPOCH` | -- | -- | epoch 而非 txid |

### 5. ID 在表行中的表示与冗余

| 引擎 | 行级隐藏列 | 容量开销 | 备注 |
|------|----------|---------|------|
| PostgreSQL | `xmin`(32)、`xmax`(32)、`cmin`、`cmax`、`ctid` | 23-byte tuple header | 6 字节用于 xmin/xmax |
| PostgreSQL（xid8） | `xmin`/`xmax` 仍然 32 位（依赖 epoch 拼接） | -- | 不增加每行开销 |
| MySQL InnoDB | `DB_TRX_ID`(48)、`DB_ROLL_PTR`(56) | 13 字节/行 | clustered index 行 |
| MariaDB | 同 InnoDB | 13 字节 | -- |
| Oracle | `ORA_ROWSCN`（可选 ROW DEPENDENCIES） | 6 字节/行（启用时） | 默认是 block-level SCN |
| SQL Server | per-row 没有显式 LSN | -- | row version 通过 row_version_pointer 间接关联 |
| SQL Server snapshot | RVS（row versioning store）TempDB | 14 字节/版本 | snapshot isolation 启用后 |
| DB2 | -- | -- | -- |
| CockroachDB | MVCCKey + timestamp | 12 字节 timestamp/版本 | KV 层 |
| Spanner | timestamp column | 12 字节 commit timestamp | -- |
| TiDB / TiKV | MVCCKey + commit_ts + start_ts | 16 字节 timestamp | KV 层 |
| Hive ACID | originalTransaction、bucket、rowId、currentTransaction | -- | 4 字段元数据 |
| Iceberg | snapshot_id（per row 否） | -- | per file，不在行级 |
| Delta | -- | -- | per parquet file |

## 各引擎 txid 详解

### PostgreSQL: 32 位 XID 与 64 位 FullTransactionId 的双轨制

PostgreSQL 的事务 ID（XID）是其历史包袱与现代演进的活生生的样本。

#### 经典 XID（32 位）

`xid` 类型在 PG 早期就是 32 位无符号整数，最大 2^32 = 42.9 亿。但实际可用空间只有 2^31 ≈ 21.4 亿，原因是 PG 用**模 2^32 的循环可比较**语义来判断"哪个 xid 在前面"：

```c
// src/backend/access/transam/transam.c
bool TransactionIdPrecedes(TransactionId id1, TransactionId id2)
{
    int32 diff;

    if (!TransactionIdIsNormal(id1) || !TransactionIdIsNormal(id2))
        return (id1 < id2);

    diff = (int32) (id1 - id2);
    return (diff < 0);
}
```

`int32 diff = id1 - id2` 是溢出回绕的减法。如果差值为负，则 id1 在 id2 之前。这意味着任意 xid 只能与"最近 21 亿"的 xid 比较——超出这个范围，"前后"关系会反转。所以当数据库里某些行的 xmin 是 1（最早事务），而当前 xid 已经达到 2^31 时，再继续就会让"过去"被解读成"未来"，活跃事务可能突然看不见已提交的数据。

PG 的解决方案是 **freezing**：当一行的 xmin 距离当前 xid 超过 `vacuum_freeze_min_age`（默认 5000 万）时，autovacuum 会把它的 xmin 改写成特殊值 `FrozenTransactionId`（2），表示"这行对所有事务可见"。同时维护数据库级的 `datfrozenxid`（数据库内最古老未冻结 xid），系统级的 `pg_database.datfrozenxid` 决定了距离 wraparound 还有多少 xid 余量。

#### 64 位 FullTransactionId（PG 13+）

PG 13（2020 年 9 月）引入 `xid8` 类型和 `FullTransactionId`：

```c
// src/include/access/transam.h
typedef struct FullTransactionId
{
    uint64 value;
} FullTransactionId;

#define EpochFromFullTransactionId(x)  ((uint32) ((x).value >> 32))
#define XidFromFullTransactionId(x)    ((uint32) (x).value)
```

`FullTransactionId` 是 32 位 epoch + 32 位 xid 拼成的 64 位。每当 xid 回卷（达到 2^32）时，epoch +1。这样 64 位完全足以撑过宇宙寿命，但 PG 表内部仍然使用 32 位 xid 存储（避免每行额外 4 字节开销），只是在判断可见性时通过 epoch 推断完整的 64 位上下文。

新 SQL 函数：

```sql
-- 13+
SELECT pg_current_xact_id();           -- 当前事务的 xid8
SELECT pg_current_xact_id_if_assigned(); -- 已分配则返回 xid8，否则 NULL
SELECT pg_xact_status(xid8);           -- in progress / committed / aborted
SELECT pg_current_snapshot();          -- pg_snapshot 类型
```

旧版 `txid_current()` 仍然存在，返回 `bigint`（实际是同样的 epoch+xid 拼接，但类型不一致），13+ 推荐使用 `pg_current_xact_id`。

#### 行级 xmin/xmax 的存储

```
PostgreSQL HeapTupleHeader (23 字节):
  t_xmin     uint32   -- 创建该版本的 xid
  t_xmax     uint32   -- 删除/锁定该版本的 xid (0 表示有效)
  t_cid      uint32   -- command id (insert/update 在事务内的子计数)
  t_ctid     ItemId   -- 自身或新版本的 (block, offset)
  t_infomask uint16   -- 标志位 (xmin 已 commit/abort 等)
  t_infomask2 uint16
  ...
```

每行 xmin/xmax 都是 32 位。FullTransactionId 在内存中是 64 位，但存储到磁盘时只截取 32 位部分，配合页头的 epoch 信息推断完整 ID。这是为什么 PG 即使有 xid8，仍然需要 freeze——存储格式没有变。

### Oracle: SCN 与 SCN_TO_TIMESTAMP

Oracle 用 **SCN（System Change Number）** 替代显式的 txid。SCN 不是事务 ID，而是数据库的"全局时钟"——每个 commit 推进 SCN，每个 redo 记录、每个 block 都打着 SCN，flashback、Data Guard、RAC 都依赖它。

#### SCN 结构

```
Oracle SCN: 6 字节
  base    : 4 字节 (32 位)  -- 主计数
  wrap    : 2 字节 (16 位)  -- 当 base 回卷时 +1
  实际容量: 2^48 = 281,474,976,710,656 ≈ 280 万亿
```

按一个数据库每秒 16,000 次 commit 计算（这是 OLTP 系统的极限），需要 280 万亿 / 16000 / 86400 / 365 ≈ 558 年才能耗尽。所以 Oracle 的 SCN 实际是"几乎用不完"的。

但历史上 Oracle 有过一个有名的 "SCN headroom" 警告：早期版本设置了一个软上限（基于"每秒 16384 个 SCN"假定计算的当前合理 SCN 值），如果某个数据库的 SCN 突然飙升（比如因为 dblink 把另一个高 SCN 的库的 SCN 拉过来），会触发 ORA-19706 等错误。Oracle 通过补丁（参数 `_external_scn_rejection_threshold_hours`）放宽了这个限制。

#### 用户 API

```sql
-- 当前 SCN
SELECT CURRENT_SCN FROM V$DATABASE;
SELECT DBMS_FLASHBACK.GET_SYSTEM_CHANGE_NUMBER FROM DUAL;

-- SCN 与时间互转 (精度: 5 分钟，因为内部映射表的颗粒度)
SELECT SCN_TO_TIMESTAMP(15234567890) FROM DUAL;
SELECT TIMESTAMP_TO_SCN(SYSTIMESTAMP - INTERVAL '1' HOUR) FROM DUAL;

-- AS OF SCN (Flashback 查询)
SELECT * FROM employees AS OF SCN 15234567890 WHERE department_id = 10;

-- AS OF TIMESTAMP (内部转 SCN)
SELECT * FROM employees AS OF TIMESTAMP SYSDATE - 1/24 WHERE department_id = 10;

-- 行级 SCN (默认按 block，启用 ROW DEPENDENCIES 后按行)
CREATE TABLE t (id NUMBER) ROWDEPENDENCIES;
SELECT id, ORA_ROWSCN, SCN_TO_TIMESTAMP(ORA_ROWSCN) FROM t;
```

#### RAC 中的 SCN 协调

Oracle RAC（Real Application Clusters）多节点共享同一数据库，需要全局单调的 SCN：

```
RAC SCN 协调（Lamport 时钟变种）:
  1. 节点 A commit 时获取本地 SCN_A (从内存计数器)
  2. 节点 A 发送消息给节点 B (附带 SCN_A)
  3. 节点 B 接收消息时: SCN_B = max(SCN_B, SCN_A) + 1
  4. 类似的 broadcast on commit / SCN piggyback 机制

调优参数:
  _max_outstanding_log_writes (默认 2)
  _lgwr_async_broadcast (默认 true) - 异步广播 SCN
```

实际中 RAC 节点间的 SCN 同步通过 LMS（Lock Manager Server）进程完成，使用高速互联（InfiniBand 或 RDMA over Ethernet）。

### SQL Server: LSN（Log Sequence Number）替代 txid

SQL Server 没有显式暴露的事务 ID（虽然内部有 `transaction_id`，但用户极少使用）。它用 **LSN** 来识别一切：每个 redo 记录、每个数据页、每个复制操作都打着 LSN。

#### LSN 结构

```
SQL Server LSN: 96 位（理论最大），实际显示为 "VLF#:offset:slot":
  VLF#   : 32 位  -- 虚拟日志文件 (Virtual Log File) 编号
  offset : 32 位  -- 该 VLF 内的字节偏移 (除以 512 字节)
  slot   : 16 位  -- 同一 log record 内的多个子记录

例:
  LSN = "10:00000045:0001"
  → VLF 10, offset 0x45 = 69 (字节偏移 69 * 512 = 35328), slot 1
```

DBCC LOG 和 sys.fn_dblog 可以查看 LSN：

```sql
-- 查看当前 transaction log
SELECT [Current LSN], [Operation], [Transaction ID], [AllocUnitName]
FROM sys.fn_dblog(NULL, NULL);

-- 查看某个事务的所有日志记录
SELECT [Current LSN], [Operation], [Begin Time]
FROM sys.fn_dblog(NULL, NULL)
WHERE [Transaction ID] = '0000:0000abcd';
```

#### LSN 单调性

LSN 在单实例内严格单调递增。VLF# 不会回卷（因为 32 位足够大，每个 VLF 通常几十 MB 到几个 GB），即使 transaction log 文件循环复用 VLF 槽位，新分配的 VLF 也会获得更大的 VLF#。

```
VLF 状态机:
  Status 0: free (可分配)
  Status 2: active (正在写入)
  Status 4: 等待复用（已截断但未释放）

循环复用:
  写满 VLF 1 → 切到 VLF 2 → ... → VLF 7 → checkpoint/log backup 截断 VLF 1-3 → 从 VLF 8 开始 (而非 VLF 1)
  VLF# 永远递增
```

#### Always On AG 的 LSN 复用

主副本写入 LSN N 后，把日志记录推送给次副本，次副本 redo 时使用相同 LSN。这保证了 AG 内所有节点的 LSN 全局一致。

### MySQL InnoDB: trx_id 6 字节平坦计数器

InnoDB 的 trx_id 是 48 位（6 字节）平坦计数器，存储在 `trx_sys` 全局结构体中：

```c
// storage/innobase/include/trx0sys.h
struct trx_sys_t {
    TrxSysMutex mutex;          // 串行化 trx_id 分配
    trx_id_t   max_trx_id;      // 下一个可分配的 trx_id
    ...
};
```

每次开启读写事务时获取一个新的 trx_id：

```c
trx->id = trx_sys->max_trx_id;
trx_sys->max_trx_id++;
```

trx_id 持久化到 `ib_logfile` 的 redo 记录、每行的 `DB_TRX_ID` 隐藏列（6 字节）、`undo log` header 中。

```
InnoDB 行格式 (Compact):
  Variable lengths
  NULL bitmap
  Record header (5 字节)
  ROW_ID (6 字节, 仅当无主键时)
  DB_TRX_ID (6 字节)  -- 最后修改本行的 trx_id
  DB_ROLL_PTR (7 字节) -- undo log 回溯指针
  Column data...
```

#### 容量与 wraparound 风险

48 位 = 281 万亿 = 2.81 × 10^14。即使每秒 100 万事务，也需要 89 年才能用完。实际 OLTP 系统更慢，所以基本不会遇到。

但有一个隐患：trx_id 是 6 字节存储但用 64 位（`uint64_t`）传输。MySQL 8.0 的源代码注释中明确说 "trx_id is 48-bit but stored as 64-bit for alignment"。

#### purge 与可见性

InnoDB 的 read view 包含 `m_low_limit_id` (创建 view 时的 max_trx_id) 与 `m_ids` (活跃 trx_id 列表)。判断行可见性时：

```
if row.DB_TRX_ID < m_low_limit_id and DB_TRX_ID not in m_ids:
    可见
elif row.DB_TRX_ID == 当前事务自己:
    可见
else:
    沿 DB_ROLL_PTR 回溯，找更老版本
```

老版本由 purge 线程清理，前提是没有任何活跃 read view 还需要它。

### MariaDB: 继承 InnoDB

MariaDB 默认存储引擎仍是 InnoDB（实际上是 MySQL InnoDB 的 fork：MariaDB 5.5 之前用 XtraDB），事务 ID 实现完全继承。

#### Aria 引擎的差异

MariaDB 自己开发的 Aria 引擎（支持 crash-safe 但不支持事务）使用不同的 ID 体系：

```
Aria control file:
  Aria log id (循环编号)
  无显式事务 ID
  靠 careful write + transactional 表的有限 ACID
```

实际生产中，MariaDB 的事务能力主要还是通过 InnoDB。

### CockroachDB: HLC（Hybrid Logical Clock）

CockroachDB 是首个商用 HLC 实现的数据库。HLC 由 Sandeep Kulkarni 等人在 2014 年的论文 "Logical Physical Clocks and Consistent Snapshots in Globally Distributed Databases" 中提出。

#### HLC 结构

```
CockroachDB HLC:
  physical : 64 位  -- 纳秒级 Unix 时间戳 (来自 NTP 同步的 wall clock)
  logical  : 32 位  -- 同一 wall clock 时刻内的逻辑序号

总宽度: 96 位（实际占用 12 字节）

更新规则（核心 HLC 算法）:
  on local event:
    j = wall_now()
    if j > L.physical:
        L.physical = j; L.logical = 0
    else:
        L.logical = L.logical + 1

  on receive message m with timestamp m.timestamp:
    j = wall_now()
    L_old = L.physical
    L.physical = max(L_old, m.timestamp.physical, j)
    if L.physical == L_old == m.timestamp.physical:
        L.logical = max(L.logical, m.timestamp.logical) + 1
    elif L.physical == L_old:
        L.logical = L.logical + 1
    elif L.physical == m.timestamp.physical:
        L.logical = m.timestamp.logical + 1
    else:
        L.logical = 0

  on send message:
    update L (as on local event)
    return L
```

HLC 的精妙在于：
- 在没有消息交换的稳定状态下，HLC ≈ 物理时钟（人类可读，便于运维）。
- 跨节点消息会自动同步 HLC，保证因果关系（happens-before）严格反映在时间戳大小上。
- 物理时间漂移有界（NTP 通常在毫秒级），所以 HLC 与真实物理时钟的差距永远有界。

CockroachDB 默认容忍 250ms 的 NTP 时钟偏差（`--max-offset`），如果实际偏差超过这个值，节点会自杀（fatal log）防止违反一致性。

#### 接口

```sql
-- 当前 HLC（返回 logical timestamp）
SELECT cluster_logical_timestamp();
-- 1759872345.0000000001  (秒.纳秒+逻辑)

-- 在某个 HLC 时刻读取（snapshot read）
SELECT * FROM accounts AS OF SYSTEM TIME '-30s' WHERE id = 1;

-- 显示事务的 HLC
SHOW TRANSACTION TIMESTAMP;
```

### Google Spanner: TrueTime 与外部一致性

Spanner（论文 OSDI 2012、SOSP 2012）通过 GPS + 原子钟提供 TrueTime API，每次调用 `TT.now()` 返回的不是单一时间戳，而是 `[earliest, latest]` 区间——保证真实物理时间一定落在这个区间内。

#### TrueTime API

```
TT.now() returns TTinterval = [earliest, latest]
TT.after(t)  returns true if t < TT.now().earliest
TT.before(t) returns true if t > TT.now().latest

不确定窗口 ε = (latest - earliest) / 2
正常情况下 ε < 7ms（GPS + 原子钟 + 频繁同步）
偶尔 ε 可能升至 10-100ms（数据中心断电恢复后）
```

#### Commit-Wait 协议

```
Spanner 写事务:
  1. acquire locks
  2. choose commit timestamp s = TT.now().latest
  3. write Paxos log (s 写入日志)
  4. wait until TT.after(s) is true   -- "commit-wait"
  5. release locks, return success to client
```

第 4 步是关键：等待真实物理时间一定大于 s，再返回客户端。这样下一个事务调用 `TT.now()` 时，得到的最早时间一定 > s，因果序得到严格保证（外部一致性，linearizability）。

代价：每个写事务多等 ~7ms（一个 ε 的等待时间）。Spanner 通过非常多的优化（pipelining、batching）摊销这个开销。

#### 接口

```sql
-- Spanner SQL: commit timestamp 列（自动填充）
CREATE TABLE Events (
  EventId STRING(36),
  EventTime TIMESTAMP OPTIONS (allow_commit_timestamp=true),
  ...
) PRIMARY KEY (EventId);

-- 读取的 timestamp（强一致 read）
SELECT * FROM Events
  AT READ TIMESTAMP TIMESTAMP "2026-04-25T00:00:00Z"
  WHERE EventId = "x";

-- stale read（避免等 commit-wait）
SELECT * FROM Events
  AT MAX_STALENESS INTERVAL 10 SECOND
  WHERE EventId = "x";
```

### TiDB: TSO（Timestamp Oracle）

TiDB 借鉴了 Google Percolator 模型，使用 PD（Placement Driver）作为 TSO 服务，集中分配 64 位时间戳。

#### TSO 结构

```
TiDB TSO: 64 位
  physical : 46 位  -- 毫秒级 Unix 时间戳
  logical  : 18 位  -- 同毫秒内的序号

最大 logical/ms: 2^18 = 262,144
总吞吐: 262K ops/ms = 262M ops/s（理论上限，实际受网络限制）
```

#### PD 单点

```
TiDB TSO 申请流程:
  client (TiDB Server) -> RPC -> PD leader
  PD leader 持有全局递增的 TSO 计数器
  PD leader 每次申请增加 logical 部分；当 wall clock 推进时重置 logical=0

性能瓶颈:
  - 单 PD leader: 实测 ~1.5M ops/sec
  - 优化: TSO batch（一次 RPC 申请多个连续 TSO）
  - 优化: PD followers 可以做"async TSO"，但仅用于 stale read

PD leader 故障切换:
  - Raft 选举（通常 1-5 秒）
  - 故障期间无法分配新 TSO（事务阻塞）
  - 新 leader 启动时检查 etcd 中的 last_max_ts，从该值之后开始分配（保证全局单调）
```

#### 接口

```sql
-- 当前 TSO
SELECT @@tidb_current_ts;
-- 459203450880753664  (uint64 编码的物理+逻辑)

-- 解析 TSO
SELECT TIDB_PARSE_TSO(@@tidb_current_ts);
-- 返回时间戳

-- snapshot read
SET @@tidb_snapshot = '2026-04-25 12:00:00';
SELECT * FROM accounts;

-- 设置 stale read
SELECT * FROM accounts AS OF TIMESTAMP NOW() - INTERVAL 5 SECOND;
```

### YugabyteDB: HLC + Spanner 风格

YugabyteDB 综合了 CockroachDB 的 HLC 与 Spanner 的 read/commit timestamp 语义。

```
YugabyteDB HLC: 64 位
  physical : 52 位  -- 微秒级 Unix 时间戳
  logical  : 12 位  -- 微秒内序号

容量:
  52 位微秒 = 142,808 年
  12 位 = 4096 ops/μs
  整体: 4096 * 1M = 4 GHz 单点写入率（理论上限）

实现:
  - tablet leader 维护本地 HLC
  - 客户端读: leader 返回当前 HLC（默认强一致）
  - 跨 tablet 写: 协调器收集所有 tablet 的 HLC，取 max + 1
  - 容忍 max_clock_skew_usec (默认 500μs)
```

### OceanBase: GTS

OceanBase 的 GTS（Global Timestamp Service）类似 TiDB TSO，但是租户级别的：

```
OceanBase GTS:
  - 每个租户一个独立的 GTS leader
  - 默认部署在 sys 租户的 RootService 节点
  - 用户租户也可以独立部署 GTS（GTS leader = 租户主 zone）

性能:
  - 单 GTS leader: ~2M ops/sec（基于 RDMA）
  - HA: GTS leader 故障 -> 其他副本 takeover

接口:
  SELECT OB_GTS();   -- 当前 GTS
  -- 类似 TiDB 的 snapshot read
  SELECT * FROM t AS OF SCN 12345;
```

### ClickHouse: 经典无事务、24.x 实验性事务

经典 ClickHouse 没有事务概念——每个 INSERT/MERGE 写入新的 immutable part（partition），原子重命名到表目录。读操作扫描所有当前可见的 part，不受新写入影响（除非数据已 merge）。

```
ClickHouse 一致性模型:
  - INSERT 是原子的（part-level）
  - 多个 INSERT 之间无事务（无法回滚跨 INSERT 的批量操作）
  - SELECT 看到的是查询开始时的 part 列表（snapshot）
  - MERGE 后台执行，对查询透明
```

ClickHouse 24.x（2024 年）引入实验性事务支持（实验性，需开 setting）：

```sql
-- 启用事务
SET allow_experimental_transactions = 1;

BEGIN TRANSACTION;
INSERT INTO t VALUES (1, 'a');
INSERT INTO t VALUES (2, 'b');
COMMIT;

-- 查看事务
SELECT * FROM system.transactions;
-- tid: 起始 CSN
-- snapshot: 读 snapshot CSN
-- state: ACTIVE / COMMITTED / ROLLED_BACK
```

CSN（Commit Sequence Number）是 64 位单调递增。MergeTree 引擎在每个 part 的元数据中记录 min_csn / max_csn，事务读时根据自己的 snapshot CSN 决定哪些 part 可见。

### Snowflake: commit timestamp + Time Travel

Snowflake 不暴露 txid，用户可见的是 query_id（UUID 字符串）和 commit timestamp。Time Travel 允许用 timestamp 或 query_id 查询历史快照：

```sql
-- 用时间戳
SELECT * FROM orders AT (TIMESTAMP => '2026-04-25 00:00:00'::TIMESTAMP);
SELECT * FROM orders AT (OFFSET => -60*60);  -- 1 小时前

-- 用 query id
SELECT * FROM orders BEFORE (STATEMENT => '8e5d0ca9-...-uuid');

-- Time Travel 保留期: 标准版 1 天，企业版 90 天
ALTER TABLE orders SET DATA_RETENTION_TIME_IN_DAYS = 30;
```

内部实现：每次 commit 在 FoundationDB metadata 中创建新 micro-partition 文件 + 更新表的 manifest。Time Travel 查询通过 manifest 找到指定时间点的 partition 集合。

### DB2: LSN

DB2 用 LSO（Log Sequence Offset）而非 LSN 这个名字，但概念相同：

```
DB2 LSO:
  64 位
  日志流中的字节偏移
  单实例严格单调

接口:
  db2pd -logs   -- 当前 LSO
  db2 LIST APPLICATIONS  -- 应用 ID + 当前 LSO
```

DB2 pureScale 集群通过 GLM（Global Lock Manager，CF）协调 LSO 全局唯一。

### Materialize: timeline timestamp

Materialize 是流式增量查询引擎，事务 ID 替代为 **timeline timestamp**：

```
Materialize timestamp:
  64 位 ms 级 Unix 时间戳
  来自源数据（Kafka offset、PG WAL LSN 转换）
  AS OF 子句指定查询的逻辑时间

接口:
  SELECT * FROM v AS OF mz_now();
  SELECT * FROM v AS OF 1700000000000;
  SELECT mz_now();
```

Materialize 的 dataflow 在每个 timestamp 边界产生一个一致的视图快照。与传统数据库不同，"事务"是流入数据的"时间轴"，而非用户的 BEGIN/COMMIT 块。

### Hive ACID: writeId

Hive 3 的 ACID v2 引入了 transactional table，每行有 4 个 ACID 字段：

```
Hive ACID 行结构:
  originalTransaction : long  -- 创建该行的 writeId
  bucket              : int   -- 桶号
  rowId               : long  -- 桶内偏移
  currentTransaction  : long  -- 最新修改的 writeId
  row                 : 用户数据

writeId 由 HiveMetaStore (HMS) 集中分配：
  HMS 调用 next_writeIds (db, table, count) 获得连续的 writeId 块
  HMS 持久化到 metadata 表 (NEXT_WRITE_ID)
  client (Tez/Spark) 用分配到的 writeId 写文件 (delta/base)
```

### Iceberg: snapshot id（非传统 txid）

Iceberg 表格式没有事务 ID，使用 **snapshot id**：

```
Iceberg snapshot:
  snapshot-id    : 64 位（哈希或单调递增）
  timestamp-ms   : commit 时间
  manifest-list  : 该 snapshot 的 manifest 文件列表
  parent-snapshot-id : 上一个 snapshot

接口:
  SELECT * FROM table.snapshots;
  SELECT * FROM table FOR VERSION AS OF 12345;
  SELECT * FROM table FOR TIMESTAMP AS OF '2026-04-25';
```

snapshot id 由 commit 时确定，可以是单调（默认）也可以是哈希（早期版本）。

### Vertica: epoch（多种 epoch）

Vertica 用 epoch 而非 txid，且有多种 epoch：

| epoch | 含义 |
|-------|------|
| Current Epoch (CE) | 当前活跃 epoch |
| Last Good Epoch (LGE) | 数据已持久化到所有节点的最大 epoch |
| Checkpoint Epoch (CPE) | 最新 checkpoint 时的 epoch |
| Ancient History Mark (AHM) | 删除标记可被物理删除的 epoch 阈值 |

```sql
SELECT current_epoch FROM v_monitor.system;
SELECT * FROM EPOCHS;
SELECT MAKE_AHM_NOW();   -- 提前 AHM
```

Vertica 的"事务"通过 epoch 边界划分，不像传统的 txid。

## PostgreSQL XID Wraparound 深入剖析

PG 32 位 XID 的 wraparound 是数据库运维领域最经典的"教科书故障"。

### 基本机制

```
PG XID 空间（视为环）:
       2^31 - 1
        ^
        |
        |  "未来" (1 billion xid)
        |
当前 xid -+- 当前 xid + 2^31
        |
        |  "过去" (1 billion xid)
        |
        v
       2^31
```

任意时刻，从当前 xid 看，前后各有约 21 亿（2^31）个 xid 可被正确比较。如果某行的 xmin 落在"过去"区间外（即超过 21 亿之前），它会突然出现在"未来"区间，被解读成"还未提交的事务"，导致数据"消失"（实际是变得不可见）。

### freeze 机制

PG 通过 vacuum 把"老" tuple 的 xmin 改为 `FrozenTransactionId` (=2)，这些 tuple 被认为对所有事务可见。

```
关键参数:
  vacuum_freeze_min_age = 50000000 (5 千万)
    -- vacuum 时，xmin 比当前 xid 老 5000 万的 tuple 被 freeze
  vacuum_freeze_table_age = 150000000 (1.5 亿)
    -- 表的 relfrozenxid 比当前 xid 老 1.5 亿时，强制全表 vacuum
  autovacuum_freeze_max_age = 200000000 (2 亿)
    -- 表的 relfrozenxid 比当前 xid 老 2 亿时，强制 autovacuum (即使关闭了 autovacuum)
  vacuum_failsafe_age = 1600000000 (16 亿) (PG 14+)
    -- 接近 wraparound 时进入 failsafe 模式，跳过非必要操作
```

### datfrozenxid 与 pg_database

```sql
-- 查看每个数据库距离 wraparound 还有多少
SELECT datname,
       age(datfrozenxid) AS xid_age,
       2^31 - age(datfrozenxid) AS xid_remaining
FROM pg_database
ORDER BY xid_age DESC;

-- 查看表级
SELECT schemaname, relname,
       age(relfrozenxid) AS xid_age,
       n_dead_tup,
       last_autovacuum
FROM pg_stat_all_tables
JOIN pg_class ON oid = relid
ORDER BY xid_age DESC
LIMIT 20;
```

### wraparound 故障案例（Sentry 2015、Joyent 等）

著名的 wraparound 故障：
- 2015 年 Sentry 因 PG XID 即将 wraparound，进入只读模式数小时（autovacuum 跟不上）。
- 2018 年 Joyent Manta 数小时停机，根因之一是 wraparound + vacuum lock 死锁。
- Mailchimp、Zalando 等都公开过类似的 incident。

防御策略：
1. 监控 `datfrozenxid age`，告警阈值通常设为 10 亿（一半警戒线）。
2. 定期手动 `VACUUM FREEZE` 大表，避免 autovacuum 突发。
3. 调高 `autovacuum_vacuum_cost_limit`，让 vacuum 更激进。
4. 升级到 PG 14+ 利用 failsafe 模式。
5. PG 13+ 新建表使用 xid8 列（虽然 xmin/xmax 仍是 32 位）。

### 紧急恢复流程

如果 XID 真的接近 wraparound（distance < 1M）：

```
1. 拒绝新事务 (PG 自动进入 read-only)
2. 单用户模式启动 PG (postgres --single)
3. 执行 VACUUM FREEZE 所有大表
4. 监控 datfrozenxid age 下降
5. 退出单用户模式，正常启动
```

PG 的 wraparound 防御是它最常被诟病的"历史包袱"，但也是它教会了整个数据库行业一课：**32 位是不够的**。

## HLC vs TrueTime vs TSO 对比

### 设计目标对比

| 维度 | HLC (CockroachDB / YugabyteDB) | TrueTime (Spanner) | TSO (TiDB / OceanBase GTS) |
|------|-------------------------------|---------------------|----------------------------|
| 时钟来源 | NTP + 内部 logical | GPS + 原子钟 | 集中式服务 |
| 全局单调 | 因果序保证（happens-before） | 严格物理序 | 严格全局序 |
| 跨节点 RPC | 不需要（每个节点本地决策） | TT.now() 本地（TT 本身已同步） | 每事务必须问 PD |
| 时钟漂移容忍 | max_offset (250ms 默认) | TT 内部 ε (通常 < 7ms) | 不容忍（PD 是权威） |
| 性能瓶颈 | 无（去中心化） | TT API 延迟 + commit-wait | PD 单点 |
| 极限吞吐 | 节点本地（受网络限制） | 区域级 ~10K commits/s | ~1.5M ops/sec (PD 单点) |
| 部署成本 | NTP（几乎零） | GPS + 原子钟（昂贵） | PD 集群（中等） |
| 外部一致性 | 否（除非客户端等待） | 是（commit-wait 保证） | 否（PD 故障期间分裂） |

### 性能特性对比

```
事务 commit 路径:

HLC (CockroachDB):
  1. tablet leader 接收 commit
  2. 分配 HLC = max(local_HLC, msg_HLC) + 1
  3. Raft 复制
  4. 返回客户端
  延迟: 1 RTT (Raft) ≈ 1-10ms

TrueTime (Spanner):
  1. 接收 commit
  2. s = TT.now().latest
  3. Paxos 复制
  4. wait until TT.after(s)   <-- 关键开销
  5. 返回客户端
  延迟: 1 RTT (Paxos) + ε ≈ 10-15ms

TSO (TiDB):
  1. 客户端预先 PD 申请 commit_ts
  2. 执行 prewrite (Percolator)
  3. PD 申请 commit_ts (必要时)
  4. 执行 commit (Percolator)
  5. 返回客户端
  延迟: 2 RPC (PD) + 2 RTT (KV) ≈ 5-20ms
  优化: TSO batch / async commit
```

### 容错与可用性

```
HLC: 
  - 不依赖中心服务，单节点故障不影响其他节点的时钟
  - 时钟漂移过大 (> max_offset) 时节点自杀
  - 风险: NTP 故障导致集群分裂

TrueTime: 
  - 依赖 GPS + 原子钟
  - GPS 故障时降级到原子钟（通常仍能保持 ε 小）
  - 数据中心断电恢复后 ε 短期变大 (~100ms)
  - 不会"错"，只会"慢"

TSO: 
  - PD leader 故障 -> 整个集群事务阻塞
  - PD Raft 选举 (1-5 秒) 后恢复
  - 风险: 单点性能瓶颈（极大集群）
  - 优化: PD followers 服务 stale read，无需 leader
```

### 选型建议

| 场景 | 推荐时钟模型 | 原因 |
|------|------------|------|
| 跨大洲多数据中心 | TrueTime | 外部一致性，地理分布 |
| 单数据中心高可用 | HLC | 去中心化，运维简单 |
| 高 QPS 集群 (< 1M ops/s) | TSO | 简单，强一致 |
| 极高 QPS (> 5M ops/s) | HLC | 避免 PD 瓶颈 |
| 严格 linearizability 要求 | TrueTime | 唯一保证外部一致性 |
| 成本敏感 | HLC | 不需要特殊硬件 |
| 跨地域只读 | TSO + async TSO | PD followers 本地服务 |

## 设计争议与权衡

### 32 位 vs 64 位的"历史包袱"

PG 在 21 世纪还坚持 32 位 XID 的根本原因是**存储开销**：

```
32 位 vs 64 位 xmin/xmax 对每行的影响:
  32 位 (PG): xmin(4) + xmax(4) = 8 字节
  64 位 (假设全 64 位): xmin(8) + xmax(8) = 16 字节
  
  对 1000 字节的行: 0.8% vs 1.6% 开销
  对 100 字节的行: 8% vs 16% 开销
  对 50 字节的行: 16% vs 32% 开销
```

PG 13 的 FullTransactionId 是个折中：内存中用 64 位，存储仍用 32 位（依赖 epoch 拼接）。这避免了存储膨胀，但带来了实现复杂度（每次读 xmin/xmax 都要拼 epoch）。

InnoDB 选了 48 位（6 字节）作为折中，既比 32 位安全（280 万亿足够）又不至于浪费空间。

### 中心化 TSO vs 去中心化 HLC

```
中心化 TSO 优势:
  - 实现简单，强一致语义
  - 调试方便（时间序明确）
  - 故障检测简单

中心化 TSO 劣势:
  - 单点性能瓶颈（PD 单 leader 极限 ~1.5M ops/s）
  - 单点故障域（PD 故障 -> 集群阻塞）
  - 跨地域延迟（PD 在 us-west，事务在 ap-east -> 每次 commit 200ms）

去中心化 HLC 优势:
  - 节点本地分配，无 RPC
  - 跨地域无额外延迟
  - 横向扩展能力强

去中心化 HLC 劣势:
  - 依赖 NTP（NTP 故障可能导致一致性问题）
  - 不保证外部一致性（除非客户端 commit-wait）
  - 时钟漂移配置参数难调
```

CockroachDB 的"linearizable" 模式实际就是用客户端 commit-wait 来强制 HLC 提供外部一致性，但需要等 max_offset (250ms) 时间，性能损失可观。

### TrueTime 的硬件成本

Spanner 的 TrueTime 依赖 GPS 接收器 + 铯/铷原子钟，每个数据中心至少 2 个 (一个主一个备)。Google 自己生产，每台几千美元。

云上托管的 Spanner 把这部分成本摊到服务费里，但自建难度极高。AlloyDB Omni（Google 的"PG + Spanner 部分能力"）在自建模式下不提供 TrueTime，只提供 PG 兼容的 XID。

### 行级 vs 块级时间戳

| 方案 | 优势 | 劣势 |
|------|------|------|
| 行级 (PG xmin/xmax) | 时间精确，可见性判断快 | 每行 8 字节开销 |
| 块级 (Oracle ORA_ROWSCN 默认) | 存储开销极小 | 同块内所有行共享 SCN，查询粒度粗 |

Oracle 的 `ROW DEPENDENCIES` 选项可以打开行级 SCN，但默认关闭——大多数应用不需要这种精度。

### 暴露 txid 给用户的利弊

```
利:
  - flashback / time travel 查询基础
  - 应用层可以做"基于 txid 的去重"
  - 调试和取证

弊:
  - 暴露内部细节，迁移到其他引擎困难
  - 用户可能误用（如把 txid 当主键，但 wraparound 后失效）
  - 跨引擎语义不一致（PG xid 32 位、Oracle SCN 6 字节）
```

PG 的 `track_commit_timestamp` 默认关闭就是因为开启后每个事务额外几字节的元数据写入。

## 关键发现

### 1. 32 位是一个明确的失败案例

PG 早期、Firebird、Greenplum 经典模式都因 32 位 XID 付出了高昂运维代价。现代设计普遍 64 位以上。即使是空间敏感的 InnoDB 也选了 48 位，留足余量。

### 2. PG 的 freeze 是世界上最复杂的 GC 之一

要在 PG 21 亿 XID 用完之前完成所有"老" tuple 的 freeze，否则数据库变只读。涉及 vacuum、autovacuum、heap 结构、xmin/xmax 编码、freeze map 等多个层面，是 PG 运维的"必修课"。PG 13+ 引入的 64 位 FullTransactionId 缓解但未根除（存储仍是 32 位）。

### 3. SQL Server LSN 和 Oracle SCN 都是"全局时钟"模型

它们不是事务 ID 而是日志/系统的全局序列号。每个 commit、每个 redo 记录、每个 page 都打着这个序号。这种设计同时支持 MVCC、复制、PITR 三大需求，比 PG 的"xid + lsn 分离"更紧凑。

### 4. 分布式数据库的"时钟之战"

- TrueTime 是 Google 工程能力的极致展示，但需要专用硬件，难以复制。
- HLC 是学术界的优雅产物（Kulkarni 2014），CockroachDB 商用化最成功，YugabyteDB 跟进。
- TSO 是 Google Percolator 模型的简化版，TiDB 用工程能力（PD batch、async commit）把单点瓶颈推到 ~1.5M ops/s。
- OceanBase GTS 是 TSO 的多租户变种，每租户独立 GTS 缓解了"全局单点"问题。

### 5. 流计算引擎用 timestamp 替代 txid

Flink、Materialize、RisingWave 没有传统的事务 ID，用 timestamp / epoch / barrier id 表示"逻辑时间"。这反映了流计算本质：数据本身有时间属性，"事务"是时间窗口而非用户操作。

### 6. 表格式（Iceberg/Delta）的 snapshot id 是新方向

数据湖时代，表格式（Iceberg、Delta、Hudi）取代了传统数据库的"事务管理器"角色。snapshot id 是文件元数据级别的版本，不在 KV 层、不在行级。这种设计支持 PB 级表的事务，但失去了行级 MVCC 的灵活性。

### 7. ClickHouse 与 Snowflake 的"事务无感"哲学

它们的设计假设是：分析查询主要是只读的，写是批量的，不需要复杂事务。所以经典模型完全没有 txid 暴露给用户。Snowflake 内部有完整 MVCC，但屏蔽细节；ClickHouse 直到 24.x 才引入实验事务。

### 8. SQL 标准的沉默是创新的空间

正因为 SQL 标准没规定事务 ID 的内部结构，过去 40 年才出现了如此多的设计：32 位、48 位、64 位、96 位、128 位；中心化、去中心化、混合时钟、原子钟……这是数据库领域罕见的"百花齐放"，也是为什么"事务 ID"听起来简单，实际牵涉到从存储到分布式协调的方方面面。

### 9. wraparound 不是"不可能"，而是"未发生过"

48 位、64 位看起来巨大无比，但摩尔定律和云规模化让"不可能"变成"未发生过"。AWS RDS 已记录到一些 PG 数据库 5 年内推进了 1000 亿 XID（频繁批处理 + 大量 OLTP 事务），按这个速度 64 位也会在 30 年后耗尽。设计 100 年期数据库时仍需考虑 128 位（如 CockroachDB 的 HLC）。

### 10. 用户友好性的两极分化

```
极度友好（暴露给用户）:
  Oracle SCN_TO_TIMESTAMP / TIMESTAMP_TO_SCN
  PG pg_current_xact_id() + pg_xact_commit_timestamp
  CockroachDB cluster_logical_timestamp() + AS OF SYSTEM TIME

极度封闭（完全隐藏）:
  Snowflake (用 query_id 和 timestamp)
  BigQuery (UUID job id)
  Databricks Delta (version 但不暴露 txid)

中间地带:
  MySQL (INFORMATION_SCHEMA.INNODB_TRX 可查但很少用)
  SQL Server (LSN 主要用于复制和恢复)
```

云数据库普遍隐藏，自建/开源数据库普遍暴露。这反映了"自建用户更需要可调试性，云用户更需要简洁 API"。

## 参考资料

- ARIES 论文（事务和恢复基础）: Mohan et al., "ARIES: A Transaction Recovery Method Supporting Fine-Granularity Locking and Partial Rollbacks Using Write-Ahead Logging" (1992), TODS
- HLC 论文: Kulkarni et al., "Logical Physical Clocks and Consistent Snapshots in Globally Distributed Databases" (2014), OPODIS
- Spanner 论文: Corbett et al., "Spanner: Google's Globally-Distributed Database" (2012), OSDI / TOCS
- Percolator 论文: Peng & Dabek, "Large-scale Incremental Processing Using Distributed Transactions and Notifications" (2010), OSDI
- PostgreSQL: [Routine Vacuuming and the Visibility Map](https://www.postgresql.org/docs/current/routine-vacuuming.html)
- PostgreSQL: [pg_current_xact_id and FullTransactionId (PG 13)](https://www.postgresql.org/docs/13/release-13.html)
- PostgreSQL Source: [src/backend/access/transam/transam.c](https://github.com/postgres/postgres/blob/master/src/backend/access/transam/transam.c)
- Oracle: [SCN_TO_TIMESTAMP / TIMESTAMP_TO_SCN](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/SCN_TO_TIMESTAMP.html)
- Oracle: [System Change Numbers (SCN)](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/data-concurrency-and-consistency.html)
- SQL Server: [Transaction Log Architecture](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-log-architecture-and-management-guide)
- SQL Server: [sys.fn_dblog](https://learn.microsoft.com/en-us/sql/relational-databases/system-functions/sys-fn-dblog-transact-sql)
- MySQL: [InnoDB Multi-Versioning](https://dev.mysql.com/doc/refman/8.0/en/innodb-multi-versioning.html)
- MariaDB: [InnoDB Internals](https://mariadb.com/kb/en/innodb/)
- CockroachDB: [Living Without Atomic Clocks](https://www.cockroachlabs.com/blog/living-without-atomic-clocks/)
- CockroachDB: [Time and Hybrid Logical Clocks](https://www.cockroachlabs.com/docs/stable/architecture/transaction-layer)
- TiDB: [Timestamp Oracle in PD](https://docs.pingcap.com/tidb/stable/tso)
- YugabyteDB: [Hybrid Logical Clock](https://www.yugabyte.com/blog/yugabyte-db-time-synchronization/)
- OceanBase: [GTS Architecture](https://www.oceanbase.com/docs/oceanbase-database/oceanbase-database/V4.2.1/distributed-transactions)
- Snowflake: [Time Travel](https://docs.snowflake.com/en/user-guide/data-time-travel)
- ClickHouse: [Transactions (experimental)](https://clickhouse.com/docs/en/guides/developer/transactional)
- Hive: [HCatalog StreamingDataWriterAPI / Transactions](https://cwiki.apache.org/confluence/display/Hive/Hive+Transactions)
- Iceberg: [Snapshots](https://iceberg.apache.org/docs/latest/snapshots/)
- Delta Lake: [Transaction Log Protocol](https://github.com/delta-io/delta/blob/master/PROTOCOL.md)
- Materialize: [Timeline timestamps](https://materialize.com/docs/sql/as-of/)
- Vertica: [Epochs](https://docs.vertica.com/latest/en/admin/database-management/epoch-management/)
- DB2: [Log Sequence Number](https://www.ibm.com/docs/en/db2/11.5?topic=management-database-logging)
