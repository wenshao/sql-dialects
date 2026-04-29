# 复制槽生命周期管理 (Replication Slot Lifecycle)

复制槽是个看似无害的小数据结构——一行系统视图记录、一个 LSN 指针、一段元数据——却能凭一己之力把一台健康的 PostgreSQL 主库拖死：当下游订阅者断连数日，未被消费的 WAL 文件会被槽"钉住"，磁盘从 50% 涨到 95% 再到 100%，所有写事务挂起，监控告警炸响，运维半夜从床上爬起来执行 `pg_drop_replication_slot`。这是 PostgreSQL 运维事故榜上的常客，也是工程师们对"流复制" + "逻辑复制"两条技术路线最痛恨的运维成本。本文梳理 45+ 数据库引擎的复制槽生命周期管理，重点回答三个问题：哪些引擎有复制槽？复制槽出问题时如何防御？没有复制槽的引擎用什么替代？

## 为什么需要复制槽

复制是把源库的修改在副本上重放。问题在于：源库不知道副本读到了哪里，也不知道副本是否还活着。如果源库只管按时间或大小回收 WAL（PostgreSQL 的 `wal_keep_size`、MySQL 的 `binlog_expire_logs_seconds`），下游一旦断连超过保留窗口，就只能重新做全量同步。

复制槽 (Replication Slot) 是 PostgreSQL 9.4 (2014 年 12 月) 引入的解决方案：

1. **持久化 LSN 指针**：每个槽记录一个 `restart_lsn` 和 `confirmed_flush_lsn`，告诉源库"我已经确认收到这里了"。
2. **WAL 保留承诺**：源库**保证**不回收任何槽尚未确认的 WAL，无论保留窗口配置如何。
3. **槽存活感知**：通过 `pg_replication_slots.active` 列可以看到槽是否在线、`active_pid` 关联的 walsender 进程。

复制槽是一把双刃剑：

- 优点：副本可以离线任意时长，重连后从断点续传；逻辑解码必须依赖槽来追踪事务边界与全局快照；同步复制可以基于槽实现精确的 fsync 确认。
- 缺点：**孤儿槽是运维噩梦**——如果创建槽的下游消费者永久离线（如测试环境删除，VM 丢失），槽会持续阻止 WAL 回收，磁盘被填满直至源库崩溃。

> 与本文相关的两篇姊妹文：`logical-decoding.md` 聚焦"WAL → 行事件"的翻译机制及输出插件协议；`logical-replication-gtid.md` 聚焦内置发布订阅 DDL 与 GTID/LSN/SCN 等事务标识体系。本文则深入复制槽这个**资源对象**的创建、监控、清理、故障切换全生命周期。

## 不存在 SQL 标准

复制槽完全没有 ISO SQL 标准。ISO/IEC 9075 从未涉及"如何记录下游消费进度"，所有相关的视图、函数、参数、命令都是厂商专有：

- PostgreSQL 用 `pg_replication_slots` 视图 + `pg_create_physical_replication_slot` / `pg_create_logical_replication_slot` / `pg_drop_replication_slot` 函数族。
- MySQL/MariaDB 完全不存在槽概念，下游通过 GTID 集合 (`gtid_executed`) 自行维护回放位置；源端只能通过 `expire_logs_days` / `binlog_expire_logs_seconds` 在时间维度上保留 binlog。
- SQL Server 通过 Distributor 角色的 `MSrepl_commands` 表持久化命令，事务复制订阅者通过 LSN 续点。
- Oracle GoldenGate 用 trail 文件 + checkpoint 表追踪进度，没有"槽"这个内核对象。
- ClickHouse ReplicatedMergeTree 完全依赖 ZooKeeper / ClickHouse Keeper 协调，副本心跳与队列存储在 ZK znode 中。
- CockroachDB / TiDB 的 CHANGEFEED / TiCDC 把 checkpoint 存储在外部 sink 端（Kafka offset、对象存储等），源端不持久化下游进度。

这种百花齐放使得"复制槽生命周期"成为最依赖具体引擎的运维知识——没有任何跨引擎的最佳实践可以直接套用。

## 支持矩阵 (45+ 引擎)

### 1. 物理复制槽

| 引擎 | 物理槽 | 命令 | 起始版本 | 备注 |
|------|------|------|--------|------|
| PostgreSQL | 是 | `pg_create_physical_replication_slot` | 9.4 (2014-12) | 流复制 standby 用 |
| MySQL | -- | -- (用 binlog file:position 或 GTID) | -- | 没有槽概念 |
| MariaDB | -- | -- | -- | 同 MySQL |
| SQLite | -- | -- | -- | 嵌入式无复制 |
| Oracle | -- | -- (Data Guard 用 archive log shipping) | -- | 用 ARCH/LGWR 进程 + log destination |
| Oracle GoldenGate | -- | -- (用 trail file + checkpoint) | -- | trail 是替代品 |
| SQL Server | -- | -- (AlwaysOn AG 用 LogReader Agent) | -- | 用 log truncation hold |
| DB2 | -- | -- (HADR 用 log shipping) | -- | -- |
| Snowflake | -- | -- (托管复制) | -- | 内部状态用户不可见 |
| BigQuery | -- | -- | -- | 不适用 |
| Redshift | -- | -- | -- | -- |
| DuckDB | -- | -- | -- | 嵌入式 |
| ClickHouse | ZK 节点 | (自动) ReplicatedMergeTree | 14.x+ | 副本队列存于 ZK |
| Trino | -- | -- | -- | 查询引擎 |
| Presto | -- | -- | -- | 查询引擎 |
| Spark SQL | -- | -- | -- | 查询引擎 |
| Hive | -- | -- (REPL DUMP/LOAD 是批模式) | -- | -- |
| Flink SQL | -- | -- (流处理) | -- | 不适用 |
| Databricks | -- (Delta Sharing) | -- | -- | -- |
| Teradata | -- | -- (Replication Services 内部) | -- | -- |
| Greenplum | 是 (PG fork) | 同 PostgreSQL | 6.0+ | mirror 段使用 |
| CockroachDB | -- (Raft 内部) | -- | -- | 用 Raft log truncation |
| TiDB | -- (Raft 内部) | -- | -- | 用 GC safe point |
| OceanBase | -- (Paxos 内部) | -- | -- | 用 clog 保留策略 |
| YugabyteDB | 是 (PG-compatible) | 同 PostgreSQL | 2.18+ | 兼容 PG 流复制 |
| SingleStore | -- | -- | -- | 内部 partition replicas |
| Vertica | -- | -- | -- | K-safety 内部 |
| Impala | -- | -- | -- | 查询引擎 |
| StarRocks | -- | -- | -- | 内部多副本 |
| Doris | -- | -- | -- | 内部多副本 |
| MonetDB | -- | -- | -- | 不支持 |
| CrateDB | -- | -- | -- | 不支持 |
| TimescaleDB | 继承 PG | 同 PostgreSQL | 继承 | -- |
| QuestDB | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | 不支持 |
| SAP HANA | -- (System Replication) | -- | -- | 内部 |
| Informix | -- (HDR/RSS) | -- | -- | 用 logical log shipping |
| Firebird | -- | -- | -- | nbackup 是物理 |
| H2 | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | 不支持 |
| Amazon Athena | -- | -- | -- | 查询引擎 |
| Azure Synapse | -- | -- | -- | 不支持 |
| Google Spanner | -- | -- (Paxos 内部) | -- | -- |
| Materialize | -- (订阅端) | -- | -- | 槽在上游 PG |
| RisingWave | -- (订阅端) | -- | -- | 槽在上游 PG |
| InfluxDB | -- | -- | -- | -- |
| DatabendDB | -- | -- | -- | -- |
| Yellowbrick | -- | -- | -- | -- |
| Firebolt | -- | -- | -- | -- |
| MongoDB | -- | -- (oplog tail) | -- | 用 oplog 大小 |
| Cassandra | -- | -- | -- | -- |

