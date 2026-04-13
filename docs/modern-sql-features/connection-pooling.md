# 连接池与会话管理 (Connection Pooling and Session Multiplexing)

一条 PostgreSQL 连接占 ~10MB 内存、需要 fork 一个进程，1 万个空闲连接就吃掉 100GB——连接池不是优化项，而是生产数据库的生存线。本文系统对比 49 个数据库引擎的连接管理模型、内置/外置池、多路复用能力与会话语义，覆盖 PgBouncer、ProxySQL、MySQL Router、pgcat、Supavisor 等关键组件。

## 为什么连接池如此关键

数据库连接的"贵"体现在三个层面：

1. **建立成本**：TCP 三次握手 + TLS 握手（10ms 级）+ 认证（密码/SCRAM/Kerberos）+ 会话初始化（设置时区、字符集、加载角色权限），冷连接建立动辄百毫秒。
2. **进程/线程成本**：PostgreSQL 每个连接 fork 一个 OS 进程，启动开销 ~1ms，常驻内存 ~10MB（含共享缓冲区映射、catalog cache、plan cache）。Oracle 专用服务器模式同理。
3. **并发瓶颈**：超过 CPU 核数 2-4 倍的活跃连接会引发上下文切换风暴和锁竞争，PostgreSQL 在 200+ 活跃连接后吞吐反向下降。

应用侧的连接池（HikariCP、c3p0、SQLAlchemy QueuePool、psycopg2.pool 等）解决"建立成本"，但解决不了"每个 Web 进程 × 副本数 × max-pool-size = 数千连接"造成的"进程/线程成本"问题。这才是 PgBouncer、ProxySQL、Supavisor 这一代外置池存在的理由。

## 没有 SQL 标准章节

ISO/IEC SQL 标准只规范"会话"（session）的语义边界（`SET SESSION`、事务隔离级别等），完全不规范连接的建立、复用、池化机制。这一切都是实现层和客户端库的领域。本文因此直接进入实现矩阵。

会话级 `SET` 语法的标准化对比，参见姊妹文章 [variables-sessions.md](variables-sessions.md)。本文聚焦"连接"和"复用"，而不是"会话变量"。

## 支持矩阵

### 1. 连接模型（进程 / 线程 / 协程）

| 引擎 | 模型 | 单连接近似内存 | 备注 |
|------|------|---------------|------|
| PostgreSQL | 进程 (fork) | ~10 MB | postmaster fork backend |
| MySQL | 线程 | ~256 KB - 数 MB | one-thread-per-connection |
| MariaDB | 线程 / 线程池插件 | ~256 KB | thread_pool 插件可用 |
| SQLite | 嵌入式 (无网络) | -- | 不存在连接概念 |
| Oracle | 进程 (专用) / 线程 (共享) | 4-15 MB / 较少 | Dedicated vs Shared Server |
| SQL Server | 线程 (内置池) | ~512 KB | UMS / SQLOS 调度 |
| DB2 | 进程或线程 (可配置) | 数 MB | DB2_THREAD_BASED |
| Snowflake | 无状态 (SaaS) | 客户端虚拟连接 | 服务端无 1:1 进程 |
| BigQuery | 无状态 REST/gRPC | 不适用 | 每查询独立 |
| Redshift | 进程 (PG fork) | ~10 MB | 继承 PostgreSQL |
| DuckDB | 嵌入式 / 线程 | -- | 同进程多连接对象 |
| ClickHouse | 线程 + 长连接 TCP | ~1 MB | HTTP 也支持 |
| Trino | 线程 (HTTP/REST) | 较低 | Coordinator 路由 |
| Presto | 线程 (HTTP/REST) | 较低 | 同 Trino |
| Spark SQL | JVM 线程 (Thrift Server) | ~JVM | STS 多用户共享 |
| Hive | JVM 线程 (HiveServer2) | ~JVM | 类似 STS |
| Flink SQL | JVM (SQL Gateway / SQL Client) | ~JVM | 流式不显式连接 |
| Databricks | SaaS / Spark Thrift | 不适用 | SQL Warehouse 复用 |
| Teradata | AMP/PE 进程 | 较高 | parsing engine 池 |
| Greenplum | 进程 (PG fork) | ~15 MB | master + segments |
| CockroachDB | Goroutine (Go) | 数 KB | 内置 SQL 层池 |
| TiDB | Goroutine (Go) | 数 KB | tidb-server 无状态 |
| OceanBase | 线程 / 协程 | ~MB | observer 多租户 |
| YugabyteDB | 进程 (PG fork) | ~10 MB | YSQL 继承 PG |
| SingleStore | 线程 | 较低 | C++ 引擎 |
| Vertica | 线程 | 数 MB | session per thread |
| Impala | 线程 (impalad) | 数 MB | C++ daemon |
| StarRocks | 线程 (FE) + BE | 较低 | FE Java, BE C++ |
| Doris | 线程 (FE) + BE | 较低 | 同 StarRocks |
| MonetDB | 进程或线程 | 数 MB | mserver5 |
| CrateDB | JVM 线程 | ~JVM | HTTP / PG wire |
| TimescaleDB | 进程 (PG fork) | ~10 MB | 继承 PG |
| QuestDB | 线程 (Java) | 较低 | 内置 PG wire |
| Exasol | 线程 | 较低 | 集群节点 |
| SAP HANA | 线程 (内置池) | 较低 | indexserver |
| Informix | 进程或线程 (DSA) | 可调 | Virtual Processors |
| Firebird | 进程 / SuperServer 线程 | 可调 | Classic / Super 架构 |
| H2 | JVM 内嵌 / TCP | ~JVM | 同 JVM 直连 |
| HSQLDB | JVM 内嵌 / TCP | ~JVM | -- |
| Derby | JVM 内嵌 / Network Server | ~JVM | -- |
| Amazon Athena | 无状态 REST | 不适用 | 同 BigQuery 模型 |
| Azure Synapse | 线程 (SQL Server 内核) | ~512 KB | -- |
| Google Spanner | 无状态 gRPC | 不适用 | 客户端 session pool |
| Materialize | 进程 (PG fork) | ~10 MB | PG wire 兼容 |
| RisingWave | 线程 (Rust) | 较低 | PG wire 兼容 |
| InfluxDB (SQL/IOx) | 异步 Rust | 较低 | Tokio 任务 |
| DatabendDB | 异步 Rust | 较低 | HTTP / MySQL wire |
| Yellowbrick | 进程 (PG fork) | ~10 MB | PG 兼容 |
| Firebolt | 无状态 REST/JDBC | 不适用 | 引擎弹性伸缩 |

