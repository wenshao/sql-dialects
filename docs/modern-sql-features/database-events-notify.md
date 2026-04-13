# 数据库事件通知 (Database Event Notifications)

当数据库行变化时，应用如何在 1 毫秒内得到通知？传统的"客户端轮询 + 时间戳列"方案延迟高、负载重，而真正的实时 UI 和事件驱动架构需要数据库主动推送变更——这就是 LISTEN/NOTIFY、Service Broker、DBMS_AQ 这类机制存在的理由。本文系统对比 45+ 个数据库的事件通知能力，是站在引擎开发者视角的"推送式通知"全景图。

> 本文聚焦"推送式"事件通知（应用注册后被动接收）。基于日志的 CDC（Change Data Capture）流式订阅请参阅 [`cdc-changefeed.md`](cdc-changefeed.md)，本文只在矩阵中作为对照引用。

## 没有 SQL 标准

ISO/IEC 9075 SQL 标准对"事件通知"几乎没有规范——LISTEN/NOTIFY、Query Notification、消息队列均为厂商扩展。最接近的是：

- **SQL/CLI（ISO/IEC 9075-3）**: 定义了异步语句执行接口（`SQLAsyncExecState`），但不定义事件订阅
- **SQL/PSM 触发器**: 标准只规定 BEFORE/AFTER 触发，不定义触发后如何通知外部进程
- **JDBC `RowSetListener`、ODBC `SQL_ATTR_ASYNC_ENABLE`**: 客户端 API 层的异步与监听，依赖驱动实现

因此，所有现代数据库的事件通知机制都是各自发明：PostgreSQL 选择 LISTEN/NOTIFY 模型（受 Sybase Open Server 启发），Oracle 选择 DBMS_ALERT + DBMS_AQ 双层结构，Microsoft 把它构建在 Service Broker 之上，Firebird 用 POST_EVENT 简单事件，IBM DB2 通过 WebSphere MQ 集成。这种碎片化导致跨数据库的"实时通知"几乎不可移植。

## 支持矩阵（综合）

### LISTEN / NOTIFY / UNLISTEN（pub-sub 风格）

| 引擎 | LISTEN | NOTIFY | UNLISTEN | 通道命名 | 载荷大小 | 版本 |
|------|--------|--------|----------|---------|---------|------|
| PostgreSQL | `LISTEN ch` | `NOTIFY ch, 'payload'` | `UNLISTEN ch` | 标识符 | 8000 字节 | 6.4 (1998)+ |
| MySQL | -- | -- | -- | -- | -- | 不支持 |
| MariaDB | -- | -- | -- | -- | -- | 不支持 |
| SQLite | -- | -- | -- | -- | -- | 不支持 |
| Oracle | DBMS_ALERT.REGISTER | DBMS_ALERT.SIGNAL | REMOVE | VARCHAR2(30) | 1800 字节 | 8i+ |
| SQL Server | -- (用 Service Broker) | -- | -- | -- | -- | 不直接支持 |
| DB2 | -- | -- | -- | -- | -- | 不支持 |
| Snowflake | -- | -- | -- | -- | -- | 不支持 |
| BigQuery | -- | -- | -- | -- | -- | 不支持 |
| Redshift | -- | -- | -- | -- | -- | 不支持 |
| DuckDB | -- | -- | -- | -- | -- | 不支持 |
| ClickHouse | -- | -- | -- | -- | -- | 不支持 |
| Trino | -- | -- | -- | -- | -- | 不支持 |
| Presto | -- | -- | -- | -- | -- | 不支持 |
| Spark SQL | -- | -- | -- | -- | -- | 不支持 |
| Hive | -- | -- | -- | -- | -- | 不支持 |
| Flink SQL | -- | -- | -- | -- | -- | 不支持 |
| Databricks | -- | -- | -- | -- | -- | 不支持 |
| Teradata | -- | -- | -- | -- | -- | 不支持 |
| Greenplum | `LISTEN` | `NOTIFY` | `UNLISTEN` | 标识符 | 8000 字节 | 继承 PG |
| CockroachDB | -- | -- | -- | -- | -- | 不支持 |
| TiDB | -- | -- | -- | -- | -- | 不支持 |
| OceanBase | -- | -- | -- | -- | -- | 不支持 |
| YugabyteDB | `LISTEN` | `NOTIFY` | `UNLISTEN` | 标识符 | 8000 字节 | 部分（单节点） |
| SingleStore | -- | -- | -- | -- | -- | 不支持 |
| Vertica | -- | -- | -- | -- | -- | 不支持 |
| Impala | -- | -- | -- | -- | -- | 不支持 |
| StarRocks | -- | -- | -- | -- | -- | 不支持 |
| Doris | -- | -- | -- | -- | -- | 不支持 |
| MonetDB | -- | -- | -- | -- | -- | 不支持 |
| CrateDB | -- | -- | -- | -- | -- | 不支持 |
| TimescaleDB | `LISTEN` | `NOTIFY` | `UNLISTEN` | 标识符 | 8000 字节 | 继承 PG |
| QuestDB | -- | -- | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | -- | -- | 不支持 |
| SAP HANA | -- | -- | -- | -- | -- | 不支持 |
| Informix | -- | -- | -- | -- | -- | 不支持 |
| Firebird | -- (用 EVENT) | `POST_EVENT` | -- | CHAR(31) | 仅事件名 | 1.0+ |
| H2 | -- | -- | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | -- | -- | 不支持 |
| Amazon Athena | -- | -- | -- | -- | -- | 不支持 |
| Azure Synapse | -- | -- | -- | -- | -- | 不支持 |
| Google Spanner | -- | -- | -- | -- | -- | 不支持 |
| Materialize | -- (用 SUBSCRIBE) | -- | -- | -- | -- | 不直接支持 |
| RisingWave | -- (用 SUBSCRIBE) | -- | -- | -- | -- | 不直接支持 |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | 不支持 |
| DatabendDB | -- | -- | -- | -- | -- | 不支持 |
| Yellowbrick | -- | -- | -- | -- | -- | 不支持 |
| Firebolt | -- | -- | -- | -- | -- | 不支持 |

