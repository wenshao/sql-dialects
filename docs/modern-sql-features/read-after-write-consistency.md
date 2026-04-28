# 读后写一致性 (Read-After-Write Consistency)

用户提交一条评论后立即刷新页面，应该能看到自己的评论；订单创建成功后，下一个请求应该能查到这条订单——这种"看到自己刚写过的数据"的能力，就是读后写一致性 (Read-Your-Writes, RYW)。在分布式数据库中，主库写入到副本应用之间存在毫秒到秒级的延迟，如果应用立即把读请求路由到尚未追上的副本，用户会看到"昨天的世界"。RYW 不只是一个用户体验问题——它是分布式系统理论中**会话一致性 (session consistency)** 的核心保证之一，与单调读 (monotonic reads)、单调写、写后读 (writes-follow-reads) 共同构成"会话保证四件套"。

本文系统对比 45+ 数据库引擎在 RYW 与有界陈旧 (bounded staleness) 上的设计差异：从 PostgreSQL 的 `synchronous_commit=remote_apply` 到 CockroachDB 的 `AS OF SYSTEM TIME`、从 Spanner 的 TrueTime 外部一致性到 DynamoDB 的 `ConsistentRead` 标志、从 Cassandra 的可调一致性级别到 Aurora 的 ~1 秒副本延迟，梳理每个引擎提供哪些一致性保证、默认值是什么、有哪些 API 让应用显式表达需求。

本文聚焦"读到的数据是否包含自己最近的写入"。读请求如何路由到副本/主库见 `replica-read-routing.md`；同步复制协议本身见 `synchronous-replication.md`；事务并发隔离的快照语义见 `snapshot-isolation-details.md`。

## 为什么 RYW 与有界陈旧很重要

- **用户体验闭环**：评论、点赞、订单这类"我做了什么"的写后立即读，必须能看到自己刚做的事，否则用户会困惑甚至重复提交。
- **业务正确性**：账户扣款后立即查余额、库存扣减后立即查剩余，业务正确性依赖看到最新数据。
- **可观测性与调试**：写入一条审计日志后，立即查询是否成功；如果读不到，调试者会怀疑是写失败。
- **延迟与可用性的权衡**：等待主库确认或同步至所有副本会增加延迟和可用性敏感性，应用应能选择"够用即可"的较弱保证。
- **跨区域读本地化**：用户在东京写、在弗吉尼亚读不一定要看到自己最新的写——但应用必须显式选择是否容忍这种"地理一致性放松"。
- **分析负载与 OLTP 隔离**：分析查询通常可容忍数秒陈旧，应用层应能为分析路径声明 "max_staleness=10s" 而不是被动接受默认强一致。

## 没有 SQL 标准——纯架构与协议选择

ANSI/ISO SQL 标准从未定义"读后写一致性"。SQL:2016 规范没有任何与 RYW、单调读、有界陈旧相关的语法。所有相关能力都是各引擎的扩展：

- **会话级保证派**：MongoDB 的 `causal consistency`、Cosmos DB 的 `Session` 一致性级别、Cassandra 的 `LOCAL_QUORUM` 配合 `LWT`。
- **显式时间戳派**：CockroachDB `AS OF SYSTEM TIME`、TiDB `AS OF TIMESTAMP`、Spanner `read_timestamp` / `max_staleness`。
- **同步复制派**：PostgreSQL `synchronous_commit=remote_apply`、MySQL 半同步、SQL Server AG Synchronous Commit。
- **客户端令牌派**：DynamoDB `ConsistentRead=true`、MongoDB `readConcern: majority` + `afterClusterTime`。
- **路由强制派**：Aurora 主库读、TiDB `tidb_read_consistency=strict`、CockroachDB 默认 leaseholder 读。

理解这些机制的语义、API 形式、性能影响，对设计现代数据库或开发分布式应用都至关重要。

## 一致性谱系：从 ACID 到最终一致

```
强一致 (Strict / Linearizable)
   |
   |  external consistency (Spanner TrueTime)
   |  linearizability (single-key)
   |  sequential consistency
   |
   | -- 会话保证四件套（"会话一致性"，session consistency）：
   |  read-your-writes
   |  monotonic reads
   |  writes-follow-reads
   |  monotonic writes
   |
   |  bounded staleness (Spanner, Cosmos DB)
   |  prefix consistency (Cosmos DB)
   |
   |  causal consistency (MongoDB, COPS)
   |  PRAM consistency
   |
最终一致 (Eventual)
```

强一致最严格但延迟最高、可用性最低；最终一致最弱但延迟最低、可用性最高。RYW、单调读、有界陈旧位于谱系的中段，是大多数 OLTP 应用的"正确点"。

## 理论背景

### Bailis 2014 VLDB：Highly Available Transactions

Peter Bailis 等人在 *Highly Available Transactions: Virtues and Limitations* (PVLDB 2014) 中系统梳理了哪些隔离级别和会话保证可以与 100% 可用性 (HAT) 共存。论文核心结论：

```
HAT-compatible (无主、无协调即可实现):
  Read Committed
  Monotonic Atomic View (MAV)
  Item Cut Isolation
  Predicate Cut Isolation
  Read-Your-Writes
  Monotonic Reads
  Monotonic Writes
  Writes-Follow-Reads
  Causal Consistency

非 HAT-compatible (必须协调，CAP 中要牺牲 A):
  Snapshot Isolation
  Repeatable Read
  Serializable
  Cursor Stability
  Linearizability
  Strict Serializability
```

Bailis 论文的关键洞见：**RYW 是可以做到 100% 可用的**——只需客户端缓存最近写入并在读取时合并即可。这与 CockroachDB、Cosmos DB 等系统的设计选择一致：把 RYW 实现为客户端层（携带 token），不强制服务端协调。

### Spanner OSDI 2012：External Consistency

Google Spanner 在 OSDI 2012 论文 *Spanner: Google's Globally-Distributed Database* 中提出 **external consistency**（即 strict serializability）：

```
若事务 T1 提交于 T2 之前 (real time), 则 T1 在序列化顺序中也排在 T2 之前。

实现关键:
  TrueTime API: TT.now() 返回 [earliest, latest] 时间区间
                典型不确定度 < 7ms (基于 GPS + 原子钟)

  Commit-Wait 协议:
    1. 选定 commit timestamp s = TT.now().latest
    2. 等待直到 TT.now().earliest > s (即"本地时钟肯定已超过 s")
    3. 此时回复客户端 commit
  这保证: 任何在 s 之后开始的事务必然能看到 T 的写入。
```

Spanner 的强一致读 (`strong=true`) 利用 TrueTime 自动提供 RYW 与 monotonic reads。陈旧读 (`max_staleness=Xs`) 则放弃 strict serializability 换取低延迟和高可用。

### Vogels 2008：Eventually Consistent

Werner Vogels 在 ACM Queue 2008 *Eventually Consistent* 中给出了影响深远的"客户端中心一致性模型"分类：

```
Read-Your-Writes:
  进程 A 写后, 进程 A 后续的读必能看到该写
  (其他进程不保证)

Session Consistency:
  RYW 的扩展: 限定在同一 session 内有效
  跨 session 不保证

Monotonic Reads:
  读到值 V 后, 后续读不会看到比 V 更旧的值
  (即"时间不会倒流")

Monotonic Writes:
  同一进程的写按提交顺序应用
  (与 PRAM consistency 相关)
```

这套术语成为后续分布式数据库 (DynamoDB, Cassandra, MongoDB, Cosmos DB) 设计 API 的统一词汇表。

### PACELC 框架

Daniel Abadi 在 2010 年提出 PACELC（CAP 的扩展）：

```
CAP: 网络分区时 (Partition), 选 Consistency 还是 Availability?
PACELC: 即使没有分区时 (Else), 选 Latency 还是 Consistency?

引擎在 PACELC 中的位置:
  PA/EL: Partition 时选 A, 正常时选 L
         例: Cassandra (eventual), DynamoDB (eventual)
  PA/EC: Partition 时选 A, 正常时选 C
         例: MongoDB (默认), Cosmos DB (Bounded Staleness)
  PC/EC: Partition 时选 C, 正常时选 C
         例: Spanner, FaunaDB, Hazelcast (CP mode)
  PC/EL: Partition 时选 C, 正常时选 L (理论存在, 较少见)
         例: PNUTS (Yahoo)
```

读后写一致性的设计选择本质上是 PACELC 中的"E"维度——正常运行时是否愿意牺牲延迟换取强一致。

## 支持矩阵 (45+)

下表对 47 个引擎在 RYW 与有界陈旧能力上做全面对比。"--" 表示不支持、不适用或需要外置方案。

### 表 1：默认一致性级别