> 统计：进程模型 ~13 个，线程模型 ~22 个，协程/异步 ~5 个，无状态 SaaS ~5 个，嵌入式 ~5 个。

### 2. 内置服务端连接池 / 线程池

| 引擎 | 内置池 | 模式 | 备注 |
|------|--------|------|------|
| PostgreSQL | 否 | 1:1 进程 | 必须用 PgBouncer/pgcat |
| MySQL | 部分 (thread_cache_size) | 仅复用线程对象 | 不复用会话 |
| MariaDB | 是 (thread pool 插件) | 任务调度 | 类 SQL Server |
| Oracle | 是 (Shared Server) | dispatcher + shared server | MTS |
| Oracle | 是 (DRCP) | Database Resident Connection Pool | 11g+ |
| SQL Server | 是 (SQLOS) | 协作式调度 | max worker threads |
| DB2 | 是 (Connection Concentrator) | dispatcher 模型 | -- |
| Snowflake | N/A | SaaS 透明 | -- |
| Redshift | 否 | 继承 PG | -- |
| ClickHouse | 是 | 线程池 | max_thread_pool_size |
| Trino | 是 | HTTP 工作线程池 | -- |
| Spark SQL (STS) | 是 | session 共享 SparkContext | -- |
| Hive (HS2) | 是 | session 共享 | -- |
| CockroachDB | 是 | Go 调度 | 内置 |
| TiDB | 是 | Go 调度 | 内置 |
| OceanBase | 是 (租户线程池) | -- | -- |
| YugabyteDB | 否 (YSQL) / 是 (YCQL) | YSQL 同 PG | -- |
| SAP HANA | 是 | -- | -- |
| Informix | 是 (DSA) | virtual processors | -- |
| Vertica | 是 (resource pool) | 资源池非连接池 | -- |
| Greenplum | 否 (PG) | 同 PG | -- |
| Materialize | 否 | 同 PG | -- |

### 3. 外置连接池 / 代理

| 引擎 | 主流外置池 | 协议层 | 备注 |
|------|-----------|--------|------|
| PostgreSQL | PgBouncer | PG wire | 最经典 |
| PostgreSQL | pgcat | PG wire | Rust，分片+池化 |
| PostgreSQL | Supavisor | PG wire | Elixir，百万级连接 |
| PostgreSQL | Odyssey | PG wire | Yandex |
| PostgreSQL | pgpool-II | PG wire | 池化 + 复制路由 |
| PostgreSQL | RDS Proxy | PG wire | AWS 托管 |
| MySQL | ProxySQL | MySQL wire | 最流行 |
| MySQL | MySQL Router | MySQL wire | 官方 (InnoDB Cluster) |
| MySQL | MaxScale | MySQL wire | MariaDB 出品 |
| MySQL | RDS Proxy | MySQL wire | AWS 托管 |
| MariaDB | MaxScale / ProxySQL | MySQL wire | -- |
| Oracle | Oracle Connection Manager (CMAN) | TNS | 官方 |
| SQL Server | 应用侧 .NET 池 | TDS | 通常应用侧 |
| DB2 | DB2 Connect Gateway | DRDA | -- |
| ClickHouse | chproxy | HTTP | -- |
| Trino | -- | -- | 通过 coordinator |
| CockroachDB | PgBouncer (兼容) | PG wire | 可用 |
| TiDB | ProxySQL (兼容) | MySQL wire | 可用 |
| YugabyteDB | PgBouncer / YSQL Connection Manager | PG wire | 内置 manager (2.21+) |
| OceanBase | OBProxy | OBProxy 协议 | 官方 |
| Greenplum | PgBouncer | PG wire | 兼容 |
| Snowflake | -- | -- | SaaS 不需要 |
| BigQuery | -- | -- | REST 不需要 |

