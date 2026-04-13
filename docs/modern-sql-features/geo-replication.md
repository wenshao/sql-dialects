# 跨区域地理复制 (Cross-Region Geo-Replication)

当洛杉矶机房整个区域失联时，应用能否在 30 秒内切到东京继续写入，且最近一笔订单不丢？这就是跨区域地理复制要回答的核心问题——它不是单数据中心高可用的延伸，而是一类独立的架构权衡：在光速、CAP、监管和成本之间寻找最优解。

## 为什么需要跨区域地理复制

- **灾难恢复 (DR, RTO/RPO)**：单区域整体故障 (区域级电力、网络、自然灾害) 时切换到异地副本。RTO (Recovery Time Objective) 衡量切换需要多长时间，RPO (Recovery Point Objective) 衡量最多丢多少数据。
- **全球读扩展**：用户分布在多大洲时，让欧洲用户读法兰克福副本、亚洲用户读新加坡副本，把 P99 从 200ms 降到 20ms。
- **数据驻留 (Data Residency / Sovereignty)**：GDPR、中国《数据安全法》、俄罗斯本地化要求等强制规定特定用户的数据必须保存在指定地理边界内。
- **跨区低延迟写入**：金融、社交、IoT 等场景需要"就近写入"，靠多主复制或地理分区让每个区域的写都本地化。
- **滚动维护与扩容**：在不影响业务的前提下做区域级机房迁移 / 退役。

## 没有 SQL 标准——纯架构选择

ANSI/ISO SQL 标准从未定义跨区域复制语法。每个数据库根据自己的存储引擎、共识协议、时钟模型做出独立的架构选择：

- **共享存储派**：Aurora Global Database 通过底层存储 quorum 复制；Oracle ASM / Exadata 共享磁盘。
- **日志流派**：MySQL / PostgreSQL / SQL Server 通过 WAL/binlog/redo 流到异地。
- **共识协议派**：Spanner (Paxos)、CockroachDB / TiDB / YugabyteDB (Raft) 在每个 range 内跨区域达成多数派。
- **应用层派**：通过 GoldenGate、Debezium、Kafka Connect 等 CDC 工具异步同步。

理解这些路线背后的取舍，比记住某个产品的语法重要得多。

## 跨区域地理复制能力矩阵

下表对 49 个引擎在跨区域复制能力上的支持做整体对比。"--"表示不支持或不适用。

### 表 1：复制拓扑（Active-Passive vs Active-Active vs Sync vs Async）

| 引擎 | 跨区主备 | 跨区多写 | 跨区同步 | 跨区异步 | 多主/Multi-leader | 内置 |
|------|--------|--------|--------|--------|-----------------|------|
| PostgreSQL | 是 (流复制) | -- | 同步流复制 | 是 | 第三方 (BDR/pglogical) | 是 |
| MySQL | 是 (binlog) | -- | semi-sync | 是 | Group Replication | 是 |
| MariaDB | 是 (binlog) | -- | semi-sync | 是 | Galera | 是 |
| SQLite | -- | -- | -- | -- | -- | 否 |
| Oracle | Data Guard | GoldenGate | Max Availability (SYNC) | Max Performance (ASYNC) | GoldenGate / Active-Active | 是 |
| SQL Server | AlwaysOn AG | 分布式 AG | 同步提交 | 异步提交 | Peer-to-Peer 复制 | 是 |
| DB2 | HADR / Q-Replication | Q-Replication | HADR SYNC | HADR ASYNC | 是 | 是 |
| Snowflake | Database Replication | Failover Group | -- | 是 (异步) | -- | 是 (企业版+) |
| BigQuery | 多区域数据集 | -- | 同步 (multi-region) | 跨区复制 | -- | 是 |
| Redshift | 跨区快照 | -- | -- | 是 | -- | 是 |
| DuckDB | -- | -- | -- | -- | -- | 否 |
| ClickHouse | ReplicatedMergeTree | -- | -- | 是 | 是 (多主) | 是 |
| Trino | -- | -- | -- | -- | -- | 否 (无状态) |
| Presto | -- | -- | -- | -- | -- | 否 (无状态) |
| Spark SQL | -- | -- | -- | -- | -- | 否 (无状态) |
| Hive | metastore 复制 | -- | -- | 是 | -- | 部分 |
| Flink SQL | -- | -- | -- | -- | -- | 否 (流) |
| Databricks | Delta Sharing / DR | -- | -- | 是 | -- | 是 |
| Teradata | Unity Director / DSU | Unity Multi-Active | -- | 是 | Multi-Active | 是 |
| Greenplum | 镜像/外部 | -- | 同步镜像 (本地) | 跨区需扩展 | -- | 部分 |
| CockroachDB | 是 | 是 | Raft 多数派 | xCluster (异步) | 是 (multi-region) | 是 |
| TiDB | 是 | 是 (Placement Rules) | Raft 多数派 | TiCDC (异步) | 是 | 是 |
| OceanBase | Primary/Standby | 是 (Zone) | Paxos 多数派 | Standby | 是 | 是 |
| YugabyteDB | 是 | xCluster + 地理分区 | Raft 多数派 | xCluster | 是 | 是 |
| SingleStore | 是 (Replication) | -- | -- | 是 | -- | 是 |
| Vertica | Disaster Recovery | -- | -- | 是 | -- | 是 |
| Impala | -- | -- | -- | -- | -- | 否 (无状态) |
| StarRocks | 跨集群复制 | -- | -- | 是 | -- | 是 |
| Doris | CCR (跨集群复制) | -- | -- | 是 | -- | 是 |
| MonetDB | -- | -- | -- | -- | -- | 否 |
| CrateDB | 是 | -- | -- | 是 | -- | 是 |
| TimescaleDB | 是 (继承 PG) | -- | 同步流复制 | 是 | -- | 是 |
| QuestDB | -- | -- | -- | -- | -- | 否 |
| Exasol | 是 | -- | -- | 是 | -- | 部分 |
| SAP HANA | System Replication | -- | SYNC / SYNCMEM | ASYNC | Active/Active (Read Enabled) | 是 |
| Informix | HDR / RSS / SDS | -- | SYNC | ASYNC | ER (Enterprise Replication) | 是 |
| Firebird | nbackup / 影子 | -- | -- | 部分 | -- | 部分 |
| H2 | -- | -- | -- | -- | -- | 否 |
| HSQLDB | -- | -- | -- | -- | -- | 否 |
| Derby | -- | -- | -- | -- | -- | 否 |
| Amazon Athena | -- | -- | -- | -- | -- | 否 (无状态) |
| Azure Synapse | 跨区恢复 | -- | -- | 是 | -- | 是 |
| Google Spanner | 是 | 是 | Paxos 多数派 | -- (默认同步) | 是 | 是 |
| Materialize | -- | -- | -- | -- | -- | 否 |
| RisingWave | -- | -- | -- | -- | -- | 否 |
| InfluxDB | 跨区复制 (3.x) | -- | -- | 是 | -- | 部分 |
| DatabendDB | 多副本 | -- | -- | 是 | -- | 部分 |
| Yellowbrick | DR 复制 | -- | -- | 是 | -- | 是 |
| Firebolt | -- | -- | -- | -- | -- | 否 |

