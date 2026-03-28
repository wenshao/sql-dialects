# 变更数据捕获 (CDC)

实时获取数据库中的数据变更——从 binlog 解析到内置 CHANGEFEED，CDC 是现代数据架构的核心能力。

## 支持矩阵

| 引擎 | CDC 机制 | 方式 | 延迟 | 备注 |
|------|---------|------|------|------|
| MySQL | binlog | 外部工具解析 | 秒级 | Debezium / Canal / Maxwell |
| PostgreSQL | WAL + Logical Replication | 外部工具或内置 | 秒级 | Debezium / pgoutput |
| CockroachDB | CHANGEFEED | **内置 SQL 语法** | 毫秒级 | 最现代的设计 |
| Snowflake | Streams + Tasks | 内置 | 分钟级 | 基于快照差异 |
| Oracle | LogMiner / GoldenGate | 日志解析 / 商业工具 | 秒级 | GoldenGate 是商业产品 |
| SQL Server | CDC / Change Tracking | 内置 | 秒级 | 两种不同机制 |
| TiDB | TiCDC | 内置组件 | 秒级 | 基于 Raft Log |
| MongoDB | Change Streams | 内置 API | 毫秒级 | 基于 oplog |
| DynamoDB | DynamoDB Streams | 内置 | 毫秒级 | AWS 原生 |

## 设计动机

### 为什么需要 CDC

```
传统方式: 定时全量同步
┌─────────┐    每小时全量导出    ┌─────────┐
│  OLTP   │ ──────────────────→ │  OLAP   │
│ (MySQL) │                     │ (数据仓) │
└─────────┘                     └─────────┘
问题: 延迟高（小时级）、资源浪费（大量不变的数据重复传输）、对源库压力大

CDC 方式: 增量实时同步
┌─────────┐    实时变更流    ┌─────────┐
│  OLTP   │ ────────────→ │  OLAP   │
│ (MySQL) │    (INSERT/    │ (数据仓) │
└─────────┘  UPDATE/DELETE) └─────────┘
优势: 延迟低（秒级）、只传输变更数据、对源库影响小
```

### CDC 的核心应用

1. **数据库同步**: MySQL → BigQuery / Snowflake / ClickHouse
2. **缓存失效**: 数据变更时自动更新 Redis 缓存
3. **搜索索引同步**: 数据变更时自动更新 Elasticsearch 索引
4. **事件驱动架构**: 数据变更触发业务流程
5. **审计日志**: 记录所有数据变更历史

## 三种 CDC 实现方式

1. 基于日志 (Log-based)

```
数据库写入操作
    ↓
Write-Ahead Log (WAL / binlog / redo log)
    ↓
CDC 工具解析日志
    ↓
变更事件流 (INSERT/UPDATE/DELETE)

优点: 对源库零侵入、捕获所有变更（包括 DELETE）、可重放
缺点: 需要解析二进制日志格式、依赖日志保留策略
代表: MySQL binlog, PostgreSQL WAL, Oracle LogMiner
```

2. 基于触发器 (Trigger-based)

```
数据库写入操作
    ↓
触发器被触发
    ↓
变更信息写入影子表
    ↓
CDC 工具轮询影子表

优点: 不依赖日志格式、任何数据库都能实现
缺点: 性能开销大（每次写入多一次触发器执行）、增加事务复杂度
代表: Debezium 的 SQL Server 早期方案
```

3. 基于快照差异 (Snapshot-based)

```
定时拍摄数据快照
    ↓
与上一个快照对比
    ↓
差异作为变更事件

优点: 实现简单、不依赖数据库特性
缺点: 无法捕获中间状态、延迟高、消耗大量资源做对比
代表: Snowflake Streams, Airbyte 增量同步
```

## 各引擎 CDC 实现

### MySQL binlog + Debezium/Canal