### 4. 池化模式（session / transaction / statement）

| 引擎 / 池 | session | transaction | statement | 备注 |
|----------|---------|------------|-----------|------|
| PgBouncer | 是 | 是 | 是 | 三种模式 |
| pgcat | 是 | 是 | -- | -- |
| Supavisor | 是 | 是 | -- | -- |
| pgpool-II | 是 | -- | -- | session 复用 |
| Odyssey | 是 | 是 | -- | -- |
| ProxySQL | 是 (透明) | 是 (语句重写) | -- | multiplexing |
| MySQL Router | 是 | -- | -- | 仅路由 |
| Oracle MTS | 是 | 是 (隐式) | -- | dispatcher 多路 |
| Oracle DRCP | 是 | -- | -- | 池化整个会话 |
| OBProxy | 是 | 是 | -- | -- |

### 5. max_connections 默认值

| 引擎 | 默认 max_connections | 备注 |
|------|---------------------|------|
| PostgreSQL | 100 | postgresql.conf |
| MySQL | 151 | -- |
| MariaDB | 151 | -- |
| Oracle | processes=300 (默认) | 受 sessions 影响 |
| SQL Server | 32767 | 实际受内存限制 |
| DB2 | 自动 (MAX_CONNECTIONS) | -- |
| Snowflake | 无显式 (按 warehouse) | SaaS |
| Redshift | 500 (节点级) | -- |
| ClickHouse | 4096 | -- |
| CockroachDB | 无硬限 | 受内存 |
| TiDB | 无硬限 | 受 token-limit |
| YugabyteDB | 300 (yb-tserver) | -- |
| Greenplum | 250 (master) | -- |
| Vertica | 50 (默认) | -- |
| SAP HANA | 视版本 | -- |
| Spanner | 客户端 session 池 (默认 100) | -- |

### 6. 会话属性保留能力（对池化模式的影响）

下表列出"在 transaction-level 池化下，是否安全"：

| 特性 | 影响 | transaction 池化下 |
|------|------|-------------------|
| 临时表 (TEMP TABLE) | 绑定 session | 不安全 |
| Prepared Statements | 绑定 session | PgBouncer 1.21+ 已修 |
| 会话变量 (`SET`) | 绑定 session | 不安全 (但 SET LOCAL 安全) |
| Advisory Lock | 绑定 session | 不安全 |
| LISTEN/NOTIFY | 绑定 session | 不安全 |
| WITH HOLD CURSOR | 跨事务 | 不安全 |
| 大对象 (LO) | 绑定 session | 不安全 |
| Application Role | 绑定 session | 不安全 |
| GUC 用户参数 | 绑定 session | 不安全 |

### 7. 空闲连接超时配置

| 引擎 | 参数 | 默认 |
|------|------|------|
| PostgreSQL | `idle_in_transaction_session_timeout` | 0 (无) |
| PostgreSQL | `idle_session_timeout` | 0 (14+) |
| MySQL | `wait_timeout` / `interactive_timeout` | 28800 秒 |
| Oracle | `IDLE_TIME` (resource profile) | UNLIMITED |
| SQL Server | `remote login timeout` | 10 秒 (登录) |
| ClickHouse | `idle_connection_timeout` | 3600 秒 |
| CockroachDB | `idle_in_session_timeout` | 0 |
| TiDB | `wait_timeout` | 28800 |
| Snowflake | client session keep-alive | 4 小时 |
| BigQuery | 不适用 (无连接) | -- |
| PgBouncer | `server_idle_timeout` | 600 秒 |
| ProxySQL | `mysql-default_idle_timeout` | 600 秒 |

### 8. 客户端连接负载均衡能力

| 引擎 / 驱动 | 内置 LB | 形式 |
|------------|---------|------|
| PostgreSQL JDBC | 是 | `targetServerType`, `loadBalanceHosts` |
| psycopg3 | 部分 | `host=h1,h2` |
| MySQL Connector/J | 是 | `loadbalance:` URL |
| MongoDB driver (对照) | 是 | SRV + topology |
| Oracle JDBC | 是 | TAF / FAN / JDBC LBG |
| Spanner client | 是 | gRPC channel pool |
| YugabyteDB JDBC | 是 | cluster-aware driver |
| CockroachDB | 应用侧 | 推荐 HAProxy |
| TiDB | 应用侧 | 推荐 LVS / HAProxy |
| ClickHouse | 是 | `host=h1,h2,h3` |
| Trino JDBC | 是 | DNS round-robin |

### 9. 服务端多路复用 (multiplexing)

"多路复用"指：N 个客户端连接复用 M 个后端连接（N >> M），同一个后端连接在同一时刻只服务一个语句/事务。

