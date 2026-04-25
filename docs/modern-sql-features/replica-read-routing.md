# 副本读路由 (Replica Read Routing)

写入主库、读取从库——这条看似简单的架构准则背后，藏着分布式数据库设计中最棘手的权衡：**复制延迟 vs 一致性 vs 吞吐量**。当主库的一条 UPDATE 刚刚提交，从库可能还没收到 binlog；当应用立即转头读这个从库，用户看到的是"昨天的世界"。副本读路由（replica read routing）就是这道路口的交通警察——它决定每一条读请求应该去哪个节点、容忍多大的陈旧、是否必须看到自己刚写的数据。

本文系统对比 45+ 数据库引擎在读写分离和副本路由上的设计差异，从 MySQL 的外置代理到 CockroachDB 的 Follower Reads、从 Spanner 的有界陈旧到 DynamoDB Global Tables 的最终一致，梳理出一套可供引擎开发者和架构师参考的权威矩阵。

## 为什么需要副本读路由

- **读写分离（Read/Write Split）**：读负载通常比写大一个数量级。将读请求路由到只读副本可以让主库专注处理写入，线性扩展只读吞吐。
- **复制延迟与一致性取舍**：异步复制下，从库落后主库几毫秒到几秒不等。应用必须显式声明"能接受多陈旧的数据"。
- **读己所写（Read-Your-Own-Writes, RYW）**：用户提交评论后立即刷新页面，应该能看到自己的评论。这需要路由器感知"刚写过"的状态。
- **有界陈旧（Bounded Staleness）**：分析类查询可以容忍几秒的陈旧（例如最近 5 秒内的快照）以换取更低延迟和更高吞吐。
- **跨区域读本地化**：用户在东京，数据主库在弗吉尼亚。就近读本地副本可以把 P99 从 200ms 降到 10ms。
- **主库故障时的读降级**：主库宕机期间，允许从副本读陈旧数据以维持只读业务运行。
- **分析型工作负载隔离**：OLAP 查询不应挤压 OLTP 主库。让分析查询走独立的只读副本或列存 TiFlash 节点。

## 没有 SQL 标准——纯架构与协议选择

ANSI/ISO SQL 标准从未定义读写分离、副本路由、陈旧读等概念。SQL:2016 也没有引入"读从库"这样的语法。所有相关能力都是各引擎独立扩展：

- **会话变量派**：TiDB `tidb_replica_read`、PostgreSQL `default_transaction_read_only`、MySQL `innodb_read_only`。
- **查询提示派**：Oracle `/*+ READ_ONLY */`、SQL Server `ApplicationIntent=ReadOnly`、CockroachDB `AS OF SYSTEM TIME`。
- **外置代理派**：ProxySQL、MaxScale、pgpool-II、HAProxy + 自定义规则。
- **驱动层派**：MySQL Connector/J 的 `ReplicationDriver`、JDBC URL 中的 `replicaSet` 参数。
- **云原生 endpoint 派**：AWS Aurora Reader Endpoint、Azure SQL Read Scale、Spanner Stale Read 客户端。

理解这些机制的组合方式，对设计一个支持副本路由的现代数据库至关重要。

## 副本读路由能力矩阵

下表对 47 个引擎在副本路由能力上做全面对比。"--"表示不支持、不适用或需要完全外置方案。

### 表 1：服务端路由 vs 客户端路由 vs 驱动层路由

| 引擎 | 服务端自动路由 | 客户端提示路由 | 驱动/连接串路由 | 外置代理 | 版本 |
|------|--------------|--------------|--------------|---------|------|
| PostgreSQL | 否 | 否 | libpq `target_session_attrs` | pgpool-II, pgbouncer, pgcat | 10+ |
| MySQL | 否 | 否 | Connector/J `ReplicationDriver` | ProxySQL, MaxScale, Vitess | 5.7+ |
| MariaDB | 否 | 否 | Connector/J `replication` | MaxScale, ProxySQL | 10.0+ |
| SQLite | -- | -- | -- | -- | 单机 |
| Oracle | Active Data Guard | `/*+ READ_ONLY */` 等 | TNS `(READ_ONLY=TRUE)` | Connection Manager | 11g+ |
| SQL Server | AlwaysOn Listener | `ApplicationIntent=ReadOnly` | ODBC/OLE DB 标志 | -- | 2012+ |
| DB2 | HADR 路由 | 客户端会话属性 | JDBC `clientRerouteServerList` | -- | 10.5+ |
| Snowflake | Warehouse 路由 | -- | -- | -- | GA |
| BigQuery | 自动 (无主从概念) | -- | -- | -- | GA |
| Redshift | Concurrency Scaling | -- | -- | -- | GA |
| DuckDB | -- | -- | -- | -- | 单机 |
| ClickHouse | 是 (Distributed) | SETTINGS load_balancing | -- | chproxy | 早期 |
| Trino | 协调器路由 | -- | -- | -- | N/A |
| Presto | 协调器路由 | -- | -- | -- | N/A |
| Spark SQL | -- | -- | -- | -- | N/A |
| Hive | -- | -- | -- | -- | N/A |
| Flink SQL | -- | -- | -- | -- | N/A |
| Databricks | SQL Warehouse | 会话 Hint | -- | -- | GA |
| Teradata | Unity Director | -- | -- | Unity Loader | Unity |
| Greenplum | Master 路由 | -- | -- | -- | GA |
| CockroachDB | 内置 | `AS OF SYSTEM TIME` | -- | -- | 19.2+ (GA, experimental from 19.1) |
| TiDB | `tidb_replica_read` | Hint `READ_FROM_STORAGE` | -- | TiProxy | 4.0+ |
| OceanBase | ODP 路由 | Hint | -- | OBProxy | 2.0+ |
| YugabyteDB | 是 (tserver) | `set_tablet_replicas_preference` | -- | -- | 2.0+ |
| SingleStore | Aggregator | -- | -- | -- | GA |
| Vertica | 是 (节点路由) | -- | -- | -- | GA |
| Impala | 协调器 | -- | -- | -- | N/A |
| StarRocks | 是 (FE 路由) | -- | -- | -- | GA |
| Doris | 是 (FE 路由) | -- | -- | -- | GA |
| MonetDB | -- | -- | -- | -- | -- |
| CrateDB | 是 (协调节点) | -- | -- | -- | GA |
| TimescaleDB | 继承 PG | -- | 继承 PG | pgpool-II | 继承 PG |
| QuestDB | -- | -- | -- | -- | -- |
| Exasol | -- | -- | -- | -- | -- |
| SAP HANA | 是 (System Replication) | Hint | -- | -- | 2.0+ |
| Informix | HDR 路由 | -- | -- | -- | GA |
| Firebird | -- | -- | -- | -- | -- |
| H2 | -- | -- | -- | -- | -- |
| HSQLDB | -- | -- | -- | -- | -- |
| Derby | -- | -- | -- | -- | -- |
| Amazon Aurora | Reader Endpoint | -- | JDBC wrapper | RDS Proxy | GA |
| Amazon Athena | -- | -- | -- | -- | N/A |
| Azure Synapse | -- | -- | -- | -- | GA |
| Azure SQL | Read Scale-Out | `ApplicationIntent=ReadOnly` | ODBC | -- | GA |
| Google Spanner | Stale Read 路由 | `READ_TIMESTAMP` / bounded | 客户端库参数 | -- | GA |
| DynamoDB | 客户端 ConsistentRead | ConsistentRead=true/false | SDK 参数 | DAX | GA |
| Cosmos DB | 一致性级别路由 | -- | SDK consistency level | -- | GA |
| Materialize | -- | -- | -- | -- | N/A |
| RisingWave | -- | -- | -- | -- | N/A |
| InfluxDB (SQL) | -- | -- | -- | -- | -- |
| DatabendDB | -- | -- | -- | -- | -- |
| Yellowbrick | -- | -- | -- | -- | -- |
| Firebolt | -- | -- | -- | -- | -- |

