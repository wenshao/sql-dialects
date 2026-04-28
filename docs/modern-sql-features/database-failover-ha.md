# 数据库高可用与故障切换 (Database HA and Failover)

凌晨三点，一个生产 MySQL 主库突然 OOM 崩溃。运维值班的工程师只有两个选择：人工介入提升从库、对外公告业务暂停几分钟；或者寄希望于自动故障切换在 30 秒内完成主从角色翻转，业务连接被代理层透明地重定向到新主库。这两个剧本背后，是一套庞大的 **HA（High Availability）** 工程体系——从主从复制到见证仲裁、从 STONITH 围栏到 Raft 多数派、从 RTO 数秒到分钟级、从允许 RPO>0 的可用性优先到 RPO=0 的强一致优先。本文系统对比 45+ 数据库引擎在自动故障切换、手动晋升、脑裂防护、典型 RTO/RPO 等维度上的设计差异。

姊妹文章：[同步复制 (Synchronous Replication)](./synchronous-replication.md) 关注 "主库等不等副本持久化" 的写路径语义；[副本读路由 (Replica Read Routing)](./replica-read-routing.md) 关注 "读流量路由到哪个副本" 的读路径语义；本文聚焦 "主库挂了之后如何让业务继续运行" 的整套故障切换流程。

## 为什么需要高可用

数据库是绝大多数 OLTP 业务的事实单点。一旦主库不可用，整个业务停摆。HA 设计的目标是把这个单点故障的影响压到最小。围绕"主库挂了怎么办"，业界用三个关键指标来描述 HA 能力：

### RTO 与 RPO 的工程定义

- **RTO（Recovery Time Objective，恢复时间目标）**：从故障发生到业务恢复所需的时间。RTO=0 意味着瞬间无感切换；RTO=30 秒是大多数 OLTP 业务的合理目标；RTO=数小时通常意味着需要人工介入恢复。
- **RPO（Recovery Point Objective，恢复点目标）**：故障切换后允许丢失的数据时间窗口。RPO=0 意味着零数据丢失（同步复制保障）；RPO=几秒是异步复制下的典型妥协；RPO=最近一次备份是没有复制时的下限。

### 手动 vs 自动故障切换

- **手动 (Manual Failover / Switchover)**：运维通过 `pg_promote()`、`STOPSLAVE; CHANGE MASTER` 等命令显式提升从库。优点是决策权完全在人手中、不会误判；缺点是 RTO 受限于响应速度（通常 5-30 分钟）。
- **自动 (Automatic Failover)**：监控组件检测到主库异常后自动选出新主、提升、并通知应用层。优点是 RTO 可压到 10-60 秒；缺点是误判（如网络抖动）会导致不必要的切换或脑裂。

### 围栏（Fencing）与脑裂（Split-Brain）问题

自动故障切换最危险的情况是**脑裂**：原主库其实还活着（只是与监控网络断开），监控误判后提升了一个新主库，结果两个节点都认为自己是主，同时接受写入并产生分叉的数据。围栏机制的目标是杜绝这种情况：

- **STONITH（Shoot The Other Node In The Head）**：强制电源断电、踢出虚拟机、拔光纤——通过物理或基础设施层面让旧主"明确死透"再切换。
- **见证节点（Witness）**：引入第三方仲裁节点参与决策，避免双节点 1:1 投票时无法判定。SQL Server WSFC、Oracle Fast-Start Failover 都依赖见证。
- **多数派仲裁（Quorum）**：要求集群中多数节点（n/2+1）共同确认才允许写入。Raft、Paxos、Galera 都基于多数派天然规避脑裂。
- **存储级围栏（SCSI Reservation, EBS Detach）**：从存储层切断旧主对共享磁盘的访问。
- **应用层围栏**：通过代理层（ProxySQL、MaxScale、PgBouncer）拒绝旧主的连接重连。

理解这套术语，是阅读各家 HA 文档时不踩坑的基础。

## 没有 SQL 标准

ANSI/ISO SQL 标准从未定义高可用、故障切换、围栏等概念。SQL:2023 也没有 `CREATE FAILOVER GROUP` 这样的语法。所有相关能力都是各引擎独立扩展或外置工具：

- **专有命令派**：Oracle `DGMGRL` 命令行、SQL Server `ALTER AVAILABILITY GROUP ... FAILOVER`、MySQL `group_replication_set_as_primary()`。
- **配置文件派**：PostgreSQL `recovery.conf` 触发 `promote`、Patroni 的 YAML 配置。
- **管理工具派**：Oracle Data Guard Broker、MySQL Router、ProxySQL、MaxScale、Patroni。
- **托管服务派**：RDS 控制台一键 Failover、Aurora API `FailoverDBCluster`、Spanner 自动管理。
- **协议级派**：CockroachDB / TiDB / YugabyteDB 的 Raft 选举本身就是故障切换。

本文剩下的部分对 45+ 引擎在这些维度上做权威对比。

## 支持矩阵

### 1. 原生自动故障切换能力总览

| 引擎 | 原生自动故障切换 | 手动晋升 | 围栏机制 | 典型 RTO | 数据丢失可能 (RPO) | 首次提供 |
|------|----------------|---------|---------|---------|----------------|---------|
| PostgreSQL | -- | `pg_promote()` | 无 (需外置) | 视外置工具 | 视复制模式 | 9.1 (流复制) |
| MySQL | Group Replication (5.7.17+) | `STOP SLAVE; CHANGE MASTER` | XCom 多数派 | 30-60s | 0（GR）/ 数秒（异步） | 5.7.17 (2016) |
| MariaDB | -- | 同 MySQL | -- | 视外置 (MHA/MaxScale) | 视复制模式 | -- |
| SQLite | -- | -- | -- | -- | -- | 单机 |
| Oracle | Data Guard Broker + FSFO | `ALTER DATABASE FAILOVER` | Observer 见证 + Fence | 5-30s | 0 (Max Protection) / 视模式 | 10g R2 (2005) |
| SQL Server | AlwaysOn AG (自动 / 手动) | `ALTER AG FAILOVER` | WSFC 仲裁 | 10-60s | 0 (同步) / 数秒 (异步) | 2012 |
| DB2 | HADR + TSA | 是 | TSA 仲裁 | 30s-数分钟 | 视模式 | 9.5+ |
| Snowflake | 托管 | -- (托管) | -- (托管) | 透明 (托管) | 0 (托管多 AZ) | GA |
| BigQuery | 托管 | -- | -- | 透明 | 0 (托管) | GA |
| Redshift | 自动 (托管) | RA3 节点替换 | -- | 数分钟 | 0 (托管) | GA |
| DuckDB | -- | -- | -- | -- | -- | 单机 |
| ClickHouse | Keeper / ZooKeeper 协调 | 是 | Keeper Quorum | 视配置 | 0 (insert_quorum) | 早期 |
| Trino | Coordinator HA (启发式) | -- | -- | 视配置 | N/A (计算引擎) | 早期 |
| Presto | Coordinator HA (有限) | -- | -- | 视配置 | N/A | 早期 |
| Spark SQL | -- | -- | -- | -- | N/A | 计算引擎 |
| Hive | HiveServer2 ZK HA | -- | ZK Quorum | 数秒 | N/A | 0.14+ |
| Flink SQL | JobManager HA | -- | ZK Quorum | 数秒 | Checkpoint | 1.x |
| Databricks | 托管 (SQL Warehouse HA) | -- | -- | 透明 | 0 (托管) | GA |
| Teradata | Dual Active 是 | 是 | 仲裁 | 数分钟 | 视模式 | 早期 |
| Greenplum | mirror 自动切换 | `gprecoverseg` | FTS 探测 | 数秒-数分钟 | 0 (mirror sync) | GA |
| CockroachDB | 原生 (Raft 选举) | 自动 | Raft Quorum | < 9s (默认) | 0 (Raft) | 1.0 (2017) |
| TiDB | 原生 (PD + Raft) | 自动 | Raft Quorum | < 30s | 0 (Raft) | 1.0 (2017) |
| OceanBase | 原生 (Paxos 选举) | 自动 | Paxos Quorum | < 30s | 0 (Paxos) | 0.5 (2014) |
| YugabyteDB | 原生 (Raft 选举) | 自动 | Raft Quorum | < 30s | 0 (Raft) | 1.0 (2018) |
| SingleStore | 主从自动 | 是 | Master Aggregator 仲裁 | 数秒 | 0 (sync) | 早期 |
| Vertica | K-safety 自动 | -- | Spread / Quorum | 数秒 | 0 (mirror) | 早期 |
| Impala | Coordinator HA + StateStore | -- | -- | 视配置 | N/A | CDH 5+ |
| StarRocks | FE Raft + BE 多副本 | 自动 | Raft Quorum | 数秒 | 0 (内部 Quorum) | GA |
| Doris | FE Raft + BE 多副本 | 自动 | Raft Quorum | 数秒 | 0 (内部 Quorum) | GA |
| MonetDB | -- | -- | -- | -- | -- | -- |
| CrateDB | 内置 (Lucene shard 分配) | 是 | Quorum | 数秒-数十秒 | 0 (quorum) | GA |
| TimescaleDB | 继承 PG (需 Patroni) | 同 PG | 同 PG | 同 PG | 同 PG | 继承 PG |
| QuestDB | -- | -- | -- | -- | -- | -- |
| Exasol | 内部冗余 + 自动接管 | 是 | -- | 数秒 | 0 (托管) | -- |
| SAP HANA | System Replication (SR) + STONITH | 是 | STONITH (HAE) | 数秒 | 0 (sync) | 2.0+ |
| Informix | HDR 自动 + sqlhosts | 是 | -- | 数秒-数十秒 | 0 (sync) | 早期 |
| Firebird | -- | -- | -- | -- | -- | -- |
| H2 | -- | -- | -- | -- | -- | 单机 |
| HSQLDB | -- | -- | -- | -- | -- | 单机 |
| Derby | -- | -- | -- | -- | -- | 单机 |
| Amazon Aurora | 原生 (集群层) | API 触发 | 存储层 6/3 quorum | 30-60s (典型) | 0 (集群) | GA |
| Amazon RDS Multi-AZ | 原生 (托管) | API 触发 | EBS / 存储层 | 60-120s (典型) | 0 (Multi-AZ sync) | GA |
| Amazon Athena | -- | -- | -- | -- | N/A | 计算引擎 |
| Azure Synapse | 托管 | -- | -- | 透明 | 0 (托管) | GA |
| Azure SQL DB | 托管 (Geo / Auto-Failover Group) | API | Quorum 内部 | 数秒-1 分钟 | 0 (本地) / RPO≈5s (Geo) | GA |
| Google Spanner | 原生 (托管) | -- | Paxos Quorum | 透明 | 0 (Paxos) | GA |
| DynamoDB | 原生 (Multi-AZ 托管) | -- | -- | 透明 | 0 (托管) | GA |
| Cosmos DB | 原生 (多副本托管) | -- | -- | 透明 | 视一致性级别 | GA |
| Materialize | Compute Replica HA | 是 | -- | 数秒 | 0 (Persist) | GA |
| RisingWave | Meta Raft + Compute Replica | 自动 | Raft Quorum | 数秒 | 0 (state store) | GA |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | -- |
| DatabendDB | Meta HA (Raft) | 是 | Raft Quorum | 数秒 | 0 (S3) | GA |
| Yellowbrick | 集群冗余 | 是 | -- | 数秒-数十秒 | 0 (mirror) | GA |
| Firebolt | 托管 | -- | -- | 透明 | 0 (托管) | GA |
| MySQL Group Replication | 原生 (XCom 多数派) | 是 | XCom Quorum | 30-60s | 0 (single-primary) | 5.7.17 (2016) |
| Galera Cluster | 原生 (认证多数派) | 自动 (无主概念) | Group Communication Quorum | 数秒 | 0 (Galera) | 早期 |