| 引擎 | 默认读一致性 | 单机/分布式 | 复制类型 | PACELC 类别 | 版本 |
|------|------------|----------|--------|-----------|------|
| PostgreSQL | 主库强一致 | 单机/Hot Standby | 流复制 (异步默认) | PC/EC (主) PA/EL (副本) | 9.0+ |
| MySQL | 主库强一致 | 单机/复制 | 异步 (默认) / 半同步 | PC/EC (主) PA/EL (副本) | 5.5+ |
| MariaDB | 主库强一致 | 单机/复制 | 异步 / 半同步 | PC/EC (主) PA/EL (副本) | 10.0+ |
| SQLite | 强一致 | 单机 | -- | -- | 单机 |
| Oracle | 主库强一致 | 单机/Data Guard | redo apply | PC/EC | 11g+ |
| SQL Server | 主库强一致 | 单机/AG | sync/async commit | PC/EC | 2012+ |
| DB2 | 主库强一致 | 单机/HADR | sync/async/super-async | PC/EC | 10.5+ |
| Snowflake | 强一致 | 云分离存储 | 单一存储层 | PC/EC | GA |
| BigQuery | 强一致 | 云存储 | Colossus | PC/EC | GA |
| Redshift | 强一致 (主) | 云分布式 | 内部复制 | PC/EC | GA |
| DuckDB | 强一致 | 单机 | -- | -- | 单机 |
| ClickHouse | 强一致 (主) | Replicated MergeTree | ZK/Keeper | PA/EL (默认) | 早期 |
| Trino | 计算引擎 | 计算/存储分离 | 取决于连接器 | -- | -- |
| Presto | 计算引擎 | 计算/存储分离 | 取决于连接器 | -- | -- |
| Spark SQL | 计算引擎 | 计算/存储分离 | 取决于连接器 | -- | -- |
| Hive | 计算引擎 | 计算/存储分离 | 取决于元存储 | -- | -- |
| Flink SQL | 流式 | 计算引擎 | -- | -- | -- |
| Databricks | 强一致 | 云分布式 | Delta Log | PC/EC | GA |
| Teradata | 强一致 | MPP | 内部复制 | PC/EC | GA |
| Greenplum | 强一致 (主) | MPP + 镜像 | 同步镜像 | PC/EC | GA |
| CockroachDB | 强一致 (lease) | 分布式 | Raft | PC/EC | 1.0+ |
| TiDB | 强一致 (leader) | 分布式 | Raft | PC/EC | 3.0+ |
| OceanBase | 强一致 (leader) | 分布式 | Paxos | PC/EC | 1.0+ |
| YugabyteDB | 强一致 (leader) | 分布式 | Raft | PC/EC | 2.0+ |
| Spanner | external consistency | 全球分布式 | Paxos + TrueTime | PC/EC | GA |
| DynamoDB | 最终一致 (默认) | 分布式 | 内部多副本 | PA/EL | GA |
| Cosmos DB | Session (默认) | 全球分布式 | 5 档可调 | 取决于级别 | GA |
| Cassandra | LOCAL_ONE (默认) | 分布式 | gossip + hinted | PA/EL | 早期 |
| ScyllaDB | LOCAL_ONE (默认) | 分布式 | Cassandra 兼容 | PA/EL | GA |
| Aurora | 强一致 (Writer) | 共享存储 | 重做记录广播 | PC/EC (Writer) PA/EL (Reader, ~1s) | GA |
| Aurora Multi-Master | 强一致 + 冲突 | 共享存储 | 重做记录广播 | PC/EC | 已弃用 |
| MongoDB | Primary (默认) | 副本集 | oplog | 可调 (readConcern) | 4.0+ |
| Couchbase | 强一致 (active) | 分布式 | DCP | PC/EC | GA |
| ArangoDB | leader 强一致 | 分布式 | Raft / async | PC/EC | GA |
| Neo4j | 主库强一致 | Causal Cluster | Raft | PC/EC | 4.0+ |
| Riak | 最终一致 | Dynamo 风格 | gossip | PA/EL | 早期 |
| FoundationDB | strict serializable | 分布式 | Paxos-like | PC/EC | GA |
| FaunaDB | strict serializable | 全球分布式 | Calvin | PC/EC | GA |
| Vitess | 主库强一致 | MySQL 分片 | 继承 MySQL | PC/EC | GA |
| Citus | 主库强一致 | PG 分片 | 继承 PG | PC/EC | GA |
| SingleStore | 强一致 | 分布式 | 同步复制 | PC/EC | GA |
| Vertica | 强一致 | MPP | k-safe 副本 | PC/EC | GA |
| TimescaleDB | 继承 PG | 单机/副本 | 继承 PG | 继承 PG | 继承 PG |
| Materialize | 强一致 | 流式视图 | 单 leader | PC/EC | GA |
| RisingWave | 强一致 | 流式视图 | 内部复制 | PC/EC | GA |
| ClickHouse Cloud | 强一致 | 云分离存储 | 单一对象存储 | PC/EC | GA |
| Athena | 强一致 | 计算/存储分离 | S3 | PC/EC | GA |
| Synapse | 强一致 | 云 MPP | 内部复制 | PC/EC | GA |
| Azure SQL | 强一致 | 云托管 | 内部副本 | PC/EC | GA |

> 统计: 约 35 个引擎默认提供主库强一致, 约 8 个 (DynamoDB, Cassandra/Scylla, Riak, Aurora Reader, Cosmos DB Session 等) 默认即提供较弱保证, 4 个 (Trino/Presto/Spark/Hive) 是计算引擎不直接持有数据。

### 表 2：显式 RYW 保证

| 引擎 | 是否提供显式 RYW API | 实现机制 | 默认开启 | 跨连接保持 |
|------|--------------------|--------|--------|----------|
| PostgreSQL | `synchronous_commit=remote_apply` (会话或事务级) | 同步至备库 redo apply | 否 | 配置生效 |
| MySQL | `WAIT_FOR_EXECUTED_GTID_SET` | 客户端等 GTID | 否 | 显式调用 |
| MariaDB | `MASTER_GTID_WAIT` | 客户端等 GTID | 否 | 显式调用 |
| SQL Server | AG Synchronous Commit + Read on Primary | 同步 commit | 否 | 路由到主 |
| Oracle | `ALTER SESSION SYNC WITH PRIMARY` | 阻塞等待 SCN | 否 | 会话级 |
| DB2 | HADR Sync mode | 同步至 standby | 否 | 配置生效 |
| Aurora | Reader Endpoint + Wait | 读取等 LSN | 否 | LSN 客户端 |
| CockroachDB | 默认 (leaseholder 读) | leaseholder 强一致 | 是 | 任意连接 |
| TiDB | 默认 (leader 读) | TSO + leader | 是 | 任意连接 |
| Spanner | Strong Read (默认) | TrueTime + Paxos | 是 | 任意连接 |
| YugabyteDB | 默认 (leader 读) | Raft + leader | 是 | 任意连接 |
| DynamoDB | `ConsistentRead=true` | 主副本读 | 否 | 请求级 |
| MongoDB | `readConcern: "majority"` + causal session | 因果令牌 | 否 (取决配置) | session 内 |
| Cosmos DB | `Session` / `Strong` 一致性 | session token | 是 (Session) | 跨请求 |
| Cassandra | `LOCAL_QUORUM` 读+写 | quorum 重叠 | 否 | 每查询 |
| ScyllaDB | `LOCAL_QUORUM` 读+写 | quorum 重叠 | 否 | 每查询 |
| Couchbase | `RequestPlus` 扫描一致性 | mutation token | 否 | 请求级 |
| FoundationDB | strict serializable (默认) | 协调器 | 是 | 任意 |
| FaunaDB | strict serializable (默认) | Calvin | 是 | 任意 |
| Riak | `R+W>N` 配合最近写覆盖 | quorum + dvv | 否 | 每查询 |
| Neo4j | leader 路由 (Causal Cluster) | bookmark | 否 | 客户端书签 |
| OceanBase | 默认 (leader 读) | Paxos + leader | 是 | 任意连接 |
| ClickHouse | `insert_quorum` + `select_sequential_consistency` | quorum 写 + 顺序读 | 否 | 会话级 |
| Vitess | `vtgate` 路由+gtid 等 | 类似 MySQL | 否 | 配置生效 |
| Snowflake | 强一致 (无副本概念) | 单一存储层 | 是 | -- |
| BigQuery | 强一致 (无副本概念) | Colossus | 是 | -- |

### 表 3：有界陈旧 API

| 引擎 | 语法/API | 单位 | 默认值 | 上限 | 备注 |
|------|---------|------|------|------|------|
| Spanner | `max_staleness` / `min_read_timestamp` / `exact_staleness` | 秒/微秒 | 15s (max) | 1h | 客户端库 + SQL hint |
| CockroachDB | `AS OF SYSTEM TIME -Xs` / `follower_read_timestamp()` | 秒/微秒 | 4.8s (内部) | 无理论上限 | SQL 子句 |
| TiDB | `AS OF TIMESTAMP NOW() - INTERVAL Xs` / `tidb_read_staleness` | 秒 | 0 (精确) | GC 时间 | SQL hint |
| YugabyteDB | `yb_follower_read_staleness_ms` / `READ TIMESTAMP` | 毫秒 | 30000 | 配置 | 会话设置 |
| Oracle ADG | `STANDBY_MAX_DATA_DELAY` | 秒 | 0 (sync) | 配置 | 超过则报错 |
| Cosmos DB | Bounded Staleness 一致性级别 (操作数 K, 时间 T) | 操作/秒 | 100K, 5min | 1M, 1day | 账户级 |
| MongoDB | `maxStalenessSeconds` (read preference) | 秒 | 90 (默认) | 90 (最小) | 客户端读偏好 |
| ClickHouse | `max_replica_delay_for_distributed_queries` | 秒 | 300 | 配置 | 分布式查询 |
| Aurora | -- (无显式有界陈旧, ~1s 平均) | -- | ~1s | -- | 无配置 |
| DynamoDB Global Tables | -- (~1s region-to-region) | -- | ~1s | -- | 无配置 |
| Cassandra | -- (按 quorum 控制) | -- | -- | -- | 不直接支持 |
| SAP HANA | `RESULT_LAG` | 秒 | 0 | 配置 | 提示 |