> 统计：约 33 个引擎提供某种形式的跨区域复制能力，约 16 个不提供 (主要是无状态查询引擎、嵌入式数据库或纯单机存储)。同步跨区复制 (跨光速距离的强一致写入) 仅有 Spanner、CockroachDB、TiDB、YugabyteDB、OceanBase 等少数几个分布式 SQL 系统作为默认拓扑提供。

### 表 2：冲突解决与一致性模型

| 引擎 | 冲突解决策略 | 跨区一致性级别 | 复制粒度 |
|------|-----------|--------------|--------|
| PostgreSQL | 流复制无冲突；BDR 用 LWW + 自定义 | 主写、备最终一致 | 整库 (WAL) |
| MySQL | binlog 主备无冲突；Group Replication 乐观冲突检测 | 主备最终一致 | 整库 (binlog) |
| MariaDB | Galera 认证复制 (cert-based) | 全局可串行化 (Galera 内部) | 写集 |
| Oracle | GoldenGate 提供 LWW、自定义、忽略、错误等多种 | DG 备库支持物理/逻辑一致 | 表/Schema |
| SQL Server | 分布式 AG 主备无冲突；Peer-to-Peer 用冲突解决器 | 同步 = 强；异步 = 最终 | 数据库 |
| DB2 | Q-Replication 提供 LWW / 自定义解析 | HADR SYNC 强；ASYNC 最终 | 表/库 |
| Snowflake | 主写无冲突；Failover Group 主备模型 | 异步 (RPO 由刷新频率决定) | 数据库/账户 |
| BigQuery | 多区域内同步无冲突 | multi-region 内强一致 | 数据集 |
| Redshift | 主备模型，无冲突 | 异步快照一致 | 集群 |
| ClickHouse | ReplicatedMergeTree 用 ZooKeeper/Keeper 选主 | 最终一致 | 表 |
| Databricks | Delta Sharing 单写者；DR 用对象存储复制 | 异步 | 表 |
| Teradata | Multi-Active 支持冲突表级路由 | Eventual / 最终 | 表 |
| CockroachDB | Raft 强一致；REGIONAL BY ROW 实现地理分区 | 默认可串行化 (Serializable) | range (64MB) |
| TiDB | Raft 强一致；Placement Rules 控制副本位置 | 可串行化快照 (SI) / RC | region (96MB) |
| OceanBase | Paxos 强一致；多 zone 模型 | RC / SI | partition |
| YugabyteDB | xCluster 双写需应用避免冲突；同步用 Raft | xCluster 最终；同步可串行化 | tablet |
| SingleStore | 主备无冲突 | 异步 | 数据库 |
| Vertica | DR 主备 | 异步 | 整库 |
| StarRocks | 主备 | 异步 | 表 |
| Doris | CCR 主备 | 异步 | 表/库 |
| CrateDB | 基于 Lucene 段复制 | 最终 | shard |
| SAP HANA | System Replication 主备 | SYNC = 强；ASYNC = 最终 | 整库 |
| Informix | ER 提供冲突解决 (LWW、SPL 自定义) | HDR SYNC 强；ASYNC 最终 | 表 |
| Spanner | 单 Paxos 组内无冲突；跨组 2PC | 外部一致 (External Consistency) | split |
| InfluxDB | 主备 | 最终 | bucket |
| DatabendDB | S3 对象一致性保证 | 最终 | 表 |
| Yellowbrick | DR 主备 | 异步 | 数据库 |

> CRDT (Conflict-free Replicated Data Types) 在传统 SQL 数据库中并不常见。Riak 等 NoSQL 系统使用 CRDT；SQL 领域内只有少数研究型系统 (如 AntidoteDB) 提供。大多数 SQL 系统选择 LWW (Last-Write-Wins)、应用层去冲突，或使用强一致协议绕过冲突问题。

### 表 3：跨区读副本与地理分区

| 引擎 | 跨区只读副本 | 地理分区 (按行/按表) | 全球数据库形态 |
|------|----------|------------------|---------------|
| PostgreSQL | 是 (流复制只读) | 通过外部表/分区手工 | -- |
| MySQL | 是 (binlog 副本) | 应用层分片 | -- |
| Oracle | Active Data Guard | Sharding (12.2+) | Sharded Database |
| SQL Server | 可读副本 (AAG) | 联合表 (legacy) | -- |
| DB2 | HADR readable standby | DPF (Database Partitioning Feature) | pureScale |
| Snowflake | Reader Account / 跨区域复制 | -- | Failover Group |
| BigQuery | 多区域读 | 表分区按地理列 | multi-region |
| Redshift | 跨 AZ；跨区需快照 | -- | -- |
| Aurora (MySQL/Postgres) | 是 (Aurora Read Replica + Global DB) | -- | Aurora Global Database |
| Databricks | Delta Sharing 跨区读 | -- | -- |
| Teradata | QueryGrid / Unity | Multi-Active 表级路由 | Multi-System |
| CockroachDB | 是 (默认所有副本可读) | REGIONAL BY ROW / REGIONAL / GLOBAL | Multi-Region Database |
| TiDB | TiFlash 副本可跨区 | Placement Rules in SQL | -- |
| OceanBase | 是 (Zone 副本可读) | Tenant + Zone Affinity | -- |
| YugabyteDB | Read Replicas (异步) | Tablespaces + Geo-Partitioning | -- |
| SAP HANA | Active/Active Read Enabled | -- | -- |
| Spanner | 是 (所有副本) | 通过 INTERLEAVE + Locality | Spanner = 全球数据库 |
| ClickHouse | 是 | 用 sharding key | -- |
| StarRocks | -- | -- | -- |
| Vertica | 是 (DR 备读) | -- | -- |

### 表 4：RPO / RTO 承诺与典型延迟