> 统计：约 28 个引擎提供某种形式的原生自动故障切换；约 7 个分布式引擎通过 Raft/Paxos 选举天然实现自动切换；PostgreSQL 是为数不多的"无原生自动切换"主流引擎，必须依赖外置工具（Patroni / repmgr / pg_auto_failover / Stolon）。

### 2. 围栏机制详分

| 引擎 | 围栏方式 | 见证节点 | 多数派要求 | STONITH 集成 |
|------|---------|---------|----------|-------------|
| PostgreSQL + Patroni | DCS 锁 (etcd / Consul / ZK) | DCS 节点 | DCS 多数派 | 可选 (watchdog) |
| PostgreSQL + repmgr | 有限 (依赖部署) | 可配 | 可配 | -- |
| PostgreSQL + pg_auto_failover | Monitor 节点 | Monitor 单点 | 主-备-Monitor 三方 | -- |
| MySQL Group Replication | XCom 多数派 | -- | majority of group | -- |
| MySQL + MHA | 应用脚本 + SSH 杀进程 | 可选 | -- | 是（脚本化） |
| MySQL + Orchestrator | 拓扑感知 | 可选 | 任选 | 可选 |
| MariaDB + MaxScale | Monitor 拓扑跟踪 | -- | -- | 可选 |
| Oracle Data Guard + FSFO | Observer 见证 | Observer | -- | Fence Group 集成 |
| SQL Server AlwaysOn | WSFC 仲裁 | File Share / Cloud Witness | WSFC 多数派 | 是（节点 evict） |
| DB2 HADR + TSA | TSA Tiebreaker | TSA | -- | 是 |
| CockroachDB | Raft Quorum | 默认 3-5 节点 | Raft 多数派 | 否（协议级） |
| TiDB | PD Raft + TiKV Raft | -- | Raft 多数派 | 否（协议级） |
| OceanBase | Paxos | -- | Paxos 多数派 | 否（协议级） |
| YugabyteDB | Raft (Master + Tablet) | -- | Raft 多数派 | 否（协议级） |
| Aurora | 存储层 6 副本 | -- | 4/6 写 / 3/6 读 | 否（托管） |
| Galera | Group Communication | 可选 garbd | 多数派 | 否 |
| Spanner | Paxos | -- | Paxos 多数派 | 否（托管） |
| ClickHouse + Keeper | Keeper 集群 | -- | Keeper 多数派 | 否 |
| SAP HANA HAE | STONITH (Pacemaker) | 是（QDevice / SBD） | -- | 是 |

> 关键观察：传统主从架构（MySQL / PG / Oracle / SQL Server）都需要某种**外部仲裁**（DCS、见证文件、Observer），否则双节点 1:1 投票无法判定主库是真死还是网络分区；分布式 SQL（CockroachDB / TiDB / Spanner）天然要求 ≥3 节点构成 quorum，故障切换是 Raft/Paxos 选举的副作用，不需要专门的"切换流程"。

### 3. 典型 RTO 数据

| 引擎 / 工具 | 检测延迟 | 选主延迟 | 数据回放 | 典型总 RTO | 备注 |
|------------|---------|---------|---------|-----------|------|
| PostgreSQL + Patroni | 5-10s | < 5s | < 5s | 10-30s | 取决于 `loop_wait` 与 `ttl` |
| PostgreSQL + repmgr | 30s-数分钟 | 数秒 | 数秒 | 数分钟 | 检测保守，避免误切 |
| PostgreSQL + pg_auto_failover | 10-30s | < 5s | < 5s | 30-60s | Monitor 决策 |
| MySQL Group Replication | 5-10s | < 5s | < 10s | 30-60s | 视写入压力 |
| MySQL + MHA | 9s (默认) | 数秒 | 视 binlog 长度 | 30s-数分钟 | 旧工具，已停止维护 |
| MySQL + Orchestrator + ProxySQL | < 10s | < 5s | 视 GTID | 10-30s | 可压到 10s 内 |
| MariaDB + MaxScale | 10s | 数秒 | 数秒 | 30s | -- |
| Oracle Data Guard FSFO | 配置 (默认 30s) | < 1s | < 5s | 5-30s | `FastStartFailoverThreshold` |
| SQL Server AlwaysOn (Auto) | 10s | < 5s | 数秒 | 10-30s | 同步副本 |
| SQL Server AlwaysOn (Manual) | 即时 | -- | -- | 5-15s | 取决于操作员响应 |
| Aurora 集群 | 10-30s | -- | 几乎无 | 30-60s | 共享存储无回放 |
| RDS Multi-AZ MySQL/PG | 30-60s | -- | 视 binlog/WAL | 60-120s | DNS 切换是瓶颈 |
| RDS Multi-AZ Cluster (PG) | 10-30s | < 5s | < 5s | 30-60s | 比传统 Multi-AZ 快 |
| CockroachDB | 4.5s (默认 lease) | < 1s | 几乎无 | < 9s | `cluster.heartbeat_interval` |
| TiDB | 5-10s | < 5s | < 5s | 10-30s | PD 心跳 |
| YugabyteDB | 默认 3s heartbeat | < 5s | < 5s | < 15s | -- |
| Spanner | 透明 | -- | -- | < 数秒 | 客户端无感 |
| Azure SQL DB Geo-Replication | -- | -- | -- | 数秒-1 分钟 | RPO≈5s |
| Galera | 即时 (group msg) | < 1s | -- | < 5s | 但写入会卡 |
| MySQL Group Replication (single primary) | 5-10s | < 5s | < 10s | 30-60s | -- |

> 关键观察：分布式 SQL（CockroachDB、TiDB、YugabyteDB）的 RTO 通常压在 10-30 秒以内（基于 lease 心跳机制）；Aurora 因共享存储无需回放 redo，典型 30-60 秒；传统 RDS Multi-AZ 因为需要 DNS 切换 + 客户端连接重建，RTO 在 60-120 秒；PostgreSQL 必须搭配 Patroni 等工具才能压到 30 秒级。

### 4. 数据丢失可能性矩阵