```sql
-- 1. 配置 MySQL 启用 binlog（ROW 格式）
-- my.cnf:
-- server-id = 1
-- log_bin = mysql-bin
-- binlog_format = ROW
-- binlog_row_image = FULL       -- 记录完整的前后值

-- 确认 binlog 状态
SHOW VARIABLES LIKE 'log_bin';
SHOW VARIABLES LIKE 'binlog_format';
SHOW MASTER STATUS;
SHOW BINARY LOGS;

-- 2. 创建 CDC 专用用户
CREATE USER 'cdc_user'@'%' IDENTIFIED BY 'password';
GRANT SELECT, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'cdc_user'@'%';

-- 3. 查看 binlog 事件（调试用）
SHOW BINLOG EVENTS IN 'mysql-bin.000001' LIMIT 100;

-- Debezium 配置（JSON 格式，通过 Kafka Connect 部署）:
-- {
--   "connector.class": "io.debezium.connector.mysql.MySqlConnector",
--   "database.hostname": "mysql-host",
--   "database.port": "3306",
--   "database.user": "cdc_user",
--   "database.server.id": "184054",
--   "database.include.list": "mydb",
--   "table.include.list": "mydb.orders",
--   "topic.prefix": "mysql-cdc"
-- }

-- Canal（阿里巴巴开源）: 伪装为 MySQL Slave，接收 binlog
-- 适合国内 MySQL 生态
```

### PostgreSQL WAL + Logical Replication

```sql
-- 1. 配置 PostgreSQL（postgresql.conf）
-- wal_level = logical              -- 必须是 logical 级别
-- max_replication_slots = 10
-- max_wal_senders = 10

-- 2. 创建发布（Publication）
CREATE PUBLICATION my_pub FOR TABLE orders, customers;
-- 或者发布所有表:
CREATE PUBLICATION all_changes FOR ALL TABLES;

-- 3. 创建逻辑复制槽
SELECT pg_create_logical_replication_slot('my_slot', 'pgoutput');

-- 4. 查看逻辑复制槽
SELECT * FROM pg_replication_slots;

-- 5. 消费变更（使用 pg_logical_slot_get_changes）
SELECT * FROM pg_logical_slot_get_changes('my_slot', NULL, NULL);
-- 返回: lsn, xid, data（JSON 格式的变更事件）

-- 6. 或者使用标准逻辑复制创建订阅（另一个 PG 实例）
CREATE SUBSCRIPTION my_sub
    CONNECTION 'host=source-host dbname=mydb'
    PUBLICATION my_pub;

-- Debezium 也支持 PostgreSQL:
-- 使用 pgoutput 或 wal2json 插件解析 WAL
-- 优势: 比 MySQL binlog 更标准化、更灵活
```

### CockroachDB CHANGEFEED（内置 SQL 语法）

```sql
-- CockroachDB 提供最现代的 CDC 设计: 直接用 SQL 创建变更流

-- 创建 CHANGEFEED（输出到 Kafka）
CREATE CHANGEFEED FOR TABLE orders, customers
INTO 'kafka://kafka-host:9092'
WITH updated, resolved = '10s', format = json;

-- 创建 CHANGEFEED（输出到云存储）
CREATE CHANGEFEED FOR TABLE orders
INTO 's3://my-bucket/cdc/?AWS_ACCESS_KEY_ID=xxx&AWS_SECRET_ACCESS_KEY=xxx'
WITH updated, resolved = '30s', format = csv;

-- 创建 CHANGEFEED（输出到 webhook）
CREATE CHANGEFEED FOR TABLE orders
INTO 'webhook-https://my-api.com/cdc'
WITH updated, format = json;

-- 监控 CHANGEFEED
SHOW CHANGEFEED JOBS;

-- 暂停 / 恢复
PAUSE JOB (SELECT job_id FROM [SHOW CHANGEFEED JOBS] WHERE description LIKE '%orders%');
RESUME JOB 123456;

-- 核心 CHANGEFEED 事件格式:
-- {"after": {"id": 1, "amount": 100}, "key": [1], "updated": "1617..."} -- INSERT/UPDATE
-- {"after": null, "key": [1], "updated": "1617..."}                     -- DELETE

-- WITH 选项:
-- updated:       包含更新时间戳
-- resolved:      定期发送解析时间戳（表示此前的变更已全部发送）
-- diff:          包含变更前的值
-- schema_change_events: 包含 schema 变更事件
-- initial_scan:  首次运行时包含现有数据的全量快照
```

