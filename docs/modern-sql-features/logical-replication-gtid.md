# 逻辑复制与全局事务标识 (Logical Replication and GTID)

物理复制传输字节，逻辑复制传输事实。前者是磁盘的镜像，后者是事务的回放——两种范式划分了现代数据库高可用与异构同步的整张地图，而 GTID/LSN/SCN 则是把两端缝合起来的针线。

## 为什么要逻辑复制

数据库复制的本质是把一台机器上的修改在另一台机器上重现。围绕"重现什么"，业界形成了两条截然不同的路线：

1. **物理复制 (Physical Replication)**：传输 WAL/redo 字节流，副本对源库做磁盘块级别的精确镜像。优点是开销小、延迟低、一致性强；缺点是源库与副本必须同版本同架构，无法跨大版本升级，无法选择性同步表，副本只能整库只读。
2. **逻辑复制 (Logical Replication)**：把 WAL 解码成行级 INSERT/UPDATE/DELETE 事件（或 SQL 语句），按表/库订阅、跨版本回放。代价是 CPU 与解码开销更高，但换来三大能力：
   - **跨大版本升级**：PostgreSQL 11 → 17 的零停机升级几乎都靠 `pg_logical_emit_message` + `CREATE SUBSCRIPTION`。
   - **异构数据集成**：把 OLTP 库的变更实时灌入数仓、搜索、缓存。
   - **多主与双向**：BDR、Group Replication 这类多写架构必须通过逻辑层冲突检测与解决。

逻辑复制并非 CDC 的同义词。CDC（参见 `cdc-changefeed.md`）通常指对外暴露行级变更流给下游消费者；而本文聚焦于数据库**内置**的发布/订阅机制——也就是同一种引擎之间用 `CREATE PUBLICATION`/`CREATE SUBSCRIPTION` 这种 DDL 语义直接搭建复制拓扑的能力。

与逻辑复制成对出现的是事务标识：在逻辑层，副本必须知道"我已经回放到了哪条事务"，否则无法续点、无法故障切换、无法做幂等去重。MySQL 用 GTID（Global Transaction ID），Oracle 用 SCN（System Change Number），PostgreSQL 用 LSN（Log Sequence Number）+ replication slot，SQL Server 用 LSN，TiDB/CockroachDB 用 HLC/MVCC 时间戳——名字不同，承担的角色一致。

> 本文不涉及 SQL 标准——逻辑复制至今没有任何 ISO SQL 标准化条款，所有语法和语义都是厂商专有的。

## 支持矩阵

### 1. 物理复制 vs 逻辑复制

| 引擎 | 物理复制 | 逻辑复制 | 内置 Pub/Sub DDL | 首次提供逻辑复制 |
|------|---------|---------|-----------------|----------------|
| PostgreSQL | 流复制 (9.0+) | 是 (10+) | `CREATE PUBLICATION` / `SUBSCRIPTION` | 2017 |
| MySQL | -- | binlog 复制 | `CHANGE REPLICATION SOURCE TO` | 3.23 (2000-2001) |
| MariaDB | -- | binlog 复制 | `CHANGE MASTER TO` | 继承自 MySQL 3.23 |
| SQLite | -- | -- | -- | 不支持 |
| Oracle | Data Guard (Physical) | GoldenGate / Streams (停用) | 是 (GoldenGate) | 1999 (Streams) |
| SQL Server | AlwaysOn AG / Log Shipping | Transactional / Merge Replication | `sp_addpublication` | 1998 (7.0) |
| DB2 | HADR | SQL Replication / Q Replication | `ASNCLP` 命令 | 1994 |
| Snowflake | -- | DATABASE REPLICATION | `ALTER DATABASE ... ENABLE REPLICATION` | 2020 |
| BigQuery | -- | -- (Data Transfer ETL) | -- | 不支持传统复制 |
| Redshift | -- | -- (Cross-region snapshots) | -- | 不支持 |
| DuckDB | -- | -- | -- | 不支持 |
| ClickHouse | ReplicatedMergeTree (Keeper) | MaterializedPostgreSQL / MaterializedMySQL | -- | 21.4+ (实验) |
| Trino | -- | -- (查询引擎) | -- | 不适用 |
| Presto | -- | -- (查询引擎) | -- | 不适用 |
| Spark SQL | -- | -- (查询引擎) | -- | 不适用 |
| Hive | -- | Hive Replication (REPL DUMP/LOAD) | `REPL DUMP` | 2018 (3.0) |
| Flink SQL | -- | -- (流处理) | -- | 不适用 |
| Databricks | Delta Live Tables | Delta Sharing / Deep Clone | `CREATE SHARE` | 2021 |
| Teradata | Dual Active | Replication Services | -- | 早期 |
| Greenplum | mirror | -- | -- | 不支持 |
| CockroachDB | Raft (内部) | CHANGEFEED / Physical Cluster Replication | `CREATE CHANGEFEED` | 2018 (2.1) |
| TiDB | Raft (内部) | TiCDC | -- (运维工具) | 2020 (4.0) |
| OceanBase | Paxos (内部) | OBCDC / OMS | -- | 2021 |
| YugabyteDB | Raft (内部) | xCluster / CDC | -- | 2.12+ |
| SingleStore | 内部 | Pipelines (导入侧) | `CREATE PIPELINE` | 6.0+ |
| Vertica | K-safety | Cross-cluster replication | -- | 早期 |
| Impala | -- | -- (查询引擎) | -- | 不适用 |
| StarRocks | 内部多副本 | -- | -- | 不支持 |
| Doris | 内部多副本 | -- | -- | 不支持 |
| MonetDB | -- | -- | -- | 不支持 |
| CrateDB | 内部分片副本 | -- | -- | 不支持 |
| TimescaleDB | 继承 PG | 继承 PG | 继承 PG | 继承 PG |
| QuestDB | -- | -- | -- | 不支持 |
| Exasol | 内部 | -- | -- | 不支持 |
| SAP HANA | System Replication | -- | -- | 仅物理 |
| Informix | HDR / RSS | Enterprise Replication | `cdr define` | 早期 |
| Firebird | nbackup | -- | -- | 不支持 |
| H2 | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | 不支持 |
| Amazon Athena | -- | -- (查询引擎) | -- | 不适用 |
| Azure Synapse | -- | -- | -- | 不支持 |
| Google Spanner | 内部 Paxos | -- | -- | 不支持 (但有 Change Streams) |
| Materialize | -- | 上游 PG/MySQL 解码 | `CREATE SOURCE` | GA |
| RisingWave | -- | 上游 PG/MySQL 解码 | `CREATE SOURCE` | GA |
| InfluxDB | -- | -- | -- | 不支持 |
| DatabendDB | -- | -- | -- | 不支持 |
| Yellowbrick | -- | -- | -- | 不支持 |
| Firebolt | -- | -- | -- | 不支持 |