> 统计：约 20 个引擎内置某种形式的副本路由，约 15 个依赖外置代理，约 12 个（流处理/单机/分析引擎）架构上不适用读写分离。

### 表 2：从主读 vs 从从读 vs 有界陈旧 vs 读己所写

| 引擎 | 强一致读（主） | 从从读 | 有界陈旧读 | 读己所写 (RYW) | 跟随者读 |
|------|--------------|-------|----------|-------------|--------|
| PostgreSQL | 是 (主) | 是 (流复制 standby) | 应用层 LSN 追踪 | 同步流复制 + 等 LSN | standby |
| MySQL | 是 (主) | 是 (binlog 复制) | GTID / WAIT_FOR_EXECUTED_GTID_SET | 同步至 GTID | 从库 |
| MariaDB | 是 (主) | 是 | GTID | MASTER_GTID_WAIT | 从库 |
| Oracle | 是 (主) | Active Data Guard | 手动 SCN 等待 | Data Guard 同步 | ADG reader |
| SQL Server | 是 (主) | AlwaysOn 可读副本 | 同步提交模式 | 同步提交 AG | Secondary |
| DB2 | 是 (主) | HADR reads on standby | 手动 LSN 追踪 | HADR SYNC | Standby |
| Snowflake | 是 (任意 warehouse) | Virtual Warehouse | -- | 单一存储层无副本问题 | -- |
| BigQuery | 是 | -- | -- | 强一致 | -- |
| Aurora | 是 (主) | Reader Endpoint | LSN 等待 | Aurora Fast Failover | Reader |
| Redshift | 是 (主) | Concurrency Scaling Cluster | -- | 自动路由 | -- |
| ClickHouse | 是 (主副本) | 是 (任意副本) | 设置 `max_replica_delay_for_distributed_queries` | 同步 INSERT | 是 |
| CockroachDB | 是 (leaseholder) | Follower Reads (5s default) | 是 (`AS OF SYSTEM TIME`) | 默认主 | 是 (closed timestamp) |
| TiDB | 是 (leader) | Follower Read (4.0+) | TSO 时间戳 | 强一致读选项 | 是 |
| OceanBase | 是 (leader) | 弱一致读 | 时间戳或 delay | stale_time | 是 |
| YugabyteDB | 是 (leader) | Follower Reads | `yb_read_from_followers` + staleness | 默认 leader | 是 |
| Spanner | 是 (Paxos leader) | Stale Reads | Bounded Staleness / Exact Staleness | Strong Read | 是 |
| DynamoDB | ConsistentRead=true | ConsistentRead=false | -- (秒级最终一致) | 应用层保证 | 全球表 |
| Cosmos DB | Strong | Bounded Staleness / Session / Eventual | 是 (多档) | Session 级别 | 是 |
| SAP HANA | 是 (主) | Active/Active System Replication | 是 | 同步复制 | 是 |
| SingleStore | 是 (leaf) | -- | -- | 强一致 | -- |
| Vertica | 是 | 内部路由 | -- | 强一致 | -- |
| TimescaleDB | 继承 PG | 继承 PG | 继承 PG | 继承 PG | 继承 PG |
| Greenplum | 是 (主) | -- | -- | 强一致 | -- |

### 表 3：陈旧度控制机制

| 引擎 | 主要机制 | 配置单位 | 默认值 | 查询语法 |
|------|--------|---------|-------|---------|
| CockroachDB | 关闭时间戳 (closed timestamp) | 秒 | 3.9 秒 (internal) | `AS OF SYSTEM TIME follower_read_timestamp()` |
| Spanner | 提交时间戳 + 有界陈旧 | 秒或毫秒 | 15 秒 (max staleness) | `read_timestamp` / `max_staleness` / `min_read_timestamp` |
| TiDB | TSO + stale read | 秒 | 0 (精确) | `SELECT ... AS OF TIMESTAMP NOW() - INTERVAL 5 SECOND` |
| YugabyteDB | Hybrid Logical Clock | 毫秒 | 30 秒 (max staleness) | `SET yb_follower_read_staleness_ms = 10000` |
| Oracle ADG | SCN 追踪 | SCN 值 | N/A | `ALTER SESSION SET STANDBY_MAX_DATA_DELAY` |
| DynamoDB 全球表 | 最终一致 | 秒级 | ~1 秒 (region-to-region) | `ConsistentRead=false` |
| Cosmos DB | 5 档一致性 | 操作数/时间 | Session | 账户级或请求级配置 |
| SAP HANA System Replication | LSN | 无 | 零 (同步) | 连接会话属性 |

## 各引擎读写分离详解

### MySQL：驱动层 + 外置代理

MySQL 核心没有内置读写分离，业界主要依赖 Connector/J 或外部代理：

```java
// 1. MySQL Connector/J 的 ReplicationDriver (已废弃但仍广泛使用)
String url = "jdbc:mysql:replication://master:3306,slave1:3306,slave2:3306/db"
           + "?loadBalanceStrategy=random";

Connection conn = DriverManager.getConnection(url, "user", "pass");
conn.setReadOnly(true);   // 下一条 SQL 会路由到 slave
stmt.executeQuery("SELECT * FROM orders");

conn.setReadOnly(false);  // 回到 master
stmt.executeUpdate("UPDATE orders SET status='shipped' WHERE id=1");
```

```sql
-- 2. MySQL 8.0.14+ 支持 optimizer hint，但仅控制查询执行时间，
--    不能做读写分离：
SELECT /*+ max_execution_time(1000) */ * FROM large_table;
-- 注意：/*+ max_execution_time */ 是超时控制，不是副本路由

-- 3. 正确做法：GTID 等待保证读己所写 (RYW)
SET SESSION SESSION_TRACK_GTIDS='OWN_GTID';
INSERT INTO orders VALUES (...);
-- 获取 @@gtid_executed，传给从库

-- 从库执行查询前先等待主库的 GTID
SELECT WAIT_FOR_EXECUTED_GTID_SET('uuid:1-100', 5);   -- 最多等 5 秒
SELECT * FROM orders WHERE id = ...;
```

**ProxySQL 做 MySQL 读写分离**：

```sql
-- 在 ProxySQL 控制台配置主机组规则
INSERT INTO mysql_query_rules (rule_id, match_pattern, destination_hostgroup, apply)
VALUES
  (1, '^SELECT.*FOR UPDATE$',  0, 1),   -- 写组 0
  (2, '^SELECT',                1, 1),   -- 读组 1
  (3, '.*',                     0, 1);  -- 其他默认写组

LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
```

