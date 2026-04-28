# 同步复制 (Synchronous Replication)

异步复制下主库一旦提交就不再等待——副本可能落后几毫秒、几秒、甚至几小时；同步复制把这个权衡彻底翻过来：主库必须等到至少一个副本"承诺"持久化后才向客户端返回 COMMIT。一边是"零数据丢失 (RPO=0)"的承诺，一边是"每次写入都吃一次跨节点 RTT"的延迟代价——这是过去三十年高可用数据库设计中最反复辩论、也最容易被误读的一组取舍。本文系统对比 45+ 数据库引擎在同步复制、半同步复制、Quorum 复制、ACK 模式、超时降级等维度上的设计差异。

## 为什么同步复制重要

数据库复制的目的是把一台机器上的事务在另一台机器上重现，使得任何一台机器宕机时数据都不会丢失、业务都能继续运行。围绕"主库等不等副本"，业界形成了三条路线：

1. **异步复制 (Async Replication)**：主库提交后立即返回客户端，副本"异步追赶"。延迟最低但 RPO 不为零——主库突然断电时，未发送的 binlog/WAL 会永久丢失。
2. **半同步复制 (Semi-Synchronous Replication)**：主库提交前必须收到至少一个副本的 ACK，但 ACK 的语义只是"我收到了 binlog"，不一定"我已经持久化"或"我已经回放"。MySQL 半同步复制是这一路线的典型代表。
3. **全同步复制 (Synchronous / Quorum Replication)**：主库提交前必须等到副本明确持久化（甚至应用）。Oracle Maximum Protection、PostgreSQL `synchronous_commit=remote_apply`、Spanner Paxos 多数派提交都属于这条路线。

三者本质都是在 **RPO（恢复点目标）vs Latency（提交延迟）vs Availability（可用性）** 这三角中选位置：

- 异步：低延迟 + 高可用 + 弱 RPO 保证
- 半同步：中延迟 + 中可用 + 中等 RPO 保证（仅"binlog 已传输"）
- 全同步：高延迟 + 受副本拖累 + 强 RPO=0 保证

理解这些机制的差异，对设计任何高可用数据库系统都是基础功——也是阅读各家文档时最容易踩到的术语雷区。

> 本文不涉及 SQL 标准——同步复制至今没有任何 ISO SQL 标准化条款，所有语法和语义都是厂商专有的。`logical-replication-gtid.md` 涵盖逻辑复制与事务标识，`replica-read-routing.md` 涵盖副本读路由，本文聚焦在**写路径上**主从间的同步语义。

## ACK 时机：write / flush / apply 三档

任何同步复制方案都必须回答一个核心问题：**副本在什么时刻向主库回 ACK？** 业界几乎统一为三档，从最快但最弱到最慢但最强：

| ACK 模式 | 副本端动作 | 故障窗口 | 典型实现 |
|---------|-----------|---------|---------|
| `write` / `remote_write` | 副本进程收到字节并写入 OS 缓冲区即 ACK | 副本 OS crash 会丢 | PG `synchronous_commit=remote_write` |
| `flush` / `on` | 副本 fsync 到磁盘后才 ACK | 副本可见性滞后 | PG `synchronous_commit=on`，MySQL AFTER_SYNC |
| `apply` / `remote_apply` | 副本 redo/binlog 已回放并对查询可见后才 ACK | 几乎无窗口，最慢 | PG `synchronous_commit=remote_apply`，Oracle Maximum Protection |

`write` 比 `flush` 快、`flush` 比 `apply` 快，差距通常一个数量级。理解这三档模式，对正确解释 MySQL 的 AFTER_SYNC、PG 的 5 档 `synchronous_commit`、Oracle Data Guard 的 SYNC/ASYNC/FAR SYNC 至关重要。

## 没有 SQL 标准——纯架构与协议选择

ANSI/ISO SQL 标准从未定义复制、同步语义、Quorum 等概念。SQL:2016 也没有 `CREATE REPLICATION` 这样的语法。所有相关能力都是各引擎独立扩展：

- **配置参数派**：PostgreSQL `synchronous_commit`、`synchronous_standby_names`，MySQL `rpl_semi_sync_master_enabled`、`rpl_semi_sync_master_timeout`。
- **DDL/系统视图派**：SQL Server `AVAILABILITY_MODE = SYNCHRONOUS_COMMIT`，Oracle `LOG_ARCHIVE_DEST_n` 配置串。
- **协议级 Quorum 派**：CockroachDB Raft、Spanner Paxos、TiDB Raft，写入"多数派持久化"是协议本身的语义，不需要额外开关。
- **架构选择派**：DynamoDB Global Tables 异步、Cosmos DB 多 region 强一致 / 有界陈旧、Aurora "六副本三 AZ"基于法定写。

本文剩下的部分对 45+ 引擎在这五个维度上做权威对比。

## 支持矩阵

### 1. 原生同步复制能力总览