> 统计：约 18 个引擎提供某种形式的内置逻辑复制；约 10 个仅有物理复制；约 14 个查询引擎或嵌入式引擎不适用复制概念。

### 2. binlog 格式 (SBR / RBR / MBR)

| 引擎 | 语句级 SBR | 行级 RBR | 混合 MBR | 默认 | 是否可在线切换 |
|------|----------|---------|---------|------|------------|
| MySQL | 是 | 是 (5.1+) | 是 (5.1+) | RBR (5.7.7+) | 是 |
| MariaDB | 是 | 是 | 是 | MBR | 是 |
| PostgreSQL | -- | 是 (logical) | -- | -- | -- |
| Oracle GoldenGate | 是 (DDL) | 是 | 是 | RBR | 是 |
| SQL Server Transactional | -- | 是 | -- | RBR | -- |
| DB2 Q Replication | -- | 是 | -- | RBR | -- |
| TiDB (TiCDC) | -- | 是 | -- | RBR | -- |
| CockroachDB CHANGEFEED | -- | 是 | -- | RBR | -- |

> 关键点：RBR 是现代默认。MySQL 自 5.7.7 起默认 ROW；MariaDB 默认 MIXED。SBR 在涉及 `NOW()`、`UUID()` 等非确定性函数时会导致主从数据漂移，因此早已不被推荐用于真正的复制拓扑。

### 3. 全局事务标识 (GTID / LSN / SCN)

| 引擎 | 标识符名称 | 格式 | 单调性 | 跨节点全局唯一 | 引入版本 |
|------|---------|------|------|--------------|--------|
| PostgreSQL | LSN | `0/1A2B3C4D` (64-bit) | 单调递增 | 单节点单调 | 早期 |
| MySQL | GTID | `source_uuid:transaction_id` | 单源单调 | 是 | 5.6 (2013) |
| MariaDB | GTID | `domain_id-server_id-sequence_number` | 域内单调 | 是 | 10.0 (2014) |
| Oracle | SCN | 64-bit 单调序号 | 严格单调 | 单实例 (RAC 全局) | 早期 |
| SQL Server | LSN | `(VLF:Offset:RecordID)` | 单调递增 | 单实例 | 早期 |
| DB2 | LRSN | 6/10 字节序号 | 单调递增 | 单成员 | 早期 |
| Snowflake | Sequence Number | 内部 | -- | 是 | -- |
| TiDB | TSO (PD 时间戳) | 64-bit (物理+逻辑) | 严格单调 | 是 | 1.0 |
| CockroachDB | HLC 时间戳 | (wall, logical) | 因果序 | 是 | 1.0 |
| OceanBase | Trans ID | -- | 单调 | 是 | 1.0 |
| YugabyteDB | HybridTime | (physical, logical) | 因果序 | 是 | 1.0 |
| Spanner | TrueTime | (earliest, latest) | 严格单调 | 是 | 内部 |
| ClickHouse | block_id | -- | 单分区 | -- | -- |