> 统计：仅 PostgreSQL 系（含 Greenplum/TimescaleDB/YugabyteDB）原生提供"复制槽"这一内核对象；ClickHouse 用 ZooKeeper 节点近似替代；其余引擎要么用 log shipping 配合手工保留策略，要么把进度持久化到外部系统。

### 2. 逻辑复制槽

| 引擎 | 逻辑槽 | 命令 | 起始版本 | 备注 |
|------|------|------|--------|------|
| PostgreSQL | 是 | `pg_create_logical_replication_slot('name', 'plugin')` | 9.4 (2014-12) | 需要 output plugin |
| MySQL | -- | -- (binlog dump 协议) | -- | 没有槽 |
| MariaDB | -- | -- | -- | 同 MySQL |
| Oracle | -- (LogMiner / XStream session) | -- | -- | session 是临时的 |
| Oracle GoldenGate | trail | `ADD EXTRACT ... CHECKPOINTTABLE` | 1999+ | checkpoint 表是软槽 |
| SQL Server | -- (CDC capture instance) | `sys.sp_cdc_enable_table` | 2008+ | 用 retention 控制保留 |
| DB2 | Q Capture subscription | `ASNCLP CREATE Q SUBSCRIPTION` | 早期 | -- |
| Snowflake | Streams | `CREATE STREAM` | GA | 类槽，依赖时间旅行 |
| BigQuery | -- | -- | -- | 用 Datastream |
| Redshift | -- | -- | -- | -- |
| ClickHouse | -- | -- (但有 MaterializedPostgreSQL 客户端槽) | 21.4+ 实验 | 在上游 PG 创建槽 |
| Hive | -- | -- (REPL DUMP 状态) | 3.0+ | 非槽 |
| Databricks | -- (Delta CDF) | -- | -- | 表级 retention |
| Greenplum | 是 (PG fork) | 同 PostgreSQL | 6.0+ | -- |
| CockroachDB | CHANGEFEED job | `CREATE CHANGEFEED` | 2.1 (2018) | job 系统替代槽 |
| TiDB | TiCDC changefeed | `cdc cli changefeed create` | 4.0 (2020) | 外部组件 |
| OceanBase | OBCDC instance | -- | 3.x (2021) | -- |
| YugabyteDB | 是 (PG-compatible) | 同 PostgreSQL | 2.18+ | xCluster 也有内部槽 |
| Spanner | Change Streams | `CREATE CHANGE STREAM` | 2022 | TVF 消费 |
| Materialize | 上游 PG 槽 | (内部创建) | GA | 上游必须开 wal_level=logical |
| RisingWave | 上游 PG 槽 | (内部创建) | GA | 同 Materialize |
| MongoDB | -- (oplog tail) | -- | -- | 用 oplogSize |
| Cassandra | CDC commitlog | (cdc=true) | 3.0 | 文件级 retention |
| Informix | ER subscription | `cdr define` | 早期 | -- |
| TimescaleDB | 继承 PG | -- | 继承 | -- |

> 统计：约 6 个引擎提供持久化"逻辑槽"对象（PG 系 + GoldenGate trail + DB2 Q Capture + Snowflake Streams 等）；约 5 个 NewSQL 用 changefeed/job 系统替代；约 25 个引擎完全不存在该概念。

### 3. WAL/日志保留控制参数

| 引擎 | 关键参数 | 含义 | 默认值 | 起始版本 |
|------|--------|------|------|--------|
| PostgreSQL | `max_wal_size` | WAL 文件总大小上限 (软) | 1GB | 9.5 |
| PostgreSQL | `wal_keep_size` | 流复制保留 WAL 大小 | 0 (无) | 13 |
| PostgreSQL | `wal_keep_segments` | 同上 (旧名) | 0 | 9.4-12 |
| PostgreSQL | `max_slot_wal_keep_size` | **槽允许保留的最大 WAL 大小** | -1 (不限) | 13 (2020-09) |
| PostgreSQL | `idle_in_transaction_session_timeout` | 闲置事务超时 | 0 (无) | 9.6 |
| PostgreSQL | `wal_sender_timeout` | walsender 心跳超时 | 60s | 9.4 |
| MySQL | `binlog_expire_logs_seconds` | binlog 保留时间 | 2592000 (30 天) | 8.0+ |
| MySQL | `expire_logs_days` | 同上 (旧) | 0 | 5.x |
| MySQL | `max_binlog_size` | 单文件大小 | 1GB | 早期 |
| MariaDB | `expire_logs_days` | 同 MySQL | 0 | 早期 |
| Oracle | `LOG_ARCHIVE_DEST_n` | 归档日志目的地 | -- | 早期 |
| Oracle | `DB_RECOVERY_FILE_DEST_SIZE` | FRA 大小 | -- | 10g+ |
| SQL Server | `RETENTION` (复制) | distribution DB 保留小时数 | 72h | 早期 |
| SQL Server | `recovery model` | FULL/SIMPLE/BULK_LOGGED | FULL | 早期 |
| ClickHouse | `cleanup_thread_preferred_points_per_iteration` | ZK 清理速率 | -- | -- |
| TiDB | `tidb_gc_life_time` | GC 保留时间 | 10min | -- |
| CockroachDB | `gc.ttlseconds` | per-zone GC TTL | 25h | -- |

PostgreSQL 13 引入的 `max_slot_wal_keep_size` 是复制槽运维的革命性改进：在此之前，孤儿槽会**无限**保留 WAL 直至磁盘塞满；之后，运维可以为槽设置 WAL 保留上限，超过时主动作废槽（标记为 `lost`），优先保护源库可用性。

### 4. 槽管理函数与视图

| 引擎 | 创建槽 | 删除槽 | 监控视图 |
|------|------|------|--------|
| PostgreSQL | `pg_create_physical_replication_slot(name, immediately_reserve)` | `pg_drop_replication_slot(name)` | `pg_replication_slots` |
| PostgreSQL | `pg_create_logical_replication_slot(name, plugin, temporary, twophase)` | 同上 | 同上 |
| PostgreSQL | `pg_replication_slot_advance(name, lsn)` | -- | -- |
| PostgreSQL | `pg_copy_physical_replication_slot(src, dst)` | -- | -- |
| PostgreSQL | `pg_copy_logical_replication_slot(src, dst, plugin)` | -- | -- |
| MySQL | -- | -- | `SHOW BINARY LOGS` / `performance_schema.replication_*` |
| MariaDB | -- | -- | `SHOW BINARY LOGS` |
| Oracle GoldenGate | `ADD EXTRACT` / `ADD REPLICAT` | `DELETE EXTRACT` / `DELETE REPLICAT` | `INFO EXTRACT *` |
| SQL Server (复制) | `sp_addpublication` | `sp_droppublication` | `MSdistribution_status` 等 |
| SQL Server (CDC) | `sys.sp_cdc_enable_table` | `sys.sp_cdc_disable_table` | `cdc.change_tables` |
| DB2 Q Repl | `ASNCLP CREATE Q SUBSCRIPTION` | 同删除命令 | `IBMQREP_*` 表 |
| Snowflake | `CREATE STREAM` | `DROP STREAM` | `SHOW STREAMS` |
| ClickHouse | (自动 ZK) | `SYSTEM DROP REPLICA` | `system.replicas` |
| YugabyteDB | 同 PG (兼容) | 同 PG | 同 PG |

### 5. 故障切换槽 (Failover Slot)

| 引擎 | 故障切换保留槽 | 实现 | 起始版本 |
|------|------------|------|--------|
| PostgreSQL (社区) | -- (16 之前不支持) | -- | -- |
| PostgreSQL 16 | 有限支持 | 逻辑解码 on standby (新基础设施) | 16 (2023-09) |
| PostgreSQL 17 | 是 | `failover = true` 槽属性 + slot sync worker | 17 (2024-09) |
| EDB pg_failover_slots | 是 | 独立扩展 | 早于 16 |
| pglogical / EDB BDR | 是 | 节点级槽同步 | 早期 |
| Patroni | 部分 | `permanent_replication_slots` 配置 | -- |
| Stolon | 部分 | -- | -- |
| MySQL | 不适用 (无槽) | -- | -- |
| Oracle Data Guard | 是 (broker 自动管理) | -- | 早期 |
| GoldenGate | 是 (Active-Active 拓扑) | -- | 早期 |
| ClickHouse | 是 (ZK 全局) | -- | -- |
| YugabyteDB | 是 (xCluster) | -- | 2.18+ |