> 统计：仅 PostgreSQL 系（PG/Greenplum/TimescaleDB/YugabyteDB）原生支持 SQL 级 LISTEN/NOTIFY；约 4-5 个引擎，其余 40+ 全部缺失。

### 查询通知（SqlDependency 风格）

| 引擎 | 机制 | API 入口 | 版本 |
|------|------|---------|------|
| PostgreSQL | -- | -- | -- |
| MySQL | -- | -- | -- |
| MariaDB | -- | -- | -- |
| SQLite | -- (可用 `update_hook` C API) | C API | 3.0+ |
| Oracle | Database Change Notification | DBMS_CHANGE_NOTIFICATION / OCI | 10g R2+ |
| SQL Server | Query Notifications | SqlDependency / SSB | 2005+ |
| DB2 | -- | -- | -- |
| Snowflake | -- | -- | -- |
| BigQuery | -- | -- | -- |
| Redshift | -- | -- | -- |
| DuckDB | -- | -- | -- |
| ClickHouse | -- | -- | -- |
| Trino | -- | -- | -- |
| Presto | -- | -- | -- |
| Spark SQL | -- | -- | -- |
| Hive | -- | -- | -- |
| Flink SQL | -- (流原生) | -- | -- |
| Databricks | -- | -- | -- |
| Teradata | -- | -- | -- |
| Greenplum | -- | -- | -- |
| CockroachDB | -- | -- | -- |
| TiDB | -- | -- | -- |
| OceanBase | -- | -- | -- |
| YugabyteDB | -- | -- | -- |
| SingleStore | -- | -- | -- |
| Vertica | -- | -- | -- |
| Impala | -- | -- | -- |
| StarRocks | -- | -- | -- |
| Doris | -- | -- | -- |
| MonetDB | -- | -- | -- |
| CrateDB | -- | -- | -- |
| TimescaleDB | -- | -- | -- |
| QuestDB | -- | -- | -- |
| Exasol | -- | -- | -- |
| SAP HANA | -- | -- | -- |
| Informix | SmartTrigger（行级回调） | -- | 11.50+ |
| Firebird | -- | -- | -- |
| H2 | -- (有 `Trigger` Java API) | -- | -- |
| HSQLDB | -- | -- | -- |
| Derby | -- | -- | -- |
| Amazon Athena | -- | -- | -- |
| Azure Synapse | -- | -- | -- |
| Google Spanner | -- | -- | -- |
| Materialize | SUBSCRIBE 增量结果 | SQL | GA |
| RisingWave | SUBSCRIBE | SQL | 1.7+ |
| InfluxDB | -- | -- | -- |
| DatabendDB | -- | -- | -- |
| Yellowbrick | -- | -- | -- |
| Firebolt | -- | -- | -- |

> 注：SQL Server 的 SqlDependency 是查询级的"结果集失效"通知，本质上构建在 Service Broker 之上，只能用于关注的简单 SELECT。

### AFTER 触发器 + 通知函数

| 引擎 | AFTER 触发器 | 可调用通知函数 | 典型组合 |
|------|------------|--------------|---------|
| PostgreSQL | 是 | `pg_notify(text, text)` | TRIGGER → pg_notify |
| MySQL | 是 | -- | 仅能写表，应用轮询 |
| MariaDB | 是 | -- | 同上 |
| SQLite | 是 | UDF（C 注册） | 触发器调 UDF |
| Oracle | 是 | `DBMS_ALERT` / `DBMS_AQ.ENQUEUE` | TRIGGER → AQ |
| SQL Server | 是 | Service Broker `SEND` | TRIGGER → SSB |
| DB2 | 是 | `MQSEND` UDF | TRIGGER → MQ |
| Snowflake | 是（流+任务） | -- (无内置通知) | 流 + Task |
| BigQuery | -- (无 row trigger) | -- | -- |
| Redshift | -- (无 row trigger) | -- | -- |
| DuckDB | -- | -- | -- |
| ClickHouse | -- (用 MV) | -- | 物化视图 |
| Trino | -- | -- | -- |
| Presto | -- | -- | -- |
| Spark SQL | -- | -- | -- |
| Hive | -- | -- | -- |
| Flink SQL | -- (流原生) | Sink | 直接写 Kafka |
| Databricks | -- | -- | -- |
| Teradata | 是 | -- | 仅能记录表 |
| Greenplum | 是 | `pg_notify` | 继承 PG |
| CockroachDB | -- (无行级 TRIGGER, 24.2+ 实验) | CHANGEFEED | 用 CDC |
| TiDB | 是 | -- | -- |
| OceanBase | 是 | DBMS_ALERT 兼容 | -- |
| YugabyteDB | 是 | `pg_notify` | 继承 PG |
| SingleStore | -- | -- | -- |
| Vertica | -- | -- | -- |
| Impala | -- | -- | -- |
| StarRocks | -- | -- | -- |
| Doris | -- | -- | -- |
| MonetDB | 是 | -- | -- |
| CrateDB | -- | -- | -- |
| TimescaleDB | 是 | `pg_notify` | 继承 PG |
| QuestDB | -- | -- | -- |
| Exasol | -- | -- | -- |
| SAP HANA | 是 | -- | -- |
| Informix | 是 | SmartTrigger 推送 | -- |
| Firebird | 是 | `POST_EVENT` | TRIGGER → POST_EVENT |
| H2 | 是 (Java) | 任意 Java | 自定义 |
| HSQLDB | 是 (Java) | 任意 Java | 自定义 |
| Derby | 是 | -- | -- |
| Amazon Athena | -- | -- | -- |
| Azure Synapse | -- | -- | -- |
| Google Spanner | -- | -- | -- |
| Materialize | -- | -- | -- |
| RisingWave | -- | -- | -- |
| InfluxDB | -- | -- | -- |
| DatabendDB | -- | -- | -- |
| Yellowbrick | -- | -- | -- |
| Firebolt | -- | -- | -- |

### CDC 用于事件通知（详见 cdc-changefeed.md）

