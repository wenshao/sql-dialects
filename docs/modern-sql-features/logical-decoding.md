# 逻辑解码 (Logical Decoding)

物理 WAL 是一串磁盘字节，逻辑解码把这串字节翻译回"INSERT 这一行、UPDATE 那一列、DELETE 这条记录"。这一步看似简单，却是 CDC、跨版本升级、异构同步、缓存失效、搜索索引更新——整个现代数据集成生态的地基。本文梳理 45+ 引擎的逻辑解码机制，从 PostgreSQL 9.4 的 Logical Decoding API 到 MySQL binlog 的 ROWS_EVENT 二进制格式，再到 Debezium、Maxwell、Canal 三大开源连接器的设计差异。

## 不存在 SQL 标准

逻辑解码完全没有 ISO SQL 标准。ISO/IEC 9075 从未涉及"如何把 WAL 翻译成行级事件"，所有相关的接口、事件格式、复制槽语义、输出插件协议都是厂商私有：

- PostgreSQL 用 Logical Decoding API + output plugin（C 语言回调）
- MySQL 用 binlog dump 协议 + ROWS_EVENT 二进制格式
- Oracle 用 LogMiner 视图或 GoldenGate 的 trail 文件
- SQL Server 用 cdc.* 系统表
- CockroachDB 用 CHANGEFEED 直接产出 JSON/Avro
- TiDB 用 TiCDC 自定义 Open Protocol

这种百花齐放的局面意味着：

1. **跨引擎不可移植**：为 MySQL 写的 binlog 解析器无法直接读 PostgreSQL WAL；为 PostgreSQL 写的 output plugin（C 语言 ABI）无法在 MySQL 上加载。
2. **生态被连接器统一**：Debezium 通过为每个数据库实现独立的 connector，对外提供统一的 Kafka Connect 事件格式（Debezium Envelope）——这成了事实标准，但仍是社区自发约定，不是 ISO 标准。
3. **版本碎片化严重**：同一个数据库的不同版本，甚至同一版本的不同插件，事件格式都可能不同（PG 的 `wal2json` v1 / v2，`pgoutput` v1 / v2 / v3 / v4 协议版本……）。

> 与本文相关的两篇姊妹文：`cdc-changefeed.md` 聚焦"对外暴露变更流"的产品形态（Debezium、CockroachDB CHANGEFEED 等），`logical-replication-gtid.md` 聚焦"内置发布订阅"和事务标识体系（GTID/LSN/SCN）。本文则深入"WAL → 行事件"的翻译层。

## 支持矩阵（45+ 引擎）

### 1. 逻辑解码原生支持

| 引擎 | 解码接口 | 输出形式 | 起始版本 | 备注 |
|------|---------|---------|---------|------|
| PostgreSQL | Logical Decoding API | output plugin (C) | 9.4 (2014) | 业界最干净的设计 |
| MySQL | binlog dump 协议 | ROWS_EVENT 二进制 | 5.1+ (RBR, 2008) | 客户端解析 |
| MariaDB | binlog dump 协议 | ROWS_EVENT (兼容 + 扩展) | 继承 5.1+ | annotate_rows 增强 |
| SQLite | -- | -- | 不支持 | 嵌入式无日志解码 |
| Oracle | LogMiner / XStream | V$LOGMNR_CONTENTS / XStream API | 早期 | LogMiner 自 8i |
| Oracle GoldenGate | Extract / Trail | trail 文件 | 1999+ | 商业产品 |
| SQL Server | CDC 表 / Transactional Repl | cdc.* 表 / Distributor | 2008 | 写入辅助表 |
| DB2 | InfoSphere CDC / Q Capture | CD 表 / MQ 队列 | 早期 | 商业组件 |
| Snowflake | Streams (快照差异) | METADATA$* 列 | GA | 非真正解码 |
| BigQuery | -- | -- (依赖 Datastream) | 不支持 | 无内置解码 |
| Redshift | -- | -- | 不支持 | -- |
| DuckDB | -- | -- | 不支持 | 嵌入式 |
| ClickHouse | -- | -- (但能消费 PG/MySQL 流) | 21.4+ (实验) | MaterializedPostgreSQL |
| Trino | -- | -- (查询引擎) | 不适用 | -- |
| Presto | -- | -- (查询引擎) | 不适用 | -- |
| Spark SQL | -- | -- (查询引擎) | 不适用 | -- |
| Hive | -- | REPL DUMP (库级) | 3.0+ | 非行级解码 |
| Flink SQL | -- | -- (流处理引擎) | 不适用 | 但有 CDC connector |
| Databricks | Delta CDF | Change Data Feed | 2021+ | Delta 表特性 |
| Teradata | -- | Replication Services | 早期 | 商业 |
| Greenplum | -- | -- | 不支持 | -- |
| CockroachDB | CHANGEFEED (内置 SQL) | JSON / Avro | 2.1 (2018) | 直接输出 |
| TiDB | TiCDC (订阅 KV change feed) | Open Protocol / Avro | 4.0 (2020) | 跳过 SQL 层 |
| OceanBase | OBCDC / OMS | LogStore protocol | 3.x (2021) | 兼容 binlog |
| YugabyteDB | xCluster / CDC Connector | 类 PG 协议 | 2.12+ | 基于 WAL |
| SingleStore | Pipelines (读侧) | -- | 6.0+ | 入口 connector |
| Vertica | -- | -- | 不支持 | -- |
| Impala | -- | -- (查询引擎) | 不适用 | -- |
| StarRocks | -- (有 Routine Load) | -- | 不支持解码 | 消费侧 |
| Doris | -- (有 Routine Load) | -- | 不支持解码 | 消费侧 |
| MonetDB | -- | -- | 不支持 | -- |
| CrateDB | -- | -- | 不支持 | -- |
| TimescaleDB | 继承 PG | 继承 PG | 继承 PG | -- |
| QuestDB | -- | -- | 不支持 | -- |
| Exasol | -- | -- | 不支持 | -- |
| SAP HANA | -- (有 Smart Data Integration) | -- | 商业组件 | -- |
| Informix | Enterprise Replication | -- | 早期 | 商业 |
| Firebird | -- | -- | 不支持 | -- |
| H2 | -- | -- | 不支持 | -- |
| HSQLDB | -- | -- | 不支持 | -- |
| Derby | -- | -- | 不支持 | -- |
| Amazon Athena | -- | -- (查询引擎) | 不适用 | -- |
| Azure Synapse | -- | -- | 不支持 | -- |
| Google Spanner | Change Streams | TVF (Table-Valued Function) | 2022 | 类似但非 WAL 解码 |
| Materialize | 上游 PG/MySQL 解码 | 内部增量计算 | GA | 复用上游 logical decoding |
| RisingWave | 上游 PG/MySQL 解码 | 内部增量计算 | GA | 同 Materialize |
| InfluxDB | -- | -- | 不支持 | -- |
| DatabendDB | -- | -- | 不支持 | -- |
| Yellowbrick | -- | -- | 不支持 | -- |
| Firebolt | -- | -- | 不支持 | -- |
| MongoDB | oplog / Change Streams | BSON 事件 | 3.6 (2017) | 文档级 CDC |
| Cassandra | CDC commitlog | 二进制 commitlog | 3.0 (2015) | 需开启 cdc=true |

> 统计：约 18 个引擎提供原生的 WAL/binlog 逻辑解码；约 6 个 NewSQL 提供基于内部存储的解码；约 21 个引擎完全不支持或属于查询/嵌入式引擎不适用。

### 2. 输出插件可插拔性

| 引擎 | 插件机制 | 默认插件 | 第三方插件 | 插件 ABI |
|------|---------|---------|----------|---------|
| PostgreSQL | output plugin (C) | `pgoutput` (10+) | `wal2json`, `decoderbufs`, `test_decoding`, `wal2mongo`, `pgrecvlogical_text` | 是 (C 回调) |
| MySQL | -- (协议固定) | binlog ROWS_EVENT | -- (客户端解析) | -- |
| MariaDB | -- (协议固定) | binlog ROWS_EVENT | -- | -- |
| Oracle LogMiner | -- (视图固定) | V$LOGMNR_CONTENTS | -- | -- |
| Oracle GoldenGate | format 选项 | trail 二进制 | JSON, Avro, Delimited Text, XML | 是 (Format 配置) |
| SQL Server | -- | cdc.* 表结构固定 | -- | -- |
| TiCDC | sink 插件 | Kafka, MySQL, MQ, S3 | 自定义 sink | 是 (Go 接口) |
| CockroachDB | sink + format | Kafka/JSON | webhook, S3, Avro | 部分 |
| Debezium | converter / SMT | JSON | Avro, Protobuf, CloudEvents | 是 (Java 接口) |
| Materialize | -- (内部) | -- | -- | -- |