PostgreSQL 16 (2023 年 9 月) 是个分水岭：在此之前**逻辑复制槽不能在 standby 上创建**，因此当主库故障切换到 standby 时，逻辑订阅者必须重新做全量同步——这是 PG 高可用部署中最痛苦的痛点。PG 16 引入"逻辑解码 on standby"基础设施，PG 17 (2024) 进一步加入 `failover` 槽属性和 slot sync worker，让槽元数据可以从主库同步到 standby，故障切换后下游可以无缝续传。

EDB 的 `pg_failover_slots` 扩展更早（PG 11/12/13 都可用）解决了同样问题，是 16 之前的事实标准。

## 各引擎深入剖析

### PostgreSQL：复制槽生态原产地

PostgreSQL 是唯一在 SQL/系统视图层面把"复制槽"作为一等公民暴露的引擎。所有的概念、命令、运维范式都是从 PG 开始演化、再反过来影响其他引擎的设计的。

```sql
-- 1. 创建物理槽（流复制 standby）
SELECT pg_create_physical_replication_slot('standby1');

-- 立即保留 WAL（默认仅在副本连接时开始保留）
SELECT pg_create_physical_replication_slot('standby1', true);

-- 2. 创建逻辑槽（CDC / 逻辑订阅）
SELECT pg_create_logical_replication_slot('cdc_slot', 'pgoutput');

-- 临时槽（会话结束自动删除，常用于一次性同步）
SELECT pg_create_logical_replication_slot('temp_slot', 'pgoutput', true);

-- 二阶段提交支持（pg14+）
SELECT pg_create_logical_replication_slot('2pc_slot', 'pgoutput', false, true);

-- 3. 监控槽状态
SELECT slot_name, slot_type, active, active_pid,
       restart_lsn, confirmed_flush_lsn,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_size
  FROM pg_replication_slots;

-- 4. 推进槽位置（手工干预，通常用于跳过坏块）
SELECT pg_replication_slot_advance('cdc_slot', '0/1A2B3C4D');

-- 5. 删除槽（前提：active = false）
SELECT pg_drop_replication_slot('cdc_slot');

-- 强制删除活跃槽：先 terminate walsender
SELECT pg_terminate_backend(active_pid)
  FROM pg_replication_slots WHERE slot_name = 'cdc_slot';
SELECT pg_drop_replication_slot('cdc_slot');

-- 6. 复制槽（PG 12+）
SELECT pg_copy_physical_replication_slot('src_slot', 'dst_slot');
SELECT pg_copy_logical_replication_slot('src_slot', 'dst_slot', 'pgoutput');
```

`pg_replication_slots` 视图列说明：

- `slot_name` / `plugin` / `slot_type` (`physical` 或 `logical`)
- `database`：逻辑槽绑定的库（物理槽为 NULL）
- `temporary`：临时槽 (true 时会话结束自动清理)
- `active` / `active_pid`：是否有 walsender 连接，对应进程 PID
- `xmin` / `catalog_xmin`：槽保留的最小事务 ID（影响 VACUUM）
- `restart_lsn`：源库不能回收的 WAL 位置
- `confirmed_flush_lsn`：下游确认已持久化的位置（仅逻辑槽）
- `wal_status`：`reserved` / `extended` / `unreserved` / `lost` (PG 13+)
- `safe_wal_size`：当前位置之前还能产生多少 WAL 不会触发槽丢失 (PG 13+)
- `two_phase`：是否启用二阶段解码 (PG 14+)
- `failover`：是否参与故障切换槽同步 (PG 17+)
- `synced`：是否已从主库同步元数据 (PG 17+)

### PostgreSQL `max_slot_wal_keep_size` 深度剖析（PG 13+）

PG 13 之前，复制槽是个"绝对优先级"的资源：只要槽存在且未推进，源库就**保证**保留 WAL，即使磁盘已经爆满、整个数据库即将崩溃。运维只能监控 `pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)` 提前告警。

PG 13 引入 `max_slot_wal_keep_size`（默认 -1 表示不限），允许运维设置槽保留 WAL 的上限。当槽保留量超过该值时：

```
1. 源库继续推进 LSN，正常回收 WAL
2. 槽的 wal_status 从 reserved → extended → unreserved → lost
3. 槽被标记为 lost 后，下游连接时收到错误：
   ERROR: requested WAL segment XXXXXX has already been removed
4. 下游必须重新做全量同步（pg_basebackup 或 pg_dump 重做）
```

```sql
-- 设置阈值（建议值：磁盘可用空间的 30-50%）
ALTER SYSTEM SET max_slot_wal_keep_size = '20GB';
SELECT pg_reload_conf();

-- 查看当前状态
SELECT slot_name, wal_status,
       pg_size_pretty(safe_wal_size) AS safe_remaining
  FROM pg_replication_slots;

-- 输出示例：
-- slot_name  | wal_status | safe_remaining
-- standby1   | reserved   | 18 GB
-- cdc_slot   | extended   | 2 GB         <- 接近阈值
-- old_slot   | lost       | -            <- 已失效
```

`wal_status` 状态机：

- `reserved`：槽保留量在 `max_wal_size` 以内，正常状态
- `extended`：槽保留量超过 `max_wal_size` 但仍在 `max_slot_wal_keep_size` 内
- `unreserved`：槽保留量超过 `max_slot_wal_keep_size`，WAL 即将被回收
- `lost`：WAL 已被回收，槽不可恢复

监控告警建议：

```sql
-- 告警 1：槽保留量超过阈值的 50%
SELECT slot_name,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained,
       active
  FROM pg_replication_slots
 WHERE pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) >
       (current_setting('max_slot_wal_keep_size')::bigint * 1024 / 2);

-- 告警 2：槽离线时长（active = false 持续多久）
SELECT slot_name, active, active_pid,
       pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) AS lag_bytes
  FROM pg_replication_slots
 WHERE active = false AND slot_type = 'logical';

-- 告警 3：槽已 lost
SELECT slot_name FROM pg_replication_slots WHERE wal_status = 'lost';
```

### PostgreSQL 故障切换槽：从 EDB 扩展到内核原生

#### 16 之前：pg_failover_slots 扩展

EDB 的 `pg_failover_slots` 扩展（开源，BSD 许可）是 PG 11-15 的事实方案：

```bash
# 主库 postgresql.conf
shared_preload_libraries = 'pg_failover_slots'
pg_failover_slots.synchronize_slot_names = 'sub_*'  # 通配符匹配

# Standby 配置
primary_slot_name = 'standby1'
hot_standby_feedback = on
```

工作原理：

1. 主库 background worker 周期性把 `pg_replication_slots` 序列化到 `pg_failover_slots` 内部表
2. WAL 复制把这张表传给 standby
3. Standby 上有对应 worker 把表数据反序列化为槽（这些槽不会推进 WAL，仅作元数据存档）
4. Standby 提升为主库后，槽自动激活，下游订阅者重连即可续传

局限：

- 槽元数据有延迟（默认 1 分钟同步），故障切换后下游可能需要补 1 分钟数据
- 不支持物理槽（仅逻辑槽）
- 需要额外维护一个扩展（PG 升级时常见兼容问题）

#### PG 16：逻辑解码 on standby

PG 16 (2023-09) 终于允许在 standby 上**直接创建**逻辑槽：

```sql
-- 直接在 standby 上创建逻辑槽
SELECT pg_create_logical_replication_slot('standby_cdc', 'pgoutput');

-- 下游订阅者可以连接 standby 消费
-- 优势：减轻主库 CPU/网络压力
-- 限制：standby 提升为主库时，槽必须由 standby 自己创建并维护
```