| 引擎 / 模式 | 同步状态 | 主库故障时数据丢失 | 备注 |
|------------|---------|----------------|------|
| MySQL 异步复制 + 任意切换工具 | async | 可能丢失最近未传 binlog | 默认模式 |
| MySQL 半同步 + MHA | semi-sync (AFTER_SYNC) | 几乎无 (除非副本也挂) | timeout 后退化为异步 |
| MySQL Group Replication (single primary) | majority quorum | 0 (多数派承诺) | 不可能脑裂 |
| MariaDB Galera | 认证型同步 | 0 | 多数派写 |
| PostgreSQL 异步流复制 + Patroni | async | 可能丢失未传 WAL | -- |
| PostgreSQL 同步流复制 + Patroni | synchronous_commit=on | 0 (除非备库都挂) | 等待 fsync |
| PostgreSQL pg_auto_failover (sync) | sync | 0 | 必须保留至少一个 sync standby |
| Oracle Maximum Performance | async | 可能丢失少量 redo | 性能优先 |
| Oracle Maximum Availability | sync (LGWR SYNC) | 0 (除非降级到异步) | 默认推荐 |
| Oracle Maximum Protection | sync + zero-loss | 0 (主库会停服) | 极端模式 |
| SQL Server AlwaysOn Sync-Commit | sync flush | 0 | 自动切换前提 |
| SQL Server AlwaysOn Async-Commit | async | 可能丢失 | 跨地域典型 |
| Aurora MySQL/PG | quorum (4/6) | 0 (集群范围) | 存储层冗余 |
| RDS Multi-AZ (传统) | sync block 级 | 0 (本地) | 跨 AZ 同步 |
| CockroachDB | Raft majority | 0 | -- |
| TiDB | Raft majority | 0 | -- |
| Spanner | Paxos majority | 0 | -- |
| YugabyteDB | Raft majority | 0 | -- |
| OceanBase | Paxos majority | 0 | -- |
| StarRocks / Doris | 内部 quorum | 0 | -- |

> 结论：要做到 RPO=0，要么使用同步复制 + 等待副本 ACK，要么使用 Raft/Paxos 多数派写入。任何依赖异步复制的方案都不可能保证 RPO=0。

### 5. 主流外置工具汇总（PostgreSQL / MySQL）

| 工具 | 适用引擎 | 开源 / 厂商 | DCS 依赖 | 自动切换 | 围栏 | 首次发布 |
|------|---------|------------|---------|---------|------|---------|
| Patroni | PostgreSQL | Zalando（开源） | etcd / Consul / ZK / K8s API | 是 | DCS 锁 + watchdog | 2015 |
| repmgr | PostgreSQL | 2ndQuadrant / EDB | -- | 是 | 有限 | 2010 |
| pg_auto_failover | PostgreSQL | Citus / Microsoft | Monitor | 是 | Monitor 决策 | 2018 |
| Stolon | PostgreSQL | Sorint.lab | etcd / Consul / K8s | 是 | DCS 锁 | 2015 |
| PAF (PostgreSQL Automatic Failover) | PostgreSQL | Pacemaker 资源代理 | Pacemaker | 是 | STONITH | 2015 |
| Crunchy PG Operator | PostgreSQL | Crunchy Data | K8s | 是 | Patroni 内嵌 | -- |
| MHA (Master High Availability) | MySQL | DeNA 工程师 | -- | 是 | SSH 脚本 | 2011 (停止维护 ~2018) |
| Orchestrator | MySQL / MariaDB | GitHub 工程师 | etcd / ZK / 自带 backend | 是 | 拓扑感知 | 2014 |
| MaxScale | MariaDB / MySQL | MariaDB Corp | -- | 是 (Monitor) | 自带 | 2015 |
| ProxySQL | MySQL | 社区开源 | -- | 配合 Orchestrator | -- | 2014 |
| MySQL Router | MySQL InnoDB Cluster | Oracle | -- | 是 (基于 GR 状态) | XCom Quorum | 2017 |
| InnoDB Cluster | MySQL | Oracle | -- | 是 (Group Replication) | XCom Quorum | 2017 |

> 关键观察：PostgreSQL 完全没有官方的故障切换工具，整个生态是社区贡献：Patroni（Zalando 2015 开源，最广泛使用）、pg_auto_failover（Citus / Microsoft 2018，更轻量）、repmgr（EDB 系，相对保守）；MySQL 经过 MHA → Orchestrator → InnoDB Cluster 几代演进，目前官方推荐 InnoDB Cluster + MySQL Router；MariaDB 的事实标准是 MaxScale。

## 各引擎深入分析

### MySQL Group Replication (5.7.17+)

MySQL 5.7.17 (2016 年 12 月) 正式 GA Group Replication，第一次让 MySQL 拥有了原生的多副本同步 + 自动故障切换能力。它基于 XCom（一种 Paxos 变种）协议实现：

```sql
-- 启用 Group Replication（在每个节点上）
INSTALL PLUGIN group_replication SONAME 'group_replication.so';

-- 配置参数
SET GLOBAL group_replication_group_name = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
SET GLOBAL group_replication_local_address = 'node1:33061';
SET GLOBAL group_replication_group_seeds = 'node1:33061,node2:33061,node3:33061';

-- 启动第一个节点（bootstrap）
SET GLOBAL group_replication_bootstrap_group = ON;
START GROUP_REPLICATION;
SET GLOBAL group_replication_bootstrap_group = OFF;

-- 其他节点加入
START GROUP_REPLICATION;

-- 查看成员状态
SELECT * FROM performance_schema.replication_group_members;

-- 单主模式手动切换
SELECT group_replication_set_as_primary('aaaaaaaa-bbbb-cccc-dddd-uuid-of-target');
```

工作模式：

- **Single-Primary（单主，默认）**：只有一个节点接受写入，其他副本只读；主库故障时自动选出新主，RTO 通常 30-60 秒。
- **Multi-Primary（多主）**：所有节点都可写入，依赖事务认证（certification）防止冲突；冲突事务后提交者会回滚；适合冲突极少的场景。

故障切换流程（Single-Primary）：

1. 节点 A（主库）崩溃；
2. 其他节点通过心跳超时（默认 5 秒）检测到 A 不可达；
3. XCom 协议视 A 为离线，从剩余成员中按 weight 选出新主 B；
4. B 应用所有已提交但未应用的 binlog；
5. B 切换为可写，对外提供服务；
6. 客户端通过 MySQL Router 透明地连接到 B。

围栏机制：基于 XCom 多数派——少数派分区会立即被踢出集群、变为 ERROR 状态、停止接受写入。这天然规避了脑裂——少数派根本无法形成 quorum。

InnoDB Cluster 是 MySQL 8.0 引入的官方 HA 解决方案，包装了 Group Replication + MySQL Router + MySQL Shell：

```javascript
// MySQL Shell 中创建 InnoDB Cluster
shell.connect('root@node1:3306');
var cluster = dba.createCluster('myCluster');
cluster.addInstance('root@node2:3306');
cluster.addInstance('root@node3:3306');

// 查看集群状态
cluster.status();

// 手动切换主库
cluster.setPrimaryInstance('node2:3306');
```

### Oracle Data Guard Broker + Fast-Start Failover (10g R2+)

Oracle Data Guard 是物理 / 逻辑 standby 的统称。Data Guard Broker 是 10g 引入的管理框架，Fast-Start Failover (FSFO) 是 10g R2 (2005) 引入的真正的自动故障切换机制：

```bash
# DGMGRL 命令行管理
dgmgrl sys/password@primary
DGMGRL> SHOW CONFIGURATION;
DGMGRL> SHOW DATABASE 'primary';
DGMGRL> SHOW DATABASE 'standby';

# 启用 FSFO（需要 Observer 节点）
DGMGRL> EDIT CONFIGURATION SET PROTECTION MODE AS MAXAVAILABILITY;
DGMGRL> EDIT DATABASE 'standby' SET PROPERTY FastStartFailoverTarget='primary';
DGMGRL> EDIT DATABASE 'primary' SET PROPERTY FastStartFailoverTarget='standby';
DGMGRL> ENABLE FAST_START FAILOVER;

# 启动 Observer（在第三方机器上）
DGMGRL> START OBSERVER;

# 查看 FSFO 状态
DGMGRL> SHOW FAST_START FAILOVER;

# 手动 Failover（破坏性，主库未来无法回到角色）
DGMGRL> FAILOVER TO 'standby';

# 手动 Switchover（角色对调，原主可重新使用）
DGMGRL> SWITCHOVER TO 'standby';
```

保护模式（Protection Mode）：

- **Maximum Performance（最大性能）**：异步复制，性能最佳但 RPO > 0；
- **Maximum Availability（最大可用性）**：默认推荐，同步 LGWR SYNC，副本不可达时降级为异步；RPO=0 在正常情况下；
- **Maximum Protection（最大保护）**：同步复制，副本不可达时主库**主动停服**而非降级；保证 RPO=0 但牺牲可用性。

FSFO 流程：

1. Observer 持续监控 Primary 和 Standby 的健康状态；
2. Primary 不可达超过 `FastStartFailoverThreshold`（默认 30 秒）；
3. Observer 与 Standby 协商，确认 Standby 已经收到所有可应用的 redo；
4. Observer 触发 Standby 的 Failover 操作；
5. Standby 应用剩余 redo，切换为新 Primary；
6. 客户端通过 TNS 配置或 Application Continuity 自动重定向。

围栏：Observer 是关键的见证节点——必须运行在与 Primary 和 Standby 都不同的第三方机器上。Observer 与 Primary 通信中断（不同时与 Standby 中断）时，FSFO 不会触发，避免误切。

### SQL Server AlwaysOn Availability Groups (2012+)

SQL Server 2012 引入 AlwaysOn AG，是基于 Windows Server Failover Cluster (WSFC) 的多副本 HA 解决方案：