| 引擎 | CDC 机制 | 推送目标 | 适用通知场景 |
|------|---------|---------|-------------|
| PostgreSQL | Logical decoding (wal2json/pgoutput) | Debezium → Kafka | 是（间接） |
| MySQL | Binlog | Debezium / Canal | 是 |
| MariaDB | Binlog | 同 MySQL | 是 |
| SQLite | -- | -- | -- |
| Oracle | LogMiner / GoldenGate / XStream | OGG / Streams | 是 |
| SQL Server | CDC + CT | Debezium | 是 |
| DB2 | InfoSphere CDC | -- | 是 |
| Snowflake | Streams（log-based） | Task / 外部消费 | 是（拉取） |
| BigQuery | -- (用 Datastream) | Datastream | 间接 |
| Redshift | -- | -- | -- |
| DuckDB | -- | -- | -- |
| ClickHouse | -- | -- | -- |
| Trino | -- | -- | -- |
| Presto | -- | -- | -- |
| Spark SQL | -- | -- | -- |
| Hive | -- | -- | -- |
| Flink SQL | CDC connector | 直接消费 | 是 |
| Databricks | Delta CDF | 流读取 | 是 |
| Teradata | -- | -- | -- |
| Greenplum | -- | -- | -- |
| CockroachDB | `CREATE CHANGEFEED` | Kafka/Webhook/Cloud | 是（原生 webhook） |
| TiDB | TiCDC | Kafka | 是 |
| OceanBase | OBCDC | Kafka | 是 |
| YugabyteDB | YugabyteDB CDC | Kafka/Debezium | 是 |
| SingleStore | Pipelines (反向) | -- | -- |
| Vertica | -- | -- | -- |
| Impala | -- | -- | -- |
| StarRocks | -- | -- | -- |
| Doris | -- | -- | -- |
| MonetDB | -- | -- | -- |
| CrateDB | -- | -- | -- |
| TimescaleDB | 继承 PG | -- | 是 |
| QuestDB | -- | -- | -- |
| Exasol | -- | -- | -- |
| SAP HANA | SDA / SDI | -- | 部分 |
| Informix | CDC API | -- | 是 |
| Firebird | -- | -- | -- |
| H2 | -- | -- | -- |
| HSQLDB | -- | -- | -- |
| Derby | -- | -- | -- |
| Amazon Athena | -- | -- | -- |
| Azure Synapse | -- | -- | -- |
| Google Spanner | Change Streams | Dataflow | 是 |
| Materialize | SUBSCRIBE / TAIL | gRPC | 原生 |
| RisingWave | SUBSCRIBE | psql wire | 原生 |
| InfluxDB | -- | -- | -- |
| DatabendDB | Stream | -- | 拉取 |
| Yellowbrick | -- | -- | -- |
| Firebolt | -- | -- | -- |

### 逻辑复制订阅（用于通知消费）

| 引擎 | 逻辑复制订阅 | 客户端可订阅 | 版本 |
|------|------------|------------|------|
| PostgreSQL | `CREATE SUBSCRIPTION` / `pg_recvlogical` | 是 | 10+ |
| MySQL | GTID 复制 | 否（仅 binlog 客户端） | 5.6+ |
| MariaDB | 同上 | 否 | 10.0+ |
| SQLite | -- | -- | -- |
| Oracle | XStream Outbound Server | 是 | 11.2+ |
| SQL Server | Transactional Replication | 仅 SQL Server 订阅者 | -- |
| DB2 | Q Replication | -- | -- |
| Snowflake | -- | -- | -- |
| BigQuery | -- | -- | -- |
| Redshift | -- | -- | -- |
| DuckDB | -- | -- | -- |
| ClickHouse | MaterializedPostgreSQL | 是 | 22.1+ |
| Trino | -- | -- | -- |
| Presto | -- | -- | -- |
| Spark SQL | -- | -- | -- |
| Hive | -- | -- | -- |
| Flink SQL | postgres-cdc connector | 是 | 1.11+ |
| Databricks | -- | -- | -- |
| Teradata | -- | -- | -- |
| Greenplum | -- | -- | -- |
| CockroachDB | -- (用 CHANGEFEED) | -- | -- |
| TiDB | TiCDC | -- | -- |
| OceanBase | OBLogProxy | -- | -- |
| YugabyteDB | 部分 | 是（pgoutput 兼容） | 2.13+ |
| SingleStore | -- | -- | -- |
| Vertica | -- | -- | -- |
| Impala | -- | -- | -- |
| StarRocks | -- | -- | -- |
| Doris | -- | -- | -- |
| MonetDB | -- | -- | -- |
| CrateDB | -- | -- | -- |
| TimescaleDB | 继承 PG | 是 | -- |
| QuestDB | -- | -- | -- |
| Exasol | -- | -- | -- |
| SAP HANA | -- | -- | -- |
| Informix | ER | -- | -- |
| Firebird | -- | -- | -- |
| H2 | -- | -- | -- |
| HSQLDB | -- | -- | -- |
| Derby | -- | -- | -- |
| Amazon Athena | -- | -- | -- |
| Azure Synapse | -- | -- | -- |
| Google Spanner | -- | -- | -- |
| Materialize | -- (作为 PG 订阅者) | -- | -- |
| RisingWave | -- | -- | -- |
| InfluxDB | -- | -- | -- |
| DatabendDB | -- | -- | -- |
| Yellowbrick | -- | -- | -- |
| Firebolt | -- | -- | -- |

### 内建消息队列 / 管道