### 4. 发布/订阅 DDL

| 引擎 | 发布命令 | 订阅命令 | 行级过滤 | 列级过滤 |
|------|--------|---------|---------|---------|
| PostgreSQL | `CREATE PUBLICATION` | `CREATE SUBSCRIPTION` | 15+ | 15+ |
| MySQL | -- (binlog 隐式) | `CHANGE REPLICATION SOURCE TO` | 替换过滤器 | 替换过滤器 |
| MariaDB | -- | `CHANGE MASTER TO` | 是 | 是 |
| Oracle GoldenGate | `ADD EXTRACT` | `ADD REPLICAT` | 是 | 是 |
| SQL Server | `sp_addpublication` | `sp_addsubscription` | 是 (filter) | 是 |
| DB2 Q Replication | `ASNCLP CREATE Q SUBSCRIPTION` | 同 | 是 | 是 |
| Snowflake | `ALTER DATABASE ... ENABLE REPLICATION` | `CREATE DATABASE ... AS REPLICA OF` | 库级 | -- |
| Hive | `REPL DUMP` | `REPL LOAD` | 库级 | -- |
| Databricks Delta Sharing | `CREATE SHARE` | `CREATE PROVIDER` | 是 | 是 |
| Materialize | `CREATE SOURCE` | -- (源端) | 是 | 是 |
| RisingWave | `CREATE SOURCE` | -- | 是 | 是 |
| CockroachDB | `CREATE CHANGEFEED` | -- (Kafka 等下游) | 是 | 是 |

### 5. 双向复制 (BDR) 与多主

| 引擎 | 双向复制 | 多主写入 | 冲突检测 | 冲突解决策略 |
|------|--------|---------|---------|------------|
| PostgreSQL (官方) | 否 (单向) | 否 | -- | -- |
| PostgreSQL + pglogical / EDB BDR | 是 | 是 | 是 | LWW / 自定义 |
| MySQL Group Replication | 是 (单主/多主) | 是 (5.7+) | 是 | Certify-based |
| MySQL InnoDB Cluster | 是 | 是 | 是 | 同 GR |
| MariaDB Galera | 是 | 是 | 是 | Certify-based |
| Oracle GoldenGate | 是 | 是 | 是 | 多种策略 |
| SQL Server Merge Replication | 是 | 是 | 是 | 自定义 / 优先级 |
| SQL Server Peer-to-Peer | 是 | 是 | 有限 | 不支持自动解决 |
| DB2 Q Replication | 是 | 是 | 是 | 多种策略 |
| CockroachDB | -- (单逻辑集群) | 是 (内部) | -- | -- |
| YugabyteDB xCluster | 是 (异步) | 是 (2.18+) | 是 | LWW |
| OceanBase | 是 | 是 | 是 | -- |
| TiDB | -- | 是 (内部) | -- | -- |
| Cassandra | 是 | 是 | 是 | LWW (timestamp) |

### 6. 逻辑解码插件 / Output Plugin

| 引擎 | 解码接口 | 默认插件 | 第三方插件 |
|------|--------|---------|----------|
| PostgreSQL | Logical Decoding API (9.4+) | `pgoutput` (10+) | `wal2json`, `decoderbufs`, `test_decoding`, `wal2mongo` |
| MySQL | binlog dump 协议 | row event | Debezium, Maxwell, Canal |
| MariaDB | binlog dump | row event | Debezium, MaxScale CDC |
| Oracle | LogMiner / XStream / GoldenGate Trail | -- | Debezium (XStream), GoldenGate |
| SQL Server | CDC tables / Change Tracking | -- | Debezium, Qlik |
| DB2 | InfoSphere CDC | -- | Debezium |
| MongoDB | oplog / Change Streams | -- | Debezium |
| TiDB | TiCDC Open Protocol | -- | TiCDC sinks |
| CockroachDB | CHANGEFEED | -- | Kafka, webhook, cloud storage |

### 7. 故障切换与自动化

| 引擎 | 自动故障切换 | 工具/组件 | 切换时间 (典型) |
|------|----------|---------|-------------|
| PostgreSQL | 否 (内置) | Patroni / repmgr / pg_auto_failover | 10-30s |
| MySQL | 是 (Group Replication) | MHA, Orchestrator, MySQL Router | 5-30s |
| MariaDB | 是 (Galera) | MaxScale | 秒级 |
| Oracle Data Guard | 是 (Fast-Start Failover) | Observer | 秒级 |
| SQL Server AlwaysOn AG | 是 | WSFC | 秒级 |
| DB2 HADR | 是 | TSAMP / Pacemaker | 秒级 |
| TiDB | 是 (内部 Raft) | -- | 秒级 |
| CockroachDB | 是 (内部 Raft) | -- | 秒级 |
| OceanBase | 是 (内部 Paxos) | -- | 秒级 |
| YugabyteDB | 是 (内部 Raft) | -- | 秒级 |
| Spanner | 是 (内部) | -- | 秒级 |
| Snowflake | 是 (Failover Group) | -- | 分钟级 |