| 引擎 | 原生同步复制 | 半同步复制 | Quorum (k-of-n) | ACK 模式 | 超时降级到异步 | 首次提供 |
|------|------------|-----------|----------------|---------|--------------|---------|
| PostgreSQL | 是 | -- | 是 (10+) | write/flush/apply | 是 | 9.1 (2011) |
| MySQL | -- | 是 (5.5+) | -- | AFTER_SYNC / AFTER_COMMIT | 是 | 5.5 (2010) |
| MariaDB | -- | 是 | -- | AFTER_COMMIT (主流) | 是 | 5.3 (2012) |
| SQLite | -- | -- | -- | -- | -- | 单机 |
| Oracle | Data Guard SYNC | -- | Far Sync | LGWR SYNC | 是（按 protection mode） | Oracle 9i (2001) |
| SQL Server | AlwaysOn Sync-Commit | -- | -- | flush | 是 | 2012 |
| DB2 | HADR SYNC / NEARSYNC | -- | -- | flush / write | 是 | 8.2 (2006) |
| Snowflake | -- | -- | -- | -- (托管) | -- | -- |
| BigQuery | -- | -- | -- | -- | -- | -- |
| Redshift | -- | -- | -- | -- | -- | -- |
| DuckDB | -- | -- | -- | -- | -- | 单机 |
| ClickHouse | `insert_quorum` | -- | 是 | flush | 是 | 早期 |
| Trino | -- | -- | -- | -- | -- | 计算引擎 |
| Presto | -- | -- | -- | -- | -- | 计算引擎 |
| Spark SQL | -- | -- | -- | -- | -- | 计算引擎 |
| Hive | -- | -- | -- | -- | -- | 计算引擎 |
| Flink SQL | checkpoint barrier | -- | -- | -- | -- | 流处理 |
| Databricks | -- | -- | -- | -- | -- | 计算引擎 |
| Teradata | Dual Active SYNC | -- | -- | flush | 是 | 早期 |
| Greenplum | mirror sync | -- | -- | flush | 是 | 早期 |
| CockroachDB | Raft majority | -- | 是 (3/5/7) | apply | 否 (协议级) | 1.0 (2017) |
| TiDB | Raft majority | -- | 是 | apply | 否 | 1.0 (2017) |
| OceanBase | Paxos majority | -- | 是 | apply | 否 | 0.5 (2014) |
| YugabyteDB | Raft majority | -- | 是 | apply | 否 | 1.0 (2018) |
| SingleStore | 同步复制（默认） | -- | -- | flush | 是 | 早期 |
| Vertica | K-safety mirror | -- | -- | flush | -- | 早期 |
| Impala | -- | -- | -- | -- | -- | 计算引擎 |
| StarRocks | 内部多副本 quorum | -- | 是 | flush | 否 | GA |
| Doris | 内部多副本 quorum | -- | 是 | flush | 否 | GA |
| MonetDB | -- | -- | -- | -- | -- | -- |
| CrateDB | quorum (默认) | -- | 是 | flush | 是 | GA |
| TimescaleDB | 继承 PG | -- | 继承 PG | 继承 PG | 继承 PG | 继承 PG |
| QuestDB | -- | -- | -- | -- | -- | -- |
| Exasol | 内部冗余 | -- | -- | -- | -- | -- |
| SAP HANA | System Replication SYNC | -- | -- | flush / sync mem | 是 | 2.0+ |
| Informix | HDR SYNC | -- | -- | flush | 是 | 早期 |
| Firebird | -- | -- | -- | -- | -- | -- |
| H2 | -- | -- | -- | -- | -- | 单机 |
| HSQLDB | -- | -- | -- | -- | -- | 单机 |
| Derby | -- | -- | -- | -- | -- | 单机 |
| Amazon Aurora | 6/3 quorum | -- | 是 | flush | 否 | GA |
| Amazon Athena | -- | -- | -- | -- | -- | 计算引擎 |
| Azure Synapse | -- | -- | -- | -- | -- | -- |
| Azure SQL | Sync-Commit Replica | -- | -- | flush | 是 | GA |
| Google Spanner | Paxos majority | -- | 是 | apply | 否 | GA |
| DynamoDB | Multi-AZ flush | -- | 是 (3 AZ) | flush | 否 | GA |
| Cosmos DB | 一致性级别可调 | -- | 是 | apply (Strong) | 否 | GA |
| Materialize | -- | -- | -- | -- | -- | 流式物化 |
| RisingWave | -- | -- | -- | -- | -- | 流式物化 |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | -- |
| DatabendDB | -- | -- | -- | -- | -- | -- |
| Yellowbrick | -- | -- | -- | -- | -- | -- |
| Firebolt | -- | -- | -- | -- | -- | -- |
| MySQL Group Replication | majority quorum | -- | 是 | flush | 否（多数派失败时阻写） | 5.7.17 (2016) |
| Galera Cluster | 认证型同步 | -- | 是（多数派） | apply | 否（脑裂时停服） | 早期 |

> 统计：约 22 个引擎提供某种形式的同步或半同步复制，约 9 个分布式引擎通过共识协议天然实现 Quorum 同步（Raft/Paxos），约 14 个引擎或在架构上不适用，或为完全托管不暴露同步控制。

### 2. 同步级别详分（write / flush / apply）

| 引擎 | write 等价 | flush 等价 | apply 等价 | 默认值 |
|------|-----------|-----------|-----------|--------|
| PostgreSQL | `remote_write` | `on` (= `remote_flush`) | `remote_apply` (9.6+) | `on` |
| MySQL 半同步 | -- | `AFTER_SYNC` (5.7+, 默认) | -- (需 Group Replication) | `AFTER_SYNC` |
| MySQL Group Replication | -- | flush | apply (after_certification) | flush |
| MariaDB 半同步 | -- | -- (相当于 AFTER_COMMIT) | -- | AFTER_COMMIT |
| Oracle Data Guard | LGWR ASYNC | LGWR SYNC | LGWR SYNC + Maximum Protection (apply lag = 0) | varies |
| SQL Server AlwaysOn | -- | Sync-Commit (flush) | -- | -- |
| DB2 HADR | `ASYNC` | `NEARSYNC` (write 到副本 mem 即 ACK) / `SYNC` (flush) | `SUPERASYNC` 反向 | NEARSYNC |
| ClickHouse | -- | `insert_quorum` (flush) | -- | -- |
| CockroachDB | -- | -- | Raft apply | apply |
| Spanner | -- | -- | Paxos apply | apply |
| YugabyteDB | -- | -- | Raft apply | apply |
| TiDB | -- | -- | Raft apply | apply |
| SAP HANA | `ASYNC` | `SYNCMEM` (write 到副本内存) | `SYNC` (flush) | varies |

> 关键观察：MySQL 半同步在 5.7+ 默认 `AFTER_SYNC`（也称 lossless），意思是"主库等副本写到 binlog 文件 + flush 后再向客户端返回 COMMIT"，但这本质是 **flush 模式**，副本并未回放。MariaDB 历史上多用 AFTER_COMMIT 语义，主库 commit 后才等副本 ACK。

### 3. Quorum / k-of-n 配置

| 引擎 | Quorum 语法 | 默认副本数 | 默认 quorum | 可调 |
|------|-----------|-----------|-----------|------|
| PostgreSQL | `synchronous_standby_names = 'ANY 2 (s1,s2,s3)'` | 用户配置 | 用户配置 | 是 |
| PostgreSQL FIRST | `synchronous_standby_names = 'FIRST 2 (s1,s2,s3)'` | 用户配置 | 优先级 | 是 |
| MySQL Group Replication | majority of group | 3 (推荐) | 2/3 | 否（协议） |
| Galera Cluster | majority | 3 (推荐) | 2/3 | 否 |
| Oracle Data Guard | Far Sync 多目标 | 配置 | 配置 | 是 |
| CockroachDB | Raft majority | 3 (默认) | 2/3 | 是 (3/5/7) |
| TiDB | Raft majority | 3 (默认) | 2/3 | 是 |
| Spanner | Paxos majority | 5 (per split) | 3/5 | 否 (托管) |
| YugabyteDB | Raft majority | 3 (默认) | 2/3 | 是 |
| OceanBase | Paxos majority | 3 (默认) | 2/3 | 是 |
| StarRocks | replication_num | 3 (推荐) | quorum_num | 是 |
| Doris | replication_num | 3 (推荐) | quorum_num | 是 |
| Aurora | 6 copies / 3 AZ | 6 (固定) | 4/6 写, 3/6 读 | 否 |
| DynamoDB | Multi-AZ | 3 AZ | 2/3 | 否 |
| ClickHouse | `insert_quorum=N` | 副本数 | N | 是 |
| CrateDB | `replication = number_of_replicas` | 1 (默认) | quorum 内部 | 是 |

> Quorum 写入需要满足 R + W > N（其中 N 是副本数，R 是读 quorum，W 是写 quorum）才能保证强一致读。Aurora 是个特例——6 副本中写 4、读 3，能容忍丢一个 AZ 加一个副本。

### 4. 超时降级行为