| 引擎 | 默认拓扑 | 典型 RPO | 典型 RTO | 跨区写延迟 |
|------|--------|--------|--------|--------|
| Aurora Global Database | 异步 (storage replication) | < 1 秒 | < 1 分钟 (托管 failover) | 写主区域：本地；从区域：只读 |
| Spanner (Multi-Region) | 同步 Paxos | 0 (RPO = 0) | 秒级 (自动) | 写需 1 个 RTT 到多数派 |
| CockroachDB Multi-Region | 同步 Raft | 0 | 秒级 | 写延迟 ≈ 离最近 2 副本的 RTT |
| TiDB + TiCDC | 异步 (TiCDC) | 秒级 | 分钟级 | 主区域本地 |
| TiDB Placement Rules (Sync) | 同步 Raft | 0 | 秒级 | RTT 多数派 |
| OceanBase (3 Zone) | 同步 Paxos | 0 | 秒级 | RTT 多数派 |
| YugabyteDB (Stretch) | 同步 Raft | 0 | 秒级 | RTT 多数派 |
| YugabyteDB (xCluster) | 异步 | < 秒级 | 秒-分钟 | 本地 |
| Snowflake Failover Group | 异步 | 分钟级 (取决于 refresh) | 秒级 (Client Redirect) | 主区域本地 |
| Oracle Data Guard SYNC (Max Avail) | 同步 | 0 | 秒-分钟 (FSFO) | RTT 1 跳 |
| Oracle Data Guard ASYNC (Max Perf) | 异步 | 秒级 | 分钟级 | 本地 |
| SQL Server AAG 同步提交 | 同步 (硬性 RTT 依赖) | 0 | 秒级 (自动 failover) | RTT 1 跳 |
| SQL Server AAG 异步提交 | 异步 | 秒级 | 分钟级 (manual failover) | 本地 |
| SAP HANA SR SYNC | 同步 | 0 | 秒级 | RTT 1 跳 |
| SAP HANA SR ASYNC | 异步 | 秒级 | 分钟级 | 本地 |
| MySQL semi-sync | 半同步 | 接近 0 (取决配置) | 分钟级 (手动/MHA) | RTT 1 跳 |
| MySQL async binlog | 异步 | 秒级 | 分钟到小时 | 本地 |
| PostgreSQL sync streaming | 同步 | 0 | 分钟级 | RTT 1 跳 |
| BigQuery multi-region | 同步 (region 内多 zone) | 0 (region 内) | 0 (托管) | -- |
| DynamoDB Global Tables (NoSQL) | 异步多主 | < 秒级 | 秒级 | 本地 |
| Cosmos DB (NoSQL/SQL API) | 多种一致性级别可选 | 0 (强一致) - 秒级 (最终) | 秒级 | 取决一致性 |

> 跨区域同步复制的 RPO=0 是有代价的：每次写都要等多数派副本 fsync，写延迟 = 客户端到多数派的最大 RTT。例如美东+美西+欧洲 3 副本，写延迟最少 70-90ms (跨大陆 RTT)。把 3 副本部署在同一国家的 3 个城市可降到 10-30ms。

## 详细引擎实现

### Amazon Aurora Global Database

Aurora Global Database 于 2018 年 re:Invent 发布，是 Aurora 的多区域扩展。架构特点：

- **存储级复制**：跨区域复制发生在 Aurora 的分布式存储层而非数据库引擎层。主区域 (Primary) 把写入持久化到本区域 6 副本，并通过专用 replication server 异步复制到目标区域。
- **典型延迟 < 1 秒**：AWS 官方承诺跨大洲场景下 RPO < 1 秒，多数情况下毫秒级。
- **托管 failover**：可手动或借助 Route 53 自动 failover，RTO 通常 < 1 分钟。
- **从区域只读**：辅助区域 (Secondary) 提供低延迟本地读，最多支持 5 个 secondary region。
- **写转发 (Write Forwarding)**：MySQL 兼容版支持 secondary region 接收写请求并转发到 primary，应用代码可视为 "全局写"。

```sql
-- Aurora Global Database 创建示例 (CLI)
-- 1. 创建 global cluster
-- aws rds create-global-cluster --global-cluster-identifier my-global \
--   --source-db-cluster-identifier arn:aws:rds:us-east-1:...:cluster:primary

-- 2. 在第二区域添加 secondary
-- aws rds create-db-cluster --db-cluster-identifier secondary-cluster \
--   --global-cluster-identifier my-global \
--   --engine aurora-mysql --source-region us-east-1

-- 3. failover (托管)
-- aws rds failover-global-cluster --global-cluster-identifier my-global \
--   --target-db-cluster-identifier arn:aws:rds:eu-west-1:...:cluster:secondary
```

### Google Cloud Spanner

Spanner 是迄今唯一在生产环境提供全球同步强一致写入的关系数据库。核心机制：

- **TrueTime API**：每个数据中心部署 GPS 接收器和铯原子钟，TT.now() 返回带误差区间的时间戳 [earliest, latest]。Spanner 用 commit-wait 等待误差边界过去，确保任何后续事务的时间戳严格大于已提交事务，从而实现 **External Consistency** (即线性一致 + 实时序保证)。
- **Paxos per split**：数据被切分为 split (类似 range)，每个 split 独立运行 Paxos 协议在多副本上达成一致。多区域配置 (例如 nam6) 在北美 4 个区域放置副本。
- **2PC for cross-split transactions**：跨 split 的事务用 2PC 协调，每个参与者本身又是 Paxos 组。
- **同步即默认**：Spanner 没有"异步" 模式，所有写入都通过 Paxos 多数派持久化，因此 RPO 始终 = 0。

```sql
-- Spanner 多区域实例创建 (gcloud)
-- gcloud spanner instances create my-instance \
--   --config=nam6 \  -- nam6 = 北美多区域 (us-central1, us-east1, ...)
--   --description="Multi-region instance" \
--   --nodes=3

-- DDL: 通过 INTERLEAVE 把子表数据物理上和父表放在同一 split
CREATE TABLE Customers (
  CustomerId  INT64 NOT NULL,
  Name        STRING(MAX)
) PRIMARY KEY (CustomerId);

CREATE TABLE Orders (
  CustomerId  INT64 NOT NULL,
  OrderId     INT64 NOT NULL,
  Amount      NUMERIC
) PRIMARY KEY (CustomerId, OrderId),
  INTERLEAVE IN PARENT Customers ON DELETE CASCADE;
```

### CockroachDB Multi-Region

CockroachDB 在 21.1 (2021 年 5 月) 正式 GA 多区域功能，把"地理感知放置"提升为一等公民。

- **3 类表**：
  - **REGIONAL BY TABLE**：整张表归属一个 home region，写在该区低延迟。
  - **REGIONAL BY ROW**：每行根据 `crdb_region` 列归属不同区域，最适合需要数据驻留的用户表。
  - **GLOBAL**：跨区域低延迟读但写延迟较高 (用于配置表、汇率表)。GLOBAL 表通过非阻塞事务和 closed-timestamp 机制实现"任意区域低延迟读"。
- **Survive Goal**：`SURVIVE ZONE FAILURE` 只跨 AZ；`SURVIVE REGION FAILURE` 至少 3 区域、可在区域整体宕机后继续工作。
- **Follow-the-Workload**：lease holder 会自动迁移到访问最频繁的区域。

```sql
-- CockroachDB 多区域 DDL
ALTER DATABASE app PRIMARY REGION "us-east1";
ALTER DATABASE app ADD REGION "europe-west1";
ALTER DATABASE app ADD REGION "asia-northeast1";
ALTER DATABASE app SURVIVE REGION FAILURE;

-- REGIONAL BY ROW: 每行按 crdb_region 列分布
CREATE TABLE users (
  id        UUID PRIMARY KEY,
  email     STRING,
  region    crdb_internal_region NOT NULL DEFAULT default_to_database_primary_region(gateway_region())
) LOCALITY REGIONAL BY ROW AS region;

-- GLOBAL 表 (跨区低延迟读)
CREATE TABLE exchange_rates (
  pair  STRING PRIMARY KEY,
  rate  DECIMAL
) LOCALITY GLOBAL;
```

### YugabyteDB

YugabyteDB 同时提供同步 (stretch) 和异步 (xCluster) 两种跨区拓扑。