| 组件 | 多路复用 | 粒度 | 备注 |
|------|---------|------|------|
| PgBouncer (transaction mode) | 是 | 事务边界 | 经典实现 |
| pgcat | 是 | 事务/语句 | + 分片路由 |
| Supavisor | 是 | 事务 | Erlang VM 支撑 100w 客户端 |
| Odyssey | 是 | 事务 | 内置 TLS 终结 |
| ProxySQL | 是 | 语句 (multiplexing on/off) | 受 user variable 等影响降级 |
| MySQL Router | 否 | 仅路由 | -- |
| Oracle MTS | 是 | 调用边界 | 三十年前就有 |
| Oracle DRCP | 是 | 整会话 grab/release | -- |
| DB2 Concentrator | 是 | 事务 | -- |
| OBProxy | 是 | 事务 | -- |
| TiProxy (TiDB) | 是 | 事务 | 6.5+ |
| YSQL Connection Manager | 是 | 事务 | YugabyteDB 2.21+ |

### 10. 客户端协议支持外置池的友好度

外置池能否做事务级多路复用，取决于"协议是否能在事务边界完整恢复 backend 状态"。

| 协议 | 多路复用难度 | 障碍 |
|------|------------|------|
| PostgreSQL wire (v3) | 中 | prepared statement 命名空间在 backend |
| MySQL wire | 中 | user variable, 临时表 |
| Oracle Net (TNS) | 低 | 协议本身设计支持 dispatcher |
| TDS (SQL Server) | 高 | 微软不鼓励第三方代理 |
| TDS-over-DRDA (DB2) | 中 | -- |
| HTTP/REST (Snowflake/BigQuery/Athena) | 不需要 | 本身就是无状态 |
| ClickHouse HTTP | 不需要 | -- |
| Trino REST | 不需要 | -- |

## 各引擎详解

### PostgreSQL：进程模型与 PgBouncer 生态

PostgreSQL 的连接模型从 1986 年的 Postgres95 沿袭至今——postmaster 守护进程在每个新连接上 `fork()` 一个 backend 进程：

```text
client → TCP → postmaster → fork() → backend process
                                     ├─ catalog cache (~3 MB)
                                     ├─ relcache, plancache
                                     ├─ work_mem 预留
                                     └─ shared_buffers 映射
```

每个 backend 常驻 RSS ~10 MB，1000 个空闲连接就是 10 GB，绝大部分空闲。更糟的是，PostgreSQL 调度依赖 OS，CPU 200% 时 1000 backend 上下文切换吞噬 30%+ CPU。

业界共识：**PostgreSQL 超过 200-500 客户端连接，必须上外置池**。

PgBouncer 是最常用的方案，三种模式：

```ini
# pgbouncer.ini
[databases]
mydb = host=127.0.0.1 port=5432 dbname=mydb

[pgbouncer]
pool_mode = transaction          ; session / transaction / statement
max_client_conn = 10000          ; 客户端可连数
default_pool_size = 25           ; 每 (db,user) 后端连接数
reserve_pool_size = 5
server_idle_timeout = 600
```

- **session 模式**：客户端 disconnect 时才归还后端连接。等同于 1:1，仅省掉 fork。
- **transaction 模式**：客户端 `COMMIT`/`ROLLBACK` 时归还后端。10000 客户端可只用 25 后端，但代价是 session 状态失效。
- **statement 模式**：每条 SQL 语句结束后归还，连显式事务都不允许。极致复用，但应用必须改成 autocommit。

PgBouncer 1.21（2023 年 10 月）引入了 transaction 模式下的 prepared statement 支持（之前的十年里这是最大痛点）：

```ini
max_prepared_statements = 100
```

PgBouncer 1.22+ 还修了多个 SCRAM 认证 + 通道绑定（channel binding）相关问题。即便如此，下列仍然在 transaction 模式下不安全：临时表、`LISTEN/NOTIFY`、`WITH HOLD` cursor、advisory lock、会话级 `SET`。

更新一代的方案：

- **pgcat**（Rust）：原生支持读写分离、分片（哈希/列表）路由、按事务多路复用，目标是替代 PgBouncer。
- **Supavisor**（Elixir/Erlang VM）：Supabase 出品，利用 BEAM 的轻量进程，单实例支撑 ~100 万客户端连接到几百个后端，是托管 PG 服务的关键基础设施。
- **Odyssey**（Yandex）：异步 + TLS 终结 + 路由组。
- **AWS RDS Proxy**：托管的 PgBouncer 变体，集成 IAM 认证。

### Oracle：Shared Server 与 DRCP

Oracle 是少数把多路复用做进**内核**的商业数据库，最早可追溯到 v7（1992 年）的 Multi-Threaded Server（后改名 Shared Server）。

```text
client ─── TNS listener ─── dispatcher (D000)
                                │
                                ▼
                           request queue (in SGA)
                                │
                                ▼
                shared server (S000) ── execute ── DB files
                                │
                                ▼
                           response queue
                                │
                                ▼
                            dispatcher
                                │
                                ▼
                              client
```