**MaxScale readwritesplit 路由器**：

```ini
[Read-Write-Service]
type=service
router=readwritesplit
servers=master,slave1,slave2
user=maxscale
master_failure_mode=error_on_write
causal_reads=local     # 启用 RYW：读之前等待 GTID
causal_reads_timeout=10
```

`causal_reads=local` 让 MaxScale 在读路由前 `SELECT WAIT_FOR_EXECUTED_GTID_SET(...)`，保证同一会话的读能看到自己的写。

### PostgreSQL：流复制 + pgpool-II

PostgreSQL 自身不路由读写，依赖外部代理或应用逻辑：

```bash
# 1. libpq 的 target_session_attrs 可选主库
psql "postgresql://host1:5432,host2:5432,host3:5432/mydb?target_session_attrs=read-write"
# 连接到第一个可写的节点（即主库）

psql "postgresql://host1:5432,host2:5432,host3:5432/mydb?target_session_attrs=read-only"
# 连接到只读副本 (PostgreSQL 14+)

# 可选值：any | read-write | read-only | primary | standby | prefer-standby
```

**pgpool-II 自动读写分离**：

```conf
# pgpool.conf
load_balance_mode = on
master_slave_mode = on
master_slave_sub_mode = 'stream'

# 自动识别 SELECT 路由到 standby
# UPDATE/INSERT/DELETE 路由到 primary
# BEGIN 后的读默认去 primary (保证事务内一致)

# 黑名单：这些函数调用永远走主库
black_function_list = 'currval,lastval,nextval,setval'
```

**WAL 等待实现 RYW**：

```sql
-- 主库写入后获取 LSN
INSERT INTO orders ...;
SELECT pg_current_wal_lsn();   -- 例如 0/1A2B3C4D

-- 从库读取前等待 LSN 到达
SELECT pg_wal_lsn_diff(pg_last_wal_replay_lsn(), '0/1A2B3C4D');
-- 若 >= 0 则已赶上，可以安全读

-- 应用层可封装为：while not caught_up: sleep(50ms)
```

### Oracle Active Data Guard

Oracle 通过 Data Guard 的 Redo 传输 + ADG 的"Physical Standby Open Read-Only"提供只读副本：

```sql
-- 查询副本角色
SELECT database_role, open_mode FROM v$database;
-- PRIMARY / READ WRITE
-- PHYSICAL STANDBY / READ ONLY WITH APPLY (ADG)

-- 客户端 TNS 配置自动路由到 ADG
-- tnsnames.ora
ORCL_RW =
  (DESCRIPTION=
    (ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=primary)(PORT=1521)))
    (CONNECT_DATA=(SERVICE_NAME=orcl)(SERVER=DEDICATED)))

ORCL_RO =
  (DESCRIPTION=
    (ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=standby)(PORT=1521)))
    (CONNECT_DATA=(SERVICE_NAME=orcl_ro)))
-- 服务 orcl_ro 在 ADG 上启动，主库故障时自动切换到新主

-- 应用层提示 (11g+)
SELECT /*+ READ_ONLY */ COUNT(*) FROM orders;
-- Oracle 会建议路由到 ADG, 但最终由服务名/连接决定

-- 陈旧度控制
ALTER SESSION SET STANDBY_MAX_DATA_DELAY = 30;    -- 最多容忍 30 秒陈旧
SELECT * FROM orders;   -- 若延迟超过 30s 则报错 ORA-03172

-- 强制 RYW：阻塞读直到应用到指定 SCN
ALTER SESSION SYNC WITH PRIMARY;
SELECT * FROM orders;   -- 保证看到主库最新数据
```

### SQL Server AlwaysOn Availability Groups

SQL Server 的读写分离依赖 AG Listener + Read-Only Routing List：

```sql
-- 1. 创建 AG
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
          FAILOVER_MODE = AUTOMATIC,
          SECONDARY_ROLE(ALLOW_CONNECTIONS = READ_ONLY,
                         READ_ONLY_ROUTING_URL = 'TCP://secondary1:1433'));

-- 2. 定义只读路由列表
ALTER AVAILABILITY GROUP OrdersAG
  MODIFY REPLICA ON 'PrimaryNode'
    WITH (PRIMARY_ROLE(READ_ONLY_ROUTING_LIST = ('SecondaryNode1','SecondaryNode2')));
```

```
# 3. 客户端连接串
Server=tcp:OrdersAGListener,1433;
Database=Orders;
ApplicationIntent=ReadOnly;
MultiSubnetFailover=True;

# 当 ApplicationIntent=ReadOnly 时，Listener 把连接转发到只读路由列表的第一个可用副本。
# 没有此参数时，连接到主副本。
```

```sql
-- 4. Read-Scale Availability Group (2017+, 无集群依赖)
-- 专用于扩展只读吞吐，不保证高可用：
CREATE AVAILABILITY GROUP ReadScaleAG
WITH (CLUSTER_TYPE = NONE)
FOR REPLICA ON ... ;
```

### CockroachDB Follower Reads 深度剖析

CockroachDB 的 Follower Reads 是读写分离在共识协议（Raft）引擎中最优雅的实现之一。

#### 核心概念：Closed Timestamp（关闭时间戳）

```
关闭时间戳定义：
  对 range r，关闭时间戳 ct 表示 "r 在 [0, ct] 区间内的所有写都已在集群中 durable"
  任何时间戳 <= ct 的读都可以在任意副本（follower）上进行，无需联系 leaseholder

机制：
  1. Leaseholder 定期广播 "关闭到 ct" 消息
  2. Followers 收到后更新自己的关闭时间戳
  3. 读时间戳 ts: 若 ts <= ct，本地副本可直接读
  4. 若 ts > ct，必须回退到 leaseholder 读

配置参数 (v23.1+):
  kv.closed_timestamp.target_duration     -- 目标延迟 (默认 3s)
  kv.closed_timestamp.side_transport_interval  -- 心跳间隔 (默认 200ms)
  kv.rangefeed.closed_timestamp_refresh_interval  -- rangefeed 刷新 (默认 3s)

有效陈旧度 = target_duration + 传播延迟 + 时钟偏移上限
           约为 3.9 秒（CockroachDB 文档推荐值）
```

#### 查询语法

```sql
-- 1. 绝对时间戳的陈旧读（精确时刻）
SELECT * FROM orders AS OF SYSTEM TIME '2026-04-23 10:00:00';

-- 2. 使用内置函数 follower_read_timestamp() (推荐)
SELECT * FROM orders AS OF SYSTEM TIME follower_read_timestamp();
-- 返回 "当前时间 - 3.9 秒"，保证能从 follower 读取

-- 3. 有界陈旧读 (v22.1+)
SELECT * FROM orders AS OF SYSTEM TIME with_max_staleness('10s');
-- 如果可以在 10 秒陈旧内读到本地副本，就读；否则走 leaseholder

SELECT * FROM orders AS OF SYSTEM TIME with_min_timestamp('2026-04-23 09:59:50');
-- 读时间戳必须 >= 指定时间戳，可以更新但不能更旧

-- 4. 会话级别启用 follower reads
SET default_transaction_use_follower_reads = on;
BEGIN;
  SELECT * FROM orders;   -- 自动使用 follower reads
  SELECT * FROM customers;
COMMIT;

-- 5. 非事务查询的会话默认：
SET default_transaction_use_follower_reads = off;  -- 默认，走 leaseholder
```