| 引擎 | 超时参数 | 默认值 | 超时后行为 | 重新升级条件 |
|------|---------|-------|-----------|------------|
| PostgreSQL | -- (无超时降级) | -- | 写入永久阻塞直到副本 ACK | 副本恢复 |
| MySQL 半同步 | `rpl_semi_sync_master_timeout` | 10000 ms | 自动降级为异步复制 | 至少一个副本恢复并 ACK |
| MariaDB 半同步 | `rpl_semi_sync_master_timeout` | 10000 ms | 自动降级为异步复制 | 副本重连 |
| Oracle Maximum Protection | -- | -- | 主库 shutdown（拒绝写入）| 副本恢复 |
| Oracle Maximum Availability | LOG_ARCHIVE_DEST_n NET_TIMEOUT | 30s | 自动降级为异步 | 副本恢复 |
| SQL Server AG | SESSION_TIMEOUT | 10s | 副本进入 NOT_SYNCHRONIZED；主库继续 | 副本重连 |
| DB2 HADR | HADR_TIMEOUT | 120s | peer disconnected → 异步 | 重连握手 |
| SAP HANA | -- | -- | 异步降级 | 重连 |
| CockroachDB | 无（协议级） | -- | quorum 不足 → 写入阻塞 | 多数派恢复 |
| TiDB | 无（协议级） | -- | 同上 | 同上 |
| Spanner | 无（协议级） | -- | 同上 | 同上 |
| Galera | -- | -- | 脑裂时拒绝写入 | quorum 恢复 |

> 关键差异：传统主从架构（MySQL、Oracle、SQL Server）几乎都内置"超时降级到异步"的策略，因为不降级会让单副本故障导致整个数据库不可写。共识协议系（Cockroach/TiDB/Spanner）则**不降级**——只要多数派活着就能继续，少数派故障在协议内消化；但如果损失多数派则集体阻塞。

### 5. 同步复制 vs 异步复制取舍对比

| 维度 | 异步复制 | 半同步复制 | 全同步复制 |
|------|---------|-----------|-----------|
| 提交延迟 | 最低（仅本地 fsync） | 本地 fsync + 副本网络往返 + 副本 fsync | 同左 + 副本回放等待 |
| RPO | 不为零（可能丢秒级到分钟级） | 通常为零（除超时降级窗口） | 严格为零 |
| 单副本故障时主库可用性 | 不影响 | 超时降级或阻写（取决于配置） | 阻写或 shutdown |
| 跨数据中心可行性 | 优秀 | 受 RTT 影响显著 | 几乎不可行（除非延迟容忍） |
| 实现复杂度 | 低 | 中 | 高（需要 wait_for_ack 协议） |
| 常见配置 | 单副本或多副本 | 1 ~ 2 个副本 | 同步副本 + 多个异步副本 |

## 各引擎同步复制详解

### MySQL 半同步复制（Semi-Synchronous Replication）

MySQL 在 5.5（2010）首次引入半同步复制插件 `rpl_semi_sync_master` / `rpl_semi_sync_slave`，是工业界第一个广泛部署的半同步复制方案。其核心权衡：

- 主库提交事务后，等待至少一个副本回 ACK 表示"我已经收到 binlog 并写入 relay log"
- 超时（默认 10s）后自动降级为异步复制，使得单副本故障不会导致主库阻塞
- 5.7.3（2013）引入 `AFTER_SYNC` 模式（lossless replication），把 ACK 时机从"COMMIT 之后"改到"COMMIT 之前"，确保即使主库在 ACK 后立即崩溃也不会丢数据

```sql
-- 1. 安装半同步插件（5.5+）
INSTALL PLUGIN rpl_semi_sync_master SONAME 'semisync_master.so';
INSTALL PLUGIN rpl_semi_sync_slave  SONAME 'semisync_slave.so';

-- 8.0.26+ 改名（更中性）
INSTALL PLUGIN rpl_semi_sync_source  SONAME 'semisync_source.so';
INSTALL PLUGIN rpl_semi_sync_replica SONAME 'semisync_replica.so';

-- 2. 主库启用
SET GLOBAL rpl_semi_sync_master_enabled = ON;
SET GLOBAL rpl_semi_sync_master_timeout = 10000;            -- 10 秒
SET GLOBAL rpl_semi_sync_master_wait_for_slave_count = 1;   -- 至少 1 个副本 ACK
SET GLOBAL rpl_semi_sync_master_wait_point = AFTER_SYNC;    -- 5.7+ 默认（lossless）
-- 可选：AFTER_COMMIT (旧默认), AFTER_SYNC (新默认)

-- 3. 副本启用
SET GLOBAL rpl_semi_sync_slave_enabled = ON;
STOP SLAVE IO_THREAD;
START SLAVE IO_THREAD;

-- 4. 监控状态
SHOW STATUS LIKE 'Rpl_semi_sync_master_status';
-- ON: 半同步生效；OFF: 已降级为异步
SHOW STATUS LIKE 'Rpl_semi_sync_master_yes_tx';     -- 半同步成功的事务数
SHOW STATUS LIKE 'Rpl_semi_sync_master_no_tx';      -- 降级为异步的事务数
SHOW STATUS LIKE 'Rpl_semi_sync_master_clients';    -- 当前半同步副本数
SHOW STATUS LIKE 'Rpl_semi_sync_master_avg_net_wait_time';  -- 平均网络等待 us
```

### AFTER_SYNC vs AFTER_COMMIT 深入对比

`rpl_semi_sync_master_wait_point` 是半同步复制最关键、也最容易被误解的参数：

```
AFTER_COMMIT （5.5 的原始实现，5.7 之前默认）
  时间线:
    1. 主库写 binlog
    2. 主库写 InnoDB redo
    3. 主库存储引擎 commit (持久化)
    4. 主库等待副本 ACK    <-- ACK 在 commit 之后
    5. 主库向客户端返回 OK

  风险: 第 3 步之后、第 4 步 ACK 之前，主库突然宕机
        从客户端角度此事务"未确认"，主库 commit 已持久
        副本未收到 binlog → 故障切换后副本作主，事务丢失
        （但其他客户端可能已经在主库读到此事务的结果）
        这就是经典的"幻读"或"幻提交"问题（phantom commit）

AFTER_SYNC （5.7.2 引入，5.7.3 GA，5.7+ 默认，称 lossless replication）
  时间线:
    1. 主库写 binlog (写到 OS buffer + fsync)
    2. 主库等待副本 ACK    <-- ACK 在 commit 之前
    3. 主库存储引擎 commit (持久化)
    4. 主库向客户端返回 OK

  优势: 副本必定收到 binlog，主库才向客户端返回 OK
        即使第 3 步后主库宕机，副本也能保证至少与已确认的客户端一致
        这是真正的"无损"语义

  代价: 提交延迟略增（本地 fsync 与远程 ACK 不能并行）
        InnoDB 内部需要锁等待，可能影响吞吐
```

### MySQL Group Replication（5.7.17+，2016）

MySQL Group Replication 是基于 Paxos 变体（XCom）的多写复制方案，**协议级提供同步复制**，写入需要多数派接受才能 commit：