这解决了一个关键场景：分析型 CDC（接 Kafka → 数仓）可以挂在 standby 上不影响主库。但**它不解决故障切换问题**——如果 standby 自己挂了，槽也丢了。

#### PG 17：原生 failover slot

PG 17 (2024-09) 引入完整的 failover slot 机制：

```sql
-- 主库创建带 failover 属性的槽
SELECT pg_create_logical_replication_slot('cdc_failover', 'pgoutput',
                                          false,  -- temporary
                                          false,  -- twophase
                                          true);  -- failover

-- Standby 配置（自动同步槽）
-- standby/postgresql.conf:
-- sync_replication_slots = on
-- primary_slot_name = 'standby1'
-- primary_conninfo = '... dbname=replication'

-- Standby 端查看同步过来的槽
SELECT slot_name, failover, synced
  FROM pg_replication_slots
 WHERE synced = true;

-- 故障切换后，订阅者连接新主库（原 standby）时自动发现槽并续传
-- 无需重做全量同步
```

工作原理：

1. 主库 walsender 把 `failover = true` 的槽元数据通过专门通道推给 standby
2. Standby 上 slot sync worker 接收并写入本地 `pg_replication_slots`
3. 同步频率由 `sync_replication_slots_inactive_timeout` 控制（默认 30 秒）
4. 故障切换后，原 standby 上的槽自动激活，`active = false → active = true`

PG 17 的 failover slot 是 PostgreSQL 高可用 + 逻辑复制走向真正生产级的关键里程碑。

### MySQL：用 GTID 集合替代槽

MySQL/MariaDB 的世界里**没有槽**。源端 binlog 按时间或大小回收（`binlog_expire_logs_seconds` / `expire_logs_days`），副本通过 `gtid_executed` 集合自行判断已回放到哪里：

```sql
-- 查看源端 binlog 文件
SHOW BINARY LOGS;
-- 输出:
-- Log_name      | File_size  | Encrypted
-- mysql-bin.001 | 1073741824 | No
-- mysql-bin.002 | 1073741824 | No
-- ...

-- 查看副本回放进度
SHOW REPLICA STATUS\G
-- Source_Log_File: mysql-bin.005
-- Read_Source_Log_Pos: 12345678
-- Executed_Gtid_Set: source-uuid:1-100000

-- 配置 binlog 保留
SET GLOBAL binlog_expire_logs_seconds = 604800;  -- 7 天

-- 副本 GTID 模式下的"续点"
-- 副本启动时把自己的 gtid_executed 发给源端
-- 源端用 gtid_purged 检查需要的 GTID 是否已被清理
SHOW GLOBAL VARIABLES LIKE 'gtid_purged';
```

MySQL 的劣势：

- 副本离线超过 `binlog_expire_logs_seconds` 后，所需 binlog 已删除，**只能重做全量同步**
- 没有"槽"对象，副本健康状态需要从源端 `SHOW PROCESSLIST` 找 `Binlog Dump GTID` 线程，间接判断
- 不能针对单个副本设置不同的保留策略

MySQL 的优势：

- **没有孤儿槽问题**——保留窗口由时间/大小固定，离线副本不会拖死源库
- 对 DBA 更友好：DDL 简单、状态一目了然，不需要监控 `pg_replication_slots`

### MariaDB：与 MySQL 同源

MariaDB 复用 MySQL 的 binlog 协议，没有槽概念。GTID 格式不同（`domain_id-server_id-sequence_number`），但生命周期管理完全一致：依赖 `expire_logs_days`。

### Oracle GoldenGate：trail 文件代替槽

Oracle 没有数据库内核层面的"槽"。Data Guard 通过 archive log shipping + log destination 的 `MANDATORY` 属性保留归档日志。GoldenGate 走另一条路——extract 进程把 redo 解码为独立的 **trail 文件**，下游 replicat 进程读 trail：

```bash
# GGSCI 命令
GGSCI> ADD EXTRACT ext_main, INTEGRATED TRANLOG, BEGIN NOW
GGSCI> ADD EXTTRAIL ./dirdat/aa, EXTRACT ext_main
GGSCI> ADD CHECKPOINTTABLE GGADMIN.CHKPT

# 查看 extract 进度
GGSCI> INFO EXTRACT ext_main, DETAIL
# EXTRACT    EXT_MAIN  Last Started 2024-01-01 10:00   Status RUNNING
# Checkpoint Lag       00:00:05
# Log Read Checkpoint  Oracle Redo Logs 2024-01-01 10:00:30
# trail file: ./dirdat/aa, current size: 50 MB
```

Trail 是 GoldenGate 的"槽"：

- Extract 写 trail，replicat 读 trail，独立于源库 redo
- Trail 文件按大小切片，由 `MAXFILESIZE` 控制
- 下游断连时，trail 持续累积，磁盘耗尽是 GG 运维的常见问题
- 通过 `CHECKPOINTTABLE` 持久化 extract / replicat 的位置

GG 的孤儿"槽"问题：测试环境删除 replicat 后，extract 仍在生成 trail，需要手动 `DELETE EXTRACT` 和 `PURGE EXTTRAIL`。

### SQL Server：分发服务器代替槽

SQL Server 事务复制依赖独立的 **Distributor** 角色：

```sql
-- 启用复制需要先配置 Distributor
EXEC sp_adddistributor @distributor = N'DIST_SERVER';

-- 创建发布
EXEC sp_addpublication @publication = N'pub_sales',
    @repl_freq = N'continuous',
    @retention = 72,           -- 保留 72 小时
    @sync_method = N'concurrent';

-- 添加订阅
EXEC sp_addsubscription @publication = N'pub_sales',
    @subscriber = N'SUB_SERVER',
    @subscription_type = N'push';

-- 查看复制状态
EXEC sp_replmonitorhelpsubscription @publisher = 'PUB_SERVER',
    @publication = 'pub_sales';
```

`MSrepl_commands` 表是 Distributor 的持久化命令队列，类似复制槽：

- LogReader Agent 从源库 transaction log 读出已提交事务，转换为命令写入 `MSrepl_commands`
- Distribution Agent 从 `MSrepl_commands` 读出命令，发往订阅者
- 订阅者确认后，命令从 `MSrepl_commands` 清除（按 `@retention` 保留）

孤儿订阅问题：删除订阅前若没有 `sp_dropsubscription` 清理，Distributor 会持续累积未确认的命令。

CDC（非复制，独立特性）走另一条路：

```sql
-- 启用库级 CDC
EXEC sys.sp_cdc_enable_db;

-- 启用表级 CDC
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'orders',
    @role_name = NULL,
    @capture_instance = N'orders_cdc';

-- CDC 捕获作业读 transaction log，写入 cdc.dbo_orders_CT 变更表
-- 通过 retention 控制保留：
EXEC sys.sp_cdc_change_job @job_type = N'cleanup', @retention = 4320;  -- 3 天 (分钟)
```

CDC 没有"订阅者确认"机制，纯粹按时间保留。下游消费者用 `sys.fn_cdc_get_all_changes_<capture_instance>` 函数查询。

### DB2：Q Replication 与 Q Capture

DB2 的 Q Replication 通过 MQ 队列做异步复制，**Q Capture** 进程读 active log 写入 MQ，**Q Apply** 从 MQ 读取写入目标库：

```bash
# ASNCLP 配置
asnclp -f setup.in
> CREATE Q SUBSCRIPTION subname
> USING REPLQMAP qmap1
> (SUBTYPE U
> SOURCE TABLE schema.tbl
> TARGET TABLE schema.tbl);

# 监控
SELECT SUBNAME, STATE, CURRENT_LOG_TIME
  FROM IBMQREP_SUBS
 WHERE SUBSTATE = 'A';
```

Q Capture 的进度持久化在 `IBMQREP_CAPMON` 等表中。MQ 队列充当"槽"——队列深度增加表示下游处理不及，需要扩容或告警。

### Snowflake：Streams 是时间旅行槽