#### Follower Reads 的性能与代价

```sql
-- 观察 follower reads 是否生效
SHOW TRACE FOR SESSION;
-- 查看 "dist sender send" 事件的目标节点

-- 实测场景：3 节点集群，跨区部署 (us-east1 / eu-west1 / asia-southeast1)
-- 不用 follower reads：
--   us-east1 的客户端查询 → leaseholder 在 eu-west1 → RTT 80ms
-- 用 follower reads：
--   us-east1 的客户端查询 → 本地 follower → RTT 2ms
-- 代价：数据可能陈旧 3.9 秒

-- 配置关闭时间戳目标时长 (集群级别)
SET CLUSTER SETTING kv.closed_timestamp.target_duration = '3s';
-- 更小值 → 陈旧度更低，但 CPU 开销略增
-- 更大值 → 网络传播故障时 follower reads 更容易成功
```

#### Global Tables (v21.2+)

```sql
-- 为全球读优化的特殊表设置
ALTER TABLE products SET LOCALITY GLOBAL;

-- Global Tables 的语义：
-- 1. 所有 follower 都能立即读（无 3.9s 延迟）
-- 2. 代价：写操作延迟增加（需要等待所有区域的时钟确认）
-- 3. 适合"多读少写"的全球只读数据（配置表、产品目录）
```

### TiDB：Follower Read + TiFlash

TiDB 自 4.0 引入 Follower Read，支持多种路由策略：

```sql
-- 1. 会话变量
SET tidb_replica_read = 'leader';             -- 默认：只读 leader
SET tidb_replica_read = 'follower';           -- 只读 follower
SET tidb_replica_read = 'leader-and-follower';-- leader 和 follower 都可
SET tidb_replica_read = 'prefer-leader';      -- 优先 leader (6.4+)
SET tidb_replica_read = 'closest-replicas';   -- 就近路由
SET tidb_replica_read = 'closest-adaptive';   -- 自适应（负载感知）

-- 2. 单表强制路由 (hint)
SELECT /*+ READ_FROM_STORAGE(TIKV[t1,t2], TIFLASH[t3]) */ 
  t1.a, t2.b, t3.c
FROM t1 JOIN t2 ON t1.id=t2.id JOIN t3 ON t2.x=t3.x;
-- t1, t2 从 TiKV 读；t3 从 TiFlash 列存读

-- 3. 陈旧读 (Stale Read, v5.0+)
-- 基于时间戳
SELECT * FROM orders AS OF TIMESTAMP '2026-04-23 10:00:00';

-- 基于相对时间（推荐）
SELECT * FROM orders AS OF TIMESTAMP NOW() - INTERVAL 5 SECOND;

-- 会话/事务级别
SET TRANSACTION READ ONLY AS OF TIMESTAMP NOW() - INTERVAL 5 SECOND;
BEGIN;
  SELECT * FROM orders;
  SELECT * FROM customers;
COMMIT;

-- 4. 跨区域部署的 follower read
-- 配合 label 约束：
ALTER TABLE orders PLACEMENT POLICY=global_policy;
-- 在每个区域都放一个 follower，就近读本区域

-- 5. TiFlash 列存副本（分析型读写分离）
ALTER TABLE large_table SET TIFLASH REPLICA 2;
-- 创建 2 个 TiFlash 副本，用于 OLAP 查询
-- 优化器会自动选择 TiKV（行存，OLTP）或 TiFlash（列存，OLAP）
```

### Spanner：精确陈旧 vs 有界陈旧

Spanner 的"陈旧读"是商业数据库中最系统化的设计之一。

```python
# Python 客户端 API
from google.cloud import spanner

client = spanner.Client()
instance = client.instance('my-instance')
database = instance.database('my-db')

# 1. 强一致读（Strong Read）：看到所有已提交的写入
with database.snapshot() as snapshot:
    results = snapshot.execute_sql("SELECT * FROM orders")
# 等价：走 Paxos leader，latency ~数十 ms

# 2. 精确陈旧读（Exact Staleness）：读精确时刻的快照
import datetime
with database.snapshot(exact_staleness=datetime.timedelta(seconds=15)) as snapshot:
    results = snapshot.execute_sql("SELECT * FROM orders")
# 读 15 秒前的数据，可以走任意 replica (包括跨区 follower)

# 3. 有界陈旧读（Bounded Staleness）：至多 N 秒陈旧
with database.snapshot(max_staleness=datetime.timedelta(seconds=15)) as snapshot:
    results = snapshot.execute_sql("SELECT * FROM orders")
# 允许 0-15 秒陈旧，Spanner 选最优副本

# 4. 最小读时间戳（Minimum Read Timestamp）
min_read = datetime.datetime.utcnow() - datetime.timedelta(seconds=10)
with database.snapshot(min_read_timestamp=min_read) as snapshot:
    results = snapshot.execute_sql("SELECT * FROM orders")

# 5. 精确读时间戳（Read Timestamp）
specific_time = datetime.datetime(2026, 4, 23, 10, 0, 0)
with database.snapshot(read_timestamp=specific_time) as snapshot:
    results = snapshot.execute_sql("SELECT * FROM orders")
```

```sql
-- SQL 客户端（Spanner CLI）
-- 使用 BEGIN READ ONLY 指定陈旧度
BEGIN READ ONLY WITH MAX_STALENESS 15 SECOND;
  SELECT * FROM orders;
  SELECT * FROM customers;
COMMIT;

BEGIN READ ONLY WITH EXACT_STALENESS 30 SECOND;
  SELECT * FROM orders;
COMMIT;
```

**Spanner 有界陈旧的内部机制**：

```
关键组件：
  1. TrueTime API：返回时间区间 [earliest, latest]，保证真实时间在内
  2. Paxos 组：每个数据 tablet 有一个 Paxos 组（leader + replicas）
  3. Safe Timestamp：每个副本维护的"可安全读的最大时间戳"
     safe_ts = min(paxos_safe_ts, lock_safe_ts)
  4. 读路由决策：
     - Strong read: 走 leader (可能需跨区)
     - Bounded staleness: 客户端选择 safe_ts 最新 + 地理最近的副本
     - Exact staleness: 精确 ts 必须 <= 副本的 safe_ts

性能对比：
  Strong read (跨区)：100-200 ms
  Bounded staleness 15s (本地副本)：5-10 ms
  吞吐差距：10-20 倍
```

### DynamoDB：ConsistentRead 参数与 Global Tables

DynamoDB 的副本路由非常简化——只有两个选项：