| 引擎 | 队列机制 | DDL | 版本 |
|------|---------|-----|------|
| PostgreSQL | pgq（外部扩展，Skytools） | `pgq.create_queue` | 2007+ |
| Oracle | Advanced Queuing (AQ / TxEventQ) | `DBMS_AQADM.CREATE_QUEUE` | 8i (1999)+ |
| SQL Server | Service Broker | `CREATE QUEUE` | 2005+ |
| DB2 | MQ Listener / MQ Functions | -- | v8+ |
| Informix | MQ DataBlade | -- | -- |
| MySQL | -- | -- | -- |
| MariaDB | -- | -- | -- |
| SQLite | -- | -- | -- |
| Snowflake | -- | -- | -- |
| BigQuery | -- (Pub/Sub 集成) | -- | -- |
| Redshift | -- | -- | -- |
| DuckDB | -- | -- | -- |
| ClickHouse | Kafka 引擎表（消费方） | `ENGINE = Kafka` | 18+ |
| Trino | -- | -- | -- |
| Presto | -- | -- | -- |
| Spark SQL | -- | -- | -- |
| Hive | -- | -- | -- |
| Flink SQL | Kafka connector | `WITH 'connector'='kafka'` | -- |
| Databricks | -- | -- | -- |
| Teradata | -- | -- | -- |
| Greenplum | pgq | -- | -- |
| CockroachDB | -- | -- | -- |
| TiDB | -- | -- | -- |
| OceanBase | -- | -- | -- |
| YugabyteDB | -- | -- | -- |
| SingleStore | Pipelines (Kafka/S3 ingest) | `CREATE PIPELINE` | 5.5+ |
| Vertica | -- | -- | -- |
| Impala | -- | -- | -- |
| StarRocks | Routine Load | `CREATE ROUTINE LOAD` | 入站 |
| Doris | Routine Load | 同上 | 入站 |
| MonetDB | -- | -- | -- |
| CrateDB | -- | -- | -- |
| TimescaleDB | 继承 PG / pgq | -- | -- |
| QuestDB | -- | -- | -- |
| Exasol | -- | -- | -- |
| SAP HANA | smart data streaming | -- | -- |
| Firebird | -- | -- | -- |
| H2 | -- | -- | -- |
| HSQLDB | -- | -- | -- |
| Derby | -- | -- | -- |
| Amazon Athena | -- | -- | -- |
| Azure Synapse | -- | -- | -- |
| Google Spanner | -- | -- | -- |
| Materialize | -- | -- | -- |
| RisingWave | -- | -- | -- |
| InfluxDB | -- | -- | -- |
| DatabendDB | -- | -- | -- |
| Yellowbrick | -- | -- | -- |
| Firebolt | -- | -- | -- |

### Watchdog / 轮询辅助函数

| 引擎 | 轮询辅助 | 描述 |
|------|---------|------|
| PostgreSQL | `pg_sleep`, advisory locks | 配合 NOTIFY |
| MySQL | `SLEEP()` | 客户端轮询时间戳列 |
| MariaDB | `SLEEP()` | 同上 |
| SQLite | `sqlite3_update_hook` (C) | 嵌入式回调 |
| Oracle | `DBMS_LOCK.SLEEP`, `DBMS_ALERT.WAITONE` | 阻塞等待 |
| SQL Server | `WAITFOR DELAY` / `WAITFOR (RECEIVE)` | RECEIVE 阻塞 |
| DB2 | `SLEEP` (proc) | -- |
| Snowflake | `SYSTEM$WAIT` | 仅延时 |
| BigQuery | -- | -- |
| Redshift | -- | -- |
| DuckDB | -- | -- |
| ClickHouse | `sleep()` | -- |
| Trino | -- | -- |
| Presto | -- | -- |
| Spark SQL | -- | -- |
| Hive | -- | -- |
| Flink SQL | -- | -- |
| Databricks | -- | -- |
| Teradata | -- | -- |
| Greenplum | `pg_sleep` | -- |
| CockroachDB | `pg_sleep` | -- |
| TiDB | `SLEEP` | -- |
| OceanBase | `SLEEP` / `DBMS_LOCK.SLEEP` | -- |
| YugabyteDB | `pg_sleep` | -- |
| SingleStore | `SLEEP` | -- |
| Vertica | `SLEEP` | -- |
| Impala | -- | -- |
| StarRocks | `sleep` | -- |
| Doris | `sleep` | -- |
| MonetDB | -- | -- |
| CrateDB | -- | -- |
| TimescaleDB | `pg_sleep` | -- |
| QuestDB | -- | -- |
| Exasol | -- | -- |
| SAP HANA | -- | -- |
| Informix | -- | -- |
| Firebird | `EVENTS WAIT` | API 阻塞 |
| H2 | -- | -- |
| HSQLDB | -- | -- |
| Derby | -- | -- |
| Amazon Athena | -- | -- |
| Azure Synapse | `WAITFOR DELAY` | -- |
| Google Spanner | -- | -- |
| Materialize | -- (SUBSCRIBE 阻塞) | -- |
| RisingWave | -- (SUBSCRIBE 阻塞) | -- |
| InfluxDB | -- | -- |
| DatabendDB | -- | -- |
| Yellowbrick | -- | -- |
| Firebolt | -- | -- |

### 数据库直接发送 WebHook

| 引擎 | 内建 WebHook | 实现方式 | 备注 |
|------|------------|---------|------|
| PostgreSQL | -- | 用 `plpython3u` / `plperlu` | 需不可信语言 |
| MySQL | -- | UDF 扩展 | 需自编译 |
| MariaDB | -- | 同 MySQL | -- |
| SQLite | -- | -- | -- |
| Oracle | UTL_HTTP | PL/SQL 直接 HTTP POST | 8i+ |
| SQL Server | sp_invoke_external_rest_endpoint | 是（云原生） | Azure SQL 2022+ |
| DB2 | UTL_HTTP（兼容包） | -- | -- |
| Snowflake | External Functions / Notification Integration | 是 | GA |
| BigQuery | Cloud Functions（外部触发） | 间接 | -- |
| Redshift | Lambda UDF | 间接 | -- |
| DuckDB | -- | -- | -- |
| ClickHouse | URL 表函数（拉取方向） | -- | -- |
| Trino | -- | -- | -- |
| Presto | -- | -- | -- |
| Spark SQL | -- | -- | -- |
| Hive | -- | -- | -- |
| Flink SQL | HTTP sink | 是 | connector |
| Databricks | Delta Live Tables 通知 | -- | -- |
| Teradata | -- | -- | -- |
| Greenplum | 同 PG | -- | -- |
| CockroachDB | `CREATE CHANGEFEED ... INTO 'webhook-https://...'` | 是（原生） | 21.2+ |
| TiDB | -- | -- | -- |
| OceanBase | -- | -- | -- |
| YugabyteDB | 同 PG | -- | -- |
| SingleStore | -- | -- | -- |
| Vertica | -- | -- | -- |
| Impala | -- | -- | -- |
| StarRocks | -- | -- | -- |
| Doris | -- | -- | -- |
| MonetDB | -- | -- | -- |
| CrateDB | -- | -- | -- |
| TimescaleDB | 同 PG | -- | -- |
| QuestDB | -- | -- | -- |
| Exasol | UDF | -- | -- |
| SAP HANA | XSJS（已弃用） | -- | -- |
| Informix | -- | -- | -- |
| Firebird | -- | -- | -- |
| H2 | Java trigger | 自由实现 | -- |
| HSQLDB | Java trigger | 同上 | -- |
| Derby | -- | -- | -- |
| Amazon Athena | -- | -- | -- |
| Azure Synapse | -- | -- | -- |
| Google Spanner | -- | -- | -- |
| Materialize | Webhook source（入站） | -- | -- |
| RisingWave | Webhook source（入站） | -- | -- |
| InfluxDB | -- | -- | -- |
| DatabendDB | -- | -- | -- |
| Yellowbrick | -- | -- | -- |
| Firebolt | -- | -- | -- |