### 表 4：会话级路由到主库 / 提交时间戳读

| 引擎 | 会话路由到主 | 提交时间戳/读时间戳 | 说明 |
|------|------------|-----------------|------|
| PostgreSQL | `target_session_attrs=read-write` | LSN (`pg_current_wal_lsn`) | 应用层等 LSN |
| MySQL | 应用判断 read/write | GTID | `WAIT_FOR_EXECUTED_GTID_SET` |
| Oracle | 服务名/PDB 切换 | SCN | `SYS_CONTEXT('USERENV','CURRENT_SCN')` |
| SQL Server | `ApplicationIntent=ReadWrite` | LSN | -- |
| CockroachDB | leaseholder 自动 | HLC 时间戳 | 内置 |
| TiDB | tidb_replica_read=leader | TSO | `tidb_current_ts` |
| Spanner | strong=true (默认) | commit_timestamp | API 返回 |
| YugabyteDB | yb_read_from_followers=false | HLC | 默认 leader |
| MongoDB | primary read preference | clusterTime | causal consistency token |
| Cosmos DB | Strong consistency | session token | header `x-ms-session-token` |
| DynamoDB | `ConsistentRead=true` | -- | 单分片读 |
| Cassandra | LOCAL_QUORUM/QUORUM | write timestamp (微秒) | 客户端选 |
| Aurora | Writer Endpoint | -- | 路由到主 |

### 表 5：写后读 (Read After Insert) 各引擎延迟实测/标称

| 引擎 | Writer→Reader 延迟 (P50) | P99 | 强制 RYW 的代价 |
|------|------------------------|-----|---------------|
| Aurora | ~10-20ms | ~100ms (default ~1s 标称) | 路由到 Writer Endpoint |
| RDS MySQL | ~50ms (异步) | 几秒 | 半同步 + GTID 等待 |
| RDS PostgreSQL | ~10ms (流复制) | 几秒 | `synchronous_commit=remote_apply` |
| Spanner | TrueTime + Paxos ~5ms | ~50ms | 默认即 RYW |
| CockroachDB | 写后立即可读 (主分片) | -- | 默认即 RYW |
| TiDB | 写后立即可读 (leader) | -- | 默认即 RYW |
| YugabyteDB | 写后立即可读 (leader) | -- | 默认即 RYW |
| DynamoDB | 默认最终 ~10ms | ~1s | `ConsistentRead=true` |
| Cassandra | gossip ~ms-100ms | -- | LOCAL_QUORUM 读+写 |
| MongoDB | oplog tail ~10-100ms | -- | majority + causal |
| Cosmos DB Session | session token ~ms | -- | 默认 |

## 各引擎详解

### PostgreSQL：流复制与 synchronous_commit

PostgreSQL 自身没有内置 RYW 概念，但提供了灵活的同步复制配置：

```sql
-- 默认: synchronous_commit = on
--   含义: 主库在收到自身 WAL fsync 后即返回 commit 成功
--   后果: 主库已 commit, 但备库可能还未收到 WAL → 备库读看不到该写

-- 加强: synchronous_commit = remote_write (PG 9.1+)
--   含义: 等待备库收到 WAL (但不一定写盘)
--   后果: 比 on 略慢, 但备库网络故障时无影响

-- 进一步加强: synchronous_commit = remote_apply (PG 9.6+, 2016)
--   含义: 等待备库 *apply* WAL (即真正可见)
--   后果: 主库写完返回时, 备库读已经能看到该写 → 真正的 RYW
--   但: 必须配置 synchronous_standby_names 指明哪些备库参与

-- 配置:
ALTER SYSTEM SET synchronous_standby_names = 'standby1, standby2';
ALTER SYSTEM SET synchronous_commit = 'remote_apply';
SELECT pg_reload_conf();

-- 会话级临时改:
SET LOCAL synchronous_commit = 'remote_apply';
INSERT INTO orders VALUES (...);
COMMIT;
-- 此 commit 等所有同步备库 apply 后返回, 任何副本读立即可见
```

PostgreSQL 14+ 的 `target_session_attrs` 提供 libpq 级路由：

```bash
# 多副本连接串, 自动选主
psql "postgresql://node1:5432,node2:5432,node3:5432/mydb?target_session_attrs=read-write"

# 仅连只读副本 (PG 14+ 才支持 read-only)
psql "postgresql://node1:5432,node2:5432,node3:5432/mydb?target_session_attrs=read-only"

# 优先备库, 备库不可用回主
psql "...?target_session_attrs=prefer-standby"
```

应用层 LSN 等待实现 RYW（替代 `synchronous_commit=remote_apply` 的客户端方案）：

```sql
-- 主库写后获取 LSN
INSERT INTO orders VALUES (...);
SELECT pg_current_wal_lsn();   -- 例 0/1A2B3C4D

-- 备库等待 LSN
SELECT pg_wal_lsn_diff(pg_last_wal_replay_lsn(), '0/1A2B3C4D');
-- 若 >= 0 表示备库已追上, 可安全读
-- 应用循环: WHILE diff < 0 SLEEP 50ms

-- PG 14+: pg_wait_for_replay 等待备库赶上指定 LSN (扩展)
-- 截至 PG 17 仍是扩展实现而非内置 SQL 函数
```

PostgreSQL Hot Standby 默认只读：

```sql
-- 备库执行写: ERROR: cannot execute INSERT in a read-only transaction
-- 备库只读由 default_transaction_read_only=on 配合恢复模式自动设定

-- 备库可以查询自身延迟:
SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(),
       EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS lag_sec;
```

### MySQL / MariaDB：GTID + 半同步复制

MySQL 提供 GTID（Global Transaction Identifier）作为客户端等待复制赶上的"令牌"：

```sql
-- 主库写入后获取最新 GTID
SET SESSION SESSION_TRACK_GTIDS = 'OWN_GTID';
INSERT INTO orders VALUES (...);
COMMIT;
-- GTID 通过协议返回到客户端 (track_gtids 包)

-- 备库读取前等待
SELECT WAIT_FOR_EXECUTED_GTID_SET('uuid:1-100', 5);
-- 返回 0: 已追上; 1: 超时
SELECT * FROM orders WHERE id = ...;

-- MariaDB 等价:
SELECT MASTER_GTID_WAIT('0-1-100', 5);
```

半同步复制配置（增强但不能完全 RYW）：

```sql
-- 加载半同步插件
INSTALL PLUGIN rpl_semi_sync_master SONAME 'semisync_master.so';
INSTALL PLUGIN rpl_semi_sync_slave  SONAME 'semisync_slave.so';

-- 主库
SET GLOBAL rpl_semi_sync_master_enabled = 1;
SET GLOBAL rpl_semi_sync_master_timeout = 1000;  -- 1 秒超时退化

-- 备库
SET GLOBAL rpl_semi_sync_slave_enabled = 1;
START SLAVE;

-- 含义: 主库 commit 等至少一个备库收到 binlog 后返回
-- 注意: 仅保证 binlog 写入, 不保证已 *apply*
-- 因此: 主库 commit 后立即在备库读, 仍可能读不到 (binlog 还在 relay log 队列)
-- MySQL 8.0 引入 AFTER_SYNC 模式 (vs AFTER_COMMIT) 改善某些场景
```

ProxySQL `causal_reads` 实现 RYW：

```ini
# proxysql.cnf
mysql_servers:
- { hostgroup_id=1, hostname="master", ... }
- { hostgroup_id=2, hostname="slave1", ... }

mysql_query_rules:
- { rule_id=1, match_pattern="^SELECT.*FOR UPDATE", destination_hostgroup=1 }
- { rule_id=2, match_pattern="^SELECT", destination_hostgroup=2 }
```

```sql
-- ProxySQL 会自动跟踪每个连接的最新 GTID
-- 路由到从库前先 SELECT WAIT_FOR_EXECUTED_GTID_SET, 保证 RYW
SET @session_track_gtids := 'OWN_GTID';   -- 启用 GTID tracking
INSERT INTO orders VALUES (...);  -- 主库写
SELECT * FROM orders WHERE id = LAST_INSERT_ID();  -- ProxySQL 路由到从库, 自动等 GTID
```

### Oracle Active Data Guard

Oracle 通过 SCN（System Change Number）和 ADG 提供物理副本与 RYW 控制：