- **Stretch Cluster (同步)**：把单个集群的 Raft 副本分布在多区域，每次写需要多数派 ack。简单但写延迟受跨区 RTT 限制。
- **xCluster (异步)**：每个区域是独立集群，通过流式 CDC 异步复制。支持单向 (master/slave) 和双向 (双活)。双向需要应用层避免主键冲突。
- **Geo-Partitioning**：通过 `tablespace` 将分区固定到指定区域，实现"行级数据驻留"。

```sql
-- YugabyteDB 地理分区：tablespace 按区域定义
CREATE TABLESPACE us_east_ts WITH (
  replica_placement='{"num_replicas":3,"placement_blocks":[
    {"cloud":"aws","region":"us-east-1","zone":"us-east-1a","min_num_replicas":1},
    {"cloud":"aws","region":"us-east-1","zone":"us-east-1b","min_num_replicas":1},
    {"cloud":"aws","region":"us-east-1","zone":"us-east-1c","min_num_replicas":1}
  ]}'
);

-- 按地理分区表
CREATE TABLE orders (
  id    UUID,
  region TEXT,
  data  JSONB,
  PRIMARY KEY (region, id)
) PARTITION BY LIST (region);

CREATE TABLE orders_us_east PARTITION OF orders
  FOR VALUES IN ('us-east') TABLESPACE us_east_ts;
```

### TiDB

TiDB 通过 **Placement Rules in SQL** (5.3+ 实验，6.0 GA) 提供跨区放置控制。

- **Raft per region**：底层 TiKV 把数据切分为 region (96MB)，每个 region 通过 Raft 在多副本上同步。
- **Placement Policy**：DBA 用 SQL 定义"哪些数据放哪些区域"。
- **TiCDC**：基于 changefeed 的异步复制工具，用于跨集群跨区域的最终一致同步，常用于双活或灾备。

```sql
-- TiDB Placement Rules
CREATE PLACEMENT POLICY beijing_only
  PRIMARY_REGION="beijing"
  REGIONS="beijing,shanghai"
  FOLLOWERS=2;

CREATE TABLE user_profiles (
  user_id BIGINT PRIMARY KEY,
  data JSON
) PLACEMENT POLICY=beijing_only;

-- TiCDC 创建 changefeed
-- tiup ctl:v6.5.0 cdc changefeed create \
--   --pd=http://10.0.10.1:2379 \
--   --sink-uri="tidb://user:pwd@10.0.20.1:4000/" \
--   --changefeed-id="cluster-a-to-b"
```

### OceanBase

OceanBase 用 Paxos 在 zone 维度做副本管理，最常见的部署是"3 个 IDC，每个 IDC 一个 zone，5 个副本"。

- **Tenant 模型**：租户是资源隔离单位，每个租户有独立的 unit，unit 分布在不同 zone 上。
- **Primary Zone**：DBA 指定哪些 zone 优先承担写入 (leader)。
- **跨城多活**：通过 5 副本 (例如 2-2-1) 实现"任两 IDC 同时故障仍保证多数派可用"。

```sql
-- OceanBase 创建 tenant 时指定 zone 分布
CREATE TENANT test_tenant
  RESOURCE_POOL_LIST=('pool_zone1','pool_zone2','pool_zone3'),
  PRIMARY_ZONE='zone1;zone2,zone3';

-- 修改 table 的 primary zone
ALTER TABLE orders SET PRIMARY_ZONE='zone1';
```

### Snowflake

Snowflake 在 2020 年发布 Database Replication，2021 年扩展为 Failover Group + Client Redirect，构成完整的跨区域 BCDR (Business Continuity & Disaster Recovery) 方案。

- **Database Replication**：异步对象级复制，源数据库中的 schema、表、视图、stage 都被复制。
- **Failover Group**：把多个数据库、warehouse、role、user 打包成一个故障切换单位，统一 failover。
- **Client Redirect**：通过 connection URL 抽象层在 failover 时自动把客户端切到目标 deployment，对应用透明。

```sql
-- Snowflake 创建 failover group (在源 account 执行)
CREATE FAILOVER GROUP fg_global
  OBJECT_TYPES = DATABASES, ROLES, WAREHOUSES, USERS
  ALLOWED_DATABASES = mydb1, mydb2
  ALLOWED_ACCOUNTS = myorg.region2_account
  REPLICATION_SCHEDULE = '10 MINUTE';

-- 在目标 account 创建副本
CREATE FAILOVER GROUP fg_global
  AS REPLICA OF myorg.region1_account.fg_global;

-- 触发 failover
ALTER FAILOVER GROUP fg_global PRIMARY;  -- 在新主 account 执行

-- Client Redirect: 创建 connection
CREATE CONNECTION my_conn;
ALTER CONNECTION my_conn ENABLE FAILOVER TO ACCOUNTS myorg.region2_account;
```

### BigQuery

BigQuery 的"跨区域"概念和别的引擎不同：

- **Multi-region 数据集**：US、EU 这类 multi-region 是底层就跨多个 zone (region) 同步存储的位置，写入时即多副本同步，RPO=0。
- **Cross-region Dataset Replication**：2023 年起支持把数据集异步复制到其它区域 (single region)，用于跨大洲读加速或灾备。
- **Managed Disaster Recovery**：BigQuery 提供 managed DR，将数据集和元数据同步到目标区域。

```sql
-- BigQuery 创建 multi-region 数据集 (US 多区域)
CREATE SCHEMA `myproject.analytics_us`
OPTIONS (location = 'US');

-- 创建 cross-region dataset replica
CREATE SCHEMA `myproject.analytics_eu`
OPTIONS (location = 'europe-west4');
-- bq mk --transfer_config --project_id=myproject \
--   --target_dataset=analytics_eu \
--   --display_name="cross-region replica" \
--   --params='{"source_dataset_id":"analytics_us","source_project_id":"myproject"}' \
--   --data_source=cross_region_copy
```

### Oracle

Oracle 提供两类跨区方案：

- **Data Guard (DG)**：物理 standby (基于 redo)，逻辑 standby (基于 SQL apply)。Active Data Guard 让 standby 同时可读。
- **GoldenGate (OGG)**：基于 trail file 的逻辑复制，支持异构、多主、双向、表级粒度，是 Oracle 最灵活的跨区方案。

Data Guard 的三种保护模式：

| 模式 | 同步性 | 数据零丢失 | 性能影响 |
|------|------|---------|--------|
| Maximum Protection | SYNC + 至少 1 standby ack | 是 | 最大 (主库会因 standby 故障停机) |
| Maximum Availability | SYNC + 1 ack (容许降级到 ASYNC) | 是 (正常时) | 中 |
| Maximum Performance | ASYNC | 否 (秒级 RPO) | 最小 |

```sql
-- 创建物理 standby (DG)
ALTER DATABASE ADD STANDBY LOGFILE GROUP 4 SIZE 200M;

-- 配置保护模式
ALTER DATABASE SET STANDBY DATABASE TO MAXIMIZE AVAILABILITY;
ALTER SYSTEM SET LOG_ARCHIVE_DEST_2='SERVICE=stby SYNC AFFIRM
   VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=stby';

-- Active Data Guard (备库可读)
ALTER DATABASE OPEN READ ONLY;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT;

-- Fast-Start Failover (FSFO)
-- DGMGRL> EDIT CONFIGURATION SET PROTECTION MODE AS MaxAvailability;
-- DGMGRL> ENABLE FAST_START FAILOVER;
```