> PostgreSQL 是唯一在数据库内核层面提供"任意输出格式"插件机制的引擎。这种设计让同一份 WAL 可以被翻译为 JSON、Protocol Buffers、Avro、自定义协议——下游消费者按需选择，无需改源库。

### 3. 复制槽 (Replication Slot)

| 引擎 | 槽机制 | 持久化保证 | 可指定起始位置 | 故障切换 |
|------|------|---------|--------------|--------|
| PostgreSQL | Replication Slot (9.4+) | 防止 WAL 被回收 | 是 (LSN) | Failover Slot (17+) |
| MySQL | binlog 文件 + position | 受 `expire_logs_days` 影响 | 是 (file:pos / GTID) | 否 (依赖 GTID 自动续点) |
| MariaDB | 同 MySQL | 同 MySQL | 同 MySQL | -- |
| Oracle LogMiner | V$ARCHIVED_LOG | redo 归档保留策略 | 是 (SCN / Time) | 手动 |
| Oracle GoldenGate | Extract checkpoint | 写入磁盘 | 是 (LSN/SCN/CSN) | Extract HA 配置 |
| SQL Server | LSN 跟踪表 (cdc.lsn_time_mapping) | 受 retention 控制 | 是 (LSN) | 手动 |
| TiCDC | changefeed checkpoint-ts | etcd / TiKV | 是 (TSO) | 自动 (capture HA) |
| CockroachDB | CHANGEFEED job | 系统表 | 是 (resolved ts) | 自动 (集群级) |
| MongoDB | oplog cursor | oplog 大小固定 (capped) | 是 (resume token) | 自动 (replica set) |
| Cassandra | commitlog 段 | 受归档触发器 | 是 (Position) | 手动 |

PostgreSQL 的复制槽是逻辑解码的关键创新：在槽创建后，源库会保留所有该槽尚未确认的 WAL，确保下游断开后重连仍能续点。代价是磁盘空间——僵尸槽会让 WAL 无限堆积，撑爆磁盘是 PG 运维最常见的事故之一。

### 4. 内置逻辑复制 (DDL 级)

| 引擎 | 发布命令 | 订阅命令 | 行过滤 | 列过滤 | 起始版本 |
|------|---------|---------|------|------|--------|
| PostgreSQL | `CREATE PUBLICATION` | `CREATE SUBSCRIPTION` | 15+ | 15+ | 10 (2017) |
| MySQL | -- (binlog 隐式) | `CHANGE REPLICATION SOURCE` | 通过 `replicate-wild-do-table` | 通过 filter | 早期 |
| MariaDB | -- | `CHANGE MASTER` | 是 | 是 | 早期 |
| Oracle GoldenGate | `ADD EXTRACT` | `ADD REPLICAT` | 是 | 是 | 1999+ |
| SQL Server | `sp_addpublication` | `sp_addsubscription` | 是 (filter clause) | 是 | 1998+ |
| DB2 Q Replication | `ASNCLP CREATE Q SUBSCRIPTION` | 同 | 是 | 是 | 早期 |
| Snowflake | `ALTER DATABASE ENABLE REPLICATION` | `CREATE DATABASE AS REPLICA OF` | 库级 | -- | 2020 |
| Hive | `REPL DUMP` | `REPL LOAD` | 库级 | -- | 3.0 (2018) |
| Databricks Delta Sharing | `CREATE SHARE` | `CREATE PROVIDER` | 是 | 是 | 2021 |
| CockroachDB | `CREATE CHANGEFEED` | -- (Kafka 等下游) | 是 | 是 | 2.1 (2018) |
| Materialize | `CREATE SOURCE` | -- | 是 | 是 | GA |
| RisingWave | `CREATE SOURCE` | -- | 是 | 是 | GA |
| Spanner | `CREATE CHANGE STREAM` | -- (Dataflow consumer) | 是 (按表/列) | 是 | 2022 |

### 5. 列级过滤 (Column-Level Filter)

| 引擎 | 列过滤支持 | 语法 | 用途 |
|------|---------|------|------|
| PostgreSQL | 是 (15+) | `CREATE PUBLICATION p FOR TABLE t (col1, col2)` | 屏蔽 PII 列 |
| MySQL | 通过 `replicate-rewrite-db` / Debezium SMT | -- | 需外部过滤 |
| Oracle GoldenGate | 是 | `MAP src, TARGET tgt, COLS (col1, col2)` | 商业级灵活 |
| SQL Server | 是 (Articles vertical filter) | `@vertical_partition` | 早期 |
| Debezium | 是 (`column.include.list` / `column.exclude.list`) | 配置项 | 跨数据库通用 |
| CockroachDB | 是 (`SELECT` 子句) | `CREATE CHANGEFEED FOR (SELECT a, b FROM t)` | v22.1+ |
| Spanner Change Streams | 是 (按列声明) | `CHANGE STREAM ... FOR t(col1, col2)` | 内置 |
| Snowflake Streams | -- (返回所有列) | -- | 需要后续 SELECT |
| TiCDC | -- (整行) | -- | 整行输出 |

PostgreSQL 15 才补齐列过滤，背景是 GDPR/CCPA 合规——PII 列不应该流出源库。在此之前，用户只能依赖 Debezium 的 `column.exclude.list` 在外层过滤，但敏感数据仍会经过解码层和网络。

### 6. SQL 命令支持

| 引擎 | 创建解码会话 | 查看槽状态 | 推进 / 删除槽 | 一次性消费 SQL |
|------|----------|---------|----------|--------------|
| PostgreSQL | `pg_create_logical_replication_slot()` | `pg_replication_slots` | `pg_replication_slot_advance()` / `pg_drop_replication_slot()` | `pg_logical_slot_get_changes()` |
| MySQL | `SHOW MASTER STATUS` (位置查询) | `SHOW BINARY LOGS` | `PURGE BINARY LOGS TO ...` | `SHOW BINLOG EVENTS` |
| Oracle | `DBMS_LOGMNR.START_LOGMNR()` | `V$LOGMNR_SESSION` | `DBMS_LOGMNR.END_LOGMNR()` | `SELECT * FROM V$LOGMNR_CONTENTS` |
| SQL Server | `sys.sp_cdc_enable_table` | `sys.dm_cdc_log_scan_sessions` | `sys.sp_cdc_disable_table` | `cdc.fn_cdc_get_all_changes_*` |
| TiDB | `cdc cli changefeed create` (CLI) | `cdc cli changefeed list` | `cdc cli changefeed remove` | -- |
| CockroachDB | `CREATE CHANGEFEED` | `SHOW CHANGEFEED JOBS` | `CANCEL JOB` / `PAUSE JOB` | `EXPERIMENTAL CHANGEFEED FOR` |
| Snowflake | `CREATE STREAM` | `SHOW STREAMS` | `DROP STREAM` | `SELECT * FROM stream` |
| Spanner | `CREATE CHANGE STREAM` | `INFORMATION_SCHEMA.CHANGE_STREAMS` | `DROP CHANGE STREAM` | `READ_*` TVF |
| MongoDB | (driver) `db.collection.watch()` | `rs.printReplicationInfo()` | (cursor close) | (driver API) |

PostgreSQL 是少数把"创建槽、查看槽、消费变更"全都做成 SQL 函数的引擎，使得逻辑解码在 `psql` 里就能调试——这对开发者体验是巨大的优势。

## PostgreSQL：逻辑解码的"教科书设计"

### 历史脉络

| 年份 | 版本 | 关键事件 |
|------|------|--------|
| 2010 | 9.0 | Streaming Replication（物理流复制） |
| 2014 | 9.4 | **Logical Decoding API + Replication Slots**，首次在内核暴露 WAL 翻译能力 |
| 2014 | -- | `wal2json` v1 发布，是首个广泛使用的第三方 output plugin |
| 2015 | -- | `pglogical` 扩展由 2ndQuadrant 发布，成为 PG 10 内置逻辑复制的原型 |
| 2016 | -- | Debezium 发布，由 Red Hat 主导，初版基于 MySQL，PostgreSQL connector 紧随其后 |
| 2017 | 10  | **内置逻辑复制 + `pgoutput`**，`CREATE PUBLICATION/SUBSCRIPTION` 进入 SQL |
| 2018 | 11 | TRUNCATE 解码支持 |
| 2019 | 12 | 生成列在解码中正确处理 |
| 2020 | 13 | 复制槽统计 (`pg_stat_replication_slots`) |
| 2021 | 14 | 流式逻辑解码（事务进行中即可发送），二进制传输模式 |
| 2022 | 15 | 行级过滤 (`WHERE`)、列级过滤、`origin` 过滤（双向复制场景） |
| 2023 | 16 | 从 standby 进行逻辑解码，并行 apply |
| 2024 | 17 | Failover slot（物理副本切换后逻辑订阅可继续）, `pg_createsubscriber` 工具 |