```sql
-- 主库写入后获取 SCN
INSERT INTO orders VALUES (...);
COMMIT;
SELECT CURRENT_SCN FROM v$database;   -- 例如 12345678

-- ADG 备库等待应用至该 SCN
ALTER SESSION SYNC WITH PRIMARY;    -- 阻塞至同步
SELECT * FROM orders;

-- 显式控制陈旧度
ALTER SESSION SET STANDBY_MAX_DATA_DELAY = 30;
SELECT * FROM orders;
-- 若 ADG 落后超过 30 秒则报 ORA-03172, 而不返回陈旧数据

-- ADG real-time apply (默认开启)
-- redo log 收到即应用, 而非等归档完成

-- 服务名路由 (TNS)
ORCL_RW = (DESCRIPTION=(ADDRESS=...)(CONNECT_DATA=(SERVICE_NAME=orcl)))
ORCL_RO = (DESCRIPTION=(ADDRESS=...)(CONNECT_DATA=(SERVICE_NAME=orcl_ro)))
-- DBMS_SERVICE.START_SERVICE/STOP_SERVICE 可在 ADG 上启停服务

-- DRCP (Database Resident Connection Pool) 自动选择 ADG vs Primary
```

### SQL Server AlwaysOn Availability Groups

SQL Server 提供同步/异步两种 commit 模式：

```sql
CREATE AVAILABILITY GROUP OrdersAG
FOR DATABASE Orders
REPLICA ON
  'PrimaryNode'
    WITH (ENDPOINT_URL = 'TCP://primary:5022',
          AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
          FAILOVER_MODE = AUTOMATIC,
          SECONDARY_ROLE(ALLOW_CONNECTIONS = NO)),
  'SecondaryNode1'
    WITH (ENDPOINT_URL = 'TCP://secondary1:5022',
          AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
          SECONDARY_ROLE(ALLOW_CONNECTIONS = READ_ONLY,
                         READ_ONLY_ROUTING_URL = 'TCP://secondary1:1433'));

-- AVAILABILITY_MODE = SYNCHRONOUS_COMMIT 含义:
--   主库 commit 等备库 *持久化* 日志后返回
--   备库 redo apply 仍是异步, 因此读备库仍可能滞后
--   实测延迟通常 < 100ms

-- ASYNCHRONOUS_COMMIT 模式:
--   主库 commit 不等备库, 延迟可达数秒
--   读备库可能严重滞后

-- 客户端路由
-- 连接串: Server=AGListener;ApplicationIntent=ReadOnly;Database=Orders
-- 自动路由到只读副本

-- 强制 RYW (路由到主):
-- ApplicationIntent=ReadWrite (默认)
```

### DB2 HADR

DB2 提供四种 HADR 同步模式：

```sql
-- SYNC: 主库 commit 等备库 fsync redo
UPDATE DB CFG FOR mydb USING HADR_SYNCMODE SYNC;

-- NEARSYNC: 主库 commit 等备库收到 redo 至内存
UPDATE DB CFG FOR mydb USING HADR_SYNCMODE NEARSYNC;

-- ASYNC: 主库 commit 不等备库
UPDATE DB CFG FOR mydb USING HADR_SYNCMODE ASYNC;

-- SUPERASYNC (10.5+): 备库延迟接受 (跨 WAN)
UPDATE DB CFG FOR mydb USING HADR_SYNCMODE SUPERASYNC;

-- 备库读 (HADR Standby Reads, 10.1+)
DB2 CONNECT TO mydb USER db2inst1
DB2 GET DB CFG FOR mydb;
-- HADR_TARGET_LIST 配置主备 list
-- HADR_PEER_WINDOW 配置主备同步窗口
```

### CockroachDB：AS OF SYSTEM TIME 与 Follower Reads

CockroachDB 默认强一致（leaseholder 读），但提供丰富的陈旧读 API：

```sql
-- 默认: 写后立即读, 强一致 (从 leaseholder 读)
INSERT INTO orders VALUES (1, 100);
SELECT * FROM orders WHERE id = 1;   -- 立即可见

-- AS OF SYSTEM TIME (1.x+): 历史时间点读
SELECT * FROM orders AS OF SYSTEM TIME '-10s';
-- 读 10 秒前的快照

-- 跟随者读 (19.1 实验性, 19.2 GA, 21.1 默认 closed timestamp)
SELECT * FROM orders AS OF SYSTEM TIME follower_read_timestamp();
-- follower_read_timestamp() = current_timestamp - 4.8s 默认
-- 此读可走任何副本, 不需 leaseholder 路由 (低延迟)

-- 自定义陈旧时间
SELECT * FROM orders AS OF SYSTEM TIME experimental_follower_read_timestamp();   -- 已弃用
SELECT * FROM orders AS OF SYSTEM TIME with_min_timestamp(now()::timestamp - INTERVAL '5s');

-- 全局只读事务的陈旧读 (21.1+)
BEGIN AS OF SYSTEM TIME '-3s';
SELECT * FROM orders;
SELECT * FROM customers;
COMMIT;
-- 整个事务用同一历史时间点

-- 跟随者读的关键参数
SET CLUSTER SETTING kv.closed_timestamp.target_duration = '3s';   -- 关闭时间戳间隔
SET CLUSTER SETTING kv.closed_timestamp.side_transport_interval = '200ms';
-- closed_timestamp_target = 3s, follower_read_timestamp = -3s + leeway

-- 路由到最近副本 (Geo)
SET CLUSTER SETTING server.cluster_name = 'mycluster';
-- locality-aware routing 自动从最近副本读
```

CockroachDB 的强 RYW 保证：默认所有读都强一致（leaseholder 路由），无需任何额外配置。陈旧读是显式选择。

### TiDB：tidb_read_staleness 与 Stale Read

TiDB 5.0 (2021) 引入 Stale Read：

```sql
-- 默认: 强一致 (TSO + leader 读)
INSERT INTO orders VALUES (1, 100);
SELECT * FROM orders WHERE id = 1;   -- 立即可见

-- 5.0+ Stale Read: 会话级
SET tidb_read_staleness = -5;  -- 读取 5 秒前的快照
SELECT * FROM orders;

-- 5.0+ Stale Read: SQL hint
SELECT * FROM orders AS OF TIMESTAMP NOW() - INTERVAL 5 SECOND;
SELECT * FROM orders AS OF TIMESTAMP '2024-01-01 10:00:00';

-- 5.4+ Stale Read 增强:
-- 自动选最近副本 (locality-aware)
SET @@tidb_replica_read = 'closest-replicas';

-- 6.0+ tidb_read_consistency
SET @@tidb_read_consistency = 'strict';   -- 默认: 强一致
SET @@tidb_read_consistency = 'weak';     -- 异步读 (TiFlash)

-- TiDB Stale Read 实现:
-- TSO 是逻辑时间戳 (8 字节: 物理 ms 高 46 位 + 逻辑 18 位)
-- Stale Read 用 (TSO - Xs) 作为读时间戳 + 直接走 follower
-- 优势: 不需经 leader, 跨地域低延迟
-- 限制: 只能读已 GC 之前的数据 (tidb_gc_life_time 默认 10min)

-- 结合 placement rules 实现地理本地读
ALTER TABLE orders SET TIFLASH REPLICA 2 LOCATION LABELS "region";
```

### Spanner：External Consistency 与 Bounded Staleness

Spanner 是首个生产级提供 external consistency 的全球分布式数据库：

```sql
-- 默认 strong read (external consistency)
SELECT * FROM Orders WHERE OrderId = 123;
-- TrueTime + Paxos 保证: 读到所有 commit_timestamp <= TT.now() 的写入

-- 客户端 API (Java)
TimestampBound bound = TimestampBound.strong();
ResultSet rs = client.singleUse(bound).executeQuery(stmt);

-- Bounded Staleness (毫秒级)
TimestampBound bound = TimestampBound.ofMaxStaleness(5, TimeUnit.SECONDS);
// 容许 5 秒陈旧, 但 Spanner 选最新可用副本
ResultSet rs = client.singleUse(bound).executeQuery(stmt);

-- Exact Staleness (精确历史时间)
TimestampBound bound = TimestampBound.ofExactStaleness(10, TimeUnit.SECONDS);
// 读 10 秒前的快照
ResultSet rs = client.singleUse(bound).executeQuery(stmt);

-- Min Read Timestamp
TimestampBound bound = TimestampBound.ofMinReadTimestamp(timestamp);
// 读取 >= 指定 timestamp 的快照
ResultSet rs = client.singleUse(bound).executeQuery(stmt);

-- Read Timestamp (绝对时间)
TimestampBound bound = TimestampBound.ofReadTimestamp(timestamp);
// 读取 == 指定 timestamp 的精确快照
ResultSet rs = client.singleUse(bound).executeQuery(stmt);
```

```sql
-- SQL hint 形式 (GoogleSQL dialect)
SELECT * FROM Orders
@{ READ_TIMESTAMP = '2024-01-01T10:00:00Z' };

SELECT * FROM Orders
@{ MAX_STALENESS = '5s' };
```

Spanner 选择有界陈旧读的代价：

- 强读：必须从 Paxos leader 或满足 TrueTime 条件的副本读，跨区域可能 50-200ms
- 5s 陈旧读：可走最近副本，可能 < 10ms
- 历史精确读：选最近副本 + 时间过滤，无需协调

### YugabyteDB：Hybrid Logical Clock + Follower Reads

YugabyteDB 默认 leader 读，提供 follower reads 配置：