配置：

```sql
ALTER SYSTEM SET DISPATCHERS='(PROTOCOL=TCP)(DISPATCHERS=4)';
ALTER SYSTEM SET SHARED_SERVERS=20;
ALTER SYSTEM SET MAX_SHARED_SERVERS=100;
```

数千客户端可被 4 个 dispatcher 多路复用到 20 个 shared server 进程上。每次"调用"（call）边界归还 shared server，类似 PgBouncer transaction 模式但更细。

Oracle 同时保留专用服务器（Dedicated Server）：1:1 进程，适合长事务、批处理、PL/SQL 长存储过程，因为不会与他人争 shared server。

11g 引入 **Database Resident Connection Pool (DRCP)**：

```sql
EXEC DBMS_CONNECTION_POOL.START_POOL();
EXEC DBMS_CONNECTION_POOL.CONFIGURE_POOL(
    pool_name        => 'SYS_DEFAULT_CONNECTION_POOL',
    minsize          => 4,
    maxsize          => 40,
    incrsize         => 2,
    session_cached_cursors => 20,
    inactivity_timeout     => 300,
    max_think_time         => 600,
    max_use_session        => 500000,
    max_lifetime_session   => 86400);
```

客户端 URL 加 `:POOLED`：

```text
sqlplus user/pwd@//host:1521/orcl:POOLED
```

DRCP 类似 PgBouncer session 模式但驻留在 Oracle 内部，PHP/Python 等"短脚本 + 多进程"的 Web 模型受益最大——每次请求 grab 一个 pooled server，结束 release，省掉 fork。

### SQL Server：内置线程池 + MARS

SQL Server 的连接管理在数据库圈是个"舒适岛"——根本不需要外置池：

- 用户态调度器 SQLOS / UMS（User Mode Scheduler）协作式调度，每核一个 scheduler，max worker threads 默认 512+。
- 每连接 ~512 KB workspace，相比 PG 进程的 10 MB 廉价两个数量级。
- TDS 协议设计上不利于第三方代理（Microsoft 也不鼓励），实践中由应用侧 .NET `SqlConnection` 池负责复用，使用 `Pooling=True;Min Pool Size=...;Max Pool Size=...` 在连接字符串中配置。

**MARS (Multiple Active Result Sets)** 让一个连接同时承载多个未读完的结果集：

```csharp
"Server=...;Database=...;MultipleActiveResultSets=True"
```

但 MARS 不是真多路复用——它在单个连接上交错执行，并不让多客户端共享后端，只是让一个客户端不必为读"两个游标"开两个连接。

### MySQL / MariaDB：线程模型与 ProxySQL

MySQL 默认是 one-thread-per-connection：每连接一个 OS 线程。线程比进程便宜得多（256 KB 栈起），但 1 万个空闲线程也是 GB 级 RSS + 海量上下文切换。

MySQL 的 `thread_cache_size` 只是**复用线程对象**，不复用会话状态，所以"建立成本"少了，但"运行成本"没少。

MariaDB 的 **thread pool 插件**（Percona 也有移植）类似 SQL Server SQLOS：

```ini
thread_handling = pool-of-threads
thread_pool_size = 16          ; 通常 = CPU 核数
thread_pool_max_threads = 1000
thread_pool_idle_timeout = 60
```

外置代理：

- **ProxySQL**：最流行，C++ 实现，事件驱动。支持读写分离、查询路由、查询重写、慢查杀手、连接多路复用：

  ```sql
  -- ProxySQL 内部配置（连接 admin 接口）
  INSERT INTO mysql_servers(hostgroup_id, hostname, port)
  VALUES (10, '10.0.0.11', 3306), (20, '10.0.0.12', 3306);

  INSERT INTO mysql_query_rules(rule_id, active, match_pattern, destination_hostgroup, apply)
  VALUES (1, 1, '^SELECT', 20, 1),
         (2, 1, '.*', 10, 1);

  LOAD MYSQL SERVERS TO RUNTIME;
  LOAD MYSQL QUERY RULES TO RUNTIME;
  ```

  ProxySQL 的 multiplexing 默认开启，但触发以下情况自动降级为"sticky"（同一 backend 不释放）：
  - 显式事务进行中
  - `SET @user_var = ...`
  - 临时表、prepared statement、`LOCK TABLES`
  - `LAST_INSERT_ID()` 引用

- **MySQL Router**：官方推出，搭配 InnoDB Cluster / Group Replication。它**不做多路复用**，仅做请求路由（PRIMARY / REPLICA），是 InnoDB Cluster 的"瘦"组件。

- **MaxScale**：MariaDB 出品，路由 + 池化 + binlog server。

### Snowflake：SaaS 虚拟连接

Snowflake 的"连接"是客户端侧的概念。服务端不存在 1:1 的进程或线程：