```sql
-- 配置 group replication（每个节点）
SET GLOBAL group_replication_group_name = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
SET GLOBAL group_replication_local_address = '192.168.1.10:33061';
SET GLOBAL group_replication_group_seeds = '192.168.1.10:33061,192.168.1.11:33061,192.168.1.12:33061';
SET GLOBAL group_replication_bootstrap_group = ON;     -- 仅在第一个节点
START GROUP_REPLICATION;
SET GLOBAL group_replication_bootstrap_group = OFF;

-- 监控集群成员
SELECT * FROM performance_schema.replication_group_members;
-- MEMBER_STATE: ONLINE / RECOVERING / ERROR / OFFLINE / UNREACHABLE

-- 单主模式 vs 多主模式
SET GLOBAL group_replication_single_primary_mode = ON;   -- 默认，单主
-- 多主下任意节点都可写，但需要冲突检测；写延迟更高
```

> 注意：Group Replication 不会"超时降级到异步"——多数派失败时直接拒绝写入，保证不分叉。这与传统半同步复制的故障行为有本质区别。

### PostgreSQL synchronous_commit 5 档模式

PostgreSQL 是工业界把同步复制语义"分级"做得最细致的引擎，在 9.1（2011）首次引入同步流复制，在 9.6（2016）将 `synchronous_commit` 从 3 档扩展为 5 档：

```
synchronous_commit 取值（9.6+）:

  off
    主库 WAL 写入 wal buffer，立即返回 commit
    后台进程异步写盘
    崩溃可能丢失最近 wal_writer_delay (200ms) 内的事务
    无副本要求，单机也能用
    适合: 性能优先、能容忍秒级丢失的工作负载（日志、临时表）

  local
    主库 WAL fsync 到本地磁盘后返回 commit
    不等待任何副本
    等同于"无同步复制"
    适合: 单机部署或副本完全异步

  remote_write
    主库 WAL fsync 本地 + 副本 WAL receiver 写入 OS buffer 后返回
    副本写入但未 fsync
    副本 OS crash 可能丢
    适合: 主备配对，但副本节点宕机风险高的场景

  on (=remote_flush)
    主库 WAL fsync 本地 + 副本 WAL receiver fsync 后返回
    默认值
    保证副本磁盘已持久化
    适合: 大多数高可用部署

  remote_apply (9.6+)
    主库 WAL fsync 本地 + 副本 WAL replay 完毕后返回
    保证副本读取也能看到此事务
    主要用于"读己所写"
    适合: 读写分离场景需要严格 RYW 时
```

```sql
-- 主库 postgresql.conf
synchronous_commit = on
synchronous_standby_names = 'standby1,standby2,standby3'    -- 优先级模式

-- 9.6+ Quorum 模式
synchronous_standby_names = 'ANY 2 (standby1,standby2,standby3)'    -- 任意 2 个 ACK 即可
synchronous_standby_names = 'FIRST 2 (standby1,standby2,standby3)'  -- 优先级前 2 个

-- 会话级覆盖
SET LOCAL synchronous_commit = remote_apply;
INSERT INTO orders VALUES (...);    -- 此事务等到副本回放完才提交
COMMIT;

-- 监控同步状态
SELECT application_name, state, sync_state, sync_priority
FROM pg_stat_replication;
-- sync_state: sync (同步) | quorum (Quorum 模式) | async (异步) | potential (备选)
```

### PostgreSQL Quorum Commit (FIRST/ANY) 深入

PostgreSQL 10（2017）引入 Quorum 模式，让 `synchronous_standby_names` 支持两种语义：

```
FIRST k (s1, s2, s3, ..., sn)   -- 优先级模式
  按 list 顺序选前 k 个为同步副本
  只有当前 k 个全部 ACK 才返回 commit
  其余副本仍是异步流复制
  应用场景: 主-备-异地容灾，要求最近的副本同步

ANY k (s1, s2, s3, ..., sn)      -- Quorum 模式（PG 10+）
  从 list 中任意 k 个 ACK 即可返回 commit
  允许 list 中"最快的 k 个"先 ACK
  应用场景: 多副本部署，写入延迟由最快 k 个决定
            而非被最慢一个拖累

例子:
  synchronous_standby_names = 'ANY 2 (s1,s2,s3)'
    3 个副本任意 2 个 ACK 即提交
    单个副本宕机不影响主库写入
    集群可容忍 1 个副本不可用

  synchronous_standby_names = 'FIRST 2 (primary_dc1, primary_dc2, backup_dc3)'
    要求 dc1 和 dc2 都 ACK，dc3 是热备
    若 dc2 宕机，主库可用性受影响
    切换为 'FIRST 2 (primary_dc1, backup_dc3, primary_dc2)' 可解
```

```sql
-- Quorum 模式下监控
SELECT application_name, sync_state, sync_priority
FROM pg_stat_replication
ORDER BY sync_priority;
-- sync_state = 'quorum' 表示在 quorum pool 内
-- sync_state = 'sync' 表示 FIRST 模式中被选中的同步副本
-- sync_priority 表示在 FIRST 列表中的位置；ANY 模式下值无意义

-- 查询当前正在等待的事务
SELECT pid, query, wait_event_type, wait_event
FROM pg_stat_activity
WHERE wait_event = 'SyncRep';
```

### Oracle Data Guard：三种保护模式

Oracle Data Guard（始于 9i，2001）从一开始就把同步/异步复制设计为三种"保护模式（Protection Mode）"，每种模式对 RPO 和可用性有不同保证：

```
Maximum Protection
  - 强制 SYNC 传输（LGWR SYNC AFFIRM）
  - 至少一个副本必须 ACK 才提交
  - 副本不可达时主库立即 SHUTDOWN（拒绝写入）
  - RPO = 0，可用性受副本拖累
  - 适合: 金融核心、绝对不能丢数据的场景

Maximum Availability （默认）
  - 默认 SYNC 传输
  - 副本不可达时降级为异步（log_archive_dest_n NET_TIMEOUT）
  - 副本恢复后自动同步追赶
  - RPO ≈ 0（恢复期间可能少量丢失）
  - 适合: 大多数高可用业务

Maximum Performance
  - 强制 ASYNC 传输（LGWR ASYNC）
  - 主库不等任何副本，性能最优
  - RPO 可能秒级到分钟级
  - 适合: 跨大洲容灾、性能优先
```

```sql
-- 查询当前保护模式
SELECT protection_mode, protection_level FROM v$database;
-- MAXIMUM PROTECTION / MAXIMUM AVAILABILITY / MAXIMUM PERFORMANCE

-- 切换为 Maximum Availability（最常用）
ALTER DATABASE SET STANDBY DATABASE TO MAXIMIZE AVAILABILITY;

-- LOG_ARCHIVE_DEST 配置 SYNC 传输
ALTER SYSTEM SET LOG_ARCHIVE_DEST_2 =
  'SERVICE=standby1
   SYNC AFFIRM
   NET_TIMEOUT=30
   VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)
   DB_UNIQUE_NAME=standby1';

-- 关键属性:
-- SYNC vs ASYNC: 同步还是异步传输 redo
-- AFFIRM vs NOAFFIRM: 副本是否 fsync 后才回 ACK
-- NET_TIMEOUT: 网络超时秒数，超时后降级（仅 Maximum Availability）

-- Far Sync 实例（11g R2+）
-- 中继节点：本地接收 SYNC redo + fsync，再异步转发到远程
-- 解决"远距离 SYNC 延迟过高"难题
ALTER SYSTEM SET LOG_ARCHIVE_DEST_2 =
  'SERVICE=farsync1
   SYNC AFFIRM
   VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)
   DB_UNIQUE_NAME=farsync1';
ALTER SYSTEM SET LOG_ARCHIVE_DEST_3 =
  'SERVICE=remote_dr
   ASYNC
   VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)
   DB_UNIQUE_NAME=remote_dr';
```