### 服务器推送事件 API（SSE / 长连接）

| 引擎 | 服务器推送 | 协议 | 备注 |
|------|----------|------|------|
| PostgreSQL | LISTEN 帧（异步消息） | 前端协议 `A` 报文 | 客户端持连接 |
| Oracle | OCI Continuous Query Notification | OCI 回调 | -- |
| SQL Server | Service Broker 队列接收 | TDS 回执 | -- |
| Firebird | Event Manager 监听端口 | 私有 TCP | -- |
| Materialize | SUBSCRIBE 流 | pgwire COPY 流 | -- |
| RisingWave | SUBSCRIBE 流 | pgwire COPY 流 | -- |
| Flink SQL | Changelog stream | -- | -- |
| CockroachDB | Changefeed webhook / SSE | HTTP | -- |
| 其余 | -- | -- | 不支持 |

> 统计：原生支持服务器推送通道的引擎 < 10 个，绝大多数仍是"客户端发起 → 服务器响应"的拉模型。

## 各引擎详解

### PostgreSQL（业界事实标准 LISTEN/NOTIFY）

PostgreSQL 自 6.4 (1998) 起就实现了 LISTEN/NOTIFY，是开源数据库里最早的事件通知机制。

```sql
-- 会话 A：注册监听
LISTEN order_created;

-- 会话 B：发送通知
NOTIFY order_created, '{"order_id": 12345, "total": 99.50}';

-- 也可用函数形式（支持动态通道名 / 动态载荷）
SELECT pg_notify('order_created', '{"order_id": 12345}');

-- 取消监听
UNLISTEN order_created;
UNLISTEN *;  -- 取消所有
```

**核心语义**：

1. **载荷大小限制 8000 字节**：写死在 `src/include/commands/async.h` 的 `NOTIFY_PAYLOAD_MAX_LENGTH`，载荷过大需通过持久表传递引用
2. **事务提交后才投递**：NOTIFY 在 COMMIT 时才真正发送；如果事务回滚，通知不会发出
3. **去重**：同一事务中同一通道和载荷的 NOTIFY 会被合并为一条
4. **跨连接**：通知通过共享内存中的 NOTIFY 队列（`pg_notify` 目录）传递，任何监听该通道的连接都收到
5. **客户端必须主动消费**：libpq `PQconsumeInput` + `PQnotifies` 或 JDBC `PGConnection.getNotifications`

```sql
-- 触发器 + pg_notify 的典型组合：行变更推送
CREATE OR REPLACE FUNCTION notify_order_change() RETURNS trigger AS $$
BEGIN
  PERFORM pg_notify(
    'orders_channel',
    json_build_object(
      'op', TG_OP,
      'id', COALESCE(NEW.id, OLD.id),
      'ts', extract(epoch from now())
    )::text
  );
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER orders_notify
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW EXECUTE FUNCTION notify_order_change();
```

**客户端轮询模式**（Python psycopg）：

```python
import select, psycopg
conn = psycopg.connect("dbname=demo", autocommit=True)
conn.execute("LISTEN orders_channel")
while True:
    select.select([conn], [], [], 60)  # 阻塞至有 IO 或超时
    conn.execute("SELECT 1")  # 触发处理
    for n in conn.notifies():
        print(n.channel, n.payload)
```

**已知限制**：

- 通知队列上限默认 8GB（`max_notify_queue_pages * 8KB`），订阅者长时间不消费会阻塞所有写事务
- 不持久化：服务器重启后未投递的通知丢失
- 无序保证仅在单连接内成立
- 主备同步模式下，通知不会复制到 standby（standby 上 LISTEN 收不到主库 NOTIFY）

### Oracle（DBMS_ALERT + DBMS_AQ + Fast Application Notification）

Oracle 提供了三层不同语义的通知机制：

**1. DBMS_ALERT（轻量级会话内事件，类似 PG NOTIFY）**

```sql
-- 会话 A：注册并阻塞等待
DECLARE
  status  INTEGER;
  message VARCHAR2(1800);
BEGIN
  DBMS_ALERT.REGISTER('order_created');
  DBMS_ALERT.WAITONE('order_created', message, status, 60);
  DBMS_OUTPUT.PUT_LINE('收到: ' || message);
END;

-- 会话 B：发出信号（事务提交后投递）
BEGIN
  DBMS_ALERT.SIGNAL('order_created', 'order_id=12345');
  COMMIT;
END;
```

DBMS_ALERT 使用数据库锁实现，载荷为 VARCHAR2(1800)，名字 30 字节，单 RAC 节点内可靠，但在 RAC 多节点上有复杂语义。

**2. DBMS_AQ（Oracle Advanced Queuing，企业级队列）**

DBMS_AQ 是 Oracle 内置的完整 JMS 兼容消息队列，支持持久化、事务、订阅、多消费者、消息延迟、优先级、传播、规则路由——全部用 SQL 管理。