## 引擎详解

### PostgreSQL：从流复制到逻辑订阅

PostgreSQL 的复制演进是最教科书式的样本：

- **8.0 (2005)**：基于文件的 WAL 归档复制（warm standby），分钟级延迟。
- **9.0 (2010)**：Streaming Replication，物理流复制 + Hot Standby，副本可读。
- **9.4 (2014)**：Logical Decoding 框架，引入 replication slot 和 output plugin 接口，但只提供底层 API，没有内置逻辑订阅 DDL。这一阶段的逻辑复制需要依赖 `pglogical` 等扩展。
- **10 (2017)**：内置逻辑复制 (`CREATE PUBLICATION` / `CREATE SUBSCRIPTION`)，自带 `pgoutput` 插件。这是 PG 第一次让用户用纯 SQL DDL 搭建跨表/跨库的发布订阅。
- **13 (2020)**：复制槽统计、分区表的复制改进。
- **14 (2021)**：流式逻辑复制（事务进行中即可发送），二进制传输模式。
- **15 (2022)**：行过滤 (`WHERE`) 和列过滤；双向（双主）复制场景下的 `origin` 过滤。
- **16 (2023)**：从 standby 进行逻辑解码；并行 apply。
- **17 (2024)**：故障切换槽 (`failover slot`)，逻辑订阅可以在物理副本切换后继续。

```sql
-- 发布端
CREATE PUBLICATION pub_orders
    FOR TABLE orders, order_items
    WITH (publish = 'insert,update,delete');

-- 15+ 的行过滤
CREATE PUBLICATION pub_eu_orders
    FOR TABLE orders WHERE (region = 'EU');

-- 订阅端
CREATE SUBSCRIPTION sub_orders
    CONNECTION 'host=primary dbname=app user=repl'
    PUBLICATION pub_orders
    WITH (copy_data = true, streaming = on, binary = on);
```

LSN 是 PG 复制的核心标识：`SELECT pg_current_wal_lsn();` 返回形如 `0/1A2B3C4D` 的 64 位偏移量，前 32 位是 WAL 文件号，后 32 位是文件内偏移。逻辑订阅通过 `pg_replication_slots.confirmed_flush_lsn` 跟踪进度，副本崩溃后从这个位置续点。

### MySQL：binlog、GTID 与 Group Replication

MySQL 的复制根植于 binlog——主库的所有写操作以事件序列写入 binary log，副本通过 IO 线程拉取，再由 SQL 线程回放：

- **3.23 (2000-2001)**：基于 binlog 的异步复制，Statement-Based（复制功能在 3.23.15 即 2000 年 5 月引入，3.23 GA 为 2001 年 1 月）。
- **5.1 (2008)**：引入 Row-Based Replication 和 Mixed 模式，解决 SBR 非确定性问题。
- **5.5 (2010)**：半同步复制 (Semi-sync)。
- **5.6 (2013)**：**GTID 引入**。在此之前，副本必须用 (`binlog file`, `position`) 来定位回放位置，故障切换极易出错；GTID 让每条事务获得全局唯一 ID，自动续点。
- **5.7 (2015)**：**Group Replication**（基于 Paxos 变体的多主复制）；MySQL 5.7.7 起 RBR 成为默认。
- **8.0 (2018)**：InnoDB Cluster 整合，Clone Plugin 用于快速搭建副本。
- **8.4 (2024)**：副本术语重命名 (`SOURCE`/`REPLICA`)，移除 Group Replication 多主写默认。

GTID 格式：

```
source_uuid:transaction_id
3E11FA47-71CA-11E1-9E33-C80AA9429562:1-3
```

`source_uuid` 是写源服务器的 server_uuid，`transaction_id` 是该源上的递增整数。`gtid_executed` 集合记录"我执行过哪些 GTID"，副本据此判断是否应跳过某条事件。

```sql
-- 启用 GTID
SET GLOBAL gtid_mode = ON_PERMISSIVE;
SET GLOBAL enforce_gtid_consistency = ON;

-- 配置副本
CHANGE REPLICATION SOURCE TO
    SOURCE_HOST = 'primary.example.com',
    SOURCE_USER = 'repl',
    SOURCE_AUTO_POSITION = 1;
START REPLICA;
```

**MySQL NDB Cluster** 是另一条线，基于 Sharding + 同步复制，binlog 由 SQL 节点产生，可与异步复制配合实现跨数据中心。