```python
import boto3
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('orders')

# 1. 最终一致读（默认）：从任意副本读，可能返回 1 秒前的数据
response = table.get_item(Key={'order_id': '123'})
# 或
response = table.get_item(Key={'order_id': '123'}, ConsistentRead=False)

# 2. 强一致读：从主副本读，保证最新
response = table.get_item(Key={'order_id': '123'}, ConsistentRead=True)
# 代价：延迟 2 倍，成本 (RCU) 2 倍

# 3. Global Tables 跨区域读
# 假设表已配置在 us-east-1, eu-west-1, ap-southeast-1 三地
# 各区域的客户端就近读本地副本
east_client = boto3.resource('dynamodb', region_name='us-east-1')
west_client = boto3.resource('dynamodb', region_name='eu-west-1')

east_table = east_client.Table('orders')
west_table = west_client.Table('orders')

# 写入 us-east-1，异步复制到 eu-west-1 (秒级)
east_table.put_item(Item={'order_id': '456', 'amount': 100})

# 立即从 eu-west-1 读可能看不到 (最终一致，跨区复制延迟 ~1s)
response = west_table.get_item(Key={'order_id': '456'})
# 几秒后可以看到

# 4. DAX (DynamoDB Accelerator) 做缓存读
# DAX 是前置缓存层，提供微秒级读延迟，但牺牲强一致
dax_client = amazondax.AmazonDaxClient.resource(endpoint_url='dax-cluster:8111')
dax_table = dax_client.Table('orders')
dax_table.get_item(Key={'order_id': '123'})   # 从 DAX 缓存读
```

**DynamoDB Global Tables 的有界陈旧特征**：

```
复制模式：Last Write Wins (LWW) + 向量时钟
跨区域延迟：< 1 秒（p50），可能 2-5 秒（尖峰）
冲突处理：根据写入时间戳保留最新（可能丢失并发写）
读路由：客户端 SDK 默认读本地区域副本
ConsistentRead 在 Global Tables 中只对本区域主副本生效
```

### SAP HANA System Replication

```sql
-- 主库查询复制状态
SELECT * FROM SYS.M_SERVICE_REPLICATION;

-- 启用活跃/活跃 (Active/Active) 只读访问
-- 在 Secondary 上直接接受只读查询
-- Secondary 必须是 logreplay_readaccess 模式

-- 客户端连接时的路由提示
-- JDBC URL:
-- jdbc:sap://primary:30015/?databaseName=HDB&splitBatchCommands=true
--   &distribution=all                        -- 客户端分发
--   &connectionTimeout=5000

-- ODBC:
-- DRIVER={HDBODBC};SERVERNODE=primary:30015;CURRENTSCHEMA=SCHEMA;
--   ACCESSMODE=readonly                      -- 只读会话

-- 会话 Hint
SELECT /*+ RESULT_CACHE */ * FROM orders;    -- 启用结果缓存
SELECT /*+ IGNORE_PLAN_CACHE */ * FROM orders;

-- 陈旧度控制（通过会话变量）
SET 'REPLICATION_DELAY_SLA' = '30';   -- 单位秒
-- 如果从库延迟 > 30s，查询报错或回退主库
```

### YugabyteDB Follower Reads

```sql
-- 会话级别启用 follower reads
SET session characteristics as transaction read only;
SET yb_read_from_followers = true;

-- 设置陈旧度（毫秒）
SET yb_follower_read_staleness_ms = 30000;   -- 30 秒

-- 查询
SELECT * FROM orders;   -- 路由到最近的 follower（就近读）

-- tserver flag 级别控制（DBA）
-- --yb_enable_read_committed_isolation=true
-- --yb_follower_reads_behavior_before_fixing_20482=0

-- 基于 tablet 级 preference 控制副本选择
-- yb_admin set_tablet_replicas_preference "us-east:1,us-west:2"

-- 典型用例：分析查询
BEGIN ISOLATION LEVEL SERIALIZABLE READ ONLY;
SET yb_read_from_followers = true;
SET yb_follower_read_staleness_ms = 60000;

SELECT COUNT(*), AVG(amount) FROM orders
WHERE created_at > NOW() - INTERVAL '1 hour';

COMMIT;
```

### ClickHouse：Replicated Tables + Distributed Routing

```sql
-- ClickHouse 的副本是对等的（multi-leader），无严格主从概念
-- 1. 创建 Replicated 表
CREATE TABLE events ON CLUSTER 'my_cluster' (
    event_id UInt64,
    timestamp DateTime,
    data String
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/events', '{replica}')
ORDER BY event_id;

-- 2. Distributed 表做路由
CREATE TABLE events_distributed AS events
ENGINE = Distributed('my_cluster', default, events, rand());

-- 3. 查询时的负载均衡设置
SET load_balancing = 'random';               -- 随机选副本（默认）
SET load_balancing = 'nearest_hostname';     -- 选最近副本
SET load_balancing = 'in_order';             -- 固定顺序
SET load_balancing = 'first_or_random';      -- 首选第一个，失败则随机
SET load_balancing = 'round_robin';          -- 轮询

-- 4. 控制陈旧度
SET max_replica_delay_for_distributed_queries = 300;  -- 单位秒
-- 延迟超过 300s 的副本不参与查询

SET fallback_to_stale_replicas_for_distributed_queries = 1;
-- 所有副本都陈旧时，仍允许查询（默认 1）

-- 5. 跨副本一致性读（选主模式）
SET insert_quorum = 2;           -- 写入需要 2 副本确认
SET select_sequential_consistency = 1;  -- 读必须看到自己的写
```

### Aurora Reader Endpoint

```python
# Aurora 提供两个 endpoint：
#   Writer endpoint:  mydb-cluster.cluster-abc.us-east-1.rds.amazonaws.com
#   Reader endpoint:  mydb-cluster.cluster-ro-abc.us-east-1.rds.amazonaws.com

# Reader endpoint 自动负载均衡到所有 reader 实例
# DNS 级别轮询 (TTL 5s)，连接粘性因此有限

import psycopg2

# 写连接
write_conn = psycopg2.connect(
    host='mydb-cluster.cluster-abc.us-east-1.rds.amazonaws.com',
    database='mydb', user='admin')

# 读连接（负载均衡到任意 reader）
read_conn = psycopg2.connect(
    host='mydb-cluster.cluster-ro-abc.us-east-1.rds.amazonaws.com',
    database='mydb', user='admin')

# 应用层选择：
with write_conn.cursor() as cur:
    cur.execute("INSERT INTO orders ...")
    write_conn.commit()

with read_conn.cursor() as cur:
    cur.execute("SELECT * FROM orders WHERE ...")
```

**AWS JDBC Wrapper for Aurora**：

```
# jdbc:aws-wrapper:postgresql://cluster-endpoint/db
# 支持插件式读写分离、快速故障切换、读连接池

spring.datasource.url=jdbc:aws-wrapper:postgresql://cluster-ro:5432/db
spring.datasource.driver-class-name=software.amazon.jdbc.Driver

# 插件列表
wrapperPlugins=readWriteSplitting,failover,efm2
```

### Databricks Delta：SQL Warehouse 的读从副本

```sql
-- Databricks 的副本路由基于 SQL Warehouse 和会话 hint
SET spark.databricks.delta.readFrom = 'secondary';
-- 从只读副本读（需要配置 Delta Sharing / Mirror）

-- Serverless SQL Warehouse 自动扩展只读副本
-- 路由由平台管理，用户无感

-- 陈旧度控制：通过读 Delta 表的历史版本
SELECT * FROM orders VERSION AS OF 12345;
SELECT * FROM orders TIMESTAMP AS OF '2026-04-23 10:00:00';
-- 这是 time travel 语义，不是副本路由
```

## 各路由机制的对比分析

### 服务端 vs 客户端 vs 驱动层路由