```sql
-- 创建 Availability Group（在主副本上）
CREATE AVAILABILITY GROUP MyAG
WITH (DB_FAILOVER = ON, DTC_SUPPORT = NONE)
FOR DATABASE [MyDB]
REPLICA ON
    'NODE1' WITH (
        ENDPOINT_URL = 'TCP://NODE1:5022',
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        FAILOVER_MODE = AUTOMATIC,
        BACKUP_PRIORITY = 50
    ),
    'NODE2' WITH (
        ENDPOINT_URL = 'TCP://NODE2:5022',
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        FAILOVER_MODE = AUTOMATIC,
        BACKUP_PRIORITY = 50
    ),
    'NODE3' WITH (
        ENDPOINT_URL = 'TCP://NODE3:5022',
        AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
        FAILOVER_MODE = MANUAL,
        BACKUP_PRIORITY = 50
    );

-- 创建 Availability Group Listener（虚拟 endpoint）
ALTER AVAILABILITY GROUP MyAG
ADD LISTENER 'MyAGListener' (
    WITH IP ((N'10.0.0.100', N'255.255.255.0')),
    PORT = 1433
);

-- 手动 Failover（不丢数据）
ALTER AVAILABILITY GROUP MyAG FAILOVER;

-- 强制 Failover（可能丢数据，主库不可达时）
ALTER AVAILABILITY GROUP MyAG FORCE_FAILOVER_ALLOW_DATA_LOSS;
```

WSFC 仲裁配置：

- **Node Majority**：3 节点 / 5 节点投票，任意时刻多数派存活则集群存活；
- **Node and Disk Majority**：节点 + 磁盘见证（共享磁盘 / SMB 共享），适合偶数节点集群；
- **Node and File Share Majority**：节点 + 文件共享见证；
- **Cloud Witness**：Azure Storage Account 作为云端见证（2016+）；
- **Disk Only**：仅依赖共享磁盘（不推荐，易脑裂）。

故障切换条件（自动切换的前提）：

1. AVAILABILITY_MODE = SYNCHRONOUS_COMMIT；
2. FAILOVER_MODE = AUTOMATIC；
3. WSFC 仲裁正常；
4. 同步副本与主库完全同步（数据未滞后）；
5. 健康监控检测到主库故障（心跳超时、SQL Server 服务停止等）。

### PostgreSQL: 没有原生自动故障切换

这是 PostgreSQL 生态最大的特点（也是争议点）：核心引擎只提供 `pg_promote()` 和流复制基础设施，**完全没有内置的"主库挂了自动切换"逻辑**。所有自动切换都依赖外置工具：

```sql
-- PostgreSQL 内置的手动切换原语
SELECT pg_promote();   -- 把当前 standby 提升为 primary

-- 早期版本（< 12）需要触发文件
-- recovery.conf:
-- trigger_file = '/tmp/promote.trigger'
-- 创建该文件即触发 promote

-- 查看复制状态
SELECT * FROM pg_stat_replication;     -- 在主库看
SELECT * FROM pg_stat_wal_receiver;    -- 在备库看

-- 启用同步复制
ALTER SYSTEM SET synchronous_standby_names = 'ANY 1 (s1, s2, s3)';
SELECT pg_reload_conf();
```

为什么没有原生自动切换？官方立场是这是**集群管理层**的职责，引擎应保持纯粹。PostgreSQL 项目专注于复制协议、流式 WAL、Logical Replication、Logical Decoding 等基础设施，把自动选主、健康监控、客户端路由都留给社区或厂商。

主流外置工具：

#### Patroni（事实标准，Zalando 2015 开源）

Patroni 是一个 Python 守护进程，运行在每个 PG 节点上，用 etcd / Consul / ZooKeeper / K8s API 作为 DCS（Distributed Configuration Store）：

```yaml
# /etc/patroni/postgresql.yml
scope: my_cluster
namespace: /service/
name: node1

restapi:
  listen: 0.0.0.0:8008
  connect_address: node1:8008

etcd:
  hosts: etcd1:2379,etcd2:2379,etcd3:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    synchronous_mode: false
    postgresql:
      use_pg_rewind: true
      parameters:
        max_connections: 100
        shared_buffers: 1GB

postgresql:
  listen: 0.0.0.0:5432
  connect_address: node1:5432
  data_dir: /var/lib/postgresql/14/data
  authentication:
    superuser:
      username: postgres
      password: ...
    replication:
      username: replicator
      password: ...

watchdog:
  mode: required
  device: /dev/watchdog
  safety_margin: 5
```

工作流程：

1. 每个 Patroni 节点定期（`loop_wait`，默认 10 秒）向 DCS 写入心跳；
2. 主库节点通过 DCS 锁（key 加 TTL）声明自己是 leader；
3. 锁的 TTL（默认 30 秒）到期前主库必须续约；
4. 主库不可达 → 锁过期 → 其他 Patroni 节点检测到 → 发起选举；
5. 落后最少的 standby 抢锁 → 抢到锁的执行 `pg_promote()` → 成为新主；
6. 其他 standby 自动 `pg_rewind` 跟随新主；
7. HAProxy / pgbouncer / pgcat 通过 Patroni REST API（`/master`, `/replica`）路由流量。

围栏：

- **DCS 锁**：核心机制，没拿到锁的节点不能 promote；
- **watchdog**：可选的硬件 / 软件 watchdog，主库 Patroni 进程挂掉时强制重启节点；
- **`maximum_lag_on_failover`**：滞后超过该字节数的 standby 不能成为 leader；
- **`synchronous_mode`**：开启后只在同步 standby 中选主，避免数据丢失。

#### pg_auto_failover（Citus / Microsoft 2018）

更轻量的方案，基于 Monitor 节点（也是 PG 实例）做仲裁：

```bash
# 创建 Monitor
pg_autoctl create monitor --pgdata /var/lib/postgresql/monitor --hostname monitor.example.com

# 创建 Primary
pg_autoctl create postgres --pgdata /var/lib/postgresql/data \
  --hostname primary.example.com \
  --monitor postgres://autoctl_node@monitor.example.com:5432/pg_auto_failover

# 创建 Secondary
pg_autoctl create postgres --pgdata /var/lib/postgresql/data \
  --hostname standby.example.com \
  --monitor postgres://autoctl_node@monitor.example.com:5432/pg_auto_failover

# 启动 keeper
pg_autoctl run

# 查看状态
pg_autoctl show state

# 手动 failover
pg_autoctl perform failover
```

特点：

- **三方架构**：Monitor + Primary + Secondary 是最小配置；
- **状态机**：每个节点维护明确的 FSM（PRIMARY、SECONDARY、CATCHINGUP、WAIT_PRIMARY、DEMOTED 等）；
- **自动 sync 切换**：根据 secondary 数量自动调整 `synchronous_standby_names`，至少保留一个同步副本。
- **简单易部署**：相比 Patroni 概念更少、配置更直观；缺点是 Monitor 单点（需要自己再做 Monitor 的 HA）。

#### repmgr（EDB / 2ndQuadrant）

更老的工具，基于 daemon + 命令行，相对保守：

```bash
# 主库初始化
repmgr -f /etc/repmgr.conf primary register

# 备库注册
repmgr -h primary -U repmgr -d repmgr -f /etc/repmgr.conf standby clone
repmgr -f /etc/repmgr.conf standby register

# 启动 repmgrd（自动切换守护进程）
repmgrd -f /etc/repmgr.conf

# 手动 promote
repmgr -f /etc/repmgr.conf standby promote

# 查看集群拓扑
repmgr -f /etc/repmgr.conf cluster show
```

特点：检测保守、误切少；缺点是 RTO 较长（通常分钟级）、围栏机制有限。

### MariaDB 的 HA 工具链：MHA / MaxScale

MariaDB 几乎完全继承 MySQL 的复制架构，但形成了独立的 HA 工具生态：

#### MHA (Master High Availability，DeNA 2011)

```bash
# masterha_check_repl 验证拓扑
masterha_check_repl --conf=/etc/app1.cnf

# masterha_manager 启动监控守护进程
masterha_manager --conf=/etc/app1.cnf

# masterha_master_switch 手动切换
masterha_master_switch --master_state=alive \
  --conf=/etc/app1.cnf \
  --new_master_host=new_master
```

MHA 工作流程：

1. Manager 监控所有节点（默认 3 秒一次）；
2. 检测到主库不可达后等待 9 秒（`ping_interval` × 3）确认；
3. 通过 SSH 连接到主库（如果还能连），保存最新 binlog；
4. 将最新 binlog 应用到最近的 slave；
5. 提升该 slave 为新主；
6. 重新指向其他 slaves 到新主。

MHA 已经 **2018 年左右停止维护**，新部署通常用 Orchestrator 或 MaxScale 替代。

#### MaxScale（MariaDB 官方）

```ini
# /etc/maxscale.cnf
[Mariadb-Monitor]
type=monitor
module=mariadbmon
servers=server1,server2,server3
user=maxscale_monitor
password=...
monitor_interval=2000
auto_failover=true
auto_rejoin=true
failover_timeout=10
switchover_timeout=10

[ReadWriteSplit]
type=service
router=readwritesplit
servers=server1,server2,server3
user=maxscale_user
password=...
```

特点：MariaDB Corp 官方维护、读写分离 + 自动故障切换一体化、支持 MySQL（兼容协议）和 MariaDB；缺点是高级特性需要 BSL 商业授权。

### CockroachDB：原生多区域韧性