### MariaDB：不同的 GTID 格式

MariaDB 早期与 MySQL binlog 兼容，但在 10.0 (2014) 引入了完全不同的 GTID 格式：

```
domain_id-server_id-sequence_number
0-1-1000
```

- `domain_id`：用户自定义的复制域，多源复制时区分不同来源。
- `server_id`：写入服务器的 `server_id`。
- `sequence_number`：递增序号。

这种设计的优势是支持 **multi-source replication**（10.0 起），副本可以同时连接多个不同的源，每个源用独立的 domain；缺点是与 MySQL GTID 不兼容，跨厂商迁移要做格式转换。

```sql
-- 多源复制
CHANGE MASTER 'src1' TO MASTER_HOST='host1', MASTER_USE_GTID=slave_pos;
CHANGE MASTER 'src2' TO MASTER_HOST='host2', MASTER_USE_GTID=slave_pos;
START ALL SLAVES;
```

MariaDB Galera Cluster 提供同步多主复制，基于 wsrep API 和认证型复制（certification-based）。

### Oracle：Data Guard、GoldenGate 与 SCN

Oracle 的复制体系最庞大也最古老：

- **Data Guard**：基于 redo log 传输的物理（或逻辑）复制。
  - **Physical Standby**：字节级镜像，可作为只读副本（Active Data Guard，需额外 license）。
  - **Logical Standby**：通过 LogMiner 解码 redo 为 SQL 应用，允许副本结构差异，但限制较多。
- **GoldenGate**：Oracle 收购的旗舰逻辑复制产品，跨 Oracle/异构数据库，支持双向、过滤、转换。基于 trail file 的解耦架构，extract 进程读 redo，replicat 进程写目标。
- **Streams**（已停用）：Oracle 9i (2002) 引入的逻辑复制框架，10g/11g 是主推方向，12c 标记为 deprecated，被 GoldenGate 取代。
- **LogMiner**：底层的 redo 解析工具，是 Streams、Logical Standby、Debezium Oracle Connector 的共同基础。

**SCN (System Change Number)** 是 Oracle 的全局事务标识，单调递增的 64 位整数，覆盖整个数据库实例（RAC 中通过 GES 协调全局唯一）。每次 commit 分配一个 SCN，后续的闪回查询、Data Guard 同步、GoldenGate 抽取都依赖 SCN 定位。

```sql
-- 当前 SCN
SELECT CURRENT_SCN FROM V$DATABASE;

-- 闪回到指定 SCN
SELECT * FROM orders AS OF SCN 12345678;
```

### SQL Server：四种复制范式 + AlwaysOn

SQL Server 提供的复制选项最多，但也最分裂：

1. **Snapshot Replication**：周期性快照，适合不常变化的小表。
2. **Transactional Replication**：从事务日志读取，按事务回放到订阅者，是最常用的逻辑复制。
3. **Merge Replication**：基于触发器和系统表的双向复制，支持冲突解决，常用于移动场景。
4. **Peer-to-Peer Replication**：多节点对等的事务复制，写写无自动冲突解决。

```sql
-- 配置事务复制（伪代码）
EXEC sp_addpublication
    @publication = 'pub_orders',
    @repl_freq = 'continuous',
    @sync_method = 'concurrent';

EXEC sp_addarticle
    @publication = 'pub_orders',
    @article = 'orders',
    @source_table = 'orders';

EXEC sp_addsubscription
    @publication = 'pub_orders',
    @subscriber = 'subserver',
    @destination_db = 'app';
```

**AlwaysOn Availability Groups (2012)** 是 SQL Server 高可用的现代答案，基于 Windows Server Failover Clustering，提供自动故障切换、可读副本、跨子网部署。这是物理层的"虚拟同步复制"，与逻辑复制并存。

**CDC (Change Data Capture)** 自 2008 起将变更写入特殊的系统表 (`cdc.dbo_orders_CT`)，用户可定期查询这些表实现下游同步——这是 SQL Server 的"内置 CDC"，但不是真正的事件流。

LSN 在 SQL Server 中以 `0x00000020:00000060:0001` 的三段式表示：(Virtual Log File ID, Log Block, Slot Number)。

### DB2：SQL Replication 与 Q Replication

IBM DB2 同样提供两条逻辑复制路线：

- **SQL Replication**：基于 Capture/Apply 程序，Capture 把 DB2 日志中的变更写入 CD (Change Data) 表，Apply 程序拉取并应用到目标。
- **Q Replication**：基于 WebSphere MQ 队列传输，延迟更低，吞吐更高。是 DB2 LUW 和 z/OS 的主推方案。

```bash
# ASNCLP 命令脚本（DB2 Replication 配置 DSL）
ASNCLP SESSION SET TO Q REPLICATION;
CREATE QSUB USING REPLQMAP 'Q1_TO_Q2'
    (SUBNAME orders_sub
     orders OPTIONS HAS LOAD PHASE I);
```