### Logical Decoding API

PG 在 9.4 引入的核心抽象是 **output plugin**：用户用 C 语言实现一组回调，PG 在解码 WAL 时按需调用。最小插件接口：

```c
// 插件入口（必须）
extern void _PG_init(void);
extern void _PG_output_plugin_init(OutputPluginCallbacks *cb);

void _PG_output_plugin_init(OutputPluginCallbacks *cb)
{
    cb->startup_cb         = my_startup;       // 会话开始
    cb->begin_cb           = my_begin;         // 事务开始
    cb->change_cb          = my_change;        // 行变更（INSERT/UPDATE/DELETE）
    cb->commit_cb          = my_commit;        // 事务提交
    cb->shutdown_cb        = my_shutdown;      // 会话结束
    cb->filter_by_origin_cb = my_filter;       // (可选) 来源过滤
    cb->message_cb         = my_message;       // (可选) 自定义消息
    cb->truncate_cb        = my_truncate;      // (11+) TRUNCATE
    cb->stream_start_cb    = my_stream_start;  // (14+) 流式事务
    cb->stream_change_cb   = my_stream_change;
    cb->stream_commit_cb   = my_stream_commit;
    cb->stream_abort_cb    = my_stream_abort;
}

// change 回调示例：把每条行变更格式化为 JSON
static void my_change(LogicalDecodingContext *ctx,
                      ReorderBufferTXN *txn,
                      Relation rel,
                      ReorderBufferChange *change)
{
    OutputPluginPrepareWrite(ctx, true);   // 开始一条消息

    appendStringInfo(ctx->out, "{\"action\":\"%s\",\"schema\":\"%s\",\"table\":\"%s\",\"data\":",
        change_action_str(change->action),
        get_namespace_name(RelationGetNamespace(rel)),
        RelationGetRelationName(rel));

    // 把 tuple 序列化为 JSON
    tuple_to_json(ctx->out, RelationGetDescr(rel), &change->data.tp.newtuple->tuple);

    appendStringInfoChar(ctx->out, '}');
    OutputPluginWrite(ctx, true);          // 结束一条消息
}
```

要点：

1. **回调驱动**：插件不主动拉数据，PG 解码 WAL 时按事件回调。
2. **Reorder Buffer**：PG 会在内存中重排乱序的 WAL 事件，确保同一事务的所有变更按提交顺序传给插件——这是 9.4 设计的关键复杂度。
3. **共享内存**：`OutputPluginPrepareWrite/OutputPluginWrite` 是把消息推入流式输出缓冲区的标准协议。
4. **可重入**：插件必须支持任意位置重启（基于 `confirmed_flush_lsn`），不能依赖会话内状态。

### SQL 接口

```sql
-- 1. 配置 wal_level
ALTER SYSTEM SET wal_level = 'logical';
-- (重启 PG)

-- 2. 创建逻辑复制槽
SELECT pg_create_logical_replication_slot('my_slot', 'pgoutput');
-- 或者用 wal2json 输出 JSON
SELECT pg_create_logical_replication_slot('my_slot_json', 'wal2json');

-- 3. 查看复制槽
SELECT slot_name, plugin, slot_type, active, restart_lsn, confirmed_flush_lsn
FROM pg_replication_slots;

-- 4. 一次性消费（peek = 不推进，get = 推进）
SELECT lsn, xid, data FROM pg_logical_slot_peek_changes('my_slot', NULL, NULL,
    'proto_version', '4', 'publication_names', 'pub_orders');

SELECT lsn, xid, data FROM pg_logical_slot_get_changes('my_slot_json', NULL, NULL,
    'format-version', '2', 'include-types', 'true');

-- 5. 推进槽（不消费数据，只移动确认位置）
SELECT pg_replication_slot_advance('my_slot', '0/1A2B3C4D');

-- 6. 删除槽（务必删除不再使用的槽，否则 WAL 不会被回收）
SELECT pg_drop_replication_slot('my_slot');
```

### 内置逻辑复制：`pgoutput`

PG 10 的 `pgoutput` 是为内置逻辑复制专门写的 output plugin，使用二进制协议（不是文本格式）：

```sql
-- 发布端
CREATE PUBLICATION pub_orders FOR TABLE orders, order_items;

-- 订阅端（另一个 PG 实例）
CREATE SUBSCRIPTION sub_orders
    CONNECTION 'host=primary dbname=app user=replicator'
    PUBLICATION pub_orders
    WITH (copy_data = true, create_slot = true, slot_name = 'sub_orders_slot');
```

`pgoutput` 协议的消息类型（每条消息以 1 字节类型字开头）：

```
'B' Begin              事务开始：包含 final LSN, commit timestamp, xid
'C' Commit             事务提交：包含 commit LSN, end LSN, timestamp
'O' Origin             (双向复制) 标记此事务的来源
'R' Relation           表元数据：oid, schema, name, replica identity, columns
'Y' Type               (15+) 自定义类型元数据
'I' Insert             插入：relation oid, 'N'(new tuple) tag, 列值
'U' Update             更新：relation oid, 'O'(old) / 'K'(key only) / 'N'(new) tag, 列值
'D' Delete             删除：relation oid, 'O' / 'K' tag, 列值
'T' Truncate           (11+) 截断：表数量, options, oid 列表
'M' Message            自定义消息（pg_logical_emit_message 写入的）
'S' Stream Start       (14+) 流式事务开始（事务尚未 commit 即开始发送）
'E' Stream Stop        (14+) 流式事务暂停
'c' Stream Commit      (14+) 流式事务提交
'A' Stream Abort       (14+) 流式事务回滚
```

每条 Insert / Update / Delete 携带的列值采用 TupleData 格式：

```
TupleData {
    Int16   number_of_columns;
    Column[] columns;
}

Column {
    Byte1   data_type;     // 'n' null, 'u' unchanged toast, 't' text, 'b' binary
    Int32   length;        // 仅当 data_type = 't' 或 'b'
    Byte[]  value;
}
```

`'u' unchanged toast` 是 PG 一个微妙的优化：如果一行 UPDATE 没有修改 TOAST 列（大字段），WAL 中不会重复存这个值，解码时插件得到的 column tag 是 `'u'`，下游需要从已知状态恢复——Debezium 的 PostgreSQL connector 有专门的 `lossless toast` 配置项处理这一点。

### Replica Identity：UPDATE/DELETE 的"老值"从哪来

PG 的 WAL 默认只记录"新值"，UPDATE/DELETE 的"旧值"取决于表的 `REPLICA IDENTITY` 设置：

```sql
-- 默认：只记录主键列的旧值
ALTER TABLE orders REPLICA IDENTITY DEFAULT;

-- USING INDEX: 用某个唯一索引的列做老值
ALTER TABLE orders REPLICA IDENTITY USING INDEX idx_orders_uuid;

-- FULL: 记录全部列的旧值（成本高，但 Debezium "before" 字段完整）
ALTER TABLE orders REPLICA IDENTITY FULL;

-- NOTHING: 不记录老值（UPDATE/DELETE 在订阅端会失败）
ALTER TABLE orders REPLICA IDENTITY NOTHING;
```

这个设置直接影响解码事件的 "before" 字段是否完整——Debezium 用户经常踩的坑就是默认 `REPLICA IDENTITY DEFAULT`，导致 UPDATE 事件的 `before` 只包含主键，无法做 "old vs new" 对比。

### 主流 Output Plugin 对比

| 插件 | 输出格式 | 用途 | 维护方 |
|------|--------|------|--------|
| `pgoutput` | 二进制（PG 内部协议） | 内置逻辑复制、Debezium、Materialize | PG 核心 |
| `wal2json` | JSON 文本 | 通用下游、调试、Kafka Connect | 第三方 (Euler Taveira) |
| `decoderbufs` | Protocol Buffers | 高性能下游 | Debezium 团队 |
| `test_decoding` | 人类可读文本 | 测试和教学（不可用于生产） | PG 核心 |
| `wal2mongo` | MongoDB BSON 风格 JSON | PG → MongoDB 同步 | 第三方 |
| `pgrecvlogical_text` | 自定义文本 | 工具 `pg_recvlogical` 使用 | PG 核心 |

`wal2json` v1 vs v2 是常见的版本踩坑点：v1 输出整个事务为一个 JSON 对象（事务大时内存爆炸），v2 改为每条变更一个 JSON 行（流式友好）。Debezium 默认用 `pgoutput`，部分用户出于"想看 JSON"会切到 `wal2json`，但忽略了 v1 的内存模型差异。