```sql
-- 默认: leader 强一致读
INSERT INTO orders VALUES (1, 100);
SELECT * FROM orders WHERE id = 1;   -- 立即可见

-- 启用 follower reads (会话级)
SET yb_read_from_followers = true;
SELECT * FROM orders;
-- 此读可走任何副本

-- 配置陈旧上限
SET yb_follower_read_staleness_ms = 30000;   -- 默认 30 秒
-- 选择延迟 < 30s 的副本读, 否则回退到 leader

-- 全局配置
ALTER SYSTEM SET yb_read_from_followers = true;
ALTER SYSTEM SET yb_follower_read_staleness_ms = 10000;

-- 显式时间戳读 (PostgreSQL hint 风格)
SELECT * FROM orders /*+ Set(yb_read_time '2024-01-01 10:00:00') */;

-- HLC (Hybrid Logical Clock):
-- 8 字节: 物理时间 (微秒) + 逻辑序号
-- 比 TrueTime 简单, 但仅在单集群内提供 monotonic 保证
-- 跨集群一致性需额外协议
```

YugabyteDB 的设计选择：默认强一致 + 显式陈旧读，类似 CockroachDB。区别在于 HLC vs TrueTime（YugabyteDB 不依赖 GPS/原子钟）。

### DynamoDB：ConsistentRead 标志

DynamoDB 是 RYW 设计的经典案例：

```python
import boto3
client = boto3.client('dynamodb')

# 写入
client.put_item(
    TableName='Orders',
    Item={'OrderId': {'S': '123'}, 'Amount': {'N': '100'}}
)

# 默认: 最终一致读 (从任意副本)
response = client.get_item(
    TableName='Orders',
    Key={'OrderId': {'S': '123'}}
)
# 可能读不到刚写入的数据 (副本延迟 ~ms)

# 强一致读: ConsistentRead=true (2012 起)
response = client.get_item(
    TableName='Orders',
    Key={'OrderId': {'S': '123'}},
    ConsistentRead=True
)
# 从主副本读, 立即可见
# 代价: 2x RCU (1 strongly consistent read = 2 eventually consistent reads)
```

DynamoDB Global Tables：

```python
# 跨区域多主写入, 始终最终一致
# Region A 写: client_a.put_item(...)
# Region B 读: ~1 秒延迟可见

# 即使 ConsistentRead=true 也只保证本区域 RYW
# 跨区域 RYW 需应用层逻辑 (例如 sticky session)
```

DynamoDB Streams + Lambda 用于变更跟踪，但不直接提供更强 RYW。

### Cassandra / ScyllaDB：可调一致性级别

Cassandra 的核心设计是 **tunable consistency**——每个查询独立选择一致性级别：

```sql
-- CQL 一致性级别 (per-query)
CONSISTENCY ALL;            -- 所有副本响应
CONSISTENCY EACH_QUORUM;    -- 每个数据中心 quorum
CONSISTENCY QUORUM;         -- 全局 quorum (>= N/2 + 1)
CONSISTENCY LOCAL_QUORUM;   -- 本地 DC quorum (默认推荐)
CONSISTENCY ONE;            -- 单一副本响应
CONSISTENCY LOCAL_ONE;      -- 本地 DC 单一副本 (默认)
CONSISTENCY ANY;            -- 任意 (含 hinted handoff)
CONSISTENCY SERIAL;         -- LWT 串行
CONSISTENCY LOCAL_SERIAL;   -- 本地 LWT 串行

-- 实现 RYW 的标准模式:
--   写: LOCAL_QUORUM (写至少 N/2+1 副本)
--   读: LOCAL_QUORUM (读至少 N/2+1 副本)
-- W + R > N 保证至少一个副本同时被读和写, RYW 自然成立

-- RF=3, LOCAL_QUORUM 写 + LOCAL_QUORUM 读:
--   W=2, R=2, N=3, W+R=4 > 3 ✓

INSERT INTO orders (id, amount) VALUES (1, 100)
USING CONSISTENCY LOCAL_QUORUM;

SELECT * FROM orders WHERE id = 1
USING CONSISTENCY LOCAL_QUORUM;   -- 必能读到刚写入

-- LWT (Lightweight Transaction) 提供更强保证:
INSERT INTO orders (id, amount) VALUES (1, 100) IF NOT EXISTS;
-- 用 Paxos 保证线性一致, SERIAL 一致性
```

Cassandra 的"读修复" (read repair)：

```sql
-- 后台读修复机制:
-- 每次 LOCAL_QUORUM 读时, 协调节点比较所有读到的副本数据
-- 若发现差异 (复制延迟造成), 修复落后的副本
-- 这是 Cassandra 实现"最终一致 → 最终一致 + RYW (W+R>N)"的关键

-- 配置:
ALTER TABLE orders WITH read_repair_chance = 0.1;        -- 10% 概率全副本修复
ALTER TABLE orders WITH dclocal_read_repair_chance = 0.1; -- 仅本 DC

-- Cassandra 4.0+ 改为 BLOCKING/NONE 配置:
ALTER TABLE orders WITH read_repair = 'BLOCKING';
-- BLOCKING: 协调节点等修复完成才返回 (LOCAL_QUORUM 标准)
-- NONE: 不在读路径修复 (推到 anti-entropy 后台)
```

ScyllaDB 兼容 Cassandra CQL，consistency 语义完全一致，性能上有所优化（C++ 实现 + shard-per-core）。

### Aurora：Reader 与 Writer 端点

AWS Aurora 在 2017 年发布时即提供 ~1 秒平均副本延迟（基于共享存储设计）：

```python
# Writer 端点: 主库, 强一致
writer_conn = psycopg2.connect("host=mycluster.cluster-XXX.us-east-1.rds.amazonaws.com")

# Reader 端点: 自动负载均衡到只读副本
reader_conn = psycopg2.connect("host=mycluster.cluster-ro-XXX.us-east-1.rds.amazonaws.com")

# 写入主库
cur = writer_conn.cursor()
cur.execute("INSERT INTO orders VALUES (1, 100)")
writer_conn.commit()

# Reader 读 (可能滞后 ~10-50ms)
cur2 = reader_conn.cursor()
cur2.execute("SELECT * FROM orders WHERE id = 1")
# 大概率读到, 但不保证

# 强 RYW: 切回 Writer Endpoint
cur3 = writer_conn.cursor()
cur3.execute("SELECT * FROM orders WHERE id = 1")
# 必读到
```

Aurora 的副本延迟特点：

- 共享存储架构：所有副本读同一份持久化数据，无 binlog/redo apply 延迟
- 实测延迟：写后 ~10-20ms 副本可见
- 标称 ~1 秒：是 SLA 上限，实际几乎总是远小于
- 不支持显式有界陈旧 API（不像 Spanner/CockroachDB）

Aurora 多主 (Multi-Master, 已废弃)：

```sql
-- 此模式下两个 Writer 都可写, 但冲突需应用解决
-- 由于复杂性已于 2023 年弃用
-- 推荐: 单主 + Reader Endpoints
```

Aurora Global Database：

```sql
-- 跨 region 复制, ~1 秒副本延迟
-- 使用基于共享存储的物理复制, 不是 binlog

-- 主区域故障时副区域可升主 (Disaster Recovery)
-- 副区域只读副本不保证 RYW (跨区域)
```

### MongoDB：Read Concerns 与 Causal Consistency

MongoDB 副本集提供细粒度的 read/write concerns：

```javascript
// 写关注 (write concern)
db.orders.insertOne(
    { _id: 1, amount: 100 },
    { writeConcern: { w: "majority", wtimeout: 5000 } }
)
// w: "majority" 等大多数副本确认 (必要的 RYW 前提)
// w: 1 (默认)        仅主库确认
// w: 3              至少 3 个副本确认

// 读关注 (read concern, 3.2+)
db.orders.find({_id: 1}).readConcern("local")     // 默认: 主库本地 (可能未提交)
db.orders.find({_id: 1}).readConcern("majority")  // 大多数已提交
db.orders.find({_id: 1}).readConcern("linearizable") // 4.2+: 线性化
db.orders.find({_id: 1}).readConcern("snapshot")  // 4.0+: 事务快照

// 读偏好 (read preference)
db.orders.find({_id: 1}).readPref("primary")            // 默认
db.orders.find({_id: 1}).readPref("secondary")          // 副本
db.orders.find({_id: 1}).readPref("nearest")            // 最近节点
db.orders.find({_id: 1}).readPref("primaryPreferred")
db.orders.find({_id: 1}).readPref("secondaryPreferred")

// maxStalenessSeconds (read preference 选项)
db.orders.find({}).readPref("secondary", [], { maxStalenessSeconds: 90 })
// 仅选延迟 < 90s 的副本

// 因果一致性 (Causal Consistency, 3.6+)
session = db.getMongo().startSession({ causalConsistency: true });
db = session.getDatabase("test");

db.orders.insertOne({_id: 1, amount: 100});      // 写, 获取 clusterTime
db.orders.find({_id: 1});                         // 同 session 读, 自动等 clusterTime
// 即使读副本, 也保证 RYW

// 跨连接传播 causal token
clusterTime = session.getClusterTime();
otherSession = otherClient.startSession({ causalConsistency: true });
otherSession.advanceClusterTime(clusterTime);
// otherSession 后续读保证看到 >= clusterTime 的写入
```