### SQL Server AlwaysOn Availability Groups（2012+）

SQL Server 在 2012 引入 AlwaysOn AG，把 Database Mirroring 的同步语义升级为多副本 AG：

```sql
-- 创建 AG（同步提交模式）
CREATE AVAILABILITY GROUP MyAG
FOR DATABASE OrdersDB
REPLICA ON
  'PrimaryNode'
    WITH (ENDPOINT_URL = 'TCP://primary:5022',
          AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
          FAILOVER_MODE = AUTOMATIC,
          SEEDING_MODE = AUTOMATIC),
  'SecondaryNode1'
    WITH (ENDPOINT_URL = 'TCP://secondary1:5022',
          AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
          FAILOVER_MODE = AUTOMATIC,
          SECONDARY_ROLE(ALLOW_CONNECTIONS = READ_ONLY)),
  'SecondaryNode2'
    WITH (ENDPOINT_URL = 'TCP://secondary2:5022',
          AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
          FAILOVER_MODE = MANUAL);

-- AVAILABILITY_MODE 取值:
--   SYNCHRONOUS_COMMIT: 主库等副本 fsync 后再返回客户端
--   ASYNCHRONOUS_COMMIT: 主库提交后异步发送，不等待

-- 监控同步状态
SELECT ar.replica_server_name,
       hars.synchronization_state_desc,
       hars.synchronization_health_desc
FROM sys.availability_replicas ar
JOIN sys.dm_hadr_availability_replica_states hars
  ON ar.replica_id = hars.replica_id;

-- synchronization_state_desc:
--   SYNCHRONIZED: 同步副本已追赶上
--   SYNCHRONIZING: 异步或同步追赶中
--   NOT SYNCHRONIZING: 已脱离同步（可能因超时）
--   REVERTING: 正在回滚未提交事务

-- 故障检测与超时
ALTER AVAILABILITY GROUP MyAG MODIFY REPLICA ON 'SecondaryNode1'
WITH (SESSION_TIMEOUT = 10);    -- 10 秒未收到响应即标记为 NOT SYNCHRONIZING

-- 同步副本失联后，主库不会阻塞（与 PG 不同）
-- 副本进入 NOT_SYNCHRONIZED 状态，主库继续接受写入
-- 副本恢复时自动追赶；追赶完成才能再次自动故障转移
```

### CockroachDB Raft 同步复制

CockroachDB（1.0，2017）从一开始就基于 Raft 协议实现同步复制：每个 range 默认 3 副本，写入需要多数派持久化才 commit。这是**协议级**同步，没有"同步/异步"开关：

```
Raft 写流程:
  1. 客户端把写请求发给 leaseholder
  2. leaseholder 转发给 Raft leader（通常同节点）
  3. leader 把 Raft log entry 写入本地 + 广播给 followers
  4. 多数派（默认 2/3）fsync log entry 后回 ACK
  5. leader 提交 entry，应用到状态机
  6. leader 通知客户端

关键点:
  - 写入必须等多数派 fsync，无法绕过
  - 单个 follower 故障不影响 (3 副本下 2/3 仍达成)
  - 多数派故障时 range 不可写（拒绝服务，不分叉）
```

```sql
-- 查询 range 的副本配置
SHOW RANGES FROM TABLE orders;

-- 配置 zone 副本数
ALTER TABLE orders CONFIGURE ZONE USING num_replicas = 5;
-- 现在每个 range 5 副本，需要 3/5 ACK 才提交
-- 容忍 2 个副本故障

-- 跨 region 部署
ALTER TABLE orders CONFIGURE ZONE USING
  num_replicas = 5,
  constraints = '{"+region=us-east": 2, "+region=us-west": 2, "+region=eu": 1}';
-- region 级别冗余，单 region 故障仍可写
```

### Spanner Paxos 同步复制

Google Spanner 用 Paxos（不是 Raft，但类似多数派语义）实现跨 region 同步复制。每个 split 的副本数通常是 3、5 或 7，写入需要多数派 ACK。

```
Spanner 写流程:
  1. 客户端把事务发给 split 的 Paxos leader
  2. leader 获取 Paxos 写锁
  3. leader 提议 Paxos log entry
  4. 多数派 acceptors ACK
  5. leader commit + 应用 + 推进 TrueTime 时间戳
  6. leader 通知客户端

跨 region 优化:
  - 同 region 多副本 + 跨 region 单副本（leader 选举可调）
  - "Read-Write split"放在同地域，"Read-Only split"跨 region
  - 写延迟 = 同 region 的 Paxos majority RTT，远低于跨 region
```

### TiDB Raft 同步复制

TiDB 计算层无状态，所有数据在 TiKV。TiKV 用 Raft 复制，每个 region 默认 3 副本：

```sql
-- 配置 region 副本数
SET CONFIG tikv `raftstore.replica-count` = 5;

-- placement-rules 控制副本分布
CREATE PLACEMENT POLICY zonal
  CONSTRAINTS = '{"+zone=z1": 2, "+zone=z2": 2, "+zone=z3": 1}';
ALTER TABLE orders PLACEMENT POLICY = zonal;

-- 查询 region 状态
SELECT * FROM information_schema.tikv_region_status;
-- 字段: replica_count, leader_id, peers, ...
```

### MariaDB 半同步复制

MariaDB 在 5.3（2012）引入半同步插件，与 MySQL 同源但行为略有不同：

```sql
-- MariaDB 半同步配置
INSTALL SONAME 'semisync_master';
INSTALL SONAME 'semisync_slave';

SET GLOBAL rpl_semi_sync_master_enabled = 1;
SET GLOBAL rpl_semi_sync_master_timeout = 10000;
SET GLOBAL rpl_semi_sync_master_wait_no_slave = 1;

-- 区别于 MySQL:
-- 1. MariaDB 的 wait point 默认行为接近 AFTER_COMMIT（早期）
-- 2. MariaDB 10.3+ 也支持 AFTER_SYNC
-- 3. MariaDB 的 GTID 域 (domain_id) 让多源复制场景下半同步语义略有不同
-- 4. MariaDB 支持半同步的延迟复制 (Delayed Replication) 组合

-- 状态变量
SHOW STATUS LIKE 'Rpl_semi_sync_master_status';
SHOW STATUS LIKE 'Rpl_semi_sync_master_clients';
```

### Galera Cluster：认证型同步复制

Galera Cluster（被 MariaDB Galera Cluster、Percona XtraDB Cluster 集成）使用 **certification-based replication**：