| 维度 | 服务端路由 | 客户端路由 | 驱动层路由 |
|------|----------|----------|----------|
| 透明度 | 最高（应用无感） | 最低（需改应用） | 中（配置级） |
| 路由粒度 | 按会话/连接 | 按查询 | 按会话 |
| 拓扑变化 | 服务端自动适配 | 客户端需重配 | 驱动感知 |
| 代表引擎 | CockroachDB / Spanner / TiDB | Oracle `/*+ HINT */` / CockroachDB `AOST` | MySQL Connector/J / Oracle TNS |
| 外置依赖 | 无 | 无 | 无 |
| 运维成本 | 低 | 最低 | 中 |
| 灵活度 | 中 | 最高 | 中 |

### 主读 vs 从读 vs 有界陈旧

**强一致读（主读）**：
- 保证：读到所有已提交的写入
- 代价：可能跨区访问 leaseholder，延迟高
- 适用：金融交易、订单状态查询

**从读（最终一致）**：
- 保证：读到某个历史时刻的快照
- 代价：数据陈旧（几毫秒到几秒）
- 适用：报表、热度排行、配置查询

**有界陈旧读（Bounded Staleness）**：
- 保证：读到的数据陈旧度不超过 N 秒
- 代价：无（本地副本通常满足）
- 适用：分析查询、日志搜索、产品目录

### 读己所写（RYW）实现机制对比

| 机制 | 原理 | 代表引擎 | 陷阱 |
|------|------|--------|------|
| 会话粘性 | 同一会话的读写落在同一节点 | MaxScale / pgpool-II | 跨会话失效（如刷新浏览器） |
| GTID / LSN 等待 | 读前等待从库追上主库进度 | MySQL `WAIT_FOR_GTID` / PG `pg_wal_replay_wait` | 读延迟增加 |
| 同步复制 | 写操作等待副本确认 | Oracle SYNC / SQL Server SYNC | 写吞吐下降 |
| 时间戳跟踪 | 客户端记录最后写入时间戳 | Spanner / DynamoDB | 客户端复杂度 |
| 一致性级别 | 按 session 的一致性承诺 | Cosmos DB Session | 跨 session 需手动 |

### 复制延迟的量化

```
同机房内（同 VPC）:
  异步复制：5-50 ms
  半同步复制：20-100 ms（等待至少一个副本）
  全同步复制：50-200 ms

跨可用区（同 region）:
  异步复制：10-100 ms
  同步复制：20-200 ms

跨区域:
  异步复制：50 ms（同洲）- 200 ms（跨洲）
  同步复制（仅 Spanner 等支持）：100-300 ms

副本落后主库的典型场景：
  - 批量写入（大事务）：副本追赶时间可达几分钟
  - 网络抖动：秒级波峰
  - 副本重启后恢复：分钟级
```

## 设计争议

### 从库读是否破坏事务隔离

在一个事务中交替读主/读从可能违反事务的快照一致性：

```sql
-- 反例：同一事务中的两次读结果不一致
BEGIN;
  SELECT * FROM orders WHERE id = 1;   -- 主库：status = 'pending'
  -- 另一事务 UPDATE 并提交：status = 'shipped'
  SELECT * FROM orders WHERE id = 1;   -- 从库：可能还是 'pending' 或已变 'shipped'
COMMIT;
```

**解决方案**：
- **CockroachDB**：事务内的读要么全走 leaseholder，要么全走 follower（不能混）
- **Spanner**：read-only 事务使用单一读时间戳，所有副本返回该时间戳的快照
- **TiDB**：Follower Read 使用事务开始时的 TSO，保证快照一致
- **MySQL/PostgreSQL**：靠代理层策略（pgpool: 事务内不路由到从库）

### 关闭时间戳 (Closed Timestamp) 的推进策略

CockroachDB、TiDB、YugabyteDB 等都使用类似概念，但推进策略各异：

```
CockroachDB:
  - Leaseholder 每 200ms 广播一次关闭时间戳
  - 关闭时间戳 = now - 3s (target_duration)
  - 慢 range 会阻塞关闭时间戳推进（gossip 降级）

TiDB:
  - PD 维护全局 TSO + 每 tablet 的 safe_ts
  - safe_ts = max(resolved_ts, ingest_ts)
  - Stale Read 使用 safe_ts 判断本地可读性

YugabyteDB:
  - Hybrid Logical Clock (HLC) + read time
  - 读请求携带 hybrid time，副本判断自己是否追上

Spanner:
  - 基于 TrueTime 和 Paxos 的 safe_time
  - safe_time = min(paxos_safe_time, lock_safe_time)
  - 全球时钟同步使推进更保守但更安全
```

### 读热点问题

副本读不是银弹，热点数据可能让某个 follower 过载：

```
场景：一个热门商品的 SKU 信息
  - 所有区域的用户都在查询
  - 该 range 的 3 个副本（每区域一个）
  - 默认"就近路由"让每个副本承受本区域的全部流量

解决方案：
  1. CockroachDB Global Tables：每个区域都有 leaseholder，写延迟高但读完全本地
  2. TiDB Placement Rules：增加副本数到 5 或 7
  3. 应用层缓存（Redis / DAX / Memcached）
  4. 路由层 consistent hashing，避免单副本热
```

### 会话粘性的失效

许多基于会话的路由（MaxScale、pgpool-II）在以下场景失效：

```
1. 连接池场景：
   - Web 请求 A 拿到 conn1，写入
   - 请求 A 释放 conn1 回到池
   - 请求 B 拿到 conn1，可能走到不同从库的连接
   - 结果：A 的写未同步到 B 读的从库 → 用户看不到自己的写

2. 长轮询场景：
   - 用户提交评论后，浏览器发起 WebSocket 订阅
   - WebSocket 与原 HTTP 连接在不同会话
   - 订阅走的从库可能未同步评论

3. 跨区域请求：
   - 用户在东京写入（路由到东京主库）
   - 用户 3 秒后切换到移动网络，IP 变为香港
   - 新请求走香港从库，香港从库还没收到 binlog
```

**正确做法**：使用 GTID/LSN 追踪 + 应用层显式等待，或切换到"最终一致"设计（评论框写入后本地乐观显示，不依赖立即读到）。

## 对引擎开发者的实现建议

### 1. 关闭时间戳推进

```
核心组件：
  ClosedTimestampTracker {
      range_id: RangeId
      leaseholder_id: NodeId
      target_duration: Duration        // 例如 3s
      current_closed_ts: HybridTime   
      pending_requests: Vec<Request>   // 未完成的写

      fn tick():                      // 每 200ms 调用
          now = clock.now()
          target_ct = now - target_duration
          max_safe = self.compute_safe_timestamp(target_ct)
          if max_safe > current_closed_ts:
              current_closed_ts = max_safe
              self.broadcast_to_followers(current_closed_ts)

      fn compute_safe_timestamp(target) -> HybridTime:
          // 所有 pending 写的最小时间戳
          min_pending = self.pending_requests.iter().map(|r| r.ts).min()
          return min(target, min_pending - 1ns)
  }

  FollowerReadValidator {
      fn can_read_at(&self, ts: HybridTime) -> bool:
          return ts <= self.current_closed_ts
  }
```