### SQL Server (AlwaysOn AG)

SQL Server 的 Always On Availability Group (AAG) 是默认的高可用 + DR 方案。

- **同步提交 (Synchronous Commit)**：主库等待 secondary 把日志硬化后才返回成功，RPO=0 但写延迟受 RTT 影响。建议同步副本数 ≤ 5 且物理就近。
- **异步提交 (Asynchronous Commit)**：主库不等 secondary，跨大区灾备时使用。
- **Distributed AG (2016+)**：跨多个 AG 复制 (例如本地 AG + 异地 DR AG)，每端独立 failover。
- **Basic AG (2016 Standard Edition+)**：单 database、1 主 1 备，限制版本。

```sql
-- 创建 AAG
CREATE AVAILABILITY GROUP ag_app
WITH (DB_FAILOVER = ON, CLUSTER_TYPE = WSFC)
FOR DATABASE app_db
REPLICA ON
  'SQL01' WITH (
    ENDPOINT_URL = 'TCP://sql01.contoso.com:5022',
    AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
    FAILOVER_MODE = AUTOMATIC),
  'SQL02-DR' WITH (
    ENDPOINT_URL = 'TCP://sql02.dr.contoso.com:5022',
    AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
    FAILOVER_MODE = MANUAL);

-- Distributed AG
CREATE AVAILABILITY GROUP dag_global
WITH (DISTRIBUTED)
AVAILABILITY GROUP ON
  'ag_us' WITH (LISTENER_URL='tcp://us-listener:5022',
                AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
                FAILOVER_MODE = MANUAL,
                SEEDING_MODE = AUTOMATIC),
  'ag_eu' WITH (LISTENER_URL='tcp://eu-listener:5022',
                AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
                FAILOVER_MODE = MANUAL,
                SEEDING_MODE = AUTOMATIC);
```

### PostgreSQL

PostgreSQL 内置流复制 (streaming replication) 是其跨区 DR 的核心。

- **物理流复制 (Physical Streaming)**：基于 WAL 字节级复制，只能整库。
- **逻辑流复制 (Logical Replication, 10+)**：基于发布订阅，可表级、跨大版本、跨架构。
- **同步复制**：通过 `synchronous_standby_names` 配置，写入需 standby ack。
- **第三方多主**：BDR (EnterpriseDB)、pglogical、Bucardo、Postgres-XL 提供多主或多区双向。

```sql
-- 主库 postgresql.conf
-- wal_level = replica
-- max_wal_senders = 10
-- synchronous_commit = on
-- synchronous_standby_names = 'FIRST 1 (standby_dr)'

-- 备库 recovery.conf (PG 11-) / postgresql.auto.conf (PG 12+)
-- primary_conninfo = 'host=primary.example.com port=5432 user=replicator'
-- primary_slot_name = 'standby_slot'

-- 在主库创建复制槽
SELECT pg_create_physical_replication_slot('standby_slot');

-- 监控复制延迟
SELECT client_addr, state,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes,
       replay_lag
FROM pg_stat_replication;
```

### MySQL

MySQL 跨区方案以 binlog 复制为核心。

- **异步复制**：默认，源库不等副本 ack。
- **半同步复制 (5.5+)**：源库等待至少 1 个副本接收 (不需要应用) binlog 后才提交，rpl_semi_sync 插件。
- **Group Replication (5.7+)**：基于 Paxos 变种 (XCom)，提供单主或多主组复制。多主模式存在冲突检测窗口，跨区 RTT 大时性能较差。
- **InnoDB Cluster / MySQL Router**：把 Group Replication 包装成可自动 failover 的高可用方案。

```sql
-- 配置半同步
INSTALL PLUGIN rpl_semi_sync_source SONAME 'semisync_source.so';
SET GLOBAL rpl_semi_sync_source_enabled = 1;
SET GLOBAL rpl_semi_sync_source_timeout = 1000;  -- ms, 超时降级为异步

-- 副本侧
INSTALL PLUGIN rpl_semi_sync_replica SONAME 'semisync_replica.so';
SET GLOBAL rpl_semi_sync_replica_enabled = 1;

-- Group Replication 启动
SET GLOBAL group_replication_bootstrap_group = ON;
START GROUP_REPLICATION;
SET GLOBAL group_replication_bootstrap_group = OFF;
```

### Azure Cosmos DB

Cosmos DB 是 Azure 的多模型数据库，提供 SQL API (注意：是 NoSQL 的 SQL 风格查询语法，并非 ANSI SQL)。其跨区域复制是产品的核心卖点之一：

- **Turnkey Global Distribution**：在 portal 勾选区域即可一键多区部署，全球一致性内置。
- **5 种一致性级别**：Strong、Bounded Staleness、Session、Consistent Prefix、Eventual。Strong 跨区时延迟最高但 RPO=0。
- **Multi-Region Writes**：可启用多区写入，使用 LWW (默认基于 _ts 字段) 或自定义 stored procedure 解决冲突。
- **Automatic Failover**：定义 failover priority，区域故障时按序自动切换。

### DynamoDB Global Tables

DynamoDB 不是 SQL 但常被对比：

- **Multi-master**：每个区域可写，通过流 (DynamoDB Streams) 异步双向复制。
- **LWW 冲突解决**：基于写入时间戳。
- **自动 failover**：不需要应用切换，所有区域均可读写。
- **典型 RPO**：< 1 秒；RTO ≈ 0 (因为多主)。

> 注意 DynamoDB 不支持 SQL 标准查询，PartiQL 只是有限子集。它出现在此对比中是因为它定义了"全球多主表"这个产品形态，影响了后来许多 SQL 系统的设计。

### SAP HANA System Replication

HANA 的 System Replication (SR) 是其旗舰 DR 方案，特别针对 in-memory + 列存场景做了优化：

- **3 种同步模式**：
  - **SYNC**：日志同步发送并等待 secondary 持久化 ack，RPO=0。
  - **SYNCMEM**：日志写到 secondary 内存即返回 ack，RPO ≈ 0 但 secondary 故障可能丢数据。
  - **ASYNC**：异步发送，跨大区典型选择。
- **Active/Active (Read Enabled)**：secondary 可承担只读查询，对报表场景很有用。
- **多层级**：HANA 可配置 1 主 + 1 备 + 1 三级备的 chain，主备同步、备到三级异步。

```sql
-- HANA SR 操作通常通过 HDBLCM 或 hdbnsutil 命令行
-- hdbnsutil -sr_register --remoteHost=primary --remoteInstance=00 \
--   --replicationMode=sync --operationMode=logreplay --name=site2
```

### IBM DB2 HADR + Q-Replication

DB2 提供两条互补路线：

- **HADR (High Availability Disaster Recovery)**：基于日志的物理复制，1 主多备，最多 3 个 standby。提供 SYNC、NEARSYNC、ASYNC、SUPERASYNC 四档同步级别。
- **Q-Replication**：基于消息队列 (MQ) 的逻辑复制，支持表级、双向、多主，常用于 OLTP-OLAP 数据流。