### Snowflake Streams + Tasks

```sql
-- Snowflake 的 CDC: 基于快照差异的 Streams

-- 1. 创建 Stream（变更追踪）
CREATE STREAM orders_changes ON TABLE orders;

-- 2. Stream 自动捕获 INSERT/UPDATE/DELETE
INSERT INTO orders VALUES (1, 'Alice', 100);
UPDATE orders SET amount = 200 WHERE id = 1;
DELETE FROM orders WHERE id = 1;

-- 3. 查询 Stream 获取变更
SELECT * FROM orders_changes;
-- 返回: 原始列 + METADATA$ACTION + METADATA$ISUPDATE + METADATA$ROW_ID

-- METADATA$ACTION: INSERT 或 DELETE
-- METADATA$ISUPDATE: TRUE 表示这是 UPDATE（一对 DELETE + INSERT）
-- UPDATE 表现为两行: 一行 DELETE（旧值），一行 INSERT（新值）

-- 4. 消费 Stream（在 DML 事务中，消费后 Stream 自动清空）
CREATE TABLE orders_history AS
SELECT *, CURRENT_TIMESTAMP() AS captured_at
FROM orders_changes;
-- 执行后 orders_changes 变为空（已消费）

-- 5. 自动化: 使用 Task 定时消费 Stream
CREATE TASK consume_orders_changes
    WAREHOUSE = my_wh
    SCHEDULE = '5 minute'                    -- 每 5 分钟执行
    WHEN SYSTEM$STREAM_HAS_DATA('orders_changes')  -- 有数据时才执行
AS
    INSERT INTO orders_history
    SELECT *, CURRENT_TIMESTAMP()
    FROM orders_changes;

ALTER TASK consume_orders_changes RESUME;    -- 启用 Task
```

### SQL Server CDC / Change Tracking

```sql
-- SQL Server 提供两种不同的变更捕获机制:

-- === CDC (Change Data Capture) === --
-- 基于事务日志，捕获完整的变更历史

-- 1. 在数据库级别启用 CDC
EXEC sys.sp_cdc_enable_db;

-- 2. 在表级别启用 CDC
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'orders',
    @role_name = N'cdc_reader',
    @supports_net_changes = 1;         -- 支持净变更查询

-- 3. 查询变更（按 LSN 范围）
DECLARE @from_lsn BINARY(10) = sys.fn_cdc_get_min_lsn('dbo_orders');
DECLARE @to_lsn BINARY(10) = sys.fn_cdc_get_max_lsn();

SELECT * FROM cdc.fn_cdc_get_all_changes_dbo_orders(
    @from_lsn, @to_lsn, 'all update old');

-- 4. 净变更查询（合并同一行的多次变更）
SELECT * FROM cdc.fn_cdc_get_net_changes_dbo_orders(
    @from_lsn, @to_lsn, 'all');

-- __$operation 列:
-- 1 = DELETE, 2 = INSERT, 3 = UPDATE (before), 4 = UPDATE (after)

-- === Change Tracking === --
-- 更轻量级，只跟踪"哪些行变了"，不记录历史值

ALTER DATABASE mydb SET CHANGE_TRACKING = ON
    (CHANGE_RETENTION = 2 DAYS, AUTO_CLEANUP = ON);

ALTER TABLE orders ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON);

-- 查询变更
SELECT ct.id, ct.SYS_CHANGE_OPERATION, ct.SYS_CHANGE_VERSION
FROM CHANGETABLE(CHANGES orders, @last_sync_version) AS ct;
-- SYS_CHANGE_OPERATION: I (INSERT), U (UPDATE), D (DELETE)
```