要点：
- 关闭时间戳必须小于等于所有未完成写的时间戳
- 推进越快（target_duration 越小），follower reads 陈旧度越低
- 网络分区时暂停推进而非误报

### 2. 陈旧度约束验证

```
StalenessPolicy {
    MaxStaleness(Duration),              // 至多 N 秒陈旧
    MinTimestamp(HybridTime),            // 不早于指定时间戳
    ExactStaleness(Duration),            // 精确 N 秒陈旧（用于可复现）
    Strong,                              // 强一致
}

fn route_read(query, policy) -> Replica:
    match policy:
        Strong => leaseholder()
        ExactStaleness(d) => {
            target_ts = clock.now() - d
            // 选择关闭时间戳 >= target_ts 的最近副本
            closest_replica_with_ct(target_ts)
        }
        MaxStaleness(d) => {
            min_allowed_ts = clock.now() - d
            // 优先本地副本；若本地副本太陈旧，回退 leaseholder
            if local_replica.ct >= min_allowed_ts:
                local_replica
            else:
                leaseholder()
        }
        MinTimestamp(ts) => {
            // 选择 ct >= ts 的副本；若无，阻塞等待
            pick_or_wait(replicas, |r| r.ct >= ts)
        }
```

### 3. 复制延迟监控

```
副本健康度指标（必须暴露给路由器）：
  - replication_lag_seconds        // 副本相对主库落后秒数
  - closed_timestamp_lag_seconds   // 关闭时间戳落后当前时间秒数
  - raft_log_index_lag             // Raft/Paxos 日志落后条数
  - last_heartbeat_time            // 最后心跳时间

路由决策中的健康度检查：
  fn select_replica(replicas, policy) -> Replica:
      eligible = replicas
          .filter(|r| r.is_alive())
          .filter(|r| r.replication_lag < policy.max_lag)
          .filter(|r| r.closed_ts >= policy.min_ts)
      if eligible.empty():
          return fallback_to_leader()
      return eligible.min_by_key(|r| r.rtt_ms)
```

### 4. 事务内的一致性保证

```
事务开始时记录快照时间戳，事务内所有读使用该时间戳：

TxnContext {
    snapshot_ts: HybridTime,
    replica_pinning: Option<ReplicaId>,   // 一旦选定就粘住
}

fn transactional_read(txn, key) -> Row:
    // 第一次读时选择副本
    if txn.replica_pinning.is_none():
        txn.replica_pinning = Some(select_replica_with_ct(txn.snapshot_ts))

    // 后续读保持粘性
    replica = cluster.get(txn.replica_pinning.unwrap())
    return replica.read_at(key, txn.snapshot_ts)
```

要点：
- 事务期间不可切换副本（即使原副本变慢）
- 快照时间戳由事务开始时确定，整个事务期间不变
- 只读事务（READ ONLY）可在 follower 上执行；读写事务必须在 leader

### 5. 路由器的故障转移

```
Leaseholder 故障时：
  1. 检测：follower 发现 leaseholder 心跳超时
  2. 选举：Raft 触发新一轮选举
  3. 路由表更新：路由器订阅 range 元数据变更
  4. 重试：失败的查询自动切换到新 leaseholder
  5. 客户端无感：retry 在 SDK 内部完成

副本故障时：
  1. 健康检查：路由器定期 ping 副本
  2. 摘除：连续 3 次心跳失败即从路由池移除
  3. 降级：所有副本故障时回退 leaseholder
  4. 恢复：副本恢复后重新加入路由池

脑裂场景：
  1. 两个节点都自认为 leaseholder
  2. 使用 lease expiration + clock skew 上界防止
  3. 任何 leaseholder 的 lease 过期前必须续约或放弃
```

### 6. 跨区域路由的延迟优化

```
策略 1：基于 RTT 的就近路由
  client.locality = "us-east1-b"
  for each range:
      replicas = range.replicas
      nearest = replicas.min_by_key(|r| rtt(client.locality, r.locality))

策略 2：基于 locality affinity
  在创建表时声明：
    CREATE TABLE users (...) LOCALITY REGIONAL BY ROW;
  数据根据行的 region 属性存储在该区域的副本

策略 3：Global Tables
  所有区域都有 leaseholder，写延迟高（需全球 Paxos 确认）
  读可完全本地化
  适合"一次写多次读"的全球数据（配置表、菜单、SKU）
```

### 7. 负载均衡算法

```
副本路由中常见的算法：

1. Round Robin:
   for each request:
       replica = replicas[counter++ % len(replicas)]

2. Random:
   replica = replicas[rand() % len(replicas)]

3. Least Connections:
   replica = replicas.min_by_key(|r| r.active_connections)

4. Weighted Round Robin (按副本性能):
   weights = [r.cpu_capacity for r in replicas]
   replica = weighted_choice(replicas, weights)

5. Consistent Hashing (避免热点):
   replica_idx = hash(query_key) % len(replicas)
   replica = replicas[replica_idx]

6. Latency-Aware:
   replica = replicas.min_by_key(|r| alpha * r.rtt + beta * r.load)
```

### 8. 读写分离中的陷阱清单

```
陷阱 1：INSERT ... RETURNING 的路由
  - SQL Server: SELECT ... OUTPUT INSERTED 是 INSERT → 主库
  - PostgreSQL: INSERT ... RETURNING 也是写操作
  - 路由器必须正确识别这些混合语句

陷阱 2：存储过程内的读
  - 存储过程可能先写后读
  - 整个调用必须走主库（过程内部路由无法拆分）

陷阱 3：CTE 内的写
  WITH updated AS (UPDATE ... RETURNING *)
  SELECT * FROM updated;
  - 整个查询必须走主库

陷阱 4：自增序列
  - nextval() 修改序列状态 → 必须主库
  - currval() 读会话状态 → 可以从库但要求连接粘性

陷阱 5：临时表
  - CREATE TEMP TABLE 在从库可能失败（只读副本）
  - 应用逻辑必须避免在只读连接上创建临时表

陷阱 6：LOCK / SELECT FOR UPDATE
  - 必须在主库上加锁
  - 路由器必须识别 FOR UPDATE / FOR SHARE

陷阱 7：读自己的 DDL
  - ALTER TABLE 后立即 SELECT 元数据
  - 从库的 schema 可能还未同步
```

## 总结对比矩阵

### 路由能力总览（主流引擎）

| 能力 | PostgreSQL | MySQL | Oracle | SQL Server | CockroachDB | TiDB | Spanner | DynamoDB |
|------|-----------|-------|--------|------------|-------------|------|---------|----------|
| 内置读写分离 | -- | -- | Active Data Guard | AlwaysOn | 是 | 是 | 是 | N/A |
| 外置代理成熟度 | pgpool-II / pgcat | ProxySQL / MaxScale | Connection Manager | -- | -- | TiProxy | -- | DAX |
| 从从读 | 流复制 standby | binlog slaves | ADG reader | AG readable secondary | Follower Reads | Follower Read | Read Replicas | Global Tables |
| 有界陈旧读 | 手动 LSN | 手动 GTID | SCN delay | 同步模式 | `with_max_staleness` | AS OF TIMESTAMP | `max_staleness` | N/A |
| 读己所写 | 同步流复制 | GTID 等待 | Data Guard SYNC | 同步提交 AG | 默认主 | 强一致事务 | Strong read | `ConsistentRead` |
| Follower Reads | -- | -- | -- | -- | 原生 | 原生 | Stale Read | N/A |
| 跨区域路由 | 需外置 | 需外置 | 是 | Listener MultiSubnet | Locality | Locality | 全球 | Global Tables |
| 会话粘性 | pgpool | MaxScale | TNS | Listener | 自动 | 自动 | 自动 | SDK |