### Cosmos DB：5 档一致性

Azure Cosmos DB 提供业界最丰富的一致性级别选择：

```csharp
// 账户级配置 (默认)
CosmosClient client = new CosmosClient(connectionString,
    new CosmosClientOptions { ConsistencyLevel = ConsistencyLevel.Session });

// 5 档一致性, 由强到弱:
// Strong:           线性一致, 多区域读延迟最高
// Bounded Staleness: 容许 K 个操作或 T 时间陈旧
// Session:          单 session 内 RYW + monotonic reads (默认)
// Consistent Prefix: 保证不读到顺序错乱的版本
// Eventual:         最终一致, 延迟最低

// 请求级覆盖 (仅可降低账户级别)
ItemResponse<Order> response = await container.ReadItemAsync<Order>(
    "1", new PartitionKey("order"),
    new ItemRequestOptions { ConsistencyLevel = ConsistencyLevel.Eventual });
```

Bounded Staleness 配置：

```javascript
// 通过 Azure Portal / ARM 配置
{
  "consistencyPolicy": {
    "defaultConsistencyLevel": "BoundedStaleness",
    "maxStalenessIntervalInSeconds": 86400,     // 24 小时
    "maxStalenessPrefix": 100000                // 10 万操作
  }
}

// 客户端读时, Cosmos DB 保证:
//   读到的数据落后主区域不超过 86400 秒 OR 100000 个操作
//   两者任一达到都触发同步
```

Session token 机制：

```csharp
// 每次写入返回 session token (类似 MongoDB clusterTime)
ItemResponse<Order> writeResp = await container.CreateItemAsync(order);
string sessionToken = writeResp.Headers.Session;

// 后续读传 session token, 保证 RYW
ItemResponse<Order> readResp = await container.ReadItemAsync<Order>(
    "1", new PartitionKey("order"),
    new ItemRequestOptions { SessionToken = sessionToken });

// session token 跨进程传递 (例如 HTTP cookie 或 JWT claim)
// 实现"用户登录后, 任何区域任何节点读, 始终看到自己的数据"
```

### Couchbase：扫描一致性

Couchbase N1QL 查询提供 scan_consistency 选项：

```javascript
// not_bounded (默认): 最终一致, 延迟最低
cluster.query("SELECT * FROM orders WHERE id = 1",
    { scanConsistency: "not_bounded" });

// at_plus: 等待至 mutation token 时间点
const mutationToken = cluster.upsert("orders", "1", {amount: 100}).mutationToken;
cluster.query("SELECT * FROM orders WHERE id = 1",
    { scanConsistency: "at_plus", consistentWith: mutationToken });
// 类似 MongoDB causal consistency

// request_plus: 等待至当前时刻所有提交可见
cluster.query("SELECT * FROM orders WHERE id = 1",
    { scanConsistency: "request_plus" });
// 强 RYW, 等索引追上
```

### FoundationDB / FaunaDB：strict serializable 默认

这两个引擎默认即提供 strict serializability（最强保证），无须任何配置：

```python
# FoundationDB
import fdb
fdb.api_version(710)
db = fdb.open()

@fdb.transactional
def write_order(tr, id, amount):
    tr['orders/' + str(id)] = str(amount)

@fdb.transactional
def read_order(tr, id):
    return tr['orders/' + str(id)]

write_order(db, 1, 100)
print(read_order(db, 1))  # 必读到, strict serializable
```

```javascript
// FaunaDB
const client = new faunadb.Client({ secret: 'secret' });

await client.query(
    q.Create(q.Collection('orders'),
             { data: { id: 1, amount: 100 } })
);

const result = await client.query(
    q.Match(q.Index('orders_by_id'), 1)
);
// 必读到, Calvin 协议保证 strict serializable
```

代价：每写都需协调，跨区域延迟较高（FaunaDB 跨 region 写 ~50-100ms）。

### Neo4j Causal Cluster

Neo4j 4.0+ Causal Clustering 提供基于 bookmark 的 RYW：

```cypher
// 客户端 driver 自动收集 bookmark
const session = driver.session({
    defaultAccessMode: neo4j.session.WRITE
});

// 写入
const result = await session.run("CREATE (o:Order {id: 1, amount: 100})");
const bookmark = session.lastBookmark();

// 跨 session/连接 RYW: 传 bookmark
const session2 = driver.session({
    defaultAccessMode: neo4j.session.READ,
    bookmarks: [bookmark]   // 等待集群追上 bookmark 后再执行
});
const result2 = await session2.run("MATCH (o:Order {id: 1}) RETURN o");
```

### ClickHouse：insert_quorum + select_sequential_consistency

ClickHouse 在 ReplicatedMergeTree 表上提供可调一致性：

```sql
-- 默认: 异步复制, RYW 不保证
CREATE TABLE events (
    event_id UInt64,
    user_id UInt64,
    event_time DateTime
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/events', '{replica}')
ORDER BY (user_id, event_time);

-- 写入时要求至少 K 个副本确认 (会话级)
SET insert_quorum = 2;          -- 默认 0 (异步)
SET insert_quorum_timeout = 60000;
INSERT INTO events VALUES (...);   -- 至少 2 个副本确认才返回

-- 顺序一致读 (会话级)
SET select_sequential_consistency = 1;
SELECT * FROM events;
-- ClickHouse 等本副本已应用至 insert_quorum 时的 log entry, 才返回
-- 实现 RYW

-- 关键: insert_quorum + select_sequential_consistency 必须配合使用
-- 仅设其一无效

-- 全局/默认值配置
ALTER USER default SETTINGS insert_quorum = 2;
ALTER USER default SETTINGS select_sequential_consistency = 1;
```

### SAP HANA System Replication

```sql
-- HANA System Replication 模式:
--   SYNC: 主备日志同步 commit
--   SYNCMEM: 主等备库内存接收 (默认推荐)
--   ASYNC: 主不等备库

-- Active/Active (Read-Enabled) 副本:
ALTER SYSTEM ALTER CONFIGURATION ('global.ini', 'SYSTEM')
SET ('system_replication', 'enable_log_replay_in_secondary') = 'true';

-- 客户端 hint 控制陈旧度
SELECT * FROM orders WITH HINT(RESULT_LAG('1S'));   -- 容许 1 秒陈旧
SELECT * FROM orders WITH HINT(RESULT_LAG('NONE')); -- 强一致 (主)
```

### Vitess (MySQL 分片)

```yaml
# Vitess 通过 vtgate 路由 + GTID 跟踪实现 RYW
# vtgate 配置:
serving_keyspace: mydb
gateway:
  type: tabletgateway
  gtidset_tracker: true

# 客户端连接时启用 RYW
gtid_mode: TRACK
```

### CrateDB

CrateDB 默认 quorum 写 + 主副本读，提供强一致：

```sql
SET refresh_interval = '1s';   -- 索引刷新频率影响 RYW

INSERT INTO orders VALUES (1, 100);
REFRESH TABLE orders;          -- 强制刷新使读可见
SELECT * FROM orders WHERE id = 1;
```

### Riak：R+W>N 配置

```python
import riak

client = riak.RiakClient()
bucket = client.bucket('orders')

# 写时设置 W
obj = bucket.new('1', data={'amount': 100})
obj.store(w='quorum')

# 读时设置 R
obj2 = bucket.get('1', r='quorum')

# W=2, R=2, N=3 → W+R=4 > N=3 → RYW 保证
# W='all' R='one' 也成立, 但延迟更高/RYW 弱
```

## Spanner External Consistency 深度剖析

Spanner 是首个生产级提供"全球 strict serializability"的数据库，其核心是 TrueTime API：

```cpp
// TrueTime API
class TT {
  TimeInterval now();   // 返回 [earliest, latest]

  bool after(Timestamp t);   // TT.now().earliest > t
  bool before(Timestamp t);  // TT.now().latest < t
};

// 提交协议 (Commit Wait)
void Commit(Transaction txn) {
  // 1. 选定 commit timestamp
  Timestamp s = TT.now().latest;

  // 2. Paxos 提交 (至少 N/2+1 副本接受)
  paxos.propose(txn.writes, s);

  // 3. Commit Wait: 等到本地时钟肯定超过 s
  while (!TT.after(s)) sleep(1ms);
  // 此时, 任何在 s 之后开始的事务必然能看到 txn 的写入

  // 4. 回复客户端
  return s;
}
```

TrueTime 的物理基础：

```
GPS 接收器: ~ms 精度, 几乎所有数据中心
原子钟:     冗余, 防止 GPS 故障

每个数据中心:
  master 时间服务器 (持有 GPS + 原子钟)
  从机定期 polling master
  时间不确定度 epsilon 由 master 间分歧 + 网络延迟决定

实测 epsilon:
  典型: 1-7ms
  最坏: ~10ms
  Commit Wait 平均代价: ~5ms 阻塞
```

为什么 TrueTime 解决了一致性问题？

```
传统 NTP 时钟:
  本地时钟可能比真实时钟快 X 或慢 X (X 未知)
  无法用本地时钟做 commit_timestamp

TrueTime:
  TT.now() 返回 [earliest, latest], 真实时间必在此区间内
  所以 Commit Wait 后真实时间必 > s
  其他副本读时, 用 TT.now().earliest 作为 read_timestamp
  保证读到所有 commit_timestamp <= read_timestamp 的写入
```