Snowflake 不存在"复制槽"概念，但 **Streams** 提供了类似语义：

```sql
-- 创建表流（捕获 INSERT/UPDATE/DELETE）
CREATE STREAM orders_stream ON TABLE orders;

-- 消费流（DML 进入流时清空消费指针）
SELECT * FROM orders_stream;
INSERT INTO orders_archive SELECT * FROM orders_stream;  -- DML 后流指针前进

-- 流的"保留期" = 表的 DATA_RETENTION_TIME_IN_DAYS（默认 1 天，企业版最长 90 天）
ALTER TABLE orders SET DATA_RETENTION_TIME_IN_DAYS = 7;

-- 查看所有流
SHOW STREAMS;
SELECT * FROM INFORMATION_SCHEMA.STREAMS;
```

Streams 与 PG 槽的对比：

- 类似点：持久化的"消费进度指针"，下游消费后才前进
- 差异：Streams 不阻塞数据回收，超过 retention 后流自动失效（`STALE = TRUE`）；不像 PG 槽会死保 WAL
- 这是 Snowflake 的设计权衡：可用性优先，但下游必须自己监控 staleness

### ClickHouse：ZooKeeper / Keeper 替代槽

ClickHouse 的 ReplicatedMergeTree 通过 ZooKeeper（或自带的 ClickHouse Keeper）协调多副本：

```sql
-- 建表时指定 ZK 路径
CREATE TABLE events (
    event_time DateTime,
    user_id UInt64,
    payload String
) ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{shard}/events',  -- ZK 路径
    '{replica}'                            -- 副本名
)
ORDER BY (user_id, event_time);

-- ZK 中的"槽"结构（伪代码）
/clickhouse/tables/01/events/
├── replicas/
│   ├── replica1/
│   │   ├── queue/        # 该副本待处理任务队列
│   │   ├── log_pointer   # 已处理的全局 log 位置
│   │   └── is_active     # 心跳节点 (ephemeral)
│   ├── replica2/
│   └── ...
├── log/                   # 全局 mutation/merge 日志
│   ├── log-0000000001
│   └── ...
└── blocks/               # 已写入块的去重元数据
```

每个副本在 ZK 中有自己的 znode，记录 `log_pointer`（处理进度），`queue`（待办任务）。这本质上就是分布式版的"复制槽"。

孤儿副本问题：

```sql
-- 副本主机宕机后，ZK 中的 replica/<name> 节点不会自动清理
-- 全局 log 和 queue 持续累积，ZK 内存压力增大
-- 必须手动清理：
SYSTEM DROP REPLICA 'dead_replica' FROM TABLE events;

-- 清理整个表的所有元数据（极端情况）
SYSTEM DROP REPLICA 'dead_replica' FROM ZKPATH '/clickhouse/tables/01/events';

-- 监控
SELECT database, table, replica_name, log_pointer, log_max_index,
       queue_size, absolute_delay
  FROM system.replicas;
```

ClickHouse Keeper（22.5+ 默认推荐）是 Raft 实现的 ZK 协议兼容服务，部署简化但孤儿槽问题机制相同。

### CockroachDB：CHANGEFEED Job 系统

CockroachDB 没有 PG 意义上的槽。`CHANGEFEED` 是 SQL DML 创建的 **job**（持久化在系统表中）：

```sql
-- 创建 changefeed
CREATE CHANGEFEED FOR TABLE orders
INTO 'kafka://broker:9092?topic_name=orders'
WITH updated, resolved = '10s';

-- 查看 job
SHOW CHANGEFEED JOBS;

-- 暂停/恢复/取消
PAUSE JOB 1234567890;
RESUME JOB 1234567890;
CANCEL JOB 1234567890;

-- Job 系统表
SELECT id, status, created, finished
  FROM crdb_internal.jobs
 WHERE job_type = 'CHANGEFEED';
```

CockroachDB 的设计哲学是"下游进度由 sink 自己持久化"——Kafka 用 offset，对象存储用文件名 + 时间戳。源端只记录 changefeed 自身的高水位（`high_water_timestamp`）和元数据。

孤儿问题处理：

- Job 长期 PAUSED 不会拖累集群（Raft log 仍按 `gc.ttlseconds` 回收）
- 如果暂停超过 GC TTL，恢复时报错"changefeed timestamp behind GC threshold"，必须重建
- 防御措施：监控 `crdb_internal.jobs` 的 paused 时长

### TiDB：TiCDC 的外部 changefeed

TiDB 的 CDC 由独立组件 **TiCDC** 实现，进度保存在 PD（集群协调服务）和 sink 端：

```bash
# 创建 changefeed
tiup ctl:v7.5.0 cdc cli changefeed create \
  --server=http://cdc-server:8300 \
  --sink-uri="kafka://kafka-broker:9092/topic-name?protocol=canal-json" \
  --changefeed-id="orders-feed"

# 查看
tiup ctl:v7.5.0 cdc cli changefeed list --server=http://cdc-server:8300

# 暂停/恢复/删除
tiup ctl:v7.5.0 cdc cli changefeed pause --changefeed-id=orders-feed
tiup ctl:v7.5.0 cdc cli changefeed resume --changefeed-id=orders-feed
tiup ctl:v7.5.0 cdc cli changefeed remove --changefeed-id=orders-feed
```

TiKV 的 GC（垃圾回收）由 PD 全局调度，`tidb_gc_life_time` 决定 MVCC 旧版本保留时长（默认 10 分钟，可配置到几小时）。如果 changefeed 落后超过 GC 窗口，会出现：

```
Error: GC life time is shorter than transaction duration
```

防御措施：监控 changefeed 的 `checkpoint_ts` 与当前时间的差距，超过 80% GC 窗口时告警。

### YugabyteDB：兼容 PG 槽 + xCluster

YugabyteDB 2.18+ 提供两套机制：

1. **PG-兼容流复制**：在 SQL 层创建 `pg_create_logical_replication_slot`，行为与 PG 一致
2. **xCluster**：Yugabyte 自己的异地多活复制，内部用 cdcsdk_state 表追踪进度

```sql
-- PG 兼容方式
SELECT pg_create_logical_replication_slot('cdc_slot', 'yboutput');

-- xCluster 方式（管理 API）
yb-admin setup_universe_replication \
    <producer_universe_uuid> \
    <producer_master_addresses> \
    <comma_separated_table_ids>

-- 查看
yb-admin get_universe_replication <producer_universe_uuid>
```

xCluster 不阻塞源端 WAL 回收（设计上副本必须保持在线，否则触发告警人工介入）。

### Materialize 与 RisingWave：上游槽消费者

这两个流处理引擎的特点是：**自己不维护槽**，但在配置 `CREATE SOURCE` 时会在上游 PG 自动创建逻辑槽：

```sql
-- Materialize
CREATE SOURCE pg_source
  FROM POSTGRES CONNECTION pg_conn (
    PUBLICATION 'mz_pub'
  )
  FOR ALL TABLES;

-- 此时上游 PG 自动创建槽: materialize_<random_id>
-- 在上游 PG 查看:
SELECT slot_name, plugin, active
  FROM pg_replication_slots
 WHERE slot_name LIKE 'materialize_%';
```

如果 Materialize 集群下线（如开发环境停掉），上游 PG 的槽会变成孤儿槽——这是 PG + Materialize 部署最常见的事故源头。Materialize 7.x+ 提供了集群关闭时清理上游槽的 hook，但仍需要运维主动配置。

### MongoDB oplog：用大小代替槽

MongoDB 副本集没有槽，依赖**有限大小的 capped collection** `local.oplog.rs`：

```javascript
// 查看 oplog 大小
db.runCommand({ replSetGetStatus: 1 });
db.getReplicationInfo();

// 修改大小（5.0+ 推荐用 hours 而非 size）
db.adminCommand({ replSetResizeOplog: 1, minRetentionHours: 24 });
```