## MySQL：binlog ROWS_EVENT 与客户端解析模型

PostgreSQL 把"WAL → 事件"放在内核，MySQL 则把这一层留给客户端：MySQL 内核只产 binlog 二进制流，所有"翻译为业务可读事件"的工作都由外部工具完成（Canal、Maxwell、Debezium、go-mysql、python-mysql-replication……）。这一设计差异塑造了两个完全不同的生态。

### binlog 历史

| 年份 | 版本 | 事件 |
|------|------|------|
| 2001 | 3.23 | binlog + Statement-Based Replication 首次发布 |
| 2008 | 5.1 | **Row-Based Replication 引入**，新增 ROWS_EVENT 系列事件 |
| 2010 | 5.5 | 半同步复制 |
| 2013 | 5.6 | GTID + binlog 行版本格式优化 |
| 2013 | -- | Canal（阿里开源）发布，伪装成 MySQL 副本拉取 binlog |
| 2015 | -- | Maxwell（Zendesk 开源）发布，首个流行的 JSON 化 binlog 解析器 |
| 2015 | 5.7 | RBR 成为默认（5.7.7+），引入 `binlog_row_image = MINIMAL/NOBLOB/FULL` |
| 2016 | -- | Debezium MySQL connector 发布 |
| 2018 | 8.0 | binlog 默认压缩（zstd），`mysqlbinlog --read-from-remote-server` 增强 |
| 2024 | 8.4 | 副本术语重命名，`PRIMARY/REPLICA` 替代 `MASTER/SLAVE` |

### binlog 配置

```ini
# my.cnf
server-id           = 1
log_bin             = mysql-bin
binlog_format       = ROW            # ROW / STATEMENT / MIXED
binlog_row_image    = FULL           # FULL / MINIMAL / NOBLOB
binlog_row_metadata = FULL           # 8.0+，包含列名等元数据
expire_logs_days    = 7
gtid_mode           = ON
enforce_gtid_consistency = ON
```

`binlog_row_image` 三个选项的差异：

| 选项 | INSERT 写入 | UPDATE 写入 | DELETE 写入 |
|-----|-----------|-----------|-----------|
| `FULL` | 全部列 | 全部新值 + 全部旧值 | 全部旧值 |
| `MINIMAL` | 全部列 | 仅修改列 + 主键旧值 | 仅主键旧值 |
| `NOBLOB` | 全部列 (BLOB 略) | 同 FULL 但跳过未变 BLOB | 同 FULL 但跳过 BLOB |

`MINIMAL` 显著降低 binlog 体积，但 CDC 下游就拿不到完整的 "before" 状态——Debezium 文档明确建议生产环境使用 `FULL`。

### binlog 事件格式

binlog 是按事件 (event) 流动的二进制文件，每个事件有标准头：

```
Common Header (19 bytes since v4):
  Int32   timestamp           // Unix 秒
  Int8    event_type          // 事件类型代码
  Int32   server_id           // 写源 server_id
  Int32   event_size          // 事件总长度（含头）
  Int32   log_pos             // 该事件在 binlog 中的位置
  Int16   flags               // 标志位
```

关键事件类型：

| 类型代码 | 名称 | 作用 |
|--------|------|------|
| 0x0F (15) | `FORMAT_DESCRIPTION_EVENT` | binlog 文件第一个事件，描述版本和事件头长度 |
| 0x21 (33) | `GTID_EVENT` (5.6+) | 标记下一个事务的 GTID |
| 0x02 (2)  | `QUERY_EVENT` | DDL 或 SBR 模式下的 DML |
| 0x13 (19) | `TABLE_MAP_EVENT` | RBR 中后续 ROWS_EVENT 引用的表元数据 |
| 0x1E (30) | `WRITE_ROWS_EVENTv2` | INSERT 行（5.6+，v1 是 0x17） |
| 0x1F (31) | `UPDATE_ROWS_EVENTv2` | UPDATE 行（5.6+，v1 是 0x18） |
| 0x20 (32) | `DELETE_ROWS_EVENTv2` | DELETE 行（5.6+，v1 是 0x19） |
| 0x10 (16) | `XID_EVENT` | 事务提交标志（包含 InnoDB transaction id） |
| 0x04 (4)  | `ROTATE_EVENT` | binlog 文件切换 |
| 0x23 (35) | `ANONYMOUS_GTID_EVENT` | 未启用 GTID 时的占位事务标识 |

#### FORMAT_DESCRIPTION_EVENT

binlog 文件的"清单"。每次打开 binlog 流必须先读这个事件，才能正确解析后续事件长度：

```
binlog_version       Int16    // 4 (since 5.0)
server_version       Char[50] // "8.0.34-mysql"
create_timestamp     Int32
event_header_length  Int8     // 19
post_header_lengths  Byte[]   // 每种事件类型的 post-header 长度
checksum_alg         Int8     // 0=NONE, 1=CRC32（5.6+ 默认）
```

#### TABLE_MAP_EVENT + ROWS_EVENT 的二元结构

RBR 模式下，行变更总是成对出现：先来一个 `TABLE_MAP_EVENT` 把表 schema 映射到 table_id，然后跟一个或多个 `ROWS_EVENT`（同一事务可批量变更）。

```
TABLE_MAP_EVENT body:
  Int48   table_id            // 临时分配的 ID
  Int16   flags
  Char    schema_name_length
  Char[]  schema_name
  Char    null_terminator
  Char    table_name_length
  Char[]  table_name
  Char    null_terminator
  PackedInt column_count
  Byte[column_count]  column_types       // 每列的 MySQL 类型代码
  PackedBytes column_meta                // 类型相关的元数据（如 VARCHAR 长度）
  Bitmap  null_bitmap                    // 哪些列允许 NULL

ROWS_EVENT body (WRITE/UPDATE/DELETE 共享):
  Int48   table_id            // 必须匹配前面的 TABLE_MAP_EVENT
  Int16   flags               // 0x01 = end of statement, 0x02 = no foreign key check, ...
  PackedInt column_count_after
  Bitmap  columns_present_bitmap_after   // 该事件覆盖了哪些列
  // (UPDATE only) Bitmap columns_present_bitmap_before
  Row[]   rows_data           // 每行的 NULL 位图 + 列值
```

每行的列值采用 MySQL 内部二进制编码（不是 SQL 文本）：INT 是小端字节序、VARCHAR 是 length-prefixed、DATETIME 是按精度变长、DECIMAL 是 BCD 压缩……解析这种格式是 binlog 客户端最复杂的工作之一。

#### GTID_EVENT

5.6 起，每个事务前都会先写一个 `GTID_EVENT`：

```
flags                Int8       // 0x01 = COMMIT, 0x00 = no commit yet
sid                  Byte[16]   // server_uuid（二进制形式）
gno                  Int64      // transaction_id
ts_type              Int8       // 2 = original/immediate timestamps
original_commit_ts   Int56
immediate_commit_ts  Int56
tx_length            PackedInt  // 整个事务字节数（5.7+）
original_seqno       Int64      // 提交序号
immediate_seqno      Int64
```

下游消费者用 `(sid, gno)` 组合还原 GTID 字符串（如 `3E11FA47-71CA-11E1-9E33-C80AA9429562:1-3`），用于断点续传。

### binlog dump 协议（拉模式）

客户端通过模拟"我是个副本"来拉 binlog：

```
1. 客户端 → 服务端：
   COM_REGISTER_SLAVE     // 0x15，伪装为 slave
   COM_BINLOG_DUMP_GTID   // 0x1E，请求从指定 GTID 集开始
       OR COM_BINLOG_DUMP // 0x12，从 file:position 开始

2. 服务端 → 客户端：
   持续推送 binlog 事件流，每个事件前面有一个 0x00 包标记（OK packet）

3. 客户端断开 / 服务端 binlog 切换 / 错误时停止
```

这就是为什么 Maxwell、Canal、Debezium 都需要数据库的 `REPLICATION SLAVE` 权限——它们对 MySQL 来说就是个伪装的副本。

### 三大开源解析器

#### Maxwell (Zendesk, 2015)

```
Java 实现，把 binlog 解析为 JSON，输出到 Kafka / Kinesis / RabbitMQ / Redis / SNS。
```

JSON 格式：

```json
{
  "database": "shop",
  "table": "orders",
  "type": "update",
  "ts": 1705500000,
  "xid": 12345,
  "commit": true,
  "data": {"id": 1001, "amount": 200, "status": "paid"},
  "old":  {"amount": 100, "status": "pending"},
  "position": "mysql-bin.000123:4567",
  "gtid": "3E11FA47-71CA-11E1-9E33-C80AA9429562:5"
}
```

特点：JSON 简单直接、配置文件单一、单进程、无 Schema Registry。