External Consistency 的形式化定义：

```
若 T1 在 real time t1 提交, T2 在 real time t2 开始, 且 t1 < t2:
  则 T2 必能看到 T1 的写入

形式化:
  对任意可见时间戳分配:
    commit_timestamp(T1) < commit_timestamp(T2)  当 t1 < t2
  且 read_timestamp(T) 满足:
    所有 commit_timestamp(T') < read_timestamp(T) 的 T' 对 T 可见
```

### Spanner 陈旧读 vs 强读延迟对比

| 读类型 | 跨区域延迟 (典型) | 一致性保证 | 适用场景 |
|------|---------------|---------|--------|
| Strong | 50-200ms | external consistency | 用户登录后看自己资料 |
| Bounded(5s) | 5-20ms | 5s 内一致 | 仪表盘数据 |
| Bounded(15s) | 5-10ms | 15s 内一致 | 报表数据 |
| Exact(1h) | 5ms | 1 小时前快照 | 历史查询 |

## Cassandra Tunable Consistency 深度剖析

Cassandra 的可调一致性是其核心设计原则，每查询独立选择：

### W + R > N 的数学保证

```
RF = N (每条数据 N 个副本)
W: 写需要确认的副本数
R: 读需要确认的副本数

W + R > N 保证:
  写时至少 W 个副本有最新值
  读时至少 R 个副本被查询
  W + R > N → 必有至少一个副本同时被读和写
  → 读必能看到该写

具体配置 (RF=3):
  W=ALL(3) + R=ONE(1):     W+R=4 > 3 ✓ 强一致 (但写慢)
  W=QUORUM(2) + R=QUORUM(2): W+R=4 > 3 ✓ 平衡 (推荐)
  W=ONE(1) + R=ALL(3):     W+R=4 > 3 ✓ 强一致 (但读慢)
  W=ONE(1) + R=ONE(1):     W+R=2 < 3 ✗ 最终一致, 不保证 RYW
```

### LOCAL_QUORUM vs QUORUM

```
EACH_QUORUM (跨 DC quorum):
  W: 每个 DC 都达 quorum 才返回
  R: 每个 DC 都达 quorum 才返回
  保证: 跨 DC 强一致, 但延迟高

QUORUM (全局 quorum):
  W: 总副本数的 quorum (跨 DC 累计)
  R: 总副本数的 quorum
  保证: 全局强一致

LOCAL_QUORUM (本 DC quorum):
  W: 本 DC 副本的 quorum
  R: 本 DC 副本的 quorum
  保证: 本 DC 内 RYW, 跨 DC 最终一致
  适用: 多 DC 部署, 用户访问就近 DC, 不需跨 DC 强一致
  延迟: 本 DC 内通信, 通常 < 10ms
```

### 读修复 (Read Repair)

```
每次 LOCAL_QUORUM 读触发的修复流程:
  1. 协调节点 R 个副本各发查询, 收集所有结果
  2. 比较时间戳 (last-write-wins)
  3. 若有副本数据落后, 后台异步推送修复
  4. 4.0+ BLOCKING 模式: 协调节点等修复完成才返回客户端

修复保证:
  - 经常被读的数据更可能保持一致
  - 冷数据靠 anti-entropy (Merkle Tree 比较) 后台修复
```

### LWT (Lightweight Transaction)

```sql
-- 标准 LWT: Paxos 实现单条 CAS
INSERT INTO orders (id, amount) VALUES (1, 100) IF NOT EXISTS;
UPDATE orders SET amount = 200 WHERE id = 1 IF amount = 100;

-- SERIAL / LOCAL_SERIAL 一致性:
--   SERIAL: 全局 Paxos, 跨 DC
--   LOCAL_SERIAL: 仅本 DC Paxos
-- 4 阶段 Paxos: prepare, promise, propose, commit
-- 性能比普通写慢 4 倍

-- 应用场景:
-- 1. 抢锁 (避免重复创建)
-- 2. 计数器 (但 Cassandra 有 counter 类型, 不需 LWT)
-- 3. 状态机迁移 (订单 pending → paid)
```

## 关键设计决策与权衡

### 决策 1：服务端强制 vs 客户端控制

**服务端强制 (CockroachDB / TiDB / Spanner / YugabyteDB)**：

```
优点: 应用无须配置, RYW 默认成立
缺点: 强一致带来更高延迟, 用户无法选择牺牲一致换延迟
适用: 数据库定位为"事务数据库", 用户期望像单机 PG/MySQL 一样
```

**客户端控制 (DynamoDB / Cassandra / Cosmos DB)**：

```
优点: 灵活, 应用可按场景选择 (强读 vs 最终读)
缺点: 应用必须懂一致性模型, 默认值若非强一致, 用户易忽略
适用: NoSQL/最终一致系 (Dynamo 论文派系)
```

### 决策 2：会话保证 vs 全局保证

**全局保证 (Spanner / FoundationDB / FaunaDB)**：

```
任何客户端任何时刻, 系统行为一致
最强但最贵 (commit_wait, 跨区域 quorum)
```

**会话保证 (MongoDB / Cosmos DB / Couchbase)**：

```
仅在同一 session/客户端 RYW
跨 session 不保证
轻量, 适合"用户"为单位的应用
```

### 决策 3：物理时间 vs 逻辑时间

**物理时间 (Spanner TrueTime)**：

```
优点: 跨集群可比较, 用户友好 (timestamp 是真实时间)
缺点: 必须 GPS + 原子钟, 大多数公司做不到
```

**逻辑时间 (CockroachDB HLC, TiDB TSO, Cassandra microsecond)**：

```
优点: 仅靠软件实现, 无硬件依赖
缺点: 跨集群不可比, 时间戳不直接对应真实时间
```

### 决策 4：RYW 的实现层次

| 层次 | 例子 | 优缺点 |
|------|------|------|
| 应用代码 | 自己缓存最近写入 | 灵活但难写, 易出错 |
| 客户端库 | MongoDB causal session | 自动, 仅本 client |
| 驱动 | Connector/J ReplicationDriver | 自动, 跨 client 不传 |
| 代理 | ProxySQL causal_reads | 透明, 跨 client 共享 GTID |
| 数据库 | CockroachDB 默认 | 透明, 用户无感知 |

## 各引擎延迟与一致性对比

### 跨区域读延迟 (典型, 同地域内 ms 级)

| 引擎 | 强一致 | 最终一致 | 有界陈旧 | RYW (会话) |
|------|------|--------|--------|----------|
| Spanner | 50-200ms (跨大洲) | -- | 5-20ms | 50-200ms |
| CockroachDB | 跨 region 50-200ms | -- | 跟随者 ~10ms | 跨 region 50ms |
| TiDB | leader 50ms (跨 region) | -- | follower ~10ms | leader 50ms |
| Cosmos DB Strong | 全球 100ms+ | -- | -- | 100ms+ |
| Cosmos DB Session | -- | -- | -- | 区域内 ms |
| DynamoDB | 区域内 ~10ms | 区域内 ~5ms | -- | ConsistentRead 10ms |
| Cassandra LOCAL_QUORUM | 本 DC 10ms | 本 DC 5ms | -- | 本 DC 10ms |
| Aurora | Writer 10ms | Reader 10-50ms | -- | Writer 10ms |
| MongoDB | primary 10ms | secondary 30ms | maxStalenessSec 30ms | causal 30ms |

### 默认配置下 RYW 是否成立

| 引擎 | 默认 RYW (同连接) | 默认 RYW (跨连接) | 启用强 RYW 的代价 |
|------|----------------|----------------|---------------|
| PostgreSQL (单机) | 是 | 是 | -- |
| PostgreSQL + Hot Standby | 主连接是 | 副本不保证 | remote_apply 或路由 |
| MySQL (单机) | 是 | 是 | -- |
| MySQL + 复制 | 主是 | 副本不保证 | 半同步 + 路由 |
| Aurora | Writer 是 | Reader 不保证 | 用 Writer Endpoint |
| CockroachDB | 是 | 是 | 默认 |
| TiDB | 是 | 是 | 默认 |
| Spanner | 是 | 是 | 默认 (commit_wait 代价) |
| YugabyteDB | 是 | 是 | 默认 |
| DynamoDB | 否 (最终一致) | 否 | ConsistentRead=true (2x RCU) |
| Cassandra (默认 LOCAL_ONE) | 否 | 否 | LOCAL_QUORUM W+R |
| MongoDB (默认 primary read) | 是 | 是 (主连接) | -- |
| MongoDB (secondary read) | 否 | 否 | causal session |
| Cosmos DB Session (默认) | 是 | 仅同 session | session token 跨进程 |
| Cosmos DB Eventual | 否 | 否 | 升级到 Session 或 Strong |
| Aurora Global DB | Writer 是 | 跨 region 不保证 | 等同步 |

## 实现模式与陷阱

### 陷阱 1：Sticky Session 不等于 RYW

许多应用以为"把同一用户的读写都路由到同一台服务器"就能 RYW。这只在该服务器是主库时成立——若 sticky 到副本，副本仍可能滞后。