CockroachDB 把"高可用"做进了协议本身——基于 Raft 的多副本架构意味着**没有单独的"故障切换"概念**，每个 range（数据分片）的 leader 选举就是天然的故障切换：

```sql
-- CockroachDB 默认每个 range 3 副本
SHOW CLUSTER SETTING kv.range_merge.queue_enabled;
SHOW CLUSTER SETTING kv.range_split.by_load_enabled;

-- 配置副本数为 5（更高可用性，更多写延迟）
ALTER RANGE default CONFIGURE ZONE USING num_replicas = 5;

-- 多区域配置（区域感知副本）
ALTER DATABASE mydb PRIMARY REGION "us-east1";
ALTER DATABASE mydb ADD REGION "us-west1";
ALTER DATABASE mydb ADD REGION "europe-west1";

-- 查看 range 的 leaseholder（实质上的 "primary"）
SELECT range_id, replicas, lease_holder
FROM crdb_internal.ranges
LIMIT 5;

-- 强制把 leaseholder 转移到指定节点
ALTER RANGE 1 RELOCATE LEASE TO 3;
```

故障切换流程（Range 级别）：

1. Range 的 leaseholder 节点崩溃；
2. 其他副本通过 Raft 心跳（默认 1.5 秒）检测到 leader 失联；
3. lease 过期（默认 4.5 秒）后，其他副本发起选举；
4. 任一存活副本拿到 Raft 多数派投票成为新 leader；
5. 新 leader 应用最近未提交的 Raft log；
6. 客户端连接到 gateway 节点，gateway 根据元数据自动路由到新 leaseholder。

典型 RTO < 9 秒（一个完整的 lease 过期 + 选举 + lease 获取周期）。

围栏：Raft 协议天然规避脑裂——少数派分区无法 commit 任何写入，多数派分区独立运行。这是**协议级**的围栏，不需要额外的 STONITH 或见证节点。

多区域韧性（Multi-Region Resilience）：

- **Region Survival**：副本分布在 3+ 个 region，单个 region 完全失效时仍可写；
- **Zone Survival**：副本分布在同一 region 的 3+ AZ，单个 AZ 失效仍可写；
- 通过 `LOCALITY` 配置控制副本放置策略：
  ```sql
  ALTER TABLE users SET LOCALITY GLOBAL;          -- 全局可读
  ALTER TABLE users SET LOCALITY REGIONAL BY ROW; -- 按行所在区域
  ALTER TABLE users SET LOCALITY REGIONAL BY TABLE IN PRIMARY REGION;
  ```

### TiDB：PD 协调的 Raft HA

TiDB 是计算 / 存储分离架构：TiDB（SQL 计算）+ TiKV（KV 存储）+ PD（Placement Driver，元数据管理）。HA 是三层都涉及的：

- **TiDB 节点**：无状态，挂掉后客户端连接到任意其他 TiDB 节点；
- **TiKV 节点**：每个 region 三副本，通过 Raft 自动选主；
- **PD 节点**：3-5 节点，自身基于 Raft，负责调度 region 的副本放置和 leader 转移。

```sql
-- 查看 region 副本分布
SHOW TABLE mytable REGIONS;

-- 强制 region leader 转移
ADMIN TRANSFER LEADER mytable TO STORE 5;

-- 配置副本数
ALTER TABLE mytable PLACEMENT POLICY = 'three_replicas';

-- 创建 placement policy
CREATE PLACEMENT POLICY p1 LEADER_CONSTRAINTS="[+region=us-east]"
                          FOLLOWER_CONSTRAINTS="{+region=us-east: 1, +region=us-west: 1}";
```

故障切换 RTO 约 10-30 秒（取决于 PD 调度速度和 region 数量）。

### YugabyteDB：原生多副本 HA

YugabyteDB 由 Yugabyte 公司（前 Facebook 工程师）2018 年发布，基于 Raft 的分布式 SQL，类似 CockroachDB 但更接近 PostgreSQL 兼容性：

- **YB-Master**：3-5 节点，存储元数据，基于 Raft 选主；
- **YB-TServer**：存储数据 tablet，每个 tablet 三副本，基于 Raft 选主；
- 默认 `raft_heartbeat_interval_ms = 500`，`leader_lease_duration_ms = 2000`，故障检测约 3-5 秒，切换 RTO < 15 秒。

```sql
-- 查看 tablet 分布
SELECT * FROM yb_servers();

-- 配置副本因子（必须在初始化时设置）
-- yb-master --replication_factor=5
```

### Spanner：Google 托管的 Paxos HA

Spanner 是 Google 内部 / 外部托管的分布式 SQL，基于 TrueTime + Paxos：

- 每个 split 默认 5 副本，跨多个 zone；
- Paxos 多数派写入；
- 故障切换由 Google SRE 完全托管，对客户端透明；
- 不暴露任何手动 failover API（这是 Google 的设计哲学：HA 是基础设施层的事）。

客户端唯一感知的是 SDK 的自动重试 / region 切换，配合"Multi-Region instance"配置可实现跨 region 自动故障切换，业务无感。

### RDS Multi-AZ vs Aurora 失败切换对比

#### RDS Multi-AZ（传统）

RDS Multi-AZ 是经典的"主备双机"架构：

- **存储级同步**：基于 EBS 块设备的同步复制（每个写入都等待两个 AZ 都 ACK）；
- **DNS 切换**：CNAME 指向不同 endpoint；
- **典型 RTO 60-120 秒**：包括检测（30-60s）、备库提升、DNS TTL 失效、客户端重连；
- **数据库重启**：备库实际上是冷启动状态，需要 redo recovery；
- **支持引擎**：MySQL、MariaDB、PostgreSQL、Oracle、SQL Server。

```bash
# 触发 RDS Multi-AZ 故障切换（运维操作）
aws rds reboot-db-instance --db-instance-identifier mydb --force-failover

# 查看 Multi-AZ 状态
aws rds describe-db-instances --db-instance-identifier mydb \
  --query 'DBInstances[0].{MultiAZ:MultiAZ,SecondaryAZ:SecondaryAvailabilityZone}'
```

RDS Multi-AZ Cluster（2022 年新增，仅 PG 和 MySQL）：

- 使用 1 主 + 2 备 架构（共 3 个独立实例）；
- 基于半同步复制（其中一个备库同步）；
- **典型 RTO 30-60 秒**（比传统 Multi-AZ 快约一倍）；
- 备库可读（区别于传统 Multi-AZ 的备库不可见）。

#### Aurora 集群故障切换

Aurora 的架构本质不同——计算与存储完全分离，存储层是 6 副本跨 3 AZ 的分布式存储：

- **存储级 quorum**：4/6 写、3/6 读；
- **故障切换语义**：主实例（writer）挂掉后，提升一个 reader 实例为新 writer；
- **不需要 redo recovery**：存储层共享，新 writer 直接接管同一个 redo 流；
- **典型 RTO 30-60 秒**：主要时间花在客户端连接重建和 RDS Proxy 路由更新；
- **故障切换不丢数据**：因为存储层 6 副本 quorum，任何已提交的写入都已经在多数派持久化。

```bash
# 触发 Aurora Failover
aws rds failover-db-cluster --db-cluster-identifier mycluster \
  --target-db-instance-identifier myreader1

# 查看集群成员
aws rds describe-db-clusters --db-cluster-identifier mycluster \
  --query 'DBClusters[0].DBClusterMembers'

# 配置 failover 优先级
aws rds modify-db-instance --db-instance-identifier myreader1 \
  --promotion-tier 0   # 0 是最高优先级
```

关键差异：

| 维度 | RDS Multi-AZ | RDS Multi-AZ Cluster | Aurora |
|------|--------------|----------------------|--------|
| 副本数 | 1 主 + 1 备 | 1 主 + 2 备 | 1 主 + ≤15 reader（共享存储） |
| 备库可见性 | 不可见 | 可读 | 可读（reader endpoint） |
| 复制机制 | EBS 同步 | 半同步 binlog/WAL | 共享分布式存储 |
| 切换触发 | EBS 块切换 | 备库提升 + binlog | reader 提升 |
| 典型 RTO | 60-120s | 30-60s | 30-60s |
| 数据丢失 | 0 | 0 | 0 |
| 跨 AZ 写延迟 | 较高（同步 EBS） | 中（半同步） | 低（NVMe 网络存储） |

### Galera Cluster：无主架构

MariaDB Galera Cluster（同样适用 Percona XtraDB Cluster）采用**无主架构**：所有节点都是对等的、都接受写入，通过 Group Communication 协议保证全局有序。

特点：

- **没有"主库"概念**：每个节点都可写；
- **认证型同步复制**：写入在提交前必须通过其他节点的认证（certification）；
- **多数派写入**：少数派分区会进入 non-primary 状态，停止接受写入；
- **故障切换 = 节点剔除**：任何节点崩溃，剩余多数派直接继续运行，不需要"切换"过程；
- **典型 RTO < 5 秒**（基于 group communication 心跳）；
- **写入冲突回滚**：如果两个节点同时写入冲突行，后提交者会得到 `ER_LOCK_DEADLOCK`。

```sql
-- 查看 Galera 集群状态
SHOW GLOBAL STATUS LIKE 'wsrep_%';

-- 关键状态变量
-- wsrep_cluster_status = Primary（多数派分区）
-- wsrep_cluster_size = 3
-- wsrep_local_state_comment = Synced
```