```
Galera 写流程（virtually synchronous）:
  1. 节点 A 接收事务，本地提交
  2. 提交时把 write set 广播到所有节点
  3. 每个节点对 write set 做 certification（基于行级冲突检测）
  4. 多数派 certify 通过则全部应用
  5. 任何冲突则在源节点回滚（其他节点都没修改）

关键点:
  - 任意节点都可写（多主）
  - 同步发生在 commit 时，"虚同步" (virtually synchronous)
  - 应用是异步的（write set 在所有节点排队等待应用）
  - 不会"超时降级到异步"，脑裂时拒绝写入

参数:
  wsrep_sync_wait        -- 读时是否等待复制队列清空（确保 RYW）
  wsrep_provider         -- libgalera_smm.so
  wsrep_cluster_address  -- gcomm://node1,node2,node3
```

### SAP HANA System Replication

SAP HANA 的 System Replication 提供 4 档同步模式：

```
ASYNC                  -- 异步，主库不等副本
SYNCMEM                -- 副本写入内存即 ACK（不 fsync）
SYNC                   -- 副本 fsync 后 ACK（默认同步模式）
SYNC + Maximum Data Safety  -- SYNC + 副本不可达时阻塞主库

配置在 system_replication 段:
  operation_mode = logreplay                   -- 日志回放
  operation_mode = delta_datashipping          -- delta + log
  operation_mode = logreplay_readaccess        -- 日志回放 + 可读副本
```

### DB2 HADR 同步模式

IBM DB2 的 HADR（High Availability Disaster Recovery）提供 4 档同步模式：

```
SYNC          -- 主库等副本 fsync 后 ACK（最强）
NEARSYNC      -- 主库等副本写入内存（不 fsync）后 ACK（默认）
ASYNC         -- 主库等副本接收（OS buffer）后 ACK
SUPERASYNC    -- 主库不等副本，最弱

参数:
  HADR_SYNCMODE = SYNC | NEARSYNC | ASYNC | SUPERASYNC
  HADR_TIMEOUT  = 120     -- peer 失联超时（秒）
  HADR_PEER_WINDOW = 0    -- peer window 模式：0 关闭，>0 启用
```

### ClickHouse Insert Quorum

ClickHouse 的 ReplicatedMergeTree 提供 `insert_quorum` 设置实现写入级 Quorum：

```sql
-- 写入级 quorum（会话或查询级别）
SET insert_quorum = 2;
SET insert_quorum_timeout = 60000;        -- 60 秒
SET insert_quorum_parallel = 0;            -- 默认 0：串行 quorum

INSERT INTO events VALUES (...);
-- 此次插入需要至少 2 个副本 ACK 才返回成功

-- insert_quorum_parallel:
--   0 (默认): 同时只能有一个 quorum 写入在进行
--   1: 允许并行 quorum 写入（要求副本支持）

-- select_sequential_consistency: 读端配套设置
SET select_sequential_consistency = 1;
SELECT * FROM events;
-- 读取保证看到所有 quorum 已确认的数据
```

### YugabyteDB / OceanBase / StarRocks / Doris

这些分布式数据库都使用 Raft（YB/OB/SR/Doris）或 Paxos（OB）协议：

```sql
-- YugabyteDB 副本配置
ALTER TABLE orders SET (replication_factor=5);
-- 默认 RF=3，写入需 2/3 ACK；RF=5 时 3/5

-- OceanBase Paxos
ALTER TABLE orders SET REPLICA_NUM = 3;

-- StarRocks 副本配置
CREATE TABLE orders (...) DISTRIBUTED BY HASH(id) BUCKETS 10
PROPERTIES ("replication_num" = "3");

-- Doris 同上
CREATE TABLE orders (...) DISTRIBUTED BY HASH(id) BUCKETS 10
PROPERTIES ("replication_num" = "3");
```

### Aurora 6/3 Quorum

Amazon Aurora 是个特别的设计：6 副本横跨 3 个 AZ（每个 AZ 2 副本），写入 quorum 4/6（容忍丢一个 AZ + 一个副本），读取 quorum 3/6：

```
Aurora 写流程:
  1. 客户端 INSERT，主库实例处理
  2. 主库把 redo log（不是数据页）发给 6 个存储节点
  3. 4/6 节点 ACK 后主库即可 commit
  4. 客户端收到响应

Aurora 关键设计:
  - 主库不"复制"，只发送 redo log（log is the database）
  - 6 个存储节点独立从 redo log 重建数据页
  - 跨 AZ 同步是"协议级"，写入永远是 quorum
  - 没有"主从切换"概念，存储层是分布式的
```

### Spanner / Cosmos DB / DynamoDB Global Tables

云原生分布式数据库的同步语义通常是协议级 + 一致性级别可调：

```
Spanner: Paxos majority（强同步）
  - 所有写入都是同步多数派
  - 跨 region 写延迟 = 跨 region majority RTT
  - TrueTime 提供外部一致性

Cosmos DB: 5 档一致性
  - Strong: 同 Spanner，写入多数派 + 读取最新
  - Bounded Staleness: 有界陈旧，T 秒或 K 操作
  - Session: 同一会话保证 RYW
  - Consistent Prefix: 保证有序但可能陈旧
  - Eventual: 异步，最弱

DynamoDB:
  - 单 region: 默认 3 AZ flush quorum
  - Global Tables: 多 region 异步复制（最终一致）
  - ConsistentRead=true 强制读主，弱一致默认
```

## 同步复制的常见误区

### 误区 1：半同步 = 零数据丢失

MySQL 半同步默认（5.7 之前的 AFTER_COMMIT 模式）只保证副本"收到 binlog"，并不能保证零丢失。考虑以下场景：

```
1. 主库 fsync binlog
2. 主库 InnoDB commit (持久化)
3. 主库等待副本 ACK
4. 主库突然断电（副本未收到 binlog）
5. 故障切换：副本作主，但少了第 2 步的事务
6. 客户端可能已经从主库读到了"幻提交"
```

5.7+ 的 AFTER_SYNC 才是真正的"无损半同步"。

### 误区 2：同步复制可以替代备份

同步复制只防"硬件故障"，不防"逻辑错误"。一条 `DELETE FROM orders` 立即在所有副本生效，没有任何同步机制能阻止。备份（PITR、定期快照）是与复制正交的需求。

### 误区 3：副本数越多越安全

副本数翻倍带来的边际安全收益递减，但同步延迟（受最慢副本影响）线性增加。3 副本 + 多数派 quorum 是工业界普遍认为的"甜点"，5 副本仅在特殊场景（金融、跨大洲容灾）使用。

### 误区 4：跨数据中心同步是免费的

跨数据中心 RTT 通常 5-50ms，单事务每次写入都要承担这个延迟。一个高频写入应用（QPS 10k）在跨 DC 同步下 P99 可能从 1ms 飙升到 50ms，吞吐下降到原来的 5%。

### 误区 5：超时降级是万能的

MySQL 半同步的超时降级看似优雅，但有副作用：降级期间写入数据**实际上是异步**，如果此时主库挂掉，新主可能没收到这些数据。监控告警必须把"降级状态"作为一级事件。