- 客户端通过 HTTPS/JSON 与全局服务（Global Services）通信。
- 每次请求带一个 session token（短 token + 长 token 续期）。
- 实际计算在 virtual warehouse（独立计算集群）上执行，warehouse 的并发度由 `MAX_CONCURRENCY_LEVEL`（默认 8）和 `STATEMENT_QUEUED_TIMEOUT_IN_SECONDS` 控制，不是连接数控制。

```sql
ALTER WAREHOUSE compute_wh SET
    MAX_CONCURRENCY_LEVEL = 8
    STATEMENT_QUEUED_TIMEOUT_IN_SECONDS = 0
    STATEMENT_TIMEOUT_IN_SECONDS = 172800;
```

应用侧仍然要使用客户端连接池（JDBC / Snowflake driver pool），目的是省掉 HTTPS + 认证开销，而不是省服务端资源。

### BigQuery：完全无状态 REST/gRPC

BigQuery 没有"连接"。每个查询是独立的 REST/gRPC 调用，认证使用 OAuth 2.0 短效令牌：

```http
POST https://bigquery.googleapis.com/bigquery/v2/projects/{project}/jobs
Authorization: Bearer ya29.a0AfH6...
Content-Type: application/json

{ "configuration": { "query": { "query": "SELECT ..." } } }
```

并发上限是项目级配额（默认 100 interactive queries），而不是连接数。客户端 SDK 维护的是 HTTP/2 连接池，与数据库会话语义无关。BigQuery **session**（用户使用 `CREATE SESSION` 创建）只是一个共享变量/临时表的逻辑容器，与 TCP 连接生命周期完全解耦。

### ClickHouse：长连接 TCP + HTTP 双协议

ClickHouse 提供两个协议端口：

- 9000: 原生 TCP，长连接，二进制，性能最高，driver 多用 `clickhouse-jdbc`、`clickhouse-go`。
- 8123: HTTP，无状态，便于代理（chproxy 即此层）。

服务端线程池：

```xml
<max_thread_pool_size>10000</max_thread_pool_size>
<max_concurrent_queries>100</max_concurrent_queries>
```

连接数本身不是 ClickHouse 的瓶颈（每连接很轻），瓶颈是 `max_concurrent_queries` 与单查询的内存/线程占用。**chproxy** 是社区代理，提供基于用户的限流、缓存、路由，但典型部署是 ClickHouse + 客户端连接池直连。

### DuckDB：嵌入式，没有"连接"

DuckDB 是进程内库，类似 SQLite。"连接"对象（`duckdb::Connection`）只是同一进程内的句柄，多线程可创建多个连接对象指向同一 `Database`，DuckDB 会做内部并发控制（MVCC）。

```cpp
duckdb::DuckDB db("file.duckdb");
duckdb::Connection conn1(db);
duckdb::Connection conn2(db);  // 同一进程
```

不存在网络、池化、多路复用。如果要给 DuckDB 加"网络层"，社区有 `duckdb-httpserver`、`MotherDuck` 等，但它们不在 DuckDB 核心范围内。

### CockroachDB：内置 Goroutine 调度

CockroachDB 用 Go 实现，每连接对应一个 goroutine（栈起步 8 KB），调度由 Go runtime 接管，因此**不需要外置池来解决"进程贵"问题**。但仍推荐使用：

- 应用侧池（HikariCP, pgx pool 等）以减少 TLS + 认证开销。
- HAProxy / cloud LB 做客户端负载均衡。
- PgBouncer **可用**（CockroachDB 兼容 PG wire），但通常没必要。

注意：CockroachDB 节点间还有内部 RPC 池，是分布式事务的另一层资源管理，与客户端连接池无关。

### TiDB：无状态 tidb-server + TiProxy

TiDB 的架构天生为高连接数设计：

- `tidb-server` 节点是无状态 SQL 层，挂掉一个不影响数据。
- 每连接一个 goroutine，无 fork。
- 客户端通常通过 LVS / HAProxy / 云 LB 分发到多个 `tidb-server`。

TiDB 6.5 引入 **TiProxy**（Go 实现），在 LB 之上提供：

- 事务级会话迁移（rolling upgrade tidb-server 时不断连）
- 智能负载均衡（基于 CPU 而非连接数）
- 协议级握手代理

TiProxy 不是"连接池"意义上的多路复用器，但它解决了 LB 不能做"零中断升级"的问题。

## PgBouncer 深度剖析

PgBouncer 是 PostgreSQL 生态中事实标准的连接池。下面把它的三种模式、关键限制、版本演进系统化整理。

### 三种池化模式

| 模式 | 后端连接归还时机 | 客户端最大数 / 后端连接 | 可用功能 |
|------|----------------|----------------------|---------|
| session | 客户端 disconnect | 1:1 | 全功能 |
| transaction | `COMMIT` / `ROLLBACK` | N:1 (高复用) | 受限（见下） |
| statement | 每条语句结束 | 极致复用 | 仅 autocommit |

```ini
pool_mode = transaction
max_client_conn = 5000          ; 全局客户端
default_pool_size = 30          ; 每 (db,user) 后端
min_pool_size = 5
reserve_pool_size = 5           ; 突发预留
reserve_pool_timeout = 3
server_lifetime = 3600
server_idle_timeout = 600
query_wait_timeout = 120
client_idle_timeout = 0
client_login_timeout = 60
```