```sql
-- 创建消息类型
CREATE OR REPLACE TYPE order_msg AS OBJECT (
  order_id NUMBER,
  total    NUMBER,
  state    VARCHAR2(20)
);

-- 创建队列表与队列
BEGIN
  DBMS_AQADM.CREATE_QUEUE_TABLE(
    queue_table        => 'orders_qt',
    queue_payload_type => 'order_msg',
    multiple_consumers => TRUE);
  DBMS_AQADM.CREATE_QUEUE('orders_q', 'orders_qt');
  DBMS_AQADM.START_QUEUE('orders_q');
END;

-- 入队
DECLARE
  enq_opt    DBMS_AQ.ENQUEUE_OPTIONS_T;
  msg_props  DBMS_AQ.MESSAGE_PROPERTIES_T;
  msg_id     RAW(16);
BEGIN
  DBMS_AQ.ENQUEUE(
    queue_name         => 'orders_q',
    enqueue_options    => enq_opt,
    message_properties => msg_props,
    payload            => order_msg(12345, 99.50, 'NEW'),
    msgid              => msg_id);
  COMMIT;
END;

-- 出队
DECLARE
  deq_opt    DBMS_AQ.DEQUEUE_OPTIONS_T;
  msg_props  DBMS_AQ.MESSAGE_PROPERTIES_T;
  msg_id     RAW(16);
  payload    order_msg;
BEGIN
  deq_opt.wait := DBMS_AQ.FOREVER;
  DBMS_AQ.DEQUEUE(
    queue_name         => 'orders_q',
    dequeue_options    => deq_opt,
    message_properties => msg_props,
    payload            => payload,
    msgid              => msg_id);
END;
```

OCI 客户端可注册回调接收"消息可用"通知，避免轮询。AQ 还支持通过 PROPAGATE 在多个数据库之间复制消息，是 Oracle Streams 的底层基础。21c 改名为 **Transactional Event Queues (TxEventQ)**，提供 Kafka 兼容的客户端接口。

**3. Fast Application Notification (FAN)**

FAN 是 Oracle RAC / Data Guard 集群事件（节点上下线、服务迁移）的推送机制，通过 ONS（Oracle Notification Service）协议发送，主要用于客户端连接池快速失效，不用于行级数据通知。

**4. Database Change Notification (DCN / Continuous Query Notification)**

OCI 注册一个 SELECT，当结果集可能变化时数据库回调客户端：

```sql
-- 通过 OCI / JDBC oracle.jdbc.dcn 包注册
-- SQL 语法不直接暴露
```

DCN 是 SqlDependency 的 Oracle 等价物，依赖跟踪查询涉及的对象与 ROWID 变化。

### SQL Server（Service Broker + Query Notifications + SqlDependency）

SQL Server 2005 引入 Service Broker (SSB)，是一个完整的事务性消息系统：

```sql
-- 1. 启用 Broker
ALTER DATABASE Demo SET ENABLE_BROKER;

-- 2. 创建消息类型 / 契约
CREATE MESSAGE TYPE OrderEventMsg VALIDATION = WELL_FORMED_XML;
CREATE CONTRACT OrderContract (OrderEventMsg SENT BY INITIATOR);

-- 3. 创建队列与服务
CREATE QUEUE OrderQueue;
CREATE SERVICE OrderService ON QUEUE OrderQueue (OrderContract);

-- 4. 发送消息
DECLARE @h UNIQUEIDENTIFIER;
BEGIN DIALOG @h FROM SERVICE OrderService TO SERVICE 'OrderService'
  ON CONTRACT OrderContract WITH ENCRYPTION = OFF;
SEND ON CONVERSATION @h MESSAGE TYPE OrderEventMsg ('<o id="123"/>');

-- 5. 接收（阻塞 60s）
WAITFOR (
  RECEIVE TOP(1) conversation_handle, message_body FROM OrderQueue
), TIMEOUT 60000;
```

**Query Notifications / SqlDependency** 构建在 Service Broker 之上：客户端用 `SqlDependency.Start()` 注册，SQL Server 会在底层创建 SSB 队列；当注册的 SELECT 结果可能变化时（通过查询缓存依赖项判定），数据库通过 SSB 把"失效"消息送回。.NET 的 `SqlDependency` / `SqlNotificationRequest` 是其客户端 API。

```csharp
// .NET 客户端示例（简化）
var cmd = new SqlCommand("SELECT id, qty FROM dbo.orders WHERE status='NEW'", conn);
var dep = new SqlDependency(cmd);
dep.OnChange += (s, e) => Console.WriteLine("结果集失效: " + e.Type);
SqlDependency.Start(connStr);
cmd.ExecuteReader();
```

限制：仅支持很受限的 SELECT 子集（无 TOP、无聚合、无 OUTER JOIN、必须 schema 限定表名等），载荷只有"失效"事件本身而非行级数据。

### DB2（WebSphere MQ 集成）

DB2 没有内建的 LISTEN/NOTIFY，而是通过与 IBM MQ 的紧密集成提供消息能力——`MQSEND`、`MQREAD`、`MQRECEIVE` 等内置 UDF 把队列暴露为 SQL：

```sql
-- 把行变化通过触发器发送到 MQ
CREATE TRIGGER notify_order
AFTER INSERT ON orders
REFERENCING NEW AS n
FOR EACH ROW
BEGIN ATOMIC
  VALUES MQSEND('ORDERS_QUEUE', '{"id":' || CHAR(n.id) || '}');
END;

-- 接收方
SELECT MQREAD('ORDERS_QUEUE') FROM SYSIBM.SYSDUMMY1;
```

InfoSphere CDC（前 Q Replication）则提供基于日志的复制和事件分发能力，与本文 LISTEN/NOTIFY 主题不直接相关。

### Firebird（Events 与 POST_EVENT）

Firebird 自 InterBase 时代起就提供原生事件机制：触发器或存储过程调用 `POST_EVENT` 通知客户端。

```sql
SET TERM ^ ;
CREATE TRIGGER orders_after_insert FOR orders
AFTER INSERT
AS
BEGIN
  POST_EVENT 'order_created';
END^
SET TERM ; ^
```

客户端通过 `isc_que_events` API（或现代驱动如 fbclient .NET / Jaybird）注册事件回调，事件名最长 31 字符，**不携带任何载荷**（仅事件名 + 计数）。事件在事务提交后投递，且 Firebird 会合并同名事件计数（"在两次轮询之间该事件发生 N 次"）。这是最简洁但表达力最弱的设计。

### Materialize（TAIL / SUBSCRIBE）