副本必须在 oplog 窗口内完成同步，否则进入 RECOVERING 状态需要 initial sync。这是"无槽"模式的典型问题——可用性不受单个副本拖累，但代价是副本有"必须跟上"的硬约束。

### Cassandra：CDC commitlog

Cassandra 3.0+ 提供 `cdc=true` 表属性，commitlog 文件被复制到 `cdc_raw_directory`：

```sql
CREATE TABLE events (
    user_id uuid, event_time timestamp, payload text,
    PRIMARY KEY (user_id, event_time)
) WITH cdc = true;
```

```yaml
# cassandra.yaml
cdc_enabled: true
cdc_raw_directory: /var/lib/cassandra/cdc_raw
cdc_total_space_in_mb: 4096   # CDC 文件总大小上限
```

文件级保留，超过 `cdc_total_space_in_mb` 时**写入会被阻塞**（关键：Cassandra 选择停写而非丢数据）。下游消费者必须主动删除已处理的 commitlog 文件。

### Greenplum / TimescaleDB：继承 PG

两者都基于 PostgreSQL，复制槽机制完全继承：

- Greenplum 6.x（基于 PG 9.4）支持物理槽，用于 mirror 段
- TimescaleDB 是 PG 扩展，复制槽行为与底层 PG 一致

### Informix Enterprise Replication

Informix ER 在 logical log 之上做行级复制，订阅记录在 `cdr define server` 命令创建的内部表中：

```bash
cdr define server --init --connect=master_node g_master
cdr define server --connect=slave_node g_slave
cdr define replicateset rs_orders
cdr define replicate "P-orders" "select * from orders"
```

类槽对象是 `replicate` 与 `replicateset`，进度持久化在 `syscdr` 库。

## 槽生命周期：创建 → 监控 → 清理

下面以 PG 为主线，展示一个复制槽完整的生命周期管理流程。

### 阶段 1：创建

```sql
-- 物理槽（流复制 standby）
SELECT pg_create_physical_replication_slot('standby1', true);
-- 第二个参数 immediately_reserve=true：立即开始保留 WAL
-- 默认 false：等到 standby 第一次连接时才保留

-- 逻辑槽（CDC / 订阅）
SELECT pg_create_logical_replication_slot(
    'cdc_orders',          -- 槽名（命名规范建议: <consumer>_<purpose>）
    'pgoutput',            -- 插件: pgoutput / wal2json / decoderbufs / test_decoding
    false,                 -- temporary: 是否会话级临时槽
    false                  -- twophase: 是否解码 PREPARE TRANSACTION (PG 14+)
);

-- 命名最佳实践
-- 包含: 消费者名称 + 用途 + 创建日期
-- 示例: debezium_orders_20240101 / matview_refresh_daily
-- 反例: slot1 / test / tmp
```

### 阶段 2：日常监控

```sql
-- 监控指标 1：槽存活
SELECT slot_name, active, active_pid,
       CASE WHEN NOT active THEN
            EXTRACT(EPOCH FROM (now() - pg_stat_replication.last_msg_receipt_time))
       END AS offline_seconds
  FROM pg_replication_slots
  LEFT JOIN pg_stat_replication ON pg_stat_replication.pid = active_pid;

-- 监控指标 2：槽延迟（WAL 字节数）
SELECT slot_name,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS total_lag
  FROM pg_replication_slots;

-- 监控指标 3：阻塞 VACUUM
SELECT slot_name, xmin, catalog_xmin,
       (SELECT max(age(xmin)) FROM pg_replication_slots) AS oldest_xact_age
  FROM pg_replication_slots
 WHERE xmin IS NOT NULL OR catalog_xmin IS NOT NULL;
-- xmin 阻塞 dead tuple 清理；catalog_xmin 阻塞 catalog 表清理

-- 监控指标 4：wal_status (PG 13+)
SELECT slot_name, wal_status,
       pg_size_pretty(safe_wal_size) AS safe_remaining
  FROM pg_replication_slots
 WHERE wal_status IN ('extended', 'unreserved', 'lost');

-- 监控指标 5：磁盘占用与 WAL 总量
SELECT pg_size_pretty(pg_size_bytes(pg_ls_dir('pg_wal'))) AS pg_wal_size;
-- 实际查 disk usage:
\! du -sh $PGDATA/pg_wal
```

### 阶段 3：故障处理

#### 场景 1：槽 active = false 持续多日

```sql
-- 诊断
SELECT slot_name, slot_type, active, active_pid,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained
  FROM pg_replication_slots
 WHERE NOT active;

-- 决策：
-- A. 下游临时离线（如重启），可继续等待 → 但要监控 retained 不超过磁盘上限
-- B. 下游永久离线（VM 已删，订阅者下线），立即删除槽
SELECT pg_drop_replication_slot('orphan_slot');
```

#### 场景 2：槽 active = true 但下游卡住

```sql
-- 检查 walsender 进程
SELECT pid, application_name, state, sync_state,
       sent_lsn, write_lsn, flush_lsn, replay_lsn,
       write_lag, flush_lag, replay_lag
  FROM pg_stat_replication;

-- 如果 lag 持续增长但下游本身忙于其他工作（合理），等待
-- 如果下游死锁/挂起，杀掉 walsender 让其重连
SELECT pg_terminate_backend(active_pid)
  FROM pg_replication_slots WHERE slot_name = 'stuck_slot';
```

#### 场景 3：磁盘即将爆满

```sql
-- 紧急方案 A：手动推进槽（仅在确认丢数据可接受时使用！）
SELECT pg_replication_slot_advance('lagging_slot', pg_current_wal_lsn());

-- 紧急方案 B：直接删除槽（下游必须重建订阅）
SELECT pg_drop_replication_slot('lagging_slot');

-- 紧急方案 C：如果有 max_slot_wal_keep_size 但太大，临时调小
ALTER SYSTEM SET max_slot_wal_keep_size = '5GB';
SELECT pg_reload_conf();
-- 槽超过限制后会被标记为 lost，源库 WAL 自动回收
```

#### 场景 4：故障切换后槽丢失

PG 16 之前：

```sql
-- standby 提升后没有原主库的逻辑槽
SELECT * FROM pg_replication_slots;
-- (空)

-- 下游订阅者连接报错：
-- ERROR: replication slot "cdc_orders" does not exist

-- 唯一办法：重建槽 + 下游重新做全量同步
SELECT pg_create_logical_replication_slot('cdc_orders', 'pgoutput');
-- 然后下游：
DROP SUBSCRIPTION sub_orders;
CREATE SUBSCRIPTION sub_orders ... WITH (copy_data = true);
```

PG 17+ failover slot：

```sql
-- 主库
SELECT pg_create_logical_replication_slot('cdc_orders', 'pgoutput',
                                          false, false, true);  -- failover=true

-- standby 自动同步该槽
-- 故障切换后，新主库（原 standby）已有该槽，下游直接重连即可
```

### 阶段 4：清理

```sql
-- 测试环境定期清理
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT slot_name FROM pg_replication_slots
             WHERE NOT active
               AND pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) > 1024 * 1024 * 1024
             -- 不活跃且保留超过 1GB WAL
    LOOP
        RAISE NOTICE 'Dropping orphan slot: %', r.slot_name;
        PERFORM pg_drop_replication_slot(r.slot_name);
    END LOOP;
END
$$;

-- 生产环境必须人工确认
-- 自动化脚本应只产生告警，不要自动删除
```

## 槽泄漏检测：基于 pg_replication_slots 的告警体系

槽泄漏 (slot leak) 指的是：槽存在但已无对应消费者，持续阻止 WAL 回收。检测的关键指标：