按 `(database, user)` 维度分池，所以 100 个 `(db,user)` 组合就是 100 池子，要谨慎规划。

### transaction 模式下不安全的特性

历史上是这样（即"经典禁忌列表"）：

1. `SET` (会话级) — 用 `SET LOCAL` 替代
2. `LISTEN / NOTIFY`
3. 临时表 (`CREATE TEMP TABLE`)
4. `WITH HOLD` cursor
5. Advisory lock (`pg_advisory_lock`)
6. Prepared statement (`PREPARE` / 协议级 Parse/Bind/Execute)
7. 大对象 API
8. 自定义 GUC (`SET app.user_id = ...`)

### Prepared Statement 在 1.21+ 的修复

2023 年 10 月发布的 PgBouncer 1.21 引入了 transaction 模式下的 protocol-level prepared statement 透明池化：

```ini
max_prepared_statements = 200
```

工作机制：PgBouncer 截获每个客户端的 `Parse(name, sql)` 消息，按 SQL 文本哈希在后端 dedupe，维护"客户端 statement name → 后端 statement name"映射表。客户端 `Bind/Execute` 时翻译到正确的后端命名。客户端切换后端连接时，PgBouncer 会按需在新后端重放 `Parse`。

注意：

- 仅支持**协议级**（extended query）prepared statement，不支持 SQL 级 `PREPARE name AS ...`（后者是会话状态，仍然不安全）。
- `max_prepared_statements` 设到 200 通常够 ORM 用，HikariCP / pgx / SQLAlchemy 都是协议级。
- 应用要确认 driver 不依赖固定 backend。

### 其他常见陷阱

- **认证传递**：PgBouncer 与后端的认证方法可能与客户端不同。常见做法是 `auth_type = scram-sha-256`，并维护 `auth_file` 或使用 `auth_query`：

  ```ini
  auth_type = scram-sha-256
  auth_user = pgbouncer_auth
  auth_query = SELECT usename, passwd FROM pg_shadow WHERE usename=$1
  ```

- **SSL 终结**：PgBouncer 1.x 才完整支持 client-side TLS。生产建议 `server_tls_sslmode = verify-full`。

- **`SHOW` 命令在 transaction 模式下被 PgBouncer 拦截**：PgBouncer 自己的 `SHOW POOLS / SHOW CLIENTS / SHOW STATS` 返回内部状态，不路由到 PG。

- **诊断**：`pgbouncer` 数据库（连接到端口 6432, dbname=`pgbouncer`）是控制台。

```sql
SHOW POOLS;
SHOW CLIENTS;
SHOW SERVERS;
SHOW STATS;
SHOW MEM;
PAUSE mydb;
RESUME mydb;
RECONNECT mydb;
```

## Oracle Shared Server vs Dedicated Server

下表对照两种模式，帮助选型：

| 维度 | Dedicated Server | Shared Server (MTS) | DRCP |
|------|-----------------|---------------------|------|
| 进程模型 | 1 client : 1 server process | N clients : M shared servers via dispatchers | 客户端会话池化 |
| 内存来源 | UGA 在 PGA 中 | UGA 在 SGA (large_pool) 中 | UGA 在 SGA |
| 适合负载 | 长事务、批处理、PL/SQL 重型 | OLTP 多短请求 | Web 短脚本（PHP/Python） |
| 网络拓扑 | listener → 直 fork | listener → dispatcher → request queue | listener → broker → pooled server |
| 故障域 | 客户端崩溃只影响自己 | dispatcher 死 = 一组客户端中断 | broker 死 = 集中影响 |
| 配置参数 | `processes`, `sessions` | `dispatchers`, `shared_servers` | `dbms_connection_pool` |
| 最大客户端数 | 受 `processes` 限制 | 远超 `processes` | 远超 `processes` |
| 不能用 | -- | RMAN, 长 DBA 操作必须 dedicated | 同 MTS |
| 历史 | v6+ | v7 (1992) MTS | 11g (2007) |

```sql
-- 配置 Shared Server
ALTER SYSTEM SET SHARED_SERVERS=20;
ALTER SYSTEM SET MAX_SHARED_SERVERS=100;
ALTER SYSTEM SET DISPATCHERS='(PROTOCOL=TCP)(DISPATCHERS=4)(CONNECTIONS=1000)';
ALTER SYSTEM SET LARGE_POOL_SIZE=512M;

-- 客户端按会话覆盖
ALTER SESSION SET SHARED_SERVERS_RESERVED = 0;

-- DRCP
EXEC DBMS_CONNECTION_POOL.START_POOL;
SELECT pool_name, status, num_busy_servers, num_open_servers
FROM   v$cpool_stats;

-- 监控
SELECT name, network, requests, busy, idle FROM v$dispatcher;
SELECT name, requests, busy(%), idle FROM v$shared_server;
SELECT name, totalq, averageq FROM v$queue;
```

经验法则：