```sql
-- 配置 HADR
UPDATE DB CFG FOR mydb USING
  HADR_LOCAL_HOST primary.example.com
  HADR_LOCAL_SVC 10000
  HADR_REMOTE_HOST standby.example.com
  HADR_REMOTE_SVC 10000
  HADR_REMOTE_INST db2inst1
  HADR_TIMEOUT 120
  HADR_SYNCMODE NEARSYNC;

START HADR ON DB mydb AS PRIMARY;
```

### Greenplum / Vertica / Teradata

MPP 数据仓库的跨区方案普遍以"快照 + 增量"为主，缺乏低 RPO 的同步方案：

- **Greenplum**：内置 mirror 是同 segment host 间的同步镜像，跨区通常依赖 backup + WAL 归档或第三方工具。
- **Vertica**：DR 通过 vbr (Vertica Backup and Restore) 的增量备份完成，典型 RPO 数分钟。
- **Teradata Unity**：一套元数据驱动的"多 active"协调层，可在多个 Teradata 系统间路由查询和复制。配合 Dual Active 配置实现跨数据中心同步。

### ClickHouse ReplicatedMergeTree

ClickHouse 的复制是基于 ZooKeeper / Keeper 的"复制 MergeTree 引擎"，每个 shard 内多个副本通过 ZK 协调写入和合并：

- **跨区域**：把 shard 的副本部署到不同区域即可。但 ZK 本身需要跨区共识，跨大区 ZK 集群延迟会拖慢整体写入。
- **多主**：所有副本都可写，通过 ZK 排序日志保证最终一致。
- **典型部署**：常见的是"区域内多副本同步、跨区 ClickHouse Copier 异步同步"。

```sql
CREATE TABLE events_replicated ON CLUSTER my_cluster (
  ts DateTime, user_id UInt64, payload String
) ENGINE = ReplicatedMergeTree(
  '/clickhouse/tables/{shard}/events',
  '{replica}'
)
ORDER BY (user_id, ts);
```

### StarRocks / Doris CCR

国产 OLAP 引擎 StarRocks 和 Doris 都提供跨集群复制 (Cross Cluster Replication, CCR)：

- **基于 binlog 的异步复制**：源集群产生类 binlog 流，目标集群消费。
- **典型用途**：异地灾备、跨地域读加速、灰度集群切换。
- **限制**：CCR 是异步的，不能提供 RPO=0；目前不支持跨大版本复制。

## Spanner TrueTime 与全球同步事务深度剖析

### TrueTime API

```
TT.now()  -> TTinterval { earliest, latest }
TT.after(t)  -> bool  // 当前时间一定 > t
TT.before(t) -> bool  // 当前时间一定 < t
```

TrueTime 不返回单一时间点，而是返回一个**带不确定区间**的时间，区间宽度 ε (epsilon) 在正常情况下 < 7ms。这个误差由 GPS / 原子钟硬件 + 时钟漂移 + 网络传播的最坏情况上界推导得到。

### Commit-Wait 协议

Spanner 写事务 T 提交时执行：

1. 选择 commit timestamp `s = TT.now().latest`。
2. **等到 `TT.after(s) == true`**，才向客户端返回 commit 成功。
3. 这保证任何后启动的事务 T' 选取的 timestamp 一定 > s，因此 T' 看到 T 的写入是因果正确的。

这就是所谓的 **External Consistency** (外部一致性)：如果 T1 在 T2 开始之前提交 (实际物理时间)，那么 T1 的 commit timestamp < T2 的 commit timestamp。比线性一致更强，因为它考虑了系统外部 (人/真实时间) 的因果。

### Paxos + 2PC

- **每个 split 一个 Paxos group**：Spanner 把表切成 split (默认 ~1GB)，每个 split 在多副本上跑 Paxos。Leader 写日志到本地 + 多数派副本，多数派 ack 后认为写成功。
- **跨 split 事务用 2PC**：2PC 的协调者本身是一个 Paxos group leader。2PC 的耐久性来自 Paxos，因此整个事务在协调者挂掉后仍能继续。
- **读事务用 snapshot timestamp**：Spanner 用 MVCC，读事务选择一个 timestamp 直接读对应版本，不需要 2PC，也不阻塞写。

### 全球 vs 区域配置

| 配置 | 副本分布 | 写延迟 | 用途 |
|------|--------|------|------|
| `regional-us-east1` | 单区域 3 zone | < 5ms | 单区域低延迟 |
| `nam6` | 4 个 NA 区域 | 50-90ms | 北美强一致 |
| `nam-eur-asia1` | 北美 + 欧洲 + 亚洲 | 200ms+ | 真正的全球强一致 |

跨大洲配置的写延迟非常高，所以 Google 内部一般用 `regional` 或 `nam6`，只有真正需要跨大洲强一致的业务才用 `nam-eur-asia1`。

## CockroachDB 地理分区与 Raft 放置

### Raft 副本位置

CockroachDB 把数据切成 **range** (默认 64-512MB)，每个 range 用 Raft 维护多个副本 (默认 3，可配置 5)。每个 range 的副本位置由 zone config 决定：

```sql
-- 给数据库设置默认 zone
ALTER DATABASE app CONFIGURE ZONE USING
  num_replicas = 5,
  constraints = '[]',
  voter_constraints = '{+region=us-east1: 2, +region=us-west1: 2, +region=europe-west1: 1}',
  lease_preferences = '[[+region=us-east1]]';
```

### REGIONAL BY ROW 实现

CockroachDB 的 `REGIONAL BY ROW` 表本质上是隐式分区：

1. 每行一个 `crdb_region` 列 (枚举类型 `crdb_internal_region`)。
2. 索引以 `(crdb_region, ...)` 为前缀，确保同一 region 的行物理相邻。
3. 每个 region 分区有独立的 zone config，把对应的 range 副本固定在相应 region。
4. 读写时通过 lease holder 跟随访问者所在区域，实现"行级地理分区"。

### GLOBAL 表的非阻塞读

`GLOBAL` 表用于"几乎不变"的引用数据：

- 写仍需 Raft 多数派 (跨区延迟高)。
- 读通过 **closed timestamp** 机制：所有 follower 都可以服务"过去某个时间点"的快照读，不需要联系 leader。
- 这样写延迟高、读延迟极低，符合"配置表"类业务的访问模式。

```sql
-- 切换为 GLOBAL
ALTER TABLE exchange_rates SET LOCALITY GLOBAL;
```

### Raft 与 Paxos 在地理复制中的差异

| 维度 | Raft | Paxos (Multi-Paxos) |
|------|------|---------------------|
| 实现复杂度 | 简单 | 复杂 |
| 可读性 | 高 | 低 |
| 性能 | 略低 (强 leader) | 略高 (multi-leader 友好) |
| 代表系统 | CockroachDB / TiDB / YugabyteDB | Spanner / OceanBase |
| 跨区表现 | 写入需 leader RTT | 类似 |

实际上，跨区域同步复制的性能瓶颈在网络 RTT，Raft vs Paxos 的差异基本可以忽略。两者都受相同的 CAP / 物理延迟约束。

## 跨区复制的物理与协议成本