#### Canal（阿里巴巴, 2013）

```
Java 实现，伪装为 MySQL slave。提供 server-client 架构：canal-server 拉 binlog，
canal-client / canal-adapter 把变更投递到下游。
```

事件格式（Protobuf）：

```protobuf
message Entry {
    Header header = 1;
    EntryType entryType = 2;
    bytes storeValue = 3;  // RowChange 序列化
}

message RowChange {
    int64 tableId = 1;
    EventType eventType = 2;  // INSERT / UPDATE / DELETE / DDL
    bool isDdl = 10;
    string sql = 11;
    repeated RowData rowDatas = 12;
}

message RowData {
    repeated Column beforeColumns = 1;
    repeated Column afterColumns = 2;
}

message Column {
    int32 index = 1;
    int32 sqlType = 2;
    string name = 3;
    bool isKey = 4;
    bool updated = 5;
    bool isNull = 6;
    string value = 9;  // 文本化的值
    int32 length = 10;
    string mysqlType = 11;
}
```

特点：阿里内部生态深度集成（OTTER、DataX、StreamCompute）；canal-adapter 直接写入 ES/HBase/Redis；中文文档丰富，国内 MySQL CDC 标配。

#### Debezium（Red Hat, 2016）

Java 实现，基于 Kafka Connect 框架。统一了 MySQL/PostgreSQL/Oracle/SQL Server/MongoDB/DB2/Cassandra 等十余种数据库的事件格式（Debezium Envelope）：

```json
{
  "schema": { /* Avro schema */ },
  "payload": {
    "before": {"id": 1001, "amount": 100, "status": "pending"},
    "after":  {"id": 1001, "amount": 200, "status": "paid"},
    "source": {
      "version": "2.5.0.Final",
      "connector": "mysql",
      "name": "shop-cdc",
      "ts_ms": 1705500000000,
      "snapshot": "false",
      "db": "shop",
      "table": "orders",
      "server_id": 1,
      "gtid": "3E11FA47-...:5",
      "file": "mysql-bin.000123",
      "pos": 4567,
      "row": 0
    },
    "op": "u",                      // c=create, u=update, d=delete, r=read(snapshot), t=truncate
    "ts_ms": 1705500001000
  }
}
```

特点：跨数据库统一事件格式；与 Kafka Connect / Schema Registry 深度集成；Debezium UI、Operator、Server（无 Kafka 模式）等周边工具完整；社区最活跃。

#### 三者对比

| 维度 | Maxwell | Canal | Debezium |
|-----|--------|-------|---------|
| 首发年份 | 2015 | 2013 | 2016 |
| 维护方 | Zendesk → Community | 阿里巴巴 | Red Hat |
| 输出格式 | JSON | Protobuf / JSON | JSON / Avro / Protobuf |
| 多数据库支持 | 仅 MySQL | MySQL / Oracle (有限) | MySQL/PG/Oracle/SQL Server/MongoDB/DB2/Cassandra/Vitess |
| 部署模型 | 独立进程 | Server + Client/Adapter | Kafka Connect / Debezium Server |
| Schema 演进 | 自动跟随 | 手动配置 | 内置支持 (Schema Registry) |
| 初始快照 | 是 | 是 | 是（snapshot.mode 多档位） |
| 国内生态 | 较少 | 强 | 中 |
| 国际生态 | 中 | 弱 | 强 |
| 典型用户 | Zendesk, Yelp | 阿里、美团、京东 | 大量国际公司 |

## Oracle：LogMiner、XStream 与 GoldenGate

Oracle 的逻辑解码体系是商业数据库的典型代表——又老又大又分裂。

### LogMiner

LogMiner 是 Oracle 8i (1999) 引入的内置工具，把 redo log（在线或归档）转为可查询的视图：

```sql
-- 1. 添加要分析的 redo 文件
EXEC DBMS_LOGMNR.ADD_LOGFILE(
    LogFileName => '/u01/oradata/redo01.log',
    Options     => DBMS_LOGMNR.NEW);

EXEC DBMS_LOGMNR.ADD_LOGFILE(
    LogFileName => '/u01/oradata/redo02.log',
    Options     => DBMS_LOGMNR.ADDFILE);

-- 2. 启动 LogMiner（基于在线字典）
EXEC DBMS_LOGMNR.START_LOGMNR(
    Options => DBMS_LOGMNR.DICT_FROM_ONLINE_CATALOG +
               DBMS_LOGMNR.COMMITTED_DATA_ONLY);

-- 3. 查询变更
SELECT scn, timestamp, operation, sql_redo, sql_undo
FROM V$LOGMNR_CONTENTS
WHERE seg_owner = 'APP' AND seg_name = 'ORDERS'
ORDER BY scn;

-- 4. 结束会话
EXEC DBMS_LOGMNR.END_LOGMNR();
```

`V$LOGMNR_CONTENTS` 的核心列：`SCN`, `TIMESTAMP`, `OPERATION` (INSERT/UPDATE/DELETE/COMMIT/...), `SQL_REDO` (重做 SQL), `SQL_UNDO` (反做 SQL), `XID`。

LogMiner 是 Debezium Oracle Connector 的底层基础——Debezium 启动一个常驻 LogMiner 会话，按 SCN 增量拉取 `V$LOGMNR_CONTENTS`。

### XStream

XStream 是 Oracle 11g (2009) 引入的高性能 CDC API（需要 GoldenGate license）：

- **XStream Out**：从 Oracle 内部直接抽取变更，比 LogMiner 快很多（不必走 SQL 文本化）。
- **XStream In**：把外部变更应用到 Oracle。

Debezium Oracle Connector 既支持 LogMiner 模式（OSS-friendly），也支持 XStream 模式（性能高，但需要 license）。

### GoldenGate

GoldenGate 是 Oracle 收购的旗舰产品，独立部署：

```
┌──────────┐    ┌──────────────┐    ┌──────────┐    ┌──────────────┐
│  Oracle  │───▶│ Extract      │───▶│ Trail    │───▶│ Replicat     │
│  (源库)  │    │ (抽取 redo)  │    │ (磁盘文件)│    │ (写入目标)   │
└──────────┘    └──────────────┘    └──────────┘    └──────────────┘
                                          │
                                          ▼
                                    ┌──────────────┐
                                    │ Pump         │
                                    │ (跨网络传输)  │
                                    └──────────────┘
```

特点：跨异构数据库（Oracle ↔ MySQL/PostgreSQL/SQL Server/Kafka/Big Data）；双向复制 + 冲突解决；商业 license。GoldenGate 自家的 trail 文件格式是私有的，但提供 Java Adapter 输出 JSON/Avro/Delimited Text。

## SQL Server：CDC 表与 Transactional Replication

SQL Server 的"逻辑解码"分两条路：

### CDC（Change Data Capture, 2008+）

CDC 在数据库内部启动一个 capture job，把 transaction log 中的变更解析后**写入辅助系统表**（不是事件流）：

```sql
-- 启用数据库级 CDC
EXEC sys.sp_cdc_enable_db;

-- 启用表级 CDC
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name   = N'orders',
    @role_name     = NULL,
    @supports_net_changes = 1;

-- 此时会创建 cdc.dbo_orders_CT 表，结构：
--   __$start_lsn        BINARY(10)
--   __$end_lsn          BINARY(10)
--   __$seqval           BINARY(10)
--   __$operation        INT       -- 1=DELETE, 2=INSERT, 3=UPDATE_BEFORE, 4=UPDATE_AFTER
--   __$update_mask      VARBINARY(128)
--   <原表所有列>

-- 查询变更
DECLARE @from BINARY(10) = sys.fn_cdc_get_min_lsn('dbo_orders');
DECLARE @to   BINARY(10) = sys.fn_cdc_get_max_lsn();

SELECT * FROM cdc.fn_cdc_get_all_changes_dbo_orders(@from, @to, 'all update old');

-- 净变更（合并同一行多次更新）
SELECT * FROM cdc.fn_cdc_get_net_changes_dbo_orders(@from, @to, 'all');
```

CDC 的局限：变更先落到 SQL Server 自己的辅助表，再由下游轮询拉取——这不是真正的"流式解码"，延迟取决于轮询间隔（默认 5 秒）。Debezium SQL Server Connector 就是定期轮询 cdc.* 表来抓取变更。

### Transactional Replication

更老的 (1998+) 方案：从 transaction log 提取 INSERT/UPDATE/DELETE，通过 Distributor 进程推送到 Subscriber。这是真正的"流式"，但管理复杂、配置繁琐：