- 默认 dedicated；OLTP 短请求量极大且 RAM 紧张时考虑 shared server。
- Web 应用（PHP-FPM、Python WSGI、Ruby Unicorn）优先 DRCP，因为它们的"每请求新连接 + 极短会话"刚好匹配 DRCP 的 grab/release 模型。
- **不要**对 RMAN backup、Data Pump、长 PL/SQL 用 shared server——会阻塞整个 dispatcher 队列。

## 关键发现

1. **PostgreSQL 进程模型是最大短板**：~10 MB / 连接 + fork 调度，超过几百活跃连接就崩。整个 PgBouncer / pgcat / Supavisor / Odyssey 生态都是为它而生。商业 PG 服务（Supabase、Neon、Crunchy、AWS RDS Proxy）的核心基础设施都是某种 PgBouncer 变体或重写。

2. **PgBouncer 1.21 (2023)** 解决了十年顽疾——transaction 模式下的协议级 prepared statement 透明池化，从此 ORM（HikariCP/pgx/SQLAlchemy/Prisma）可以安全地用 transaction 模式。但 SQL 级 `PREPARE`、临时表、`LISTEN/NOTIFY` 等会话状态仍然不安全。

3. **Oracle 1992 年就内置多路复用**：Multi-Threaded Server / Shared Server / Dispatcher 的设计领先 PgBouncer 二十年；2007 年的 DRCP 又针对 Web 短脚本场景做了优化。Oracle 工程上的优势在协议层（Oracle Net 原生支持 dispatcher 抽象），是 PG wire 协议无法轻易复制的。

4. **SQL Server 是连接管理的"舒适岛"**：内核态 SQLOS 协作式调度 + ~512 KB / 连接的低开销 + 应用侧 .NET 池，三层组合让连接数极少成为 SQL Server 的瓶颈。代价是 TDS 协议封闭，第三方代理生态稀薄。

5. **MySQL 介于 PG 和 SQL Server 之间**：线程模型比 PG 进程便宜，但比 SQL Server 协作调度差。MariaDB 的 thread pool 插件向 SQL Server 模型靠拢。生产环境 ProxySQL 几乎是默认部署，提供路由 + 多路复用 + 查询重写一体化能力。

6. **Snowflake / BigQuery / Athena / Firebolt**：SaaS 数据仓库的"无连接"模型从根本上消解了池化问题——HTTP/REST + 短令牌 + 服务端弹性伸缩，客户端只剩"为什么还要保留 driver 池"这一个微小关切（认证开销）。

7. **新生代分布式数据库（CockroachDB / TiDB / YugabyteDB）的差异**：
   - CockroachDB / TiDB 用 Go goroutine，本身无连接成本问题，外置池主要为认证开销和 LB。
   - YugabyteDB YSQL 继承 PG 进程模型（YugabyteDB 是在 PG backend 之上重写存储），所以同样面临"PG 连接贵"问题，2.21 内置了 **YSQL Connection Manager**（基于 Odyssey），是分布式数据库中少见的"自带池"方案。
   - TiDB 6.5+ 的 **TiProxy** 不是池而是会话级代理，主要解决 rolling upgrade 不断连。

8. **Supavisor 是 PG 连接管理的天花板**：Erlang/BEAM 的轻量进程让单实例服务百万级客户端连接成为现实，是 Supabase 多租户托管 PG 的核心。它证明了"连接池可以不只是 C 实现"——语言运行时本身可以是答案。

9. **prepared statement 是事务级池化最大的兼容性敌人**：PgBouncer、pgcat、Supavisor、ProxySQL 都为此打过补丁。统一答案是"哈希 SQL 文本 + 后端 dedupe + 名字翻译"，但需要协议级（extended query）而非 SQL 级 PREPARE。

10. **DuckDB / SQLite 是另一个极端**：嵌入式无网络，根本不存在池化问题。"无连接"是分析型嵌入数据库的核心 USP，大幅降低了应用部署复杂度。

11. **客户端池 vs 服务端池不是替代关系**：HikariCP / pgx pool 解决的是 TLS + 认证 + DNS 的"建立成本"，PgBouncer 解决的是 backend 的"运行成本"。生产 PG 部署通常是双层池：app pool (HikariCP, max=20) → PgBouncer (transaction, default_pool_size=25) → PG。两层缺一不可。

12. **session 属性的"显隐"决定多路复用边界**：所有事务级池都受同一个根本限制——session 状态（GUC、临时表、prepared statement、advisory lock、LISTEN）。能否复用，取决于应用是否能把这些状态都改成事务级或避免使用。这是为什么"无 session 状态"的应用框架（HTTP 短请求 + JWT）和事务级池天然契合，而长连接会话型应用（数据库工具、报表生成器）只能 session 池化。

13. **协议设计影响生态**：Oracle Net 和 PG wire 一开始就允许"dispatcher 中介"模型，所以代理生态发达；TDS 不允许，所以 SQL Server 没有外置池生态。这种 30 年前的协议决定影响着今天每一个数据库的运维形态。