LRSN (Log Record Sequence Number) 是 DB2 z/OS 的位置标识，在 LUW 上对应 LSN。

### TiDB：TiCDC 取代旧版 binlog drainer

TiDB 早期通过 `tidb-binlog` 工具（pump + drainer 架构）实现 CDC 功能，模拟 MySQL binlog 协议。但这套方案的瓶颈是 drainer 单点，无法水平扩展，事务大小受限。

**TiCDC** 自 4.0 (2020) 起取代旧 binlog drainer：

- 直接订阅 TiKV 的 raw KV change feed，跳过 SQL 层。
- 水平扩展：多个 TiCDC capture 节点协作，按 region 分片。
- 输出 Open Protocol 或直接写 Kafka/MySQL/CDC 文件。

```sql
-- TiCDC changefeed 创建（命令行）
-- tiup cdc cli changefeed create \
--     --pd=http://pd:2379 \
--     --sink-uri="kafka://kafka:9092/cdc-topic" \
--     --start-ts=437465787876573185
```

TiDB 的事务标识是 **TSO (Timestamp Oracle)**，由 PD (Placement Driver) 分配的 64 位时间戳，前 18 位是物理时间（毫秒），后 18 位是逻辑序号。每条 changefeed 都从一个 `start-ts` 开始，断点续传依赖 TSO 单调性。

### CockroachDB：CHANGEFEED + Physical Cluster Replication

CockroachDB 没有传统意义上的逻辑复制（因为内部已经用 Raft 复制），但提供两条对外接口：

1. **CHANGEFEED (2.1, 2018)**：行级变更流，输出到 Kafka、Webhook、云存储或同集群表。Enterprise 版支持事务性、解析后的 schema 变更。

```sql
CREATE CHANGEFEED FOR TABLE orders
    INTO 'kafka://broker:9092'
    WITH updated, resolved = '10s', format = avro;
```

2. **Physical Cluster Replication (23.2+)**：跨集群的物理副本复制，类似 Data Guard，目标是灾备。

CockroachDB 用 HLC (Hybrid Logical Clock) 时间戳，CHANGEFEED 每条事件携带 `(ts, logical)` 元组，下游可以基于 `resolved timestamp` 实现精确一次和因果一致。

### Snowflake：DATABASE REPLICATION 与 Streams

Snowflake 不提供传统行级复制，但有两套机制：

- **Streams + Tasks**：Stream 跟踪表的变更（INSERT/UPDATE/DELETE），Task 周期性消费 Stream，常用于 ELT 而非外部下游同步。
- **DATABASE REPLICATION (2020)**：跨账号、跨区域的整库复制，支持故障切换组 (Failover Group)。

```sql
-- 启用主库复制
ALTER DATABASE app_db ENABLE REPLICATION TO ACCOUNTS myorg.account2;

-- 副本库
CREATE DATABASE app_db AS REPLICA OF myorg.account1.app_db;

-- 触发刷新
ALTER DATABASE app_db REFRESH;

-- Stream 用法
CREATE STREAM s_orders ON TABLE orders;
SELECT * FROM s_orders WHERE METADATA$ACTION = 'INSERT';
```

Snowflake 的复制延迟通常以分钟为单位，因为它建立在共享存储 + 元数据复制之上。

### BigQuery：没有传统复制

BigQuery 完全不提供数据库层的复制概念。其"数据迁移"能力体现在：

- **Data Transfer Service**：调度型 ETL，把 SaaS（Google Ads、YouTube）和外部数仓（Redshift、Teradata）数据周期性导入 BigQuery。这是 ETL 而非复制。
- **Cross-region Dataset Copy**：手动或调度的数据集级别复制。
- **Datastream**：Google 的独立 CDC 服务，从 Oracle/MySQL/PostgreSQL 抓取变更写入 BigQuery，但仍属于外部组件，不是 BigQuery 内置。

### YugabyteDB：xCluster 异步复制

YugabyteDB 内部用 Raft 同步复制，跨集群灾备依靠 **xCluster**：

- **2.12+**：单向 xCluster。
- **2.18+**：双向（Active-Active），LWW 冲突解决。

```sql
-- yb-admin 命令配置 xCluster
-- yb-admin -master_addresses primary setup_universe_replication \
--     producer_universe_uuid producer_master_addresses table_ids
```

时间戳采用 HybridTime，与 Spanner TrueTime 类似但不依赖原子钟。

## GTID 格式深度对比