### Flink CDC Connectors

```sql
-- Flink SQL 可以直接将数据库变更作为流表消费

-- MySQL CDC 源表
CREATE TABLE orders_cdc (
    id INT,
    customer_name STRING,
    amount DECIMAL(10, 2),
    order_time TIMESTAMP(3),
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'mysql-cdc',
    'hostname' = 'mysql-host',
    'port' = '3306',
    'username' = 'cdc_user',
    'password' = 'password',
    'database-name' = 'mydb',
    'table-name' = 'orders'
);

-- 实时聚合
SELECT customer_name, SUM(amount) AS total
FROM orders_cdc
GROUP BY customer_name;

-- PostgreSQL CDC 源表
CREATE TABLE pg_orders_cdc (
    id INT,
    amount DECIMAL(10, 2),
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'postgres-cdc',
    'hostname' = 'pg-host',
    'database-name' = 'mydb',
    'schema-name' = 'public',
    'table-name' = 'orders',
    'slot.name' = 'flink_slot',
    'decoding.plugin.name' = 'pgoutput'
);

-- CDC 到 Sink（例如写入 Elasticsearch）
INSERT INTO es_orders
SELECT * FROM orders_cdc;
```

## 设计对比

| 维度 | 基于日志 | 基于触发器 | 基于快照 |
|------|---------|-----------|---------|
| 性能影响 | 极小（读已有日志） | 大（写入额外表） | 中（定时扫描） |
| 延迟 | 毫秒~秒级 | 毫秒~秒级 | 分钟~小时级 |
| 完整性 | 所有变更 | 所有变更 | 可能丢失中间状态 |
| 实现复杂度 | 高（解析日志格式） | 低 | 低 |
| DELETE 捕获 | 支持 | 支持 | 困难 |
| Schema 变更 | 需特殊处理 | 需更新触发器 | 自动适应 |
| 代表 | MySQL binlog, PG WAL | 早期 CDC 工具 | Snowflake Streams |

## 对引擎开发者的建议

### CDC 作为核心能力

CDC 已经从"可选特性"变为"核心能力"。现代数据架构（Data Mesh、实时数仓）都依赖 CDC。

引擎应该像 CockroachDB 一样提供内置的 CDC 语法：

```sql
-- 建议的语法设计
CREATE CHANGEFEED [name]
    FOR TABLE table1 [, table2, ...]
    INTO 'sink_url'                    -- kafka:// | s3:// | webhook://
    WITH (
        format = JSON | AVRO | CSV,
        envelope = DEBEZIUM | PLAIN,   -- 事件包装格式
        updated = TRUE,                -- 包含时间戳
        initial_snapshot = TRUE,       -- 初始全量快照
        schema_change = INCLUDE        -- 包含 schema 变更
    );
```

### 关键设计决策

1. **事件格式**: Debezium 格式已成为事实标准（before/after/source/op）
2. **初始快照**: 首次启动时需要一致性快照，这对大表是个挑战
3. **Schema 演进**: 上游表 ALTER TABLE 后，CDC 事件的 schema 如何变化
4. **Exactly-once**: 如何保证每个变更恰好被捕获和传递一次
5. **回溯能力**: 能否从过去某个时间点重新消费变更

## 参考资料

- Debezium: [Documentation](https://debezium.io/documentation/)
- CockroachDB: [CHANGEFEED](https://www.cockroachlabs.com/docs/stable/create-changefeed)
- Snowflake: [Streams](https://docs.snowflake.com/en/sql-reference/sql/create-stream)
- SQL Server: [Change Data Capture](https://learn.microsoft.com/en-us/sql/relational-databases/track-changes/about-change-data-capture-sql-server)
- PostgreSQL: [Logical Replication](https://www.postgresql.org/docs/current/logical-replication.html)
- Flink CDC: [Documentation](https://ververica.github.io/flink-cdc-connectors/)
- Canal: [GitHub](https://github.com/alibaba/canal)