应用层注意：

- 客户端通常通过 HAProxy + 健康检查指向"任意一个 Synced 节点"；
- 写入应尽量集中到一个节点以减少冲突（"伪单主模式"）；
- 大事务在 Galera 下性能很差（认证开销与事务大小成正比）。

## PostgreSQL 外置工具深入对比

PostgreSQL 没有原生自动切换，所有方案都是社区贡献。以下是主流工具的深入对比：

### Patroni 详解

```
+----------------+         +----------------+         +----------------+
|   Patroni 1    |         |   Patroni 2    |         |   Patroni 3    |
|   (PG primary) |         |  (PG replica)  |         |  (PG replica)  |
+--------+-------+         +--------+-------+         +--------+-------+
         |                          |                          |
         | DCS lock (key + TTL)     |                          |
         +--------------------------+--------------------------+
                                    |
                          +---------+---------+
                          |   etcd / Consul   |
                          |   3-5 nodes       |
                          +-------------------+
```

DCS 选择对比：

| DCS | 一致性协议 | 部署难度 | 性能 | 推荐场景 |
|-----|----------|---------|------|---------|
| etcd | Raft | 中 | 高 | 标准选择，K8s 友好 |
| Consul | Raft | 中 | 高 | 多服务发现场景 |
| ZooKeeper | ZAB | 高 | 中 | 已有 ZK 投资的环境 |
| Kubernetes API | etcd 后端 | 低（K8s 内） | 中 | K8s 内部署 |

故障检测时间公式：

```
最坏情况切换时间 = ttl + 选举延迟 + promote 时间 + 客户端重连
                ≈ 30s + 5s + 5s + 5s = 45s

推荐配置（平衡稳定性与 RTO）：
ttl = 30
loop_wait = 10
retry_timeout = 10
```

防误切机制：

- **`master_start_timeout`**：主库不可达后，先等待这段时间是否能恢复；
- **`maximum_lag_on_failover`**：滞后超过该字节数的备库不能成为新主；
- **`synchronous_mode`**：开启后只考虑同步备库；
- **`watchdog`**：硬件 / 软件 watchdog，主库 Patroni 进程异常时强制重启节点；
- **`nofailover`**：标记某些节点永不参选（如跨地域副本）。

### pg_auto_failover 详解

更轻量的方案，三方架构：

```
+-----------------+     +-----------------+     +-----------------+
|     Monitor     |<--->|     Primary     |<--->|    Secondary    |
|   (PG instance) |     |  (pg_autoctl)   |     |  (pg_autoctl)   |
+-----------------+     +-----------------+     +-----------------+
        ^                       |                        |
        +-----------------------+------------------------+
              keeper 心跳上报，monitor 决策
```

状态机：

```
PRIMARY ----(被 demoted)----> DEMOTED
  ^                              |
  |                              v
WAIT_PRIMARY <--(secondary 上线)-- DEMOTE_TIMEOUT

SECONDARY ----(主库挂)----> CATCHINGUP ---> WAIT_FOR_PROMOTION ---> PROMOTING ---> PRIMARY
```

特点：

- 配置简单（无需 etcd / Consul）；
- 状态机明确，每个状态转换都有日志；
- Monitor 是单点（需要单独做 Monitor 的 HA，如运行在 K8s 中或额外做 Monitor 备份）；
- 自动管理 `synchronous_standby_names`：保证至少一个同步副本，但允许从同步副本中选择 RPO=0 的故障切换。

### Stolon

```
+---------+---------+---------+
| Sentinel  Sentinel  Sentinel|       决策层
+--------+--+--------+--------+
         |
+--------+--------+--------+
| Keeper   Keeper   Keeper |             节点管理层
| + PG     + PG     + PG   |
+--------+--------+--------+
         |
+--------+--------+--------+
|   Proxy  Proxy  Proxy    |             路由层
+--------------------------+
         |
+--------+--------+--------+
|        etcd / Consul     |             状态存储
+--------------------------+
```

特点：完整的"全栈"方案，包含 Sentinel（决策）、Keeper（节点管理）、Proxy（流量路由）；面向 Kubernetes 设计；活跃度低于 Patroni。

### 选型决策树

```
是否使用 K8s？
├── 是 → 使用 Patroni Operator / CrunchyData Operator / StackGres
└── 否 → 是否能维护 etcd 集群？
        ├── 是 → Patroni（事实标准，最成熟）
        └── 否 → pg_auto_failover（更简单，Monitor 单点是接受度高的妥协）

是否需要严格的 STONITH？
├── 是 → PAF（Pacemaker） + Fencing 设备
└── 否 → 上述任一

更看重稳定性而非 RTO？
├── 是 → repmgr（保守，但 RTO 较长）
└── 否 → Patroni（默认 30s ttl 平衡 RTO 与稳定性）
```

## Aurora 存储级故障切换 vs MySQL 主库故障切换

Aurora 的"故障切换"在概念上与传统 MySQL 主库切换完全不同。理解这个差异是云数据库选型的关键：

### MySQL 主库故障切换（传统主从）

```
[Client] --write--> [Master] --binlog--> [Replica 1]
                       |               --> [Replica 2]
                       |               --> [Replica 3]
                       |
                       v
                   [crash!]

故障切换步骤：
1. 检测主库不可达（ProxySQL / Orchestrator）
2. 选出最新的 Replica
3. 等待 Replica 应用完所有可见 binlog（read-write event）
4. STOP SLAVE; CHANGE MASTER TO empty; (Replica 切换为新 Master)
5. 应用层切换连接到新 Master
6. 其他 Replica 重新指向新 Master（可能需要 reset slave）

时间开销：检测 30s + 同步等待 5-30s + 切换 5s + 客户端重连 5s = 45-90s
```

风险点：

- **未传 binlog 永久丢失**：异步复制下，主库本地的 binlog 来不及发送给副本；
- **副本回放滞后**：异步复制下，副本可能滞后几秒，切换时这几秒数据丢失；
- **半同步降级**：MySQL 半同步在副本不响应时会自动降级为异步，此时切换可能丢数据。

### Aurora 集群故障切换（共享存储）

```
[Client] --SQL--> [Writer (compute only)]
                       |
                       v
+----+----+----+----+----+----+
| A1 | A1 | A2 | A2 | A3 | A3 |  (6 副本跨 3 AZ 的分布式存储)
+----+----+----+----+----+----+
                       ^
                       |
                  [Reader (compute only)]

故障切换步骤：
1. 检测 Writer 不可达
2. 选择一个 Reader 实例（或冷启动一个新实例）
3. 该实例 attach 到现有的存储 volume（不需要复制数据！）
4. 应用层切换连接到 Writer endpoint（Aurora 自动更新）

时间开销：检测 10-30s + 实例切换 5-15s + 客户端重连 5-15s = 30-60s
```

关键差异：

- **没有 binlog 流**：Writer 直接把 redo log 写到分布式存储；存储层 4/6 quorum 保证持久化；Reader 实例不需要回放，只需要从存储层读取最新页；
- **没有数据丢失**：任何已 ACK 的写入都在 6 副本中的至少 4 副本上，新 Writer 接管后能看到所有已提交事务；
- **Reader 升级为 Writer 不需要数据复制**：因为存储是共享的，整个故障切换本质是"cache 重热 + endpoint 切换"。

这个架构带来的"附加红利"：

- **添加 Reader 实例 < 1 分钟**：无需复制数据；
- **快速克隆**：copy-on-write，生产数据的 5TB 克隆可以在几秒内完成；
- **跨区域只读副本**：通过 Aurora Global Database，跨 region 复制延迟通常 < 1 秒。

代价：

- **存储层是 AWS 私有的实现**：vendor lock-in；
- **每个 instance 必须连接到同一存储**：跨 region 需要 Global Database（额外组件）；
- **写入延迟比本地 MySQL 略高**：因为 redo 必须跨 AZ ack。

## 脑裂防护：详细机制

脑裂是自动故障切换最危险的失败模式。本节系统对比各引擎的防护机制：

### 1. DCS 锁（Patroni / Stolon 等）

```
原理：所有 promote 必须先抢到 DCS 中的全局锁；锁有 TTL，主库定期续约。

时间线：
  t=0   主库续约 → 锁的 expire 时间 = t + 30s
  t=10  主库续约 → 锁的 expire 时间 = t + 30s
  t=20  主库续约 → 锁的 expire 时间 = t + 30s
  t=25  主库网络中断（但进程仍在运行）
  t=30  备库观察到锁的 expire 时间已到，但 DCS 中锁还存在 → 等待
  t=50  锁过期被删除 → 备库尝试抢锁
  t=51  备库 A 抢到锁 → 执行 pg_promote()
  t=52  备库 A 成为新主，开始接受写入

旧主回归：
  t=100  网络恢复 → 旧主尝试续约 → 发现锁已经被 B 持有 → 自动 demote 为 standby
```

弱点：

- 旧主在 25s ~ 50s 期间仍然认为自己是主，可能接受写入；
- watchdog 可以让旧主在网络中断时直接重启（fence-by-self），缩短窗口。

### 2. STONITH（Pacemaker / Corosync）