Materialize 是流式数据库，其"事件通知"以 SUBSCRIBE（旧名 TAIL）形式呈现：在任意视图上订阅增量变化。

```sql
-- 订阅一个物化视图的变更流
COPY (SUBSCRIBE TO orders_summary WITH (PROGRESS, SNAPSHOT)) TO STDOUT;

-- 客户端通过 pgwire COPY OUT 流持续接收 (mz_timestamp, mz_diff, ...) 行
-- mz_diff = +1 表示新增，-1 表示删除
```

每行包含一个时间戳和一个 diff 计数，使下游可以重建准确的变更日志。这本质上是把所有 SELECT 都变成"持续查询"，是 LISTEN/NOTIFY 的"声明式 + 强一致"升级版。

### RisingWave（SUBSCRIBE）

RisingWave 1.7+ 引入 `SUBSCRIBE` 子句，语义类似 Materialize：

```sql
CREATE SUBSCRIPTION orders_sub FROM orders WITH (retention = '1D');

-- 流式拉取
DECLARE cur SUBSCRIPTION CURSOR FOR orders_sub;
FETCH NEXT FROM cur;
```

其变更行带有 `op` 列指示 INSERT/UPDATE/DELETE，便于下游构建实时 UI。

### YugabyteDB（继承 PG + 自身 CDC）

YugabyteDB 部分继承 PostgreSQL 的 LISTEN/NOTIFY 语法，但因为它是分布式数据库，跨节点 NOTIFY 投递有一致性折扣：在多 tablet 模式下 NOTIFY 实际上仅在发送方所在节点的会话间传递，跨节点订阅推荐改用 YugabyteDB CDC（兼容 Debezium）。

### CockroachDB（CHANGEFEED 取代 LISTEN/NOTIFY）

CockroachDB 没有 LISTEN/NOTIFY，但提供了原生 CDC：

```sql
-- 投递到 Kafka
CREATE CHANGEFEED FOR TABLE orders
INTO 'kafka://broker:9092'
WITH updated, resolved='10s';

-- 投递到 HTTPS Webhook
CREATE CHANGEFEED FOR TABLE orders
INTO 'webhook-https://hooks.example.com/ingest?secret=xxx'
WITH updated, resolved='10s';
```

CockroachDB 的 webhook sink 让数据库直接 POST JSON 到 HTTP 端点，是少数原生支持"数据库 → HTTP"的通知形态。

### Snowflake（Streams 是日志而非推送）

Snowflake Streams 提供"自从上次消费以来的变更"视图，需要 Task 调度处理：

```sql
CREATE STREAM orders_stream ON TABLE orders;

CREATE TASK process_orders
  WAREHOUSE = my_wh
  SCHEDULE = '1 minute'
WHEN SYSTEM$STREAM_HAS_DATA('orders_stream')
AS
  INSERT INTO orders_audit
  SELECT *, METADATA$ACTION FROM orders_stream;
```

这是拉模型而非推模型；Snowflake 另有 **Notification Integration**，可以让 Task / 存储过程通过 SQS / Pub/Sub 发出消息，是其唯一的"推"通道。

### ClickHouse（无内建通知，依赖物化视图与 Kafka 引擎）

ClickHouse 设计上不支持事件通知。常见实践：

```sql
-- Kafka 引擎表 + 物化视图：把表变化"推"到 Kafka
CREATE TABLE orders_kafka (
  id UInt64, total Float64
) ENGINE = Kafka
SETTINGS kafka_broker_list='kafka:9092',
         kafka_topic_list='orders_out',
         kafka_format='JSONEachRow';

CREATE MATERIALIZED VIEW orders_to_kafka
TO orders_kafka AS
SELECT id, total FROM orders;
```

但这是"写入时复制"，订阅者在 Kafka 侧消费，ClickHouse 自身没有客户端可挂载的事件流。

### MySQL / MariaDB（彻底缺失）

MySQL 与 MariaDB 完全没有 LISTEN/NOTIFY 等价物。常见替代方案：

1. 应用端轮询 `updated_at` 索引列
2. binlog 客户端（mysqlbinlog / Canal / Maxwell / Debezium）— 拉日志解析
3. UDF 编写 socket / HTTP 推送插件（如 mysql-udf-http）

### SQLite（嵌入式，可用 update_hook）

SQLite 嵌入在进程内，不需要"通知"层；但 C API 提供 `sqlite3_update_hook(db, cb, arg)`，注册行级回调，可用于构建简单的内存事件总线。SQL 层无 LISTEN/NOTIFY。

### 其他 OLAP / 流处理引擎

BigQuery、Redshift、Athena、Synapse、Spanner、Vertica、Greenplum (OLAP) 等分析型数据库均无客户端事件通知机制——它们的设计目标是大批量分析查询，事件推送被视为外围系统（Pub/Sub、SNS、EventBridge）的职责。

## PostgreSQL LISTEN/NOTIFY 深度解析

### 8000 字节载荷限制的来源

```c
/* src/include/commands/async.h（PostgreSQL 源码） */
#define NOTIFY_PAYLOAD_MAX_LENGTH (BLCKSZ - NAMEDATALEN - 128)
```

`BLCKSZ` 默认 8192，减去通道名（`NAMEDATALEN = 64`）和定长头部，剩下约 8000 字节。改大需重编译 PostgreSQL 并改 `BLCKSZ`，会影响所有页存储。绝大多数应用做法是把大载荷写入"消息表"，NOTIFY 中只携带主键，订阅方收到通知后再 SELECT。

### 事务语义

NOTIFY 是事务性的：

1. NOTIFY 命令立即把通知放进会话本地 NOTIFY 列表
2. COMMIT 时通知被复制到全局共享 NOTIFY 队列
3. 监听该通道的所有后端进程被信号唤醒
4. 客户端在下次 IO 时收到 `NotificationResponse` 帧

如果事务回滚，NOTIFY 也跟着回滚——这是 PostgreSQL 与 RabbitMQ 等外部消息队列的关键区别：与业务数据修改原子提交，避免"消息发出但数据未提交"的不一致。

### 队列溢出与消费者必须及时处理