```
正确做法:
1. 同 user 总是写主库 (任何主库节点)
2. 读时显式选择: 主库 OR 副本 + 等待 RYW token
3. 不要依赖"上次读的服务器还能继续读"
```

### 陷阱 2：异步通知 + 立即查询

```python
# 错误模式
def create_order(order):
    db.execute("INSERT INTO orders ...")
    queue.publish("order_created", order_id)
    # 消费者立即查询 orders 表
    # 可能查不到! (主库已写但副本未同步)

# 正确模式
def create_order(order):
    db.execute("INSERT INTO orders ...")
    db.commit()
    # 在事务提交后再发消息
    queue.publish("order_created", order_id)
    # 消费者还要做副本等待 (或路由到主库)
```

### 陷阱 3：RYW 不等于 monotonic reads

```
RYW: 我能看到自己刚写的
Monotonic Reads: 我看到值 V 后, 不会再看到比 V 旧的值

例:
  T1: 用户更新 amount 100 → 200
  T2: (从副本 A) 读到 amount = 200
  T3: (从副本 B, 副本 B 还在 100) 读到 amount = 100  ← 违反 monotonic reads

要同时保证 RYW 和 monotonic reads, 通常需要:
  - 同一会话固定一个副本 (sticky), OR
  - 客户端记录 max(read_timestamp), 后续读 >= 该 timestamp
```

### 陷阱 4：异构系统的因果传播

```
用户在 service A 写 order, 然后 service B 收到通知去查 order:
  service A → DB.write
  service A → message_queue.publish
  service B ← message_queue.consume
  service B → DB.read   ← 跨服务 RYW

正确实现:
  - service A 写完返回 GTID/LSN/commit_timestamp
  - 通过 message 传播到 service B
  - service B 读时用该 token 等待

许多系统忽略此点, 用 sleep(1s) 凑合, 不可靠。
```

## 微服务架构下的 RYW 模式

### Outbox 模式

```
事务中同时写业务表和 outbox 表:
  BEGIN;
  INSERT INTO orders ...;
  INSERT INTO outbox (event, payload) ...;
  COMMIT;

后台进程读 outbox, 投递到消息队列, 删除已投递条目。
保证: 业务写和事件发布原子性。但仍需配合 RYW 处理消费者侧。
```

### Event Sourcing

```
所有变更记录为事件流, 状态由事件聚合得到。
RYW 实现:
  - 写事件后获取事件序列号 (SN)
  - 读时投影状态至 >= 该 SN
  - 等价于 Spanner read_timestamp
```

### CQRS

```
写模型 + 读模型分离:
  写模型: OLTP, 强一致
  读模型: 反范式化, 最终一致, 异步同步

挑战: 写后立即从读模型查询可能滞后
解决:
  - UI 临时直接查写模型 (短期 RYW)
  - 用 lambda architecture 同时查最近事件 + 读模型
  - 应用层维护"待同步"标记
```

## 关键发现

1. **绝大多数关系型数据库默认强一致**：PostgreSQL/MySQL/Oracle/SQL Server/DB2 在主库读默认即提供 RYW，只有当应用显式路由到副本时才会破坏。

2. **NoSQL 系统多默认弱一致**：DynamoDB、Cassandra、Riak 默认最终一致，需显式启用强读 (`ConsistentRead`、`QUORUM`)。

3. **现代分布式 SQL (CockroachDB / TiDB / Spanner / YugabyteDB) 默认强一致**：以 leaseholder/leader 路由 + Raft/Paxos 实现，应用无须配置。

4. **PostgreSQL 9.6 (2016) 的 `synchronous_commit=remote_apply` 是流复制 RYW 的关键**：之前的 `on` 仅保证 WAL fsync，副本仍可能滞后。

5. **Spanner 的 TrueTime 是 external consistency 的物理基础**：GPS + 原子钟把时钟不确定度压到 <10ms，commit_wait 代价 ~5ms。

6. **Cassandra 的 W+R>N 是去中心化系统 RYW 的经典手法**：LOCAL_QUORUM(W=2)+LOCAL_QUORUM(R=2) 在 RF=3 时保证 RYW，且仅本 DC 通信。

7. **Bailis 2014 证明 RYW 与 100% 可用性兼容**：客户端缓存最近写入即可，无须服务端协调——这是 CockroachDB / Cosmos DB 设计依据。

8. **DynamoDB ConsistentRead 自 2012 起**：标志位简单但代价显著（2x RCU），且不跨 Global Tables 区域。

9. **CockroachDB AS OF SYSTEM TIME 自 1.x**：闭时间戳 (closed timestamp) 协议让 follower 读默认 4.8 秒陈旧度，跨 region 大幅降低延迟。

10. **TiDB Stale Read 自 5.0 (2021)**：相对较晚，但提供 SQL 标准的 `AS OF TIMESTAMP` 语法，与 Spanner 风格接近。

11. **Cosmos DB 的 5 档一致性独树一帜**：Bounded Staleness 和 Consistent Prefix 在业界少见，提供细粒度的 staleness vs latency 控制。

12. **Aurora 的"~1 秒副本延迟"是营销标称，实际通常 < 50ms**：基于共享存储的物理复制无 binlog/redo apply 串行化瓶颈。

13. **MongoDB 4.0+ causal consistency**：通过 cluster time + session token 提供跨连接 RYW，是因果一致性的工业实现典范。

14. **会话保证四件套 (RYW / monotonic reads / writes-follow-reads / monotonic writes) 仍是分布式系统教科书核心**：Vogels 2008 提出，至今仍是 API 设计指导。

15. **客户端层 RYW (Sticky / GTID / token) 比服务端协调代价低**：但需应用配合，易出错。服务端实现 (lease, Paxos leader) 透明但延迟高。

## 实现 RYW 的工程清单

设计支持 RYW 的现代数据库时应考虑：

1. **明确默认一致性级别**：是否默认 RYW？跨连接是否保证？文档要明示。
2. **提供 token 机制**：commit_timestamp / GTID / LSN / cluster_time / session_token 之一，让客户端可显式同步。
3. **支持有界陈旧 API**：让低延迟场景能显式放弃强一致。
4. **路由层感知一致性**：代理 (ProxySQL / pgpool) 应能识别 RYW 需求并自动等待。
5. **跨区域语义清晰**：Global Table / Multi-Region 是否提供跨区域 RYW？通常不，文档要明确。
6. **监控副本延迟**：暴露 lag (秒) / lag (operations) 指标，让运维和应用能感知。
7. **文档说明常见陷阱**：sticky session、消息队列、CQRS 下 RYW 不自动成立。
8. **测试场景**：对每个一致性级别，写明在何种网络/节点故障下保证仍成立。

## 参考资料

- Bailis et al., *Highly Available Transactions: Virtues and Limitations*, PVLDB 2014
- Corbett et al., *Spanner: Google's Globally-Distributed Database*, OSDI 2012
- Vogels, *Eventually Consistent*, ACM Queue 2008
- Berenson et al., *A Critique of ANSI SQL Isolation Levels*, SIGMOD 1995
- Adya, *Weak Consistency: A Generalized Theory and Optimistic Implementations for Distributed Transactions*, MIT PhD Thesis 1999
- Abadi, *Consistency Tradeoffs in Modern Distributed Database System Design (PACELC)*, IEEE Computer 2012
- DeCandia et al., *Dynamo: Amazon's Highly Available Key-value Store*, SOSP 2007
- Lakshman & Malik, *Cassandra: A Decentralized Structured Storage System*, LADIS 2009
- PostgreSQL: [synchronous_commit](https://www.postgresql.org/docs/current/runtime-config-wal.html#GUC-SYNCHRONOUS-COMMIT)
- PostgreSQL: [target_session_attrs](https://www.postgresql.org/docs/current/libpq-connect.html)
- MySQL: [WAIT_FOR_EXECUTED_GTID_SET](https://dev.mysql.com/doc/refman/8.0/en/gtid-functions.html)
- CockroachDB: [Follower Reads](https://www.cockroachlabs.com/docs/stable/follower-reads.html)
- CockroachDB: [AS OF SYSTEM TIME](https://www.cockroachlabs.com/docs/stable/as-of-system-time.html)
- TiDB: [Stale Read](https://docs.pingcap.com/tidb/stable/stale-read)
- Spanner: [Read Types](https://cloud.google.com/spanner/docs/reads)
- DynamoDB: [Read Consistency](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.ReadConsistency.html)
- Cassandra: [Configuring Data Consistency](https://cassandra.apache.org/doc/latest/cassandra/architecture/dynamo.html#tunable-consistency)
- MongoDB: [Causal Consistency](https://www.mongodb.com/docs/manual/core/read-isolation-consistency-recency/)
- Cosmos DB: [Consistency Levels](https://learn.microsoft.com/en-us/azure/cosmos-db/consistency-levels)
- Aurora: [Replication](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Replication.html)
- YugabyteDB: [Follower Reads](https://docs.yugabyte.com/preview/develop/build-global-apps/follower-reads/)
- Couchbase: [N1QL Scan Consistency](https://docs.couchbase.com/server/current/n1ql/n1ql-language-reference/index.html)