```sql
-- 创建发布
EXEC sp_addpublication
    @publication = N'pub_orders',
    @repl_freq   = N'continuous',
    @sync_method = N'concurrent',
    @retention   = 72;

EXEC sp_addarticle
    @publication = N'pub_orders',
    @article     = N'orders',
    @source_table = N'orders';

-- 订阅
EXEC sp_addsubscription
    @publication = N'pub_orders',
    @subscriber  = N'sub_server',
    @destination_db = N'app_replica';
```

## CockroachDB CHANGEFEED：把逻辑解码做成 SQL DDL

CockroachDB 没有像 PG 那样开放底层 API，而是直接把"逻辑解码 + 输出"封装成 `CREATE CHANGEFEED` SQL 语句：

```sql
CREATE CHANGEFEED FOR TABLE orders
    INTO 'kafka://broker:9092'
    WITH updated, resolved = '10s', format = avro,
         confluent_schema_registry = 'http://schema-registry:8081';

-- 输出到云存储
CREATE CHANGEFEED FOR TABLE orders
    INTO 's3://my-bucket/cdc/?AWS_ACCESS_KEY_ID=xxx&AWS_SECRET_ACCESS_KEY=xxx'
    WITH updated, resolved = '30s', format = json;

-- 投影 + 过滤（v22.1+ CDC Transformations）
CREATE CHANGEFEED INTO 'kafka://...'
    AS SELECT id, amount, status FROM orders
       WHERE region IN ('US', 'EU');

-- 监控
SHOW CHANGEFEED JOBS;
SHOW CHANGEFEED JOB 12345;
```

事件格式（默认）：

```json
{
  "after":   {"id": 1, "amount": 200, "status": "paid"},
  "before":  {"id": 1, "amount": 100, "status": "pending"},  // 仅当 WITH diff
  "key":     [1],
  "updated": "1705500000.000000001",
  "topic":   "orders"
}
```

**Resolved Timestamp** 是 Cockroach CHANGEFEED 的关键创新：周期性发送一个特殊事件，告诉下游 "在此时间戳之前的所有变更都已发完"。基于此，下游可以做精确一次和因果一致的物化视图。

## TiDB TiCDC：跳过 SQL 层直接订阅 KV

TiDB 早期通过 `tidb-binlog`（pump + drainer 架构）模拟 MySQL binlog 协议，但 drainer 是单点。TiCDC 自 4.0 (2020) 起取代旧方案，直接订阅 TiKV 的 raw KV change feed：

```
┌──────────┐    ┌─────────────┐    ┌──────────────┐
│  TiKV    │───▶│ TiCDC       │───▶│ Sink         │
│ (Raft)   │    │ (Capture)   │    │ (Kafka/MySQL)│
└──────────┘    └─────────────┘    └──────────────┘
       ▲             │
       │             ▼
       │       ┌────────────┐
       └───────│  PD        │ ← TSO (timestamp)
               └────────────┘
```

```bash
# 创建 changefeed
tiup cdc cli changefeed create \
    --pd=http://pd:2379 \
    --sink-uri="kafka://kafka:9092/cdc-topic" \
    --start-ts=437465787876573185 \
    --config=cdc-config.toml

# 查看
tiup cdc cli changefeed list
tiup cdc cli changefeed query -c <id>
```

TiCDC Open Protocol 的事件格式（JSON）：

```json
{
  "u": {                                    // u=update, d=delete, e=ddl
    "id":     {"t": 8,  "h": true, "v": 1},
    "amount": {"t": 4,  "v": 200, "p": 100},   // p = pre-value
    "status": {"t": 15, "v": "paid", "p": "pending"}
  },
  "ts": 437465787876573185
}
```

TiCDC 直接订阅 TiKV 而不是 SQL 层意味着：1) 解码不依赖 TiDB 计算节点；2) 吞吐随 TiKV 扩展；3) 跨表事务的一致性由 TSO 保证。

## YugabyteDB xCluster：复用 PG 协议

YugabyteDB 内部用 Raft 复制，跨集群解码通过 xCluster 实现。CDC connector 输出兼容 PostgreSQL logical replication 的事件格式（因为 YugabyteDB 提供 PostgreSQL 兼容 SQL 层）：

```sql
-- 类似 PG 语法
CREATE PUBLICATION pub FOR TABLE orders;
SELECT * FROM pg_create_logical_replication_slot('s1', 'yboutput');
```

底层用 YugabyteDB 自家的 `yboutput` 插件（基于 `pgoutput` 衍生），事件流可被 Debezium 的 PG connector 直接消费。

## OceanBase OBCDC：兼容 MySQL binlog 协议

OceanBase 从 3.x 起提供 OBCDC 组件，对外暴露**伪 MySQL binlog 接口**——下游工具（Maxwell / Canal / Debezium MySQL connector）几乎不用改就能消费：

```
┌──────────┐    ┌────────────┐    ┌─────────────────┐
│ OB Tx    │───▶│ OBCDC      │───▶│ binlog 兼容服务 │ ◀── Canal/Debezium
│  Log     │    │ (libobcdc) │    │ (libobbinlog)   │
└──────────┘    └────────────┘    └─────────────────┘
```

这种"伪装协议"策略让 OceanBase 在中国 MySQL 生态里能直接复用 Canal 配套生态，而无需重新发明轮子。

## MongoDB Change Streams：文档级 CDC

MongoDB 不是 SQL 数据库，但其 Change Streams（3.6, 2017）是文档数据库 CDC 的代表：

```javascript
// driver API
const changeStream = db.collection('orders').watch([
    { $match: { 'fullDocument.region': 'US' } }
]);

for await (const change of changeStream) {
    console.log(change);
    /*
    {
        _id: { _data: '825F...' },           // resume token
        operationType: 'update',
        clusterTime: Timestamp(1705500000, 1),
        ns: { db: 'shop', coll: 'orders' },
        documentKey: { _id: ObjectId(...) },
        updateDescription: {
            updatedFields: { amount: 200 },
            removedFields: []
        },
        fullDocument: { ... },                // 完整新值（需配置 fullDocument: 'updateLookup'）
        fullDocumentBeforeChange: { ... }     // 完整旧值（需 6.0+ 和 changeStreamPreAndPostImages）
    }
    */
}
```

Change Streams 基于 oplog，但封装成了高层 cursor API，避免用户直接解析 oplog 二进制。Debezium MongoDB Connector 和 Spark Structured Streaming MongoDB Source 都用这套 API。

## Cassandra CDC：基于 commitlog

Cassandra 3.0 (2015) 引入 CDC commitlog 机制：

```cql
-- 在表上启用 CDC
ALTER TABLE shop.orders WITH cdc = true;
```

启用后，Cassandra 把对该表的写入额外保留一份 commitlog 段到 `cdc_raw` 目录，由用户编写的消费器轮询解析。Cassandra 自带的 `org.apache.cassandra.tools.JsonTransformer` 可以把 commitlog 转 JSON，但生产环境通常用 Debezium Cassandra Connector 或 Stargate CDC。

特点：分区/集群无关（每个节点独立产 cdc_raw）；解析需要 Cassandra 内部 SSTable 库；事件没有"事务"概念（Cassandra 是 BASE）。

## Snowflake Streams：基于快照差异，不是真正解码

```sql
CREATE STREAM s_orders ON TABLE orders;

-- INSERT/UPDATE/DELETE 后查询 stream
SELECT *, METADATA$ACTION, METADATA$ISUPDATE, METADATA$ROW_ID
FROM s_orders;
-- METADATA$ACTION:    INSERT 或 DELETE
-- METADATA$ISUPDATE:  TRUE 表示这是 UPDATE 的拆分
-- UPDATE 表现为两行: 一行 DELETE（旧值）+ 一行 INSERT（新值）
```

Snowflake Streams 不解析事务日志，而是基于"上次消费时间点"和"当前时间点"的快照差异——本质是定期 SELECT 计算 diff。延迟通常以分钟计，但消除了对 WAL 解析的需要。

## Databricks Delta CDF：Delta Lake 的内置 CDC

Delta Lake 在 2021+ 提供 Change Data Feed（CDF）：

```sql
-- 在 Delta 表上启用 CDF
ALTER TABLE orders SET TBLPROPERTIES (delta.enableChangeDataFeed = true);

-- 查询变更
SELECT * FROM table_changes('orders', 1, 10);
-- 返回原表列 + _change_type (insert/update_preimage/update_postimage/delete) + _commit_version + _commit_timestamp
```

CDF 在 Delta 表的 commit 日志中额外记录变更行，下游通过版本号增量读取。这与 PostgreSQL 的 WAL 解码本质类似（基于事务日志），但运行在 Spark / Databricks 引擎上。

## Materialize / RisingWave：上游解码的"消费者"

Materialize 和 RisingWave 是流式数据库，不解码自家数据，而是消费上游 PG/MySQL 的 logical decoding 流：