### 光速、RTT 与同步写延迟

跨区域同步复制的写延迟受物理光速制约。下表给出常见跨区 RTT 的近似值 (生产网络，光纤路径非大圆距离)：

| 路径 | 直线距离 | RTT (光速理论) | 实际 RTT (生产) |
|------|--------|--------------|---------------|
| 同 AZ (同机房) | < 5km | < 0.05ms | 0.1-0.5ms |
| 跨 AZ 同区域 (us-east1) | 50-100km | 0.3-0.7ms | 1-2ms |
| 跨城同国 (北京-上海) | 1000km | 7ms | 25-35ms |
| 跨大区同洲 (us-east-us-west) | 4000km | 27ms | 60-80ms |
| 跨洲 (us-east-eu-west) | 6000km | 40ms | 80-100ms |
| 跨太平洋 (us-west-asia) | 8000-10000km | 53-67ms | 100-150ms |
| 全球环路 | -- | -- | 200-300ms |

> 关键事实：同步多数派写延迟 ≈ 客户端到第 ⌈n/2⌉+1 个最近副本的最大 RTT。所以"3 副本部署在 us-east-1, us-west-2, eu-west-1"的写延迟由"次远 RTT"决定 (因为 3 个里面要等 2 个回 ack)。

### 共识协议的常见误区

1. **"Raft 比 Paxos 慢"**：错。两者在跨区延迟上几乎等价。Raft 的强 leader 模式让所有写都到 leader，理论上比 multi-leader Paxos 多一跳；但实践中 multi-Paxos 通常也只有 1 个稳定 leader，差异可忽略。
2. **"5 副本比 3 副本可用性高且性能更好"**：5 副本可用性更高 (容忍 2 副本失败)，但写延迟由 3 个最近副本决定 (5 副本多数派 = 3)，且通信开销增加。生产中 3 副本仍是最常见选择。
3. **"加副本能降低写延迟"**：错，副本越多通信开销越大。读延迟可以通过 follower read 降低，但写延迟下界由多数派 RTT 决定。

### CAP 与 PACELC 的实际表现

PACELC 比 CAP 更适合描述跨区数据库：

- **P (分区时)**：选 C (一致性) 还是 A (可用性)
- **E (无分区时)**：选 L (低延迟) 还是 C (一致性)

| 系统 | 分区时 | 无分区时 |
|------|------|--------|
| Spanner | C (拒绝) | C (commit-wait 增加延迟) |
| CockroachDB | C | C |
| TiDB | C | C |
| YugabyteDB (sync) | C | C |
| YugabyteDB (xCluster) | A | L |
| Aurora Global | A | L (从区) / C (主区) |
| Cassandra | A | L |
| DynamoDB Global Tables | A | L |
| MySQL Group Replication (single-primary) | C | C |
| MariaDB Galera | C | L (本地节点) |

> Spanner 是 PC/EC，但通过 TrueTime + 充足带宽把 C 模式下的延迟控制到可接受范围。CockroachDB 同样选 PC/EC，但默认 max-offset 500ms 比 Spanner 大得多 (因为没有 GPS/原子钟)。

## 多区部署的运维实务

### 容量规划

- **副本因子 vs 区域数**：常见组合 (副本数, 区域数)：(3,3) 单区域内 3 副本；(5,3) 跨区典型；(3,1) + 异步 DR 仍是大部分企业的折衷。
- **跨区带宽**：每秒写 X MB → 跨区流量 X * (副本数 - 1) MB/s。100MB/s 写入在 5 副本跨区场景下产生 400MB/s 跨区带宽，云厂商按 GB 计费可能成为 dominant cost。
- **磁盘 IOPS**：每个副本独立 fsync，多副本不会均摊 IOPS 而是放大。

### 数据驻留合规

GDPR、《数据安全法》、HIPAA、CCPA、PIPL 等法规对跨境数据流动有严格要求。常见技术对策：

1. **物理隔离**：欧洲用户的数据库实例物理上只部署在欧洲，跨境复制完全禁止。最简单但限制全球查询能力。
2. **行级地理分区**：单一全球数据库内，按用户的 country 列把行钉在对应区域，全球查询通过分区投影完成。CockroachDB REGIONAL BY ROW、YugabyteDB 地理分区是典型实现。
3. **加密 + 跨境元数据**：业务数据加密本地存储，仅密文索引或匿名标识跨境流动。需要应用配合。
4. **多个独立 instance + 联邦查询**：维护多个区域 instance + 通过 federated query (BigQuery Omni、Trino) 跨实例查询。

### 测试与演练

跨区切换不是配好就行，必须定期演练：

- **Chaos 演练**：定期 kill 一个区域的所有节点，验证 failover 时间和数据一致性。
- **灰度切换**：先把 1% 流量切到 DR 区域，观察延迟与错误率，再逐步放大。
- **回切 (failback)**：切到 DR 后，原区域恢复时如何回切？很多系统的回切流程比 failover 更复杂 (需要 reseed 数据)，必须有手册。
- **数据校验**：跨区复制后，定期 checksum 主备表对比 (例如 pt-table-checksum)，发现潜在 silent corruption。

### 监控指标清单

跨区复制的健康监控应至少覆盖：

- **复制延迟 (lag)**：通常以字节 (WAL 字节差) 和秒 (apply lag) 双指标监控。
- **副本健康**：每副本最近一次心跳 / Raft 投票时间。
- **跨区带宽利用率**：避免被流量冲爆专线。
- **failover 准备状态**：DR 副本是否就绪，readonly 是否能立即转 readwrite。
- **跨区 RTT**：用 ping / TCP probe 周期采样，RTT 异常增长往往是问题前兆。

## 跨区域复制与其他特性的关系

- **MVCC 实现**：跨区强一致依赖 MVCC + global timestamp。Spanner 的 timestamp 来自 TrueTime，CockroachDB 来自 HLC，TiDB 来自 PD (Placement Driver) 的全局 TSO。不同 timestamp 源决定了能否提供 external consistency。详见 `mvcc-implementation.md`。
- **事务隔离级别**：跨区复制不改变隔离级别的语义，但会影响实现。例如 Spanner 在跨区场景仍提供 strict serializable，代价是 commit-wait；CockroachDB 提供 serializable 但允许 bounded staleness 读，让全球读延迟可接受。详见 `transaction-isolation-comparison.md`。
- **逻辑复制 (单区聚焦)**：单区复制的诸多概念 (binlog、WAL、GTID、semi-sync) 是跨区复制的基础。详见 `logical-replication-gtid.md`。
- **分区策略**：跨区地理分区是分区策略的特例，把分区键和地理位置耦合。详见 `partition-strategy-comparison.md`。
- **CDC / Changefeed**：异步跨区方案 (xCluster、TiCDC、GoldenGate) 本质是 CDC 流。详见 `cdc-changefeed.md`。

## 关键发现

1. **没有 SQL 标准**：跨区域复制完全是厂商架构选择。即使 PostgreSQL / MySQL 这样的"标准"开源数据库也各自有截然不同的复制语法和拓扑，应用代码若依赖跨区行为基本无法在引擎间移植。