| 维度 | MySQL GTID | MariaDB GTID | PostgreSQL LSN | Oracle SCN |
|-----|----------|------------|--------------|----------|
| 格式 | `uuid:txnid` | `domain-server-seq` | `0/1A2B3C4D` | 64-bit 整数 |
| 全局唯一 | 是 (uuid 标识) | 是 (server_id 标识) | 单实例单调 | 单实例单调 |
| 多源支持 | 不直接 | 是 (domain) | 是 (multi-slot) | GoldenGate |
| 跨集群迁移 | UUID 冲突需手动处理 | domain 隔离 | 不可移植 | 不可移植 |
| 单调性 | 单源单调，全局偏序 | 域内单调 | 严格单调 | 严格单调 |
| 副本续点 | `gtid_executed` 集合 | `gtid_slave_pos` | `confirmed_flush_lsn` | redo apply position |
| 支持 GTID 集合运算 | 是 (`GTID_SUBSET`, `GTID_SUBTRACT`) | 是 | -- | -- |

**MySQL GTID 集合运算**：

```sql
-- 检查副本是否落后
SELECT GTID_SUBTRACT(@@global.gtid_executed, '3E11FA47-...:1-100');

-- 等待副本追上指定 GTID
SELECT WAIT_FOR_EXECUTED_GTID_SET('3E11FA47-...:1-100', 10);
```

**为什么两家 GTID 不兼容**：MySQL GTID 把 server_uuid 作为复制源的天然标识，副本看到不同 uuid 就知道事务来源；MariaDB 设计时希望显式建模"复制域"以支持多源拓扑，所以引入 domain_id。这两种设计在哲学上不可调和——把 MariaDB 的 `0-1-100` 转换成 MySQL 形式，必须人为伪造一个 UUID，反向同样需要拆解 domain 维度。社区有一些桥接工具（如 `gh-ost`、`pt-online-schema-change` 在 MariaDB 模式下做了适配），但都不能做到无损往返。

## PostgreSQL 逻辑复制演进时间线 (2010-2024)

| 版本 | 年份 | 关键特性 |
|-----|------|--------|
| 9.0 | 2010 | Streaming Replication (物理), Hot Standby |
| 9.1 | 2011 | 同步复制 |
| 9.2 | 2012 | 级联复制 |
| 9.4 | 2014 | Logical Decoding API, Replication Slots |
| 9.5 | 2015 | pglogical 扩展 (2ndQuadrant) 进入主流 |
| 10  | 2017 | **内置逻辑复制**, `pgoutput`, `CREATE PUBLICATION/SUBSCRIPTION` |
| 11  | 2018 | TRUNCATE 支持 |
| 12  | 2019 | 生成列复制 |
| 13  | 2020 | 复制槽统计 |
| 14  | 2021 | 流式事务 (in-progress streaming), 二进制传输 |
| 15  | 2022 | 行过滤 (WHERE), 列过滤, two_phase commit, origin 过滤 |
| 16  | 2023 | 从 standby 解码, 并行 apply |
| 17  | 2024 | Failover slot, pg_createsubscriber 工具 |

每个版本都在补足前一个版本的短板：10 出生时不支持 TRUNCATE、不支持流式事务、不支持过滤；到 15 时几乎所有"商用复制"该有的能力都补齐了；到 17 时连副本切换后逻辑订阅的延续都解决了——这是社区花了 7 年时间才让逻辑复制达到生产级的故事。

```sql
-- 14+ 流式逻辑复制（不必等待大事务结束）
CREATE SUBSCRIPTION sub_big
    CONNECTION 'host=primary dbname=app'
    PUBLICATION pub_big
    WITH (streaming = on);

-- 15+ 行过滤
CREATE PUBLICATION pub_recent_orders
    FOR TABLE orders WHERE (created_at > '2024-01-01');

-- 15+ 列过滤
CREATE PUBLICATION pub_orders_pii_safe
    FOR TABLE orders (id, amount, status);

-- 17+ 故障切换槽
SELECT pg_create_logical_replication_slot('s1', 'pgoutput', false, false, true);
--                                                                       ^ failover
```

## 关键发现

1. **逻辑复制没有 SQL 标准**。从 1980 年代到现在，逻辑复制始终是厂商各自为政的领域，没有任何 ISO SQL 条款定义 `CREATE PUBLICATION` 或 GTID。所有语法、所有事务标识格式都是私有的，互不兼容。

2. **PostgreSQL 是最晚但最完整的"标准式"逻辑复制**。直到 PG 10 (2017) 才有内置的 `CREATE PUBLICATION/SUBSCRIPTION`，而 MySQL 早在 2002 年就有了 binlog 复制、Oracle Streams 在 2002 年也有了。但 PG 用 7 年时间（10 → 17）补齐了流式、过滤、故障切换槽等关键特性，今天的 PG 逻辑复制是设计最干净的厂商方案。

3. **MySQL GTID 与 MariaDB GTID 是不可调和的两套体系**。两者都叫 GTID，但格式、语义、续点机制完全不同，互相无法直接复制——这是开源数据库分叉后最显著的不兼容点之一。