```sql
-- Materialize
CREATE SOURCE orders_src
    FROM POSTGRES CONNECTION pg_conn (PUBLICATION 'pub_orders')
    FOR ALL TABLES;

-- RisingWave
CREATE SOURCE orders_src WITH (
    connector = 'postgres-cdc',
    hostname = 'pg-host',
    port = '5432',
    database.name = 'shop',
    schema.name = 'public',
    table.name = 'orders',
    slot.name = 'rw_slot'
) FORMAT PLAIN ENCODE JSON;
```

它们内部包了 `pgoutput` 客户端协议解码逻辑，把 PG 复制流转成内部增量计算引擎的输入。

## 解码事件的统一抽象：Debezium Envelope

Debezium 在 2016 起逐渐确立了一套跨数据库的事件包络格式，今天已经成为社区事实标准：

```json
{
  "schema": { /* Avro schema 自描述 */ },
  "payload": {
    "before": <full row before> | null,
    "after":  <full row after>  | null,
    "source": {
      "version": "<connector version>",
      "connector": "mysql" | "postgresql" | "oracle" | "sqlserver" | "mongodb" | ...,
      "name": "<logical server name>",
      "ts_ms": <event timestamp>,
      "snapshot": "true" | "false" | "last",
      "db": "<database name>",
      "schema": "<schema name>",
      "table": "<table name>",
      // 数据库特定字段
      "lsn": <PG LSN> | "scn": <Oracle SCN> | "gtid": <MySQL GTID> | "ts": <Mongo Timestamp>,
      ...
    },
    "op": "c" | "u" | "d" | "r" | "t",
    //   create, update, delete, read(snapshot), truncate
    "ts_ms": <wall-clock event timestamp>,
    "transaction": {
      "id": "<txn id>",
      "total_order": <event order in txn>,
      "data_collection_order": <event order in collection>
    } | null
  }
}
```

下游消费者只需理解 `op + before + after + source`，就能处理来自任意数据库的事件。Schema Registry 维护事件 schema 演进，Confluent Kafka Connect 提供 transformation 框架（SMT）做字段重命名、过滤、加密等后处理。

这套 Envelope 已被 Apache Flink CDC、Spark Structured Streaming、Snowflake Snowpipe Streaming 等众多消费者支持。它在事实上扮演了 ISO SQL 标准未能扮演的"跨引擎统一格式"角色。

## 引擎实现指南

### 1. 设计 output plugin 接口的关键决策

如果一个新数据库要做逻辑解码，PG 的 output plugin 设计是最值得借鉴的样本：

```
关键回调（按必须性排序）：
  1. begin       事务开始（提供 xid + commit timestamp）
  2. change      行变更（提供 relation + old/new tuple + action）
  3. commit      事务提交（提供 commit LSN + end LSN）
  4. shutdown    清理资源
  5. truncate    TRUNCATE（PG 11+ 才补齐）
  6. message     自定义消息（pg_logical_emit_message）
  7. stream_*    流式事务（PG 14+，避免大事务内存爆炸）

非必须但强烈建议：
  8. filter_by_origin  双向复制场景的来源过滤
  9. filter_by_table   订阅端按表/列过滤
```

如果做成 C ABI 插件（PG 风格），下游可以用任意第三方插件输出任意格式；如果做成 SQL DDL（CockroachDB 风格），用户体验更好但灵活性差。两种路线都可以，但要在设计早期决定，后期切换会破坏兼容性。

### 2. 复制槽 / checkpoint 的关键不变量

```
不变量 1：源库不能丢任何"槽未确认"的 WAL/binlog
  否则下游会丢事件，违反 at-least-once 语义。
  PG 的 restart_lsn 和 confirmed_flush_lsn 就是这个目的。
  代价：磁盘空间。僵尸槽会撑爆磁盘。

不变量 2：消费者必须能从任意位置精确续点
  位置标识必须能重新定位到 WAL 中的具体字节。
  PG 用 LSN，MySQL 用 (file, pos) 或 GTID，TiCDC 用 TSO。

不变量 3：解码结果必须是确定性的
  同一段 WAL 多次解码必须输出相同事件序列。
  否则下游去重无法工作。

不变量 4：事务边界要明确
  begin / commit 必须成对，commit 之前的所有 change 必须已发出。
  PG 的 reorder buffer 就是为了在乱序 WAL 中重排出"按 commit 顺序"的事件流。
```

### 3. ROWS_EVENT 的列编码陷阱

实现 binlog 兼容协议（OceanBase OBCDC 等场景）时，ROWS_EVENT 的列编码细节最容易踩坑：

```
1. NULL 位图：每行开头有一个位图，bit i = 1 表示第 i 列是 NULL，跳过该列字节
2. 列顺序：必须严格按 TABLE_MAP_EVENT 中的顺序，不能用名字
3. 类型编码：DECIMAL 是 BCD 压缩、DATETIME 在 5.6+ 改为 fractional-seconds、JSON 是 MySQL 内部二进制
4. 字符集：CHAR/VARCHAR 的实际编码取决于表的 collation，binlog 不携带 collation 元数据 (8.0 部分修复)
5. ENUM/SET：以 INT 形式存储，下游需查询表元数据才能解码为字符串
6. 分区表：分区操作 (ALTER PARTITION) 不在 binlog 中明确标记，需 DDL 解析
7. 隐藏列：8.0 的 INVISIBLE 列在 binlog 中正常存在
```

### 4. 大事务流式输出

传统逻辑解码必须等事务 commit 后才输出（否则可能输出未提交数据），这导致大事务（百万行 INSERT、批量 UPDATE）会在内存中堆积。PG 14 的"流式事务"解决方案：

```
事务开始 → 持续 spool 事件到磁盘缓冲区
缓冲区超过 logical_decoding_work_mem (默认 64MB) → 触发流式输出
  发送 'S' Stream Start
  发送已 spool 的事件（'I'/'U'/'D'/...）
  发送 'E' Stream Stop
事务最终 commit → 'c' Stream Commit；下游应用所有 streamed 事件
事务最终 abort → 'A' Stream Abort；下游丢弃所有 streamed 事件
```

下游必须能 buffer 已收到的 streamed 事件直到收到最终 commit/abort。Debezium PG Connector 在 2.0+ 版本支持流式接收。

### 5. Schema 演进

DDL（ALTER TABLE）发生时，逻辑解码必须能：

1. 检测到 schema 变化（PG 通过 catalog 版本，MySQL 通过 QUERY_EVENT 中的 ALTER TABLE 文本）
2. 把新 schema 元数据传递给下游（PG 的 Relation 消息会重发，MySQL 通过 TABLE_MAP_EVENT）
3. 让下游消费者处理 schema 变化（Debezium 的 Schema Registry 自动注册新版本）

Online DDL（如 MySQL gh-ost、pt-online-schema-change）会产生大量影子表写入，下游必须有规则忽略影子表事件——这是 CDC 实践中常见的 schema 演进陷阱。

### 6. Toast / 大字段处理

PG 的 TOAST（The Oversized-Attribute Storage Technique）会把大字段存在独立表，WAL 中只记录引用。如果该 TOAST 列在 UPDATE 中没变，WAL 不会重复存值——这导致 `pgoutput` 给出的 column tag 是 `'u' (unchanged toast)`，下游必须从已知状态恢复。

```
列值 tag：
  'n' NULL
  'u' Unchanged TOAST  ← 下游需要：要么 REPLICA IDENTITY FULL，要么自己维护状态
  't' Text format
  'b' Binary format
```

类似地，MySQL 的 BLOB/TEXT 在 `binlog_row_image = NOBLOB` 模式下也会被省略——CDC 实现必须明确文档建议用户设置为 `FULL`。

### 7. 双向复制的 origin 过滤

双向复制（A ↔ B）有循环风险：A 的写入流到 B，B 应用后又被 B 自己的 WAL 捕获，回流到 A，无限循环。PG 15 的 `origin` 过滤回调允许下游告诉源库 "我不想看到来自我自己的事件"：

```c
static bool my_filter_origin(LogicalDecodingContext *ctx,
                              RepOriginId origin_id)
{
    // 返回 true 表示"过滤掉"
    return origin_id == my_local_origin;
}
```

任何要支持双向 / 多主复制的引擎都必须有类似机制。

## 关键发现

1. **逻辑解码完全没有 SQL 标准，30 年来都是厂商各自为政**。从 1998 年 SQL Server Transactional Replication 到 2024 年 PG 17 Failover Slot，没有任何 ISO 条款定义"如何把 WAL 翻译成事件"。事实上的统一来自社区——Debezium Envelope 在 2016+ 逐渐成为跨引擎共识。