```
原理：在 promote 新主之前，先通过 IPMI / 智能 PDU / vCenter 等接口"明确杀死"旧主。

流程：
1. Pacemaker 检测到主库不可达
2. 不立即 promote！先执行 STONITH 操作：
   - 通过 IPMI 远程电源切断旧主
   - 或通过 vCenter API 强制关机虚拟机
   - 或通过 SCSI Reservation 切断旧主对存储的访问
3. STONITH 操作 ACK 后，确认旧主"死透"
4. 在备库执行 promote
```

优点：彻底杜绝脑裂——旧主真的没电了；

缺点：依赖外部设备（IPMI / iLO / 智能电源 / vCenter）；操作时间从几秒到一分钟不等；裸金属环境配置复杂。

### 3. WSFC 仲裁（SQL Server）

```
原理：Windows Server Failover Cluster 集群每个节点都参与投票，必须多数派同意才能形成"集群"。

仲裁模式：
- Node Majority：3 节点中需要 2 个存活
- Node and File Share Majority：4 节点 + 1 见证文件，5 票需要 3 票
- Node and Disk Majority：4 节点 + 1 共享磁盘
- Cloud Witness：4 节点 + Azure Storage 见证（推荐）

少数派分区行为：
- 集群进入"无 quorum"状态
- AlwaysOn AG 自动停止（数据库进入 RESOLVING 状态）
- 不接受任何写入
```

### 4. Raft / Paxos 多数派（CockroachDB / TiDB / Spanner）

```
原理：协议本身要求多数派（n/2+1）确认才能 commit，这是天然的脑裂防护。

举例：5 副本集群，3-2 网络分区
- 多数派（3 副本）继续选举出 leader、接受写入
- 少数派（2 副本）无法选出 leader，所有写入超时失败
- 网络恢复后：少数派副本通过 Raft 日志同步追上多数派
- 不存在"两个 leader 都接受写入然后冲突"的可能
```

这是分布式 SQL 相对传统主从架构最重要的改进——**协议级**的脑裂防护，不需要额外的 STONITH 或见证。

### 5. Galera Group Communication

```
原理：Group Communication 系统（gcomm）维护成员视图，少数派分区会进入 non-primary 状态。

行为：
- Primary 状态：多数派可见 → 接受写入
- non-Primary 状态：少数派可见 → 拒绝所有写入（自动只读）
- 成员从 non-Primary 恢复到 Primary 时自动同步状态（IST 或 SST）
```

### 6. 应用层围栏（ProxySQL / MaxScale / RDS Proxy）

```
原理：流量都经过代理层，代理层只把写流量路由到当前的"已确认主"。

举例：MySQL Group Replication + MySQL Router
- Router 持续查询每个节点的 group_replication_members
- 只把写流量发送到 PRIMARY 状态的节点
- 旧主即使没死，因为不在 quorum 中、状态变为 ERROR，Router 不会再向它发送流量
```

这是最弱的围栏（依然信任旧主会"自觉"停止写入），但在很多生产系统中已经够用。

### 围栏强度排序

```
最强 →                                                             → 最弱
STONITH（物理切电） > Raft/Paxos 协议级 > WSFC 仲裁 + Cluster 停服
> DCS 锁 + watchdog > DCS 锁 > 应用层路由围栏 > 无围栏（裸主从复制）
```

## 关键发现

### 1. 自动故障切换不是"开关"，是工程系统

许多团队把"开启自动故障切换"等同于"我有 HA 了"。实际上，自动切换是一个完整的工程系统：

- 检测组件（监控、心跳、健康检查）的灵敏度 vs 误判平衡；
- 围栏机制的强度（STONITH / Quorum / DCS 锁）；
- 客户端的连接重建能力（重连、重试、idempotency）；
- 数据回放的语义（异步切换可能丢数据，同步切换 RPO=0）；
- 跨区域时的网络分区策略；
- 切换后的"反向拥护"流程（旧主回归后能否自动 demote）。

### 2. PostgreSQL 是主流 OLTP 引擎中唯一没有原生自动切换的

这是 PostgreSQL 项目的明确立场——不把"集群管理"纳入引擎核心。生态用 Patroni / pg_auto_failover / repmgr / Stolon / PAF 填补了这个空白。

实际生产中：

- **Patroni** 是事实标准，K8s 内外都广泛使用；
- **pg_auto_failover** 在小规模部署或不想引入 etcd 的场景受欢迎；
- **repmgr** 主要存在于历史部署中，新项目较少选择。

### 3. RTO 30 秒是"行业默认底线"

绝大多数现代 HA 工具的默认配置都把 RTO 压在 30 秒级：

- Patroni 默认 ttl=30 秒、loop_wait=10 秒；
- Oracle FSFO 默认 FastStartFailoverThreshold=30 秒；
- AWS RDS Multi-AZ 典型 60-120 秒（DNS 切换是瓶颈）；
- Aurora 典型 30-60 秒；
- CockroachDB 默认 lease=4.5 秒，整体 RTO < 9 秒。

更短的 RTO 需要付出更高的误切风险代价。

### 4. RPO=0 必须搭配同步复制或多数派写

任何依赖异步复制的方案都不可能保证 RPO=0：

- MySQL 异步 + MHA / Orchestrator → RPO > 0；
- PostgreSQL 异步流复制 + Patroni → RPO > 0；
- Oracle Maximum Performance → RPO > 0；
- SQL Server Async-Commit → RPO > 0；

要 RPO=0：

- 同步复制：MySQL 半同步（AFTER_SYNC）、PG `synchronous_commit=on`、Oracle Maximum Availability、SQL Server Sync-Commit；
- 多数派写：MySQL Group Replication、Galera、Raft / Paxos 系（CockroachDB / TiDB / Spanner / YugabyteDB / OceanBase）；
- 共享存储：Aurora 的 6/3 quorum。

### 5. 分布式 SQL 重新定义了 HA

CockroachDB / TiDB / Spanner / YugabyteDB / OceanBase 等分布式 SQL 引擎让"故障切换"这个概念本身变得不那么重要：

- 没有"主库挂了"的语义，只有"某个 range 的 leader 挂了"；
- 没有专门的故障切换流程，Raft / Paxos 选举本身就是切换；
- 没有专门的运维命令（`promote` / `failover`），所有切换都是协议自发的；
- RTO 仅取决于协议参数（lease 长度、心跳间隔）。

代价：必须 ≥3 节点部署、写入延迟受 quorum 影响、查询有跨节点跳转。

### 6. Aurora 与 RDS Multi-AZ 的故障切换是两个不同的故事

许多人误以为 Aurora 是 "更好的 RDS Multi-AZ"。实际上它们的故障切换机制完全不同：

- RDS Multi-AZ 是经典主备双机 + 块级同步；
- Aurora 是"计算 + 共享分布式存储"，故障切换 = "新计算实例 attach 到现有存储"。

两者都做到 RPO=0，但 Aurora 因为不需要 redo recovery、能更快速地添加 reader、能克隆共享存储，在云原生 OLTP 场景明显更有优势。

### 7. 围栏机制是 HA 的"安全锁"

没有围栏的自动故障切换比没有自动故障切换更危险——脑裂可能导致数据严重分叉、合并困难、业务数据错乱。所有生产级 HA 部署都必须包含某种形式的围栏：

- 协议级（Raft / Paxos / 多数派）→ 最强；
- STONITH（物理切电）→ 极强但部署复杂；
- WSFC 仲裁 / DCS 锁 → 主流妥协；
- 应用层路由 → 最弱，但配合其他机制依然可用。

### 8. MySQL 的"半同步 lossless" 是误读最深的术语

MySQL 半同步（rpl_semi_sync_master_enabled = ON）在 5.7+ 默认 AFTER_SYNC 模式：

- 主库等待至少一个备库**收到 binlog 并写入磁盘**后才向客户端返回 COMMIT；
- 但这只保证 **binlog 的传输**，不保证备库已经回放（应用）；
- 如果主库崩溃，最新事务在备库的 binlog 中还**没有应用到 InnoDB**，需要切换后再 SQL 线程回放；
- 重要：超时（默认 10 秒）后会自动**降级为异步**，此时 RPO 不再保证为 0。

这个"lossless"标签经常误导工程师认为 MySQL 半同步等价于 PostgreSQL `synchronous_commit=on`——其实 MySQL 半同步比 PG 同步弱一档（只 flush，不 apply），且超时后还会降级。

### 9. 切换 ≠ 灾难恢复

故障切换（failover）和灾难恢复（disaster recovery）是不同概念：

- **故障切换**：单个数据中心 / 单个 region 内的高可用；典型 RTO 数十秒；典型 RPO=0；
- **灾难恢复**：跨地域 / 跨数据中心；典型 RTO 数分钟到数小时；典型 RPO 从几秒到几分钟。

很多 "HA" 方案只覆盖前者（如 RDS Multi-AZ、Patroni 同 region 集群），跨 region 的容灾需要单独设计（如 Aurora Global Database、Spanner Multi-Region、自建 logical replication）。

### 10. HA 的核心成本是"运维复杂度"，不是"硬件成本"

部署一个 3-5 节点的 HA 集群相对于单机的硬件成本只是 2-5 倍，但运维复杂度是指数级增长：

- 监控（每个节点都要有完整指标）；
- 备份（每个节点的 WAL / binlog 都要归档）；
- 升级（滚动升级要保证集群始终有 quorum）；
- 故障演练（切换测试不能在生产高峰期做）；
- 调试（脑裂、误切、复制延迟问题难定位）。