NOTIFY 队列存储于 `pg_notify` 目录的 SLRU 缓冲，默认上限 8GB（PG 13+）。一旦某个 LISTEN 连接长时间不消费，未读通知堆积会阻塞所有写事务（NOTIFY 报错）。监控建议：

```sql
-- PG 13+
SELECT pg_notification_queue_usage();  -- 0.0 ~ 1.0
-- 接近 1 时立即排查 LISTEN 久挂连接
SELECT pid, application_name, state, query_start
FROM pg_stat_activity
WHERE wait_event = 'AsyncCtlLock' OR query LIKE 'LISTEN%';
```

### 客户端必须主动 IO

PostgreSQL 协议中通知是"附带在响应中"的——服务器只在已有 IO 通道时把 `NotificationResponse` 帧发出。客户端必须：

- 持有打开的连接
- 通过 `PQconsumeInput` / `select()` 监听套接字可读
- 调用 `PQnotifies` 取出已收到的通知

很多语言驱动封装了"异步通知线程"，如 JDBC 在 `getNotifications(timeout)` 里自动 ping。若整段时间没有发送任何 SQL，某些驱动可能要求显式 `SELECT 1` 才会触发协议读。

## Oracle Advanced Queuing (AQ) 作为完整消息队列

AQ 与"数据库轻量通知"不同，它是企业级 JMS：

| 能力 | DBMS_ALERT | DBMS_AQ |
|------|-----------|---------|
| 持久化 | 否（内存锁） | 是（队列表） |
| 事务一致 | 部分（commit 投递） | 完全（与业务事务同 commit） |
| 多消费者 | 否（每个会话独立） | 是（订阅、规则路由） |
| 优先级 | 否 | 是 |
| 延迟投递 | 否 | 是（DELAY） |
| 过期 | 否 | 是（EXPIRATION） |
| 跨数据库传播 | 否 | 是（PROPAGATION） |
| JMS 兼容 | 否 | 是（aqapi.jar） |
| 类型安全 | VARCHAR2 | 用户对象 / RAW / XML / JSON |

**TxEventQ (21c+)** 是 AQ 的重写版本，使用 sharded 队列实现 Kafka 级吞吐，并提供 Kafka 兼容的客户端 API——业务可以直接用 Kafka SDK 连 Oracle 数据库。这让 Oracle 成为目前唯一一个把"分布式日志"类消息系统嵌入数据库引擎的商用 RDBMS。

```sql
-- 21c TxEventQ 创建
EXEC DBMS_AQADM.CREATE_SHARDED_QUEUE('orders_kafka_q', queue_payload_type=>'JSON');
EXEC DBMS_AQADM.START_QUEUE('orders_kafka_q');

-- Java 客户端可用 Kafka API 消费 orders_kafka_q
```

## 关键发现

1. **没有标准**：SQL 标准从未定义事件通知。LISTEN/NOTIFY 是 PostgreSQL 1998 年的扩展，DBMS_ALERT 是 Oracle 8i 的扩展，Service Broker 是 SQL Server 2005 的扩展——三者完全不兼容。
2. **PostgreSQL 是开源生态事实标准**：PG 系（PG / Greenplum / TimescaleDB / 部分 YugabyteDB）是仅有的原生支持 SQL 级 `LISTEN`/`NOTIFY` 的开源数据库；其余 40+ 引擎全部缺失。
3. **载荷大小普遍受限**：PostgreSQL 8000 字节、Oracle DBMS_ALERT 1800 字节、Firebird 仅事件名（无载荷）。"大消息走表，通道传引用"是普遍模式。
4. **MySQL / MariaDB 完全缺失**：这是最大的开源 RDBMS 阵营的盲区，催生了 Canal / Maxwell / Debezium 等"伪推送"基于 binlog 的工具链。
5. **OLAP / 云数仓全部缺失**：Snowflake、BigQuery、Redshift、ClickHouse、Vertica、Athena、Synapse 都没有客户端事件订阅；它们假定推送是外部 Pub/Sub 服务的职责。
6. **Oracle 是最完备的**：DBMS_ALERT（轻量）+ DBMS_AQ / TxEventQ（队列）+ DCN（查询失效）+ FAN（集群事件）四层覆盖；其他厂商最多 1-2 层。
7. **事务语义是分水岭**：PG NOTIFY、Oracle AQ、SQL Server Service Broker 都做到"与业务事务原子提交"，避免外部消息队列的"双写一致性"陷阱。
8. **流式数据库正在重新定义事件**：Materialize 的 SUBSCRIBE、RisingWave 的 SUBSCRIBE 把所有视图都变成"持续查询"，让任意 SELECT 自动获得增量推送能力——这是 LISTEN/NOTIFY 之上的下一代范式。
9. **CockroachDB 走 Webhook 路线**：跳过 LISTEN/NOTIFY，直接让 CHANGEFEED 把 JSON POST 到 HTTPS 端点，把"通知"和"传输协议"绑定到 HTTP 这个最通用的胶水层。
10. **客户端协议是隐形门槛**：即便数据库支持事件通知，客户端驱动也得显式实现"异步消息读取循环"——许多 ORM（Hibernate、SQLAlchemy 早期版本）都没有暴露这一能力，开发者必须降级到原生驱动。
11. **持久化与可靠性需要队列而非通知**：LISTEN/NOTIFY 在服务器重启或客户端断连时会丢失；要可靠投递必须使用 AQ / Service Broker / 持久化消息表。把通知与持久化混为一谈是最常见的设计错误。
12. **CDC 是事件通知的"替代解"**：当数据库不支持 LISTEN/NOTIFY 时，绝大多数团队的实际方案是接 CDC（Debezium、Canal、Flink CDC）。这导致"事件通知"事实上从数据库内部职责外移到了消息系统层——见 [`cdc-changefeed.md`](cdc-changefeed.md)。

> 选型建议：**OLTP 实时 UI 推送**首选 PostgreSQL LISTEN/NOTIFY 或 Oracle AQ；**企业级可靠队列**用 Oracle AQ 或 SQL Server Service Broker；**跨数据库统一事件总线**走 CDC + Kafka；**实时分析视图推送**用 Materialize / RisingWave SUBSCRIBE；**云数仓**接受拉模型 + 外部 Pub/Sub。