2. **PostgreSQL 的 Logical Decoding API 是业界最干净的设计**。9.4 (2014) 引入的 output plugin + replication slot 模型，把"WAL 物理格式"和"输出格式"完全解耦，让 `pgoutput`、`wal2json`、`decoderbufs` 等多种插件可以共存于同一个数据库——这种灵活性是 MySQL/Oracle/SQL Server 都没有的。

3. **MySQL 把解码工作甩给客户端，催生了 Debezium / Maxwell / Canal 三大开源生态**。MySQL 内核只产 binlog 二进制流，所有"翻译为业务事件"的工作由外部完成。这一架构差异让 MySQL 的 CDC 工具市场远比 PostgreSQL 繁荣（数量上），但也意味着每个工具都要重新造轮子（解析 ROWS_EVENT、处理 GTID、handle schema 变化）。

4. **Debezium 是事实上的统一标准**。Red Hat 主导的 Debezium 自 2016 起为 MySQL/PostgreSQL/Oracle/SQL Server/MongoDB/DB2/Cassandra/Vitess 等十余种数据库实现统一的事件 envelope，今天已被 Flink CDC、Spark Structured Streaming、Snowflake Snowpipe 等众多消费者支持。它扮演了 SQL 标准未能扮演的"跨引擎统一"角色。

5. **CockroachDB 把逻辑解码做成 SQL DDL，是最现代的设计**。`CREATE CHANGEFEED FOR TABLE ... INTO 'kafka://'` 比 PG 的 `pg_create_logical_replication_slot()` + 编写 output plugin + 启动 `pg_recvlogical` 客户端要简洁得多。如果今天从零设计一个数据库的 CDC，CockroachDB 风格更值得借鉴。

6. **Maxwell / Canal / Debezium 三家本质上都是 MySQL "假副本"**。它们都通过 `COM_REGISTER_SLAVE` + `COM_BINLOG_DUMP_GTID` 协议伪装成 MySQL 副本，区别在于输出格式和上层生态：Maxwell 输出 JSON 简洁、Canal 中文生态强、Debezium 跨数据库统一。

7. **TiCDC 证明了"基于存储层"优于"基于 SQL 层"**。TiDB 早期模拟 MySQL binlog 的 drainer 是单点，TiCDC 改为直接订阅 TiKV 的 raw KV change feed 后，水平扩展和事务一致性都得到根本改善。任何分布式数据库做 CDC 都应学习这一思路。

8. **OceanBase OBCDC 提供"伪 binlog 协议"是中国 MySQL 生态的实用主义典范**。直接复用 Canal/Debezium 配套工具，不重造轮子。这种"协议兼容"策略对国内迁移用户极有价值。

9. **REPLICA IDENTITY 是 PG 用户最常踩的坑**。默认 `DEFAULT` 只记录主键的旧值，导致 Debezium UPDATE 事件的 `before` 字段不完整。生产环境如果需要完整 before/after 对比，必须设为 `FULL`，但这会增加 WAL 体积和写入开销。

10. **流式逻辑解码（PG 14+）解决了大事务的内存炸裂问题**。传统设计必须等 commit 后才能输出，导致 1 亿行的批量更新在解码端 OOM。PG 14 引入 stream_start/change/commit/abort 回调，让事务进行中即可发送，下游 buffer 直到看到最终 commit/abort。Debezium 2.0+ 已支持。

11. **TOAST / BLOB unchanged 是跨引擎的共同设计**。无论是 PG 的 `'u' unchanged toast`、MySQL 的 `binlog_row_image = MINIMAL`，还是 Oracle 的 chained row，逻辑解码都要面对"大字段没变就不重复存"的优化与"下游需要完整值"的需求之间的张力。

12. **Failover Slot（PG 17）补齐了 PG 逻辑解码最后的高可用短板**。在此之前，物理副本切换会让逻辑订阅永久失效——副本的 LSN 与主库不同步。PG 17 让槽信息也物理同步到副本，切换后逻辑订阅可继续。这一特性的迟来表明：即使是设计最干净的 PG，CDC 高可用也花了 10 年才补齐。

13. **嵌入式数据库不需要逻辑解码**。SQLite、DuckDB、H2、HSQLDB、Derby、Firebird 都没有内置 CDC——它们的部署模型（单进程、本地文件）天然不需要"把变更同步到下游"。需要时只能依赖外部工具（litestream 之于 SQLite）做日志归档。

14. **流处理引擎是消费者而非生产者**。Trino、Presto、Spark SQL、Flink SQL、Impala 都不解码自己的数据，因为它们没有"自己的数据"——它们读外部存储。Materialize 和 RisingWave 是例外，但它们消费的也是上游 PG/MySQL 的逻辑解码流。

15. **云数仓基本不做行级解码**。Snowflake Streams 是基于快照差异的轮询，BigQuery 完全没有，Redshift 只有快照——它们的"变更追踪"概念是表级或数据集级，与传统 WAL 解码完全不同。Databricks Delta CDF 是个例外，但它运行在 Spark / Delta Lake 上，本质是 lakehouse 的特性。

16. **Spanner Change Streams 是 NewSQL CDC 的另一种范式**。不像 CockroachDB 用 CHANGEFEED 推送外部，Spanner 用 `CREATE CHANGE STREAM` + TVF 拉取——下游通过 Apache Beam / Dataflow 连接器消费。这种 pull 模型对 Google 数据流架构更自然。

## 参考资料

- PostgreSQL: [Logical Decoding](https://www.postgresql.org/docs/current/logicaldecoding.html)
- PostgreSQL: [Replication Slots](https://www.postgresql.org/docs/current/logicaldecoding-explanation.html#LOGICALDECODING-REPLICATION-SLOTS)
- PostgreSQL: [Output Plugins](https://www.postgresql.org/docs/current/logicaldecoding-output-plugin.html)
- PostgreSQL: [Logical Replication Message Formats](https://www.postgresql.org/docs/current/protocol-logicalrep-message-formats.html)
- wal2json: [GitHub](https://github.com/eulerto/wal2json)
- pglogical: [GitHub](https://github.com/2ndQuadrant/pglogical)
- MySQL: [The Binary Log](https://dev.mysql.com/doc/refman/8.4/en/binary-log.html)
- MySQL: [Binlog Event Format](https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_replication.html)
- MariaDB: [Binary Log](https://mariadb.com/kb/en/binary-log/)
- Maxwell: [GitHub](https://github.com/zendesk/maxwell)
- Canal: [GitHub](https://github.com/alibaba/canal)
- Debezium: [Documentation](https://debezium.io/documentation/)
- Debezium: [Connector for MySQL](https://debezium.io/documentation/reference/stable/connectors/mysql.html)
- Debezium: [Connector for PostgreSQL](https://debezium.io/documentation/reference/stable/connectors/postgresql.html)
- Oracle: [LogMiner](https://docs.oracle.com/en/database/oracle/oracle-database/19/sutil/oracle-logminer-utility.html)
- Oracle: [GoldenGate Documentation](https://docs.oracle.com/en/middleware/goldengate/)
- SQL Server: [Change Data Capture](https://learn.microsoft.com/en-us/sql/relational-databases/track-changes/about-change-data-capture-sql-server)
- SQL Server: [Transactional Replication](https://learn.microsoft.com/en-us/sql/relational-databases/replication/transactional/transactional-replication)
- CockroachDB: [Change Data Capture](https://www.cockroachlabs.com/docs/stable/change-data-capture-overview)
- TiDB: [TiCDC](https://docs.pingcap.com/tidb/stable/ticdc-overview)
- TiDB: [TiCDC Open Protocol](https://docs.pingcap.com/tidb/stable/ticdc-open-protocol)
- YugabyteDB: [Change Data Capture](https://docs.yugabyte.com/preview/architecture/docdb-replication/cdc/)
- OceanBase: [OBCDC](https://en.oceanbase.com/docs/common-oceanbase-database-10000000001978706)
- MongoDB: [Change Streams](https://www.mongodb.com/docs/manual/changeStreams/)
- Cassandra: [CDC](https://cassandra.apache.org/doc/latest/cassandra/operating/cdc.html)
- Snowflake: [Streams](https://docs.snowflake.com/en/user-guide/streams-intro)
- Spanner: [Change Streams](https://cloud.google.com/spanner/docs/change-streams)
- Databricks: [Delta Lake Change Data Feed](https://docs.databricks.com/en/delta/delta-change-data-feed.html)
- Materialize: [Sources](https://materialize.com/docs/sql/create-source/)
- RisingWave: [PostgreSQL CDC Source](https://docs.risingwave.com/docs/current/ingest-from-postgres-cdc/)
- Flink CDC: [Documentation](https://nightlies.apache.org/flink/flink-cdc-docs-release-3.0/)