### 引擎选型建议

| 场景 | 推荐引擎/方法 | 原因 |
|------|-------------|------|
| 传统 OLTP + 读扩展 | Oracle ADG / SQL Server AlwaysOn | 成熟的内置方案，RYW 保证 |
| 云原生读扩展 | Aurora / Azure SQL Read Scale | Endpoint 级路由，运维简单 |
| 全球分布 OLTP | Spanner / CockroachDB | 原生 follower reads + bounded staleness |
| HTAP 混合负载 | TiDB + TiFlash | 行存 OLTP + 列存 OLAP 分离 |
| 已有 MySQL 架构 | ProxySQL / MaxScale | 成熟代理，GTID 追踪 |
| 已有 PostgreSQL 架构 | pgpool-II / pgbouncer + RYW 逻辑 | 自动路由 + LSN 等待 |
| KV 全球读 | DynamoDB Global Tables + DAX | 最终一致 + 缓存 |
| 列存分析 | ClickHouse Distributed | Replicated 表 + 负载均衡 |
| 文档模型 + 多档一致 | Cosmos DB | 5 档一致性的精细控制 |

## 关键发现（Key Findings）

1. **没有 SQL 标准**：45+ 年 SQL 标准史上从未定义副本路由语法。每个引擎的 `/*+ HINT */`、`AS OF SYSTEM TIME`、`ConsistentRead`、`ApplicationIntent` 都是独立发明，互不兼容。

2. **MySQL 和 PostgreSQL 依然依赖外置代理**：核心引擎从未把读写分离做进服务端。ProxySQL、MaxScale、pgpool-II、pgcat 是事实标准。这是分布式数据库（CockroachDB、TiDB、Spanner）相对传统关系库的核心差异化能力之一。

3. **Follower Reads 是现代分布式 SQL 的分水岭**：CockroachDB (2019)、TiDB (2020)、YugabyteDB 的 follower reads 基于"关闭时间戳"机制，让只读查询可以在任意副本本地执行，彻底解耦读和 Raft leader。这是 Google Spanner 设计思想的大规模落地。

4. **关闭时间戳的典型值 ~3 秒**：CockroachDB 的 `follower_read_timestamp()` 返回当前时间减约 3.9 秒。Spanner 的 bounded staleness 默认 15 秒。这个"几秒"的陈旧度窗口是工程学权衡的结果：小于 1 秒需要极精确的时钟同步，大于 30 秒则失去业务价值。

5. **Spanner 是陈旧读能力最丰富的引擎**：提供 exact staleness、bounded staleness、min read timestamp、read timestamp 等 5 种模式，远超其他引擎。这是 Google TrueTime 硬件时钟基础设施的直接受益。

6. **DynamoDB 的 ConsistentRead 是最简化的接口**：只有 true/false 两个值，`true` 强一致、`false` 最终一致（可能陈旧 1 秒）。设计上的极简主义反而让 API 容易正确使用。

7. **读己所写（RYW）是一致性语义中最被低估的**：在复制架构下保证 RYW 需要 GTID/LSN 追踪、同步复制或会话粘性——但这三种方案都有缺陷。真正的全球 RYW 在工程上极难实现，通常靠应用层乐观 UI 绕过。

8. **AS OF SYSTEM TIME 的时间旅行属性**：CockroachDB 和 TiDB 把 follower reads 建立在时间旅行查询（time travel query）之上。`AS OF TIMESTAMP '2026-04-23 10:00:00'` 既是历史查询，又是 follower routing 的触发条件。这种语义统一是设计上的精妙之处。

9. **Global Tables 牺牲写延迟换读本地化**：CockroachDB Global Tables、Spanner GLOBAL 表、DynamoDB Global Tables 都基于同一思路——把 leaseholder 分布到所有区域，代价是写操作的跨区延迟。适合"写少读多"的全球数据（产品目录、配置）。

10. **读写分离的本质是 CAP 权衡**：强一致读（主）= CP，从从读 = AP，bounded staleness = 接近 AP 但有延迟上界。现代引擎的进步在于让应用按查询粒度（而非系统级）选择权衡。

## 参考资料

- PostgreSQL: [Hot Standby](https://www.postgresql.org/docs/current/hot-standby.html)
- PostgreSQL: [target_session_attrs](https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNECT-TARGET-SESSION-ATTRS)
- MySQL: [Connector/J Replication](https://dev.mysql.com/doc/connector-j/en/connector-j-master-slave-replication-connection.html)
- ProxySQL: [Query Rules](https://proxysql.com/documentation/main-runtime/#mysql_query_rules)
- MariaDB MaxScale: [Read-Write Split Router](https://mariadb.com/kb/en/mariadb-maxscale-25-readwritesplit/)
- Oracle: [Active Data Guard Reader Farm](https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/)
- SQL Server: [AlwaysOn Read-Only Routing](https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/configure-read-only-routing-for-an-availability-group)
- CockroachDB: [Follower Reads](https://www.cockroachlabs.com/docs/stable/follower-reads.html)
- CockroachDB: [AS OF SYSTEM TIME](https://www.cockroachlabs.com/docs/stable/as-of-system-time.html)
- CockroachDB: [Closed Timestamp](https://www.cockroachlabs.com/blog/consensus-made-thrive/)
- TiDB: [Follower Read](https://docs.pingcap.com/tidb/stable/follower-read)
- TiDB: [Stale Read](https://docs.pingcap.com/tidb/stable/stale-read)
- YugabyteDB: [Follower Reads](https://docs.yugabyte.com/preview/develop/build-global-apps/follower-reads/)
- Google Spanner: [Timestamp Bounds](https://cloud.google.com/spanner/docs/timestamp-bounds)
- Google Spanner: [Read-Only Transactions](https://cloud.google.com/spanner/docs/reads)
- DynamoDB: [Read Consistency](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/HowItWorks.ReadConsistency.html)
- DynamoDB: [Global Tables](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html)
- Cosmos DB: [Consistency Levels](https://learn.microsoft.com/en-us/azure/cosmos-db/consistency-levels)
- Aurora: [Reader Endpoint](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Overview.Endpoints.html)
- Azure SQL: [Read Scale-Out](https://learn.microsoft.com/en-us/azure/azure-sql/database/read-scale-out)
- ClickHouse: [load_balancing](https://clickhouse.com/docs/en/operations/settings/settings#load_balancing)
- SAP HANA: [System Replication](https://help.sap.com/docs/SAP_HANA_PLATFORM/4e9b18c116aa42fc84c7dbfd02111aba/b74e16a9e09541749a745f41246a065e.html)
- Corbett, J.C. et al. "Spanner: Google's Globally-Distributed Database" (OSDI 2012)
- Taft, R. et al. "CockroachDB: The Resilient Geo-Distributed SQL Database" (SIGMOD 2020)