2. **同步复制的物理上限**：同步跨区写入的最低延迟由光速 + 网络设备决定。东京到洛杉矶 RTT ≈ 100ms，因此任何"同步跨太平洋"系统单笔写至少 50-100ms，无论用 Raft/Paxos/2PC。这不是工程问题而是物理问题，理解这一点比记任何产品语法更重要。

3. **真正的全球同步强一致只有少数选手**：Google Spanner、CockroachDB、TiDB (Placement Rules + 同步)、YugabyteDB (stretch)、OceanBase (跨城) 是真正"默认 RPO=0 跨区"的 SQL 系统。Aurora Global Database、Snowflake Failover Group 都是异步，RPO ≥ 1 秒。

4. **TrueTime 不是必需的，但简化了实现**：Spanner 用 TrueTime 解决了"如何选 commit timestamp 既保证因果又保证全球唯一"的问题。CockroachDB 用 HLC (Hybrid Logical Clock) + 网络 RTT 上界 (`max_offset = 500ms`) 达成类似目标，代价是不能保证严格的 external consistency，只能保证 serializable + bounded staleness。

5. **主备 vs 多主的真实成本**：多主 (multi-master) 听起来很美，但所有非"基于共识"的多主方案 (Galera、Group Replication、GoldenGate 双向、xCluster 双向、DynamoDB Global Tables) 都把"冲突解决"留给应用或简单 LWW，实际可用性远低于宣传。基于共识的多主 (Spanner/CockroachDB) 又受 CAP 约束，跨区写延迟无法回避。

6. **地理分区 (Geo-Partitioning) 是数据驻留的工程答案**：要满足 GDPR/数据主权法规，最干净的做法是按用户所在区域把数据物理上钉死在该区域。CockroachDB `REGIONAL BY ROW`、YugabyteDB Tablespace、TiDB Placement Rules、Spanner Locality Group、Cosmos DB Partition Key + 多区策略都是这一思路的实现。MySQL/PostgreSQL 上做地理分区只能靠应用层分库分表，运维代价巨大。

7. **存储级 vs 引擎级复制**：Aurora 的"存储层复制"在单区 Aurora 已经验证了优势 (6 副本 + quorum)，扩展到跨区时利用同样的存储抽象，比 binlog/WAL 这种引擎级方案少一层 round-trip，因此 Aurora Global Database 的跨区 RPO 能稳定在 < 1 秒。但代价是必须用 AWS 托管，无法在自有机房复制。

8. **Failover 自动化往往是真正的瓶颈**：RPO=0 容易 (用同步复制)，RTO < 30 秒难。难点在自动检测脑裂、客户端连接重定向、应用幂等性。Snowflake Client Redirect、Aurora Global Failover、CockroachDB 内建 failover、Cosmos DB Automatic Failover 都是把这件事做成"托管按钮"的尝试，但对于自建 PostgreSQL/MySQL，failover 自动化仍是工程难题 (常用 Patroni、orchestrator、MHA)。

9. **跨区读副本 ≠ 跨区写**：很多团队把"加跨区只读副本"误以为解决了 DR 问题。只读副本只能解决读扩展和"灾后人工切换"，不能解决"写主区域宕机时立刻继续写"。后者必须有自动化 failover + RPO 保证。

10. **混合拓扑日益成为主流**：现代部署很少是"纯同步"或"纯异步"，而是"区域内同步 + 跨区域异步"：例如美东 3 副本 Raft 同步 + 异步流到欧洲 DR；或同步 stretch 到 3 个邻近城市 + 异步跨大洲。这把 RPO/RTO/延迟/成本的平衡留给业务自己选择。

11. **冷数据跨区是另一个被忽视的维度**：很多分析型系统 (Snowflake、BigQuery、Redshift、Databricks) 数据本质上存在对象存储 (S3/GCS)，对象存储的跨区复制 (S3 Cross-Region Replication) 是数据库跨区复制的"默认底座"。对这类引擎而言，"跨区复制"的真正含义是元数据 catalog 和计算节点的复制，而非业务数据本身。

12. **测试覆盖度普遍不足**：跨区复制类故障是生产中最严重也最难调试的故障类型之一。许多企业只在上线前做过一次 failover 测试，就再也没碰过——这等于没做。建议每季度执行一次 region kill 演练，每月执行一次 lag 报警阈值核对。

## 参考资料

- Google: [Spanner: Google's Globally-Distributed Database (OSDI 2012)](https://research.google/pubs/pub39966/)
- Google: [Cloud Spanner Multi-region configurations](https://cloud.google.com/spanner/docs/instance-configurations)
- AWS: [Aurora Global Database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html)
- AWS: [DynamoDB Global Tables](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html)
- CockroachDB: [Multi-Region Capabilities Overview](https://www.cockroachlabs.com/docs/stable/multiregion-overview.html)
- CockroachDB: [REGIONAL and GLOBAL Tables](https://www.cockroachlabs.com/docs/stable/table-localities.html)
- TiDB: [Placement Rules in SQL](https://docs.pingcap.com/tidb/stable/placement-rules-in-sql)
- TiDB: [TiCDC Overview](https://docs.pingcap.com/tidb/stable/ticdc-overview)
- YugabyteDB: [xCluster Replication](https://docs.yugabyte.com/preview/architecture/docdb-replication/async-replication/)
- YugabyteDB: [Row-Level Geo-Partitioning](https://docs.yugabyte.com/preview/explore/multi-region-deployments/row-level-geo-partitioning/)
- OceanBase: [Multi-IDC Deployment](https://en.oceanbase.com/docs/)
- Snowflake: [Database Replication and Failover](https://docs.snowflake.com/en/user-guide/account-replication-intro)
- BigQuery: [Cross-region dataset replication](https://cloud.google.com/bigquery/docs/data-replication)
- Oracle: [Data Guard Concepts and Administration](https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/)
- Microsoft: [Always On Availability Groups](https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/always-on-availability-groups-sql-server)
- Microsoft: [Distributed Availability Groups](https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/distributed-availability-groups)
- PostgreSQL: [Streaming Replication](https://www.postgresql.org/docs/current/warm-standby.html#STREAMING-REPLICATION)
- MySQL: [Group Replication](https://dev.mysql.com/doc/refman/8.0/en/group-replication.html)
- SAP HANA: [System Replication](https://help.sap.com/docs/SAP_HANA_PLATFORM/4e9b18c116aa42fc84c7dbfd02111aba/afac7100bb571014b3fc9283b0e91070.html)
- IBM: [Db2 HADR](https://www.ibm.com/docs/en/db2/11.5?topic=availability-high-disaster-recovery-hadr)
- Azure: [Cosmos DB Global Distribution](https://learn.microsoft.com/en-us/azure/cosmos-db/distribute-data-globally)
- Galera Cluster: [Documentation](https://galeracluster.com/library/documentation/)
- Corbett et al. "Spanner: Google's Globally-Distributed Database" OSDI 2012
- Taft et al. "CockroachDB: The Resilient Geo-Distributed SQL Database" SIGMOD 2020
- Abadi, Daniel J. "Consistency Tradeoffs in Modern Distributed Database System Design: CAP is Only Part of the Story" IEEE Computer 2012 (PACELC)