4. **RBR 已经成为事实默认**。MySQL 5.7.7、MariaDB、所有现代逻辑复制（PostgreSQL、TiCDC、CockroachDB CHANGEFEED、Debezium）都使用行级事件。SBR 因为非确定性函数问题被淘汰；MBR 仍存在但更多是为了 binlog 体积优化而非主流复制。

5. **NewSQL 重新发明了"全局事务标识"**。TiDB 用 TSO，CockroachDB 用 HLC，YugabyteDB 用 HybridTime，Spanner 用 TrueTime——它们都不再叫 GTID，但承担了完全相同的角色：让分布式事务在副本侧可定位、可续点。HLC/TSO 这一代设计的关键差异在于跨节点全局有序，而 MySQL GTID 仅做到单源全序。

6. **物理复制做高可用，逻辑复制做生态**。所有提供"自动故障切换 + 秒级 RPO"的产品都依赖物理复制或共识协议（Raft/Paxos）：Data Guard、AlwaysOn、TiKV Raft、CockroachDB Raft。逻辑复制的延迟天然高一个数量级，更适合跨版本升级、跨地域同步、异构集成、灰度切换。

7. **GoldenGate 是 Oracle 的真正答案**。Oracle Streams 早已停用，Logical Standby 限制重重，真正的 Oracle 逻辑复制基础设施是 GoldenGate——独立产品、独立 license、独立架构。这导致 Oracle 用户的逻辑复制成本远高于其他数据库。

8. **TiCDC 的演进证明了"基于存储层"优于"基于 SQL 层"**。TiDB 早期模拟 MySQL binlog 的 drainer 架构有单点和可扩展性问题，TiCDC 改为直接订阅 TiKV 的 KV change feed 后，水平扩展和事务一致性都得到根本改善。

9. **云数仓基本不做传统复制**。Snowflake 的 DATABASE REPLICATION 是分钟级元数据同步，BigQuery 完全没有，Redshift 只有快照——它们的"复制"概念是数据集级别的快照/共享，而非行级事件流。Snowflake Streams 解决了表内增量消费但不是跨集群复制。

10. **嵌入式数据库没有复制**。SQLite、DuckDB、H2、HSQLDB、Derby、Firebird 都没有内置复制——它们的部署模型不需要复制。需要时只能依赖外部工具（litestream、rqlite 等）做日志归档式高可用。

11. **流处理引擎与查询引擎不适用复制**。Trino、Presto、Spark SQL、Flink SQL、Impala、Athena 都是无状态查询/流处理引擎，复制属于底层存储的责任。Materialize 和 RisingWave 例外，它们通过 `CREATE SOURCE` 把上游 PG/MySQL 的逻辑复制流接入。

## 参考资料

- PostgreSQL: [Logical Replication](https://www.postgresql.org/docs/current/logical-replication.html)
- PostgreSQL: [Streaming Replication](https://www.postgresql.org/docs/current/warm-standby.html#STREAMING-REPLICATION)
- PostgreSQL: [CREATE PUBLICATION](https://www.postgresql.org/docs/current/sql-createpublication.html)
- PostgreSQL: [Logical Decoding](https://www.postgresql.org/docs/current/logicaldecoding.html)
- MySQL: [Replication with GTIDs](https://dev.mysql.com/doc/refman/8.4/en/replication-gtids.html)
- MySQL: [Group Replication](https://dev.mysql.com/doc/refman/8.4/en/group-replication.html)
- MariaDB: [Global Transaction ID](https://mariadb.com/kb/en/gtid/)
- MariaDB: [Multi-source Replication](https://mariadb.com/kb/en/multi-source-replication/)
- Oracle: [Data Guard Concepts](https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/)
- Oracle: [GoldenGate Documentation](https://docs.oracle.com/en/middleware/goldengate/)
- SQL Server: [SQL Server Replication](https://learn.microsoft.com/en-us/sql/relational-databases/replication/sql-server-replication)
- SQL Server: [Always On Availability Groups](https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/overview-of-always-on-availability-groups-sql-server)
- DB2: [Q Replication and Event Publishing](https://www.ibm.com/docs/en/idr)
- TiDB: [TiCDC Overview](https://docs.pingcap.com/tidb/stable/ticdc-overview)
- CockroachDB: [Change Data Capture](https://www.cockroachlabs.com/docs/stable/change-data-capture-overview)
- Snowflake: [Database Replication](https://docs.snowflake.com/en/user-guide/account-replication-intro)
- YugabyteDB: [xCluster Replication](https://docs.yugabyte.com/preview/architecture/docdb-replication/async-replication/)
- Debezium: [Connectors Documentation](https://debezium.io/documentation/reference/stable/connectors/)
- Werner Vogels: "Eventually Consistent" (2008)
- Kreps, Jay: "The Log: What every software engineer should know about real-time data's unifying abstraction" (2013)