托管服务（RDS、Aurora、Spanner）值钱的不是基础设施，而是把运维复杂度从客户身上移走了。

## 对引擎开发者的建议

### 1. 健康检测灵敏度参数

设计自动故障切换时，最关键的参数是健康检测的"超时":

```
heartbeat_interval: 心跳间隔（典型 1-3 秒）
heartbeat_timeout:  心跳超时（典型 5-10 秒）
fence_timeout:      触发围栏前的等待时间（典型 10-30 秒）
```

这三个参数共同决定 RTO 与误切率的权衡：

- 太短（如 heartbeat_timeout=2 秒）→ 误切率高（GC 暂停、网络抖动都会触发）；
- 太长（如 heartbeat_timeout=60 秒）→ RTO 长（业务感知到长时间不可用）。

经验值：心跳间隔 1-3 秒、心跳超时 5-10 秒、围栏触发 15-30 秒。

### 2. 状态机设计

每个节点必须有明确的状态机，状态转换要有日志：

```
PRIMARY ←→ DEMOTING → DEMOTED → CATCHING_UP → SECONDARY
                                                  ↓
                                          WAIT_FOR_PROMOTION
                                                  ↓
                                              PROMOTING
                                                  ↓
                                              PRIMARY
```

每次状态转换都应该：

- 持久化到 DCS / 元数据存储；
- 写入审计日志；
- 触发 webhook / 监控告警；
- 防止幂等问题（如重复触发 promote）。

### 3. 围栏机制必须可观测

故障切换日志应明确记录：

- **谁触发了切换**（监控组件 / 手动命令 / 协议自发）；
- **何时触发**（精确到毫秒）；
- **基于什么证据**（哪些节点的心跳超时、哪些节点的状态）；
- **围栏操作的结果**（DCS 锁是否抢到、STONITH 是否 ACK）；
- **切换后的拓扑**（新主是谁、其他节点状态）。

这些日志在故障复盘时是金矿。

### 4. 防误切设计

避免故障切换的最大风险是误切（false positive）。设计时应考虑：

- **多源验证**：不止依赖单一心跳，结合 SQL 健康检查、磁盘可写性、复制状态等多维度证据；
- **延迟决策**：检测到异常后再等待一个周期确认（避免瞬时网络抖动）；
- **优先级控制**：标记某些节点（如跨地域副本、性能差的节点）不参选；
- **滞后阈值**：备库滞后超过阈值时不能 promote（避免 RPO 损失）；
- **手动确认门槛**：极端场景（如所有节点都不健康）应要求人工确认。

### 5. 客户端连接重建的协议设计

故障切换的"最后一公里"是客户端连接重建。设计协议时应考虑：

- **明确的 endpoint 抽象**：客户端连接到 endpoint 而非具体节点（如 Aurora Reader/Writer Endpoint、SQL Server AG Listener）；
- **快速失败**：客户端检测到当前连接不可用时应快速退出（避免长 socket timeout）；
- **重试 + idempotency**：未确认的写操作要支持幂等重试；
- **元数据缓存**：客户端缓存集群元数据，故障切换后能快速找到新主；
- **会话状态重建**：临时表、prepared statement、会话变量在切换后是否丢失要明确语义。

### 6. 切换后的"反向回归"流程

故障切换不是终点——旧主恢复后需要明确的"回归"流程：

- 自动 demote 为 standby（不能再独立接受写入）；
- 通过 `pg_rewind` / GTID skip / Raft snapshot 与新主对齐数据；
- 视情况是否需要重新 sync 到新主（如果旧主缺失了切换期间的写入）；
- 重新加入 quorum 池或读取流量池。

这个流程在很多老旧 HA 工具中是手动的——MHA、早期 Patroni 都需要 DBA 介入。现代工具（Patroni 1.0+、CockroachDB、Spanner）都已经做到全自动。

### 7. 端到端测试矩阵

HA 系统必须有完整的测试矩阵：

- 单节点崩溃 + 自动切换；
- 网络分区（多数派 vs 少数派）；
- 网络分区导致脑裂尝试（验证围栏生效）；
- 慢节点（GC 暂停、磁盘 I/O 慢）→ 不应触发切换；
- 滚动升级（始终保证 quorum）；
- 多个备库同时挂掉；
- 主库与所有备库都挂掉（验证 RPO 边界）；
- 备库重新上线后的状态同步；
- 切换期间的客户端流量；
- 历史 binlog / WAL 损坏的恢复。

每一项都应该有自动化的混沌测试（Chaos Engineering）。

## 总结对比矩阵

### HA 能力总览

| 能力 | PostgreSQL | MySQL | Oracle | SQL Server | Aurora | RDS Multi-AZ | CockroachDB | TiDB | Spanner |
|------|-----------|-------|--------|------------|--------|--------------|-------------|------|---------|
| 原生自动切换 | -- | GR (5.7.17+) | DG Broker FSFO | AlwaysOn AG | 是 | 是 | 是 (Raft) | 是 (Raft) | 是 (Paxos) |
| 手动晋升 | `pg_promote()` | `CHANGE MASTER` | `DGMGRL FAILOVER` | `ALTER AG FAILOVER` | API | API | 自动 | 自动 | 不可见 |
| 围栏 | 外置 (DCS / STONITH) | XCom Quorum | Observer + Fence Group | WSFC 仲裁 | 存储层 quorum | EBS 块同步 | Raft Quorum | Raft Quorum | Paxos |
| 典型 RTO | 视外置 (10-30s) | 30-60s | 5-30s | 10-60s | 30-60s | 60-120s | < 9s | < 30s | 透明 |
| RPO=0 可能 | 同步复制 | GR / 半同步 | Max Availability/Protection | Sync-Commit | 是 (集群) | 是 (本地) | 是 | 是 | 是 |
| 多数派 quorum | 是（5.x ANY） | GR 是 | Far Sync 多目标 | -- | 6/4 写 4/3 读 | -- | 是 | 是 | 是 |

### 引擎选型建议

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| 单 region 高可用 OLTP（PG） | PostgreSQL + Patroni + etcd | 事实标准，K8s 友好 |
| 单 region 高可用 OLTP（MySQL） | InnoDB Cluster (Group Replication + Router) | 官方推荐，原生集成 |
| 强一致 + 跨地域 | CockroachDB / Spanner / TiDB | 协议级 quorum，自然多区域 |
| 强一致 + 云上托管 | Aurora（MySQL/PG）/ Spanner | 托管 HA + 共享存储优势 |
| 极低 RTO（< 10s）| CockroachDB / Spanner | Raft / Paxos 协议级 |
| 极简部署 + 自动 HA | pg_auto_failover / RDS Multi-AZ | 配置简单 |
| Windows 生态 | SQL Server AlwaysOn + WSFC | 与 OS 深度集成 |
| Oracle 生态 | Data Guard + FSFO + Observer | 久经验证 |
| 分析型 OLAP | Snowflake / BigQuery / Databricks | 完全托管，无需关心 HA |
| 边缘 / 嵌入式 | SQLite / DuckDB | 单机本身可靠 |

## 参考资料

- MySQL: [Group Replication](https://dev.mysql.com/doc/refman/8.0/en/group-replication.html)
- MySQL: [InnoDB Cluster](https://dev.mysql.com/doc/refman/8.0/en/mysql-innodb-cluster-introduction.html)
- MySQL: [MySQL Router](https://dev.mysql.com/doc/mysql-router/8.0/en/)
- Oracle: [Data Guard Broker](https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/)
- Oracle: [Fast-Start Failover](https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/oracle-data-guard-broker-concepts.html#GUID-0E0AD46F-1D3C-44CB-A3F2-D29A06D55ED2)
- SQL Server: [Always On Availability Groups](https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/always-on-availability-groups-sql-server)
- SQL Server: [Windows Server Failover Cluster](https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/wsfc-with-sql-server)
- PostgreSQL: [pg_promote](https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-RECOVERY-CONTROL-FUNCTIONS)
- Patroni: [Documentation](https://patroni.readthedocs.io/)
- pg_auto_failover: [GitHub](https://github.com/citusdata/pg_auto_failover)
- repmgr: [Documentation](https://repmgr.org/docs/current/)
- Stolon: [GitHub](https://github.com/sorintlab/stolon)
- MariaDB: [MaxScale](https://mariadb.com/kb/en/mariadb-maxscale/)
- AWS: [Aurora Failover](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Concepts.AuroraHighAvailability.html)
- AWS: [RDS Multi-AZ](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html)
- CockroachDB: [Disaster Recovery](https://www.cockroachlabs.com/docs/stable/disaster-recovery.html)
- TiDB: [High Availability FAQ](https://docs.pingcap.com/tidb/stable/faq-best-practices)
- Google Spanner: [Replication](https://cloud.google.com/spanner/docs/replication)
- YugabyteDB: [Fault Tolerance](https://docs.yugabyte.com/preview/architecture/docdb-replication/)
- Galera: [Cluster Documentation](https://galeracluster.com/library/documentation/)
- Brewer, E. "CAP Twelve Years Later: How the Rules Have Changed" (2012), IEEE Computer
- Gray, J., Helland, P. et al. "The Dangers of Replication and a Solution" (1996), SIGMOD