```sql
-- 综合告警查询
WITH slot_health AS (
  SELECT
    slot_name,
    slot_type,
    active,
    active_pid,
    database,
    wal_status,
    pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS retained_bytes,
    pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) AS lag_bytes,
    age(xmin) AS xmin_age,
    age(catalog_xmin) AS catalog_xmin_age,
    safe_wal_size
  FROM pg_replication_slots
)
SELECT
  slot_name,
  CASE
    WHEN wal_status = 'lost' THEN 'CRITICAL: slot lost, recreate required'
    WHEN wal_status = 'unreserved' THEN 'CRITICAL: WAL about to be removed'
    WHEN wal_status = 'extended' AND NOT active THEN 'WARN: extended + inactive'
    WHEN retained_bytes > 10 * 1024 * 1024 * 1024 THEN 'WARN: > 10 GB retained'
    WHEN catalog_xmin_age > 1000000 THEN 'WARN: blocking VACUUM'
    WHEN NOT active AND retained_bytes > 1024 * 1024 * 1024 THEN 'INFO: inactive > 1 GB'
    ELSE 'OK'
  END AS status,
  pg_size_pretty(retained_bytes) AS retained,
  pg_size_pretty(lag_bytes) AS lag,
  pg_size_pretty(safe_wal_size) AS safe_remaining
FROM slot_health
ORDER BY retained_bytes DESC;
```

### Prometheus 风格指标

```yaml
# postgres_exporter 内置 pg_replication_slot 指标
- pg_replication_slot_current_wal_lsn{slot_name=...}
- pg_replication_slot_confirmed_flush_lsn{slot_name=...}
- pg_replication_slot_is_active{slot_name=...}
- pg_replication_slot_safe_wal_size{slot_name=...}
- pg_replication_slot_xmin_age{slot_name=...}

# 告警规则示例
- alert: PgReplicationSlotInactive
  expr: pg_replication_slot_is_active == 0
  for: 30m
  annotations:
    summary: "Replication slot {{ $labels.slot_name }} inactive for 30m+"

- alert: PgReplicationSlotLagHigh
  expr: pg_wal_lsn_diff(pg_current_wal_lsn(), pg_replication_slot_restart_lsn) > 10737418240
  for: 5m
  annotations:
    summary: "Slot {{ $labels.slot_name }} retains > 10 GB WAL"

- alert: PgReplicationSlotWalStatusLost
  expr: pg_replication_slot_wal_status{wal_status="lost"} == 1
  annotations:
    summary: "Slot {{ $labels.slot_name }} entered LOST state — must recreate"
```

### 槽泄漏的常见根因

| 根因 | 表现 | 防御 |
|------|------|------|
| 测试环境删除订阅者忘清理槽 | active=false 持续累积 | CI/CD 流水线删除环境时强制 `DROP SUBSCRIPTION` |
| 应用进程崩溃但守护进程未重启 | active=false 短暂，但若死循环 OOM 永久离线 | 监控 active 翻转频率 |
| 网络分区导致 walsender 长期等待 | active=true 但 sent_lsn 不前进 | `wal_sender_timeout` 兜底 |
| Materialize/RW 集群被删 | 上游 PG 出现 `materialize_*` 孤儿槽 | 删除前清理 hook |
| Debezium connector 误删未清槽 | `debezium_*` 孤儿槽 | drop.slot.on.stop=true 配置 |
| 主备切换后旧槽残留 | standby 提升后历史槽变孤儿 | PG 17 failover slot |
| 大事务导致 catalog_xmin 长期保留 | 阻塞 VACUUM | 限制大事务时长 |

## 引擎设计权衡：有槽 vs 无槽

| 维度 | 有槽 (PG / GoldenGate / ClickHouse) | 无槽 (MySQL / MongoDB / 时间窗口模型) |
|------|----------------------------------|-----------------------------------|
| 下游断连容忍 | 任意时长（受 max_slot_wal_keep_size 限制） | 受时间/大小窗口限制 |
| 孤儿资源风险 | 高（必须监控 + 清理） | 低（自动过期） |
| 续点准确性 | 字节级精确 | GTID 集合或 oplog timestamp，需重做边界事务 |
| 运维复杂度 | 高（专门视图与命令） | 低（仅监控 binlog 大小） |
| 故障切换成本 | 高（需 failover slot 机制） | 中（GTID 自动续点） |
| 全局快照支持 | 是（逻辑槽内置） | 否（需外部协调） |
| 适用场景 | 关键 CDC、跨大版本升级、零丢失逻辑订阅 | 备份恢复、容忍少量重做的备库 |

PG 选择"有槽"的根本原因是它的 MVCC 与 catalog_xmin 强耦合：逻辑解码必须能保证某个事务的 catalog 元数据可见，否则解码出错——这要求源库在槽存在期间不能 VACUUM 该 xmin 之前的 catalog 行。MySQL 的 binlog 解码不依赖 catalog 状态（schema 变更通过 DDL event 显式记录），因此天然不需要槽。

## 实现层面的关键设计

### PG 复制槽的存储

物理槽和逻辑槽的元数据持久化在 `$PGDATA/pg_replslot/<slot_name>/` 目录：

```
$PGDATA/pg_replslot/standby1/state
$PGDATA/pg_replslot/cdc_orders/state
$PGDATA/pg_replslot/cdc_orders/snap-...   (逻辑槽快照文件)
```

`state` 文件是二进制格式，启动时由 `RestoreSlotFromDisk()` 加载到共享内存。逻辑槽还会在 `pg_replslot/<name>/snap-*` 目录写入 catalog snapshot 文件，用于解码时构造历史 schema 视图。

### 逻辑解码的 catalog_xmin 问题

逻辑槽必须保留 catalog 的 dead tuple，因为解码可能需要回溯到很久之前的 catalog 状态：

```c
// PG 源码 backend/replication/logical/snapbuild.c
// SnapBuildSerialize 在槽推进时持久化 catalog snapshot
// catalog_xmin = 槽确认的最早事务的 xid
// VACUUM FREEZE 时跳过 < catalog_xmin 的 dead catalog tuples
```

实际影响：长时间运行的逻辑槽会让 catalog 表（如 `pg_class`、`pg_attribute`）膨胀，必须监控 `pg_total_relation_size('pg_class')` 等。

### 大事务的内存与磁盘溢出

PG 14 之前，逻辑解码必须把整个事务在内存中重构再发往下游。一个 100GB 的 BULK INSERT 事务会让 walsender 进程 OOM。

PG 14 引入 **streaming changes**（`logical_decoding_work_mem` 控制阈值）：

```sql
-- 配置（默认 64MB）
ALTER SYSTEM SET logical_decoding_work_mem = '256MB';

-- 客户端协议升级
-- pgoutput protocol_version = 2: 支持 streaming
-- pgoutput protocol_version = 3: 支持 two-phase
-- pgoutput protocol_version = 4: 支持 parallel apply (PG 16+)
```

超过阈值后，事务变更会被序列化到磁盘临时文件，下游可以选择性接收 streaming 模式（边写边读）或等事务提交后再发。

### walsender 与槽的关系

PG 内部，槽与 walsender 进程是**多对一**关系：

- 一个槽至多被一个 walsender 持有（通过 `active_pid` 锁）
- walsender 退出时槽自动释放（`active = false`），但槽对象仍在共享内存
- 重启后从 `pg_replslot/<name>/state` 重建槽

逻辑解码 walsender 的工作流：

```
1. backend 通过 START_REPLICATION SLOT cdc_orders LOGICAL 0/0 命令启动
2. walsender 调用 LogicalDecodingProcessRecord 逐条解析 WAL
3. ReorderBuffer 缓存事务变更直到 COMMIT
4. SnapBuild 维护 catalog snapshot 历史
5. 输出插件回调 (begin/change/commit) 序列化变更
6. 通过 libpq 发送给下游
7. 下游 ACK 后调用 LogicalConfirmReceivedLocation 推进 confirmed_flush_lsn
```

### 大事务对槽推进的影响

`restart_lsn` 不能跨过任何**未提交事务**的开始位置，否则崩溃恢复无法重建一致性快照。这意味着：

```
T1: BEGIN at LSN 0/100
T2: BEGIN at LSN 0/200, COMMIT at LSN 0/300
T1: ... (持续运行) ...
T1: COMMIT at LSN 0/1000

槽的 restart_lsn 在 T1 提交前 = 0/100（卡住）
即使下游已经处理完 T2，restart_lsn 也无法推进到 0/300
```