## 设计争议

### 协议级同步 vs 配置级同步

这是过去十年最大的范式分歧：

- **传统主从架构（MySQL、PG、Oracle、SQL Server、DB2、HANA）**：同步是配置项，可以打开关闭，可以超时降级。优点是灵活；缺点是配置复杂、容易踩坑。
- **共识协议系（CockroachDB、TiDB、YugabyteDB、Spanner、OceanBase）**：同步是协议本身，不可绕过。优点是简单一致；缺点是损失多数派时整体阻塞，无法在"少量节点存活"时提供降级写入。

### 物理 vs 逻辑同步

- **物理同步**（MySQL row-based binlog、PG WAL streaming、Oracle redo SYNC）：直接传输 redo/binlog 字节，效率高但要求版本一致。
- **逻辑同步**（Galera certification、MySQL Group Replication）：传输事务的 write set 或行级变更，可跨大版本但需要冲突检测。

### 单写 vs 多写

- **单写**：MySQL/MariaDB（传统）、PG、Oracle Data Guard、SQL Server AG、所有共识系。
- **多写**：MySQL Group Replication（多主模式）、Galera、Cockroach（实际是 leaseholder 路由）、Cosmos DB、Aurora Multi-Master（已停售）。

多写引入冲突解决问题，工业界除 Galera/Cosmos 外几乎都回避。

### Lock-step Apply vs Lazy Apply

- **Lock-step**：副本一定要回放完才回 ACK（PG `remote_apply`、Oracle Maximum Protection）。RYW 强、延迟最高。
- **Lazy**：副本写入即可 ACK，回放异步（PG `remote_write/on`、MySQL AFTER_SYNC）。延迟低、RYW 需要应用层处理。

## 对引擎开发者的实现建议

### 1. ACK 时机的选择

实现同步复制时，必须先想清楚 ACK 在哪个时刻：

```
关键决策表:

| ACK 模式 | 实现复杂度 | 副本端开销 | 主库延迟 | 适用场景 |
|---------|----------|---------|---------|---------|
| write    | 低       | 低       | 低      | 副本节点稳定的同地域 |
| flush    | 中       | 中       | 中      | 跨 AZ 同步，主流默认 |
| apply    | 高       | 高       | 高      | RYW 必需，可读副本 |

实现要点:
  - write: 副本网络层 receiver 收到 + write 到本地内存即可
  - flush: 副本必须 fsync redo log 才能 ACK
  - apply: 副本必须 redo replay 完毕，对查询可见才 ACK
```

### 2. 超时与降级策略

```
设计选择:

  策略 A (MySQL/MariaDB/Oracle MA/SQL Server): 超时降级到异步
    优点: 单副本故障不阻塞主库
    缺点: 降级窗口内写入可能丢失
    必备: 降级状态告警 + 自动恢复机制

  策略 B (PostgreSQL/Oracle MP): 永久阻塞
    优点: RPO 绝对为零
    缺点: 单副本故障即整体不可写
    必备: 多个同步副本 + 监控

  策略 C (Cockroach/TiDB/Spanner): 协议级 quorum
    优点: 单副本/少数派故障不影响
    缺点: 多数派故障时整体阻塞
    必备: 至少 3 副本，最好 5 副本跨 region
```

### 3. 同步状态监控

任何同步复制实现都必须暴露的监控指标：

```
1. 同步状态（同步/异步/降级）
   - PG: pg_stat_replication.sync_state
   - MySQL: Rpl_semi_sync_master_status
   - SQL Server: sys.dm_hadr_database_replica_states.synchronization_state

2. 复制延迟
   - 字节级: 主副 LSN/binlog 位点差
   - 时间级: 最近一个事务在副本的回放延迟
   - 必报: P50, P99, 最大值

3. 副本健康
   - 心跳超时
   - 网络往返时间
   - 回放线程状态

4. 关键事件
   - 同步副本失联
   - 降级到异步
   - 自动故障切换
```

### 4. 与 WAL 设计的耦合

同步复制和 WAL 设计紧密耦合：

```
WAL 流式发送:
  - PG: WAL receiver 直接读取主库的 WAL 流
  - MySQL: I/O thread 拉取 binlog 写入 relay log
  - Oracle: LGWR 直接发送 redo + RFS 进程接收

ACK 设计:
  - PG: WAL receiver 报告 LSN 给主库的 walsender
  - MySQL: 半同步插件在 binlog dump thread 中等待 ACK 包
  - Oracle: LGWR SYNC 模式下 RFS 回 ACK

关键挑战:
  - 网络包丢失/重排：必须有重试与去重
  - 副本重连：必须能从最近 ACK 点续传
  - 主库切换：新主必须知道哪些事务已经被旧副本接收
```

### 5. 与组提交的协同

组提交（group commit）与同步复制的协同设计是引擎实现的难点：

```
设计要点:

  独立 ACK vs 批量 ACK:
    - 独立 ACK: 每个事务独立等待
    - 批量 ACK: 副本对一批事务回单个 ACK（吞吐高但延迟略增）

  组提交 + 同步复制:
    - 主库的 group commit 把多个事务的 fsync 合并
    - 同步复制可以借此机会一次发送多个事务的 redo
    - 副本一次 fsync 一批事务，回单个 ACK
    - PG 和 MySQL 都做了这个优化

  Group Replication 的 binlog 组:
    - 单次 Paxos 提议可包含多个事务
    - 大幅减少 Paxos 协议开销
```

### 6. 跨地域部署的特殊考虑

跨地域同步复制的延迟挑战：

```
1. 同步副本必须在低延迟范围内 (< 5ms RTT)
   - 同 region 不同 AZ: 通常 1-2ms，可接受
   - 跨 region: 通常 30-100ms，几乎不可行
   - 解决方案: Far Sync 中继（Oracle）或多层架构

2. 异步副本可跨大洲
   - 跨太平洋: 100-200ms RTT
   - 必然异步，RPO 通常分钟级

3. 多 region 多写架构
   - Spanner: 同步多 region（依赖 TrueTime）
   - DynamoDB Global Tables: 异步多 region
   - Cosmos DB: 一致性级别可选，多 region 强一致最贵
```

### 7. 同步复制与故障切换

同步复制的真正价值在于"故障切换时不丢数据"，但实现完整的自动切换非常复杂：

```
组件:
  1. 健康检查: 心跳 + 复制延迟监控
  2. 选主: 选出最新副本作为新主
  3. 切换: VIP 漂移 / DNS 更新 / 客户端通知
  4. 旧主隔离: 防止脑裂
  5. 新副本配置: 让其他副本指向新主

工业实现:
  - MySQL: MHA, Orchestrator, MyperLabs
  - PostgreSQL: Patroni, repmgr, pg_auto_failover
  - Oracle: Data Guard Broker
  - SQL Server: AG Listener + Quorum (Windows Failover Clustering)
  - Cockroach/TiDB/Spanner: 协议内自动切换 (Raft/Paxos)
```

### 8. 测试与验证

实现同步复制必须验证以下场景：