防御措施：

- 限制单事务执行时长（`statement_timeout` / `idle_in_transaction_session_timeout`）
- 监控 `pg_stat_activity` 的 `xact_start` 找出长事务
- 必要时用 `pg_terminate_backend` 终止

## 关键发现

1. **复制槽是 PostgreSQL 独有的内核对象**：45+ 引擎中，仅 PG 系（含 Greenplum、TimescaleDB、YugabyteDB 这些 PG 派生）原生提供"复制槽"作为 SQL 视图与函数可见的一等公民；其他引擎要么没有此概念（MySQL、SQL Server 事务复制、TiDB），要么用外部协调服务（ClickHouse 的 ZK）替代。

2. **PostgreSQL 9.4 (2014-12) 引入了基础设施**：`pg_create_physical_replication_slot` 和 `pg_create_logical_replication_slot` 在同一版本登场，但这一版本**没有任何防御机制**——孤儿槽可以无限保留 WAL 直至磁盘爆满。这一缺陷困扰 PG 用户 6 年。

3. **PostgreSQL 13 (2020-09) 的 max_slot_wal_keep_size 是革命性改进**：首次允许运维设置槽保留 WAL 的硬上限，超过后槽进入 `lost` 状态而非拖死源库。这是 PG 高可用走向真正生产级的关键参数。

4. **PostgreSQL 16 (2023-09) 解决了 standby 上不能创建逻辑槽的痛点**：在 16 之前，所有逻辑订阅必须挂在主库上，CPU/网络压力直接打到主库；16 引入"逻辑解码 on standby"基础设施后，分析型 CDC 可以转移到 standby。

5. **PostgreSQL 17 (2024-09) 的 failover slot 是 PG 高可用最后一块短板的填补**：之前必须依赖 EDB 的 `pg_failover_slots` 扩展，故障切换后下游订阅者要么靠扩展同步元数据要么重做全量。17 把 `failover` 属性纳入内核，配合 `sync_replication_slots` 让槽自动从主库流向 standby。

6. **MySQL 至今没有槽，并且这是个深思熟虑的设计**：binlog 按时间/大小自动回收，副本通过 GTID 集合自行续点。优势是没有孤儿槽风险，运维心智负担低；劣势是副本离线超过保留窗口必须重做全量同步。在云原生与 Kubernetes 短生命周期 Pod 场景，MySQL 的"无槽"模式反而更鲁棒。

7. **ClickHouse 的复制槽实现在 ZooKeeper / Keeper 中**：每个 ReplicatedMergeTree 副本在 ZK 有自己的 znode，类似分布式槽。孤儿副本（ZK 中残留 znode）的处理方式是 `SYSTEM DROP REPLICA`，与 PG 的 `pg_drop_replication_slot` 语义对应。

8. **Materialize / RisingWave 是上游 PG 槽的"隐式消费者"**：这两个流处理引擎在 `CREATE SOURCE` 时会自动在上游 PG 创建逻辑槽，但当流处理引擎被销毁时，上游 PG 的槽不会自动清理——这是 PG + 流处理引擎部署最常见的事故源头。

9. **CockroachDB / TiDB 选择"changefeed = job"模式**：把下游进度持久化在外部 sink（Kafka offset、对象存储），源端只记录 changefeed 高水位。优点是不需要复杂的槽管理；缺点是 PAUSED 时间过长（超过 GC TTL）就只能重建。

10. **GoldenGate 的 trail 文件是商业版本的"槽"**：trail 是物理文件，extract 写、replicat 读，独立于源库 redo。运维体验类似 PG 槽（要监控 trail 累积），但优势是 trail 可以被多个 replicat 并行消费，下游解耦更彻底。

11. **catalog_xmin 是逻辑槽运维的隐藏成本**：逻辑槽必须阻塞 catalog 表的 VACUUM，长时间存在的逻辑槽会让 `pg_class` / `pg_attribute` 等系统表膨胀。监控 `pg_total_relation_size('pg_class')` 是 PG 长期 CDC 部署的必要项。

12. **大事务对槽推进的影响是新手容易忽视的陷阱**：`restart_lsn` 不能跨过未提交事务的开始位置，单个长事务会让槽完全卡住。`statement_timeout` 和 `idle_in_transaction_session_timeout` 是配套防御措施。

13. **PG 14 的 streaming changes 解决了大事务的内存爆掉问题**：之前必须等事务 COMMIT 才能开始解码下发，100GB 的大事务直接 OOM walsender 进程；14 之后通过 `logical_decoding_work_mem` 阈值触发流式输出，磁盘临时文件兜底。

14. **跨引擎的"无槽"模式各有取舍**：MongoDB 用 capped collection，超过窗口副本进入 RECOVERING；Cassandra 用文件大小阈值，超过时**停写**；MySQL 用时间窗口，超过时副本必须重做。三者代表了"可用性优先" vs "数据保证优先"的不同价值取向。

15. **复制槽问题的运维护理已有成熟工具链**：postgres_exporter 内置 `pg_replication_slot_*` 全套指标；Patroni 提供 `permanent_replication_slots` 配置；EDB 的 `pg_failover_slots` 是 PG 16 之前的事实标准；Debezium connector 默认开启 `drop.slot.on.stop=true` 防止孤儿槽。但这些工具的存在本身也说明了：PG 复制槽是个**需要专门运维知识才能用好**的高级特性，无法零成本上手。

## 参考资料

- PostgreSQL: [Replication Slots](https://www.postgresql.org/docs/current/warm-standby.html#STREAMING-REPLICATION-SLOTS)
- PostgreSQL: [pg_replication_slots view](https://www.postgresql.org/docs/current/view-pg-replication-slots.html)
- PostgreSQL: [Logical Decoding](https://www.postgresql.org/docs/current/logicaldecoding.html)
- PostgreSQL 13 release notes: [max_slot_wal_keep_size](https://www.postgresql.org/docs/release/13.0/)
- PostgreSQL 16 release notes: [Logical decoding from standby](https://www.postgresql.org/docs/release/16.0/)
- PostgreSQL 17 release notes: [Failover slots](https://www.postgresql.org/docs/release/17.0/)
- EDB pg_failover_slots: [github.com/EnterpriseDB/pg_failover_slots](https://github.com/EnterpriseDB/pg_failover_slots)
- MySQL: [Replication GTID](https://dev.mysql.com/doc/refman/8.0/en/replication-gtids.html)
- MySQL: [Binary Logging Options](https://dev.mysql.com/doc/refman/8.0/en/replication-options-binary-log.html)
- Oracle GoldenGate: [Trail Files](https://docs.oracle.com/en/middleware/goldengate/core/21.3/admin/managing-trail-files.html)
- SQL Server: [Transactional Replication](https://learn.microsoft.com/en-us/sql/relational-databases/replication/transactional/transactional-replication)
- ClickHouse: [Data Replication](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replication)
- ClickHouse: [SYSTEM DROP REPLICA](https://clickhouse.com/docs/en/sql-reference/statements/system#drop-replica)
- CockroachDB: [Changefeeds](https://www.cockroachlabs.com/docs/stable/create-changefeed)
- TiDB: [TiCDC Overview](https://docs.pingcap.com/tidb/stable/ticdc-overview)
- YugabyteDB: [Logical Replication](https://docs.yugabyte.com/preview/explore/change-data-capture/using-logical-replication/)
- Debezium PostgreSQL Connector: [drop.slot.on.stop option](https://debezium.io/documentation/reference/stable/connectors/postgresql.html)
- Patroni: [Permanent replication slots](https://patroni.readthedocs.io/en/latest/replication_modes.html)
- Snowflake: [Streams](https://docs.snowflake.com/en/user-guide/streams-intro)
- MongoDB: [Replica Set Oplog](https://www.mongodb.com/docs/manual/core/replica-set-oplog/)
- Cassandra: [Change Data Capture](https://cassandra.apache.org/doc/latest/cassandra/operating/cdc.html)