```
基础正确性:
  - 主库正常 commit 后副本能立即看到
  - 副本短暂网络抖动后能自动恢复
  - 主库重启后副本不丢数据

故障注入:
  - 副本宕机：超时是否生效，是否降级或阻塞
  - 主库宕机：故障切换后数据是否一致
  - 网络分区：是否有脑裂
  - 慢副本：单个慢副本是否拖累所有写入（FIRST 与 ANY 的差异）

性能验证:
  - 单事务延迟 P50 / P99 / max
  - 吞吐量随副本数变化
  - 跨 AZ 与同 AZ 的延迟差
```

## 总结对比矩阵

### 关键能力总览

| 能力 | PostgreSQL | MySQL 半同步 | Oracle DG | SQL Server AG | CockroachDB | Spanner |
|------|-----------|------------|----------|--------------|------------|---------|
| ACK 时机 | write/flush/apply | flush (5.7+ AFTER_SYNC) | flush (LGWR SYNC) | flush | apply (Raft) | apply (Paxos) |
| Quorum 配置 | FIRST/ANY (10+) | wait_for_slave_count | 多目标 | -- | RF=3/5/7 | 5 (默认) |
| 超时降级 | 不降级 | 是 (10s) | 仅 MA 模式 | NOT_SYNCHRONIZING | 不降级 | 不降级 |
| 跨 region | 难（延迟太高） | 难 | Far Sync | 难 | 受地理 | 内置 |
| 自动切换 | 外部工具 | 外部工具 | DG Broker | 内置 | 内置 | 内置 |
| 多写 | -- | Group Replication | -- | -- | leaseholder | -- |
| 首次发布 | 9.1 (2011) | 5.5 (2010) | 9i (2001) | 2012 | 1.0 (2017) | 2017 (公开) |

### 选型建议

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| 同 AZ 双副本零丢失 | PG `synchronous_commit=on` | 最稳定，5 档可调 |
| 跨 AZ 高可用 + 不阻塞 | MySQL 半同步 AFTER_SYNC | 超时降级保证可用性 |
| 金融绝对零丢失 | Oracle Maximum Protection | 副本不可达即拒绝写入 |
| 多副本灵活配置 | PG Quorum (ANY k) | 不被最慢副本拖累 |
| 多 region 强一致 | Spanner 或 Cosmos DB Strong | 协议级 + TrueTime |
| 多 region 弱一致 | DynamoDB Global Tables | 异步复制，性能最优 |
| 自建分布式 | CockroachDB / TiDB / YB | 协议级 quorum，无配置 |
| 多主写入 | Galera 或 Group Replication | 多主 + 冲突检测 |

## 关键发现

1. **MySQL 半同步是工业界第一个广泛部署的同步复制方案**：5.5（2010）首次引入，5.7.3（2013）通过 AFTER_SYNC 实现真正"无损"语义。但它本质是 flush 模式，不保证副本回放。

2. **PostgreSQL 是同步语义最细致的引擎**：从 9.1（2011）的同步流复制到 9.6（2016）的 5 档 `synchronous_commit`（off/local/remote_write/on/remote_apply）+ Quorum FIRST/ANY，提供了从最弱到最强、写/flush/apply 三档完整覆盖。

3. **Oracle Data Guard 三种保护模式定义了行业框架**：Maximum Protection（绝对零丢失）/ Maximum Availability（默认，超时降级）/ Maximum Performance（异步），后续厂商的同步复制设计大多借鉴此分类。

4. **共识协议系（Raft/Paxos）天然提供同步复制**：CockroachDB、TiDB、YugabyteDB、Spanner、OceanBase 都把同步复制做在协议本身，不暴露"同步/异步"开关。代价是失去多数派时整体阻塞。

5. **超时降级 vs 协议级 quorum 是范式分歧**：传统主从架构默认"超时降级到异步"以保证可用性；共识协议系拒绝降级以保证一致性。前者灵活、后者简单，没有谁更好的答案。

6. **跨 region 同步复制几乎不可行**：物理定律决定 RTT 是几十毫秒级，每次写都吃这个延迟会摧毁吞吐。Spanner 的 TrueTime + Paxos 是少数能做到的特例（依赖 GPS/原子钟）。

7. **半同步的"半"字暗藏陷阱**：默认配置（如 MariaDB 早期、MySQL AFTER_COMMIT）并不保证零丢失。务必使用 AFTER_SYNC（MySQL 5.7+）或等价语义。

8. **Aurora 的 6/3 quorum 是云原生范式革命**：把存储层做成分布式（log is the database），写入永远是 quorum，无需关心副本同步——开启了"存储计算分离 + 协议级同步"的新范式。

9. **超时参数的默认值差异巨大**：MySQL 半同步默认 10 秒，DB2 HADR 默认 120 秒，Oracle Data Guard 默认 30 秒。这些默认值反映了不同时代的网络假设，运维时必须根据实际拓扑调整。

10. **同步复制不能替代备份**：复制只防硬件故障，不防逻辑错误（如误删数据）。任何高可用部署都必须组合"复制 + PITR + 定期快照"三层保护。

## 参考资料

- PostgreSQL: [synchronous_commit](https://www.postgresql.org/docs/current/runtime-config-wal.html#GUC-SYNCHRONOUS-COMMIT)
- PostgreSQL: [synchronous_standby_names](https://www.postgresql.org/docs/current/runtime-config-replication.html#GUC-SYNCHRONOUS-STANDBY-NAMES)
- MySQL: [Semisynchronous Replication](https://dev.mysql.com/doc/refman/8.0/en/replication-semisync.html)
- MySQL: [Group Replication](https://dev.mysql.com/doc/refman/8.0/en/group-replication.html)
- MariaDB: [Semisynchronous Replication](https://mariadb.com/kb/en/semisynchronous-replication/)
- Oracle: [Data Guard Protection Modes](https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/oracle-data-guard-protection-modes.html)
- SQL Server: [Availability Modes (Always On)](https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/availability-modes-always-on-availability-groups)
- DB2: [HADR sync mode](https://www.ibm.com/docs/en/db2/11.5?topic=hadr-synchronization-modes)
- SAP HANA: [System Replication](https://help.sap.com/docs/SAP_HANA_PLATFORM/4e9b18c116aa42fc84c7dbfd02111aba/aff8a812dbf447b285be0d56f96e3a7d.html)
- CockroachDB: [Replication Layer](https://www.cockroachlabs.com/docs/stable/architecture/replication-layer.html)
- TiDB: [TiKV Architecture](https://docs.pingcap.com/tidb/stable/tikv-overview)
- Spanner: [TrueTime and External Consistency](https://cloud.google.com/spanner/docs/true-time-external-consistency)
- YugabyteDB: [Replication Architecture](https://docs.yugabyte.com/preview/architecture/docdb-replication/)
- Aurora: [Aurora Storage Demystified](https://www.allthingsdistributed.com/2019/03/Amazon-Aurora-design-cloud-native-relational-database.html)
- Galera: [Certification-Based Replication](https://galeracluster.com/library/documentation/certification-based-replication.html)
- ClickHouse: [insert_quorum](https://clickhouse.com/docs/en/operations/settings/settings#insert-quorum)
