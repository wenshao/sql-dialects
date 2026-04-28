# DDL 复制 (DDL Replication)

DML 复制把行的变化送到副本，DDL 复制要把表结构本身的变化也送过去——这一步往往是分布式数据库最难、最容易踩坑的部分，也是为什么"自动复制 DDL"在很多引擎里至今都是半吊子或干脆不支持。

## 为什么 DDL 是复制里最难的部分

复制的本意是"在副本上重现源库的状态"。对 INSERT/UPDATE/DELETE 这类 DML，重现的对象是行；对 ALTER TABLE / CREATE INDEX / DROP COLUMN 这类 DDL，重现的对象是 catalog 自身。它们看起来都是"事务里的一段操作"，但工程上是两个完全不同的难度等级：

1. **DDL 不是单纯的数据变化，而是 catalog 变化**。DML 的回放只需要找到目标行、应用新值；DDL 的回放则要修改系统表、重建索引、可能重写整张表的物理布局，并且需要保证 catalog 在副本上和源端一致。
2. **DDL 通常涉及非事务性的副作用**。MySQL 的 `ALTER TABLE` 在 8.0 之前都是**隐式提交**的——开始时 commit 当前事务，结束时再开一个。这意味着 binlog 里很难把 DDL 和它前后的 DML 放进同一个事务，回放顺序错一点，副本结构就和源端不一致。
3. **DDL 和 DML 互相阻塞**。源端正在 ALTER 大表时，新写入的 DML 通常会被 metadata lock 阻塞；但如果复制是异步的，副本上的 DDL 可能和正在回放的旧 DML 冲突——很多复制工具直接选择"DDL 不能和 DML 同时执行"，复制延迟因此被放大。
4. **物理 vs 逻辑两条路截然不同**：
   - **物理复制**（PG 流复制、Oracle Data Guard、SQL Server AG）从 WAL 字节级回放，DDL "天然"被复制——只要源端的字节到了副本，副本就会执行同样的 catalog 修改和数据重写，不需要复制层做任何特殊处理。代价是副本必须和源端架构、版本完全一致，不能选择性同步表，不能跨大版本升级。
   - **逻辑复制**（PG 10+ logical replication、MySQL row-based binlog、Debezium、TiCDC）则只复制行级事件，DDL 默认不会被传输，需要额外的机制（事件触发器、DDL extractor、DDL filter）来捕获、传送、回放——而且每一步都有坑：DDL 文本可能包含 schema 限定符、可能引用源端独有的对象、可能在副本上语法不被接受。
5. **跨引擎和异构同步几乎一定要丢 DDL**。Debezium → ClickHouse、PG → BigQuery、MySQL → Snowflake——这些场景里源端的 DDL 语法在目标端根本不合法，所以工业界普遍的做法是：DDL 在源端执行，目标端通过外部工具（Flyway、Liquibase、自研脚本）单独 apply，复制流只携带 DML。

> 与本文相关的姊妹篇：`logical-replication-gtid.md` 讲事务标识与发布订阅拓扑，`logical-decoding.md` 讲 WAL → 行事件的解码层，`online-ddl-implementation.md` 讲单库内 DDL 不阻塞 DML 的实现。本文聚焦"DDL 如何（或如何不）被复制到副本"。

## 不存在 SQL 标准

ISO/IEC 9075（SQL 标准）从未涉及任何形式的复制——无论是 DML 还是 DDL。所有相关的语法、语义、协议、配置都是厂商专有：

- PostgreSQL 的物理流复制基于 WAL，逻辑复制基于 `pgoutput`，DDL 复制至今需要事件触发器或第三方扩展
- MySQL 的 binlog 把 DDL 当作 STATEMENT 事件记录（即使在 ROW 模式下），副本通过执行 SQL 文本来复制
- Oracle GoldenGate 用 DDL 触发器在源端拦截 DDL 文本，写入 trail 文件，副本端解析回放
- SQL Server transactional replication 默认**不**复制 DDL，需要显式 `sp_changepublication @property = 'replicate_ddl'`
- CockroachDB / Spanner / TiDB 的 DDL 是分布式 schema change 协议的一部分，本身就是"全集群一致地修改 catalog"，没有"复制 DDL"这个独立概念
- Galera Cluster 用 TOI（Total Order Isolation）让 DDL 在所有节点同时执行
- Vitess 用 VReplication 在 MySQL shard 之间同步 schema，本质上是把 DDL 当作 binlog 事件传送

这种碎片化意味着：**没有任何一种"通用"的 DDL 复制方案**——每个引擎都需要单独学习其机制和限制。

## 支持矩阵（45+ 引擎）

### 1. 物理复制是否自动携带 DDL

物理复制（流复制、redo log shipping、AG 等）按字节回放 WAL/redo log，DDL 自动被复制。下表展示各引擎的物理复制对 DDL 的支持情况。

| 引擎 | 物理复制机制 | 自动复制 DDL | 副本可读 | 跨大版本 | 备注 |
|------|------------|------------|---------|--------|------|
| PostgreSQL | 流复制 (WAL) | 是 | 是 (hot standby) | 否 | 必须同 major version |
| MySQL | -- | -- | -- | -- | 不提供物理复制 |
| MariaDB | -- | -- | -- | -- | 同 MySQL |
| SQLite | -- | -- | -- | -- | 嵌入式不适用 |
| Oracle | Data Guard Physical | 是 | Active Data Guard | 否 | 商业 |
| SQL Server | Always On AG / Log Shipping | 是 | 是 (readable secondary) | 否 | 同版本 |
| DB2 | HADR | 是 | 是 (HADR Reads) | 否 | 同版本 |
| Snowflake | -- (内部) | -- | -- | -- | 计算存储分离 |
| BigQuery | -- | -- | -- | -- | 不适用 |
| Redshift | -- | -- | -- | -- | 不适用 |
| DuckDB | -- | -- | -- | -- | 嵌入式 |
| ClickHouse | ReplicatedMergeTree | 是 (DDL 通过 Keeper) | 是 | 是 | 见下文 ON CLUSTER |
| Trino | -- | -- | -- | -- | 查询引擎 |
| Spark SQL | -- | -- | -- | -- | 查询引擎 |
| Hive | -- | -- | -- | -- | -- |
| Flink SQL | -- | -- | -- | -- | 流处理 |
| Databricks | -- | -- | -- | -- | -- |
| Teradata | Dual Active | 是 | 是 | 否 | 商业 |
| Greenplum | mirror (segment) | 是 | -- | 否 | 故障切换 |
| CockroachDB | Raft (内部) | 是 | 是 | 是 | 见 F1 协议 |
| TiDB | Raft (内部) | 是 | 是 | 是 | 见 schema broadcast |
| OceanBase | Paxos (内部) | 是 | 是 | 是 | -- |
| YugabyteDB | Raft (内部) | 是 | 是 | 是 | -- |
| SingleStore | 内部 | 是 | 是 | 是 | -- |
| Vertica | K-safety | 是 | 是 | 否 | -- |
| Impala | -- | -- | -- | -- | 查询引擎 |
| StarRocks | 内部多副本 | 是 | 是 | 是 | -- |
| Doris | 内部多副本 | 是 | 是 | 是 | -- |
| MonetDB | -- | -- | -- | -- | -- |
| CrateDB | 内部分片副本 | 是 | 是 | 是 | -- |
| TimescaleDB | 继承 PG | 是 | 是 | 否 | -- |
| QuestDB | -- | -- | -- | -- | -- |
| Exasol | 内部 | 是 | 是 | 否 | -- |
| SAP HANA | System Replication | 是 | Active/Active R/O | 否 | -- |
| Informix | HDR / RSS | 是 | 是 | 否 | -- |
| Firebird | nbackup | 不直接 | -- | -- | 备份增量 |
| H2 | -- | -- | -- | -- | -- |
| HSQLDB | -- | -- | -- | -- | -- |
| Derby | -- | -- | -- | -- | -- |
| Athena | -- | -- | -- | -- | -- |
| Synapse | -- | -- | -- | -- | -- |
| Spanner | 内部 Paxos | 是 | 是 | 是 | -- |
| Materialize | -- | -- | -- | -- | -- |
| RisingWave | -- | -- | -- | -- | -- |
| InfluxDB | -- | -- | -- | -- | -- |
| Vitess | MySQL 物理复制 (per-shard) | 是 (shard 内) | 是 | 否 | 跨 shard 见 VReplication |
| MongoDB | replica set (oplog) | 是 (oplog 是物理+逻辑混合) | 是 (secondary) | 否 | -- |
| Cassandra | gossip + hint handoff | 是 (内置一致性) | 是 | 是 | 见 schema migration |

> 统计：约 18 个引擎提供物理复制（或类物理的 raft/paxos 同步）并自动复制 DDL；约 15 个 NewSQL/分布式引擎将 DDL 视为分布式 schema change 的一部分；约 12 个引擎完全不提供物理复制。

### 2. 逻辑复制是否原生携带 DDL

逻辑复制只复制行级事件，是否复制 DDL 取决于引擎设计。这是本文的重点矩阵。

| 引擎 | 逻辑复制机制 | 默认复制 DDL | 启用方式 | 局限 |
|------|------------|------------|---------|------|
| PostgreSQL | logical replication (10+) / pglogical | 否 | 手动同步 / 第三方扩展 | PG 18 才有原生支持的提案 |
| MySQL | binlog (STATEMENT/ROW/MIXED) | 是 (DDL 即使在 ROW 模式也写 STATEMENT) | 默认开启 | 见 MySQL 章节 |
| MariaDB | binlog | 是 | 同 MySQL | -- |
| SQLite | -- | -- | -- | -- |
| Oracle | GoldenGate / Streams (停用) | 是 (需开 DDL 触发器) | `ENABLE_DDL_TRIGGER` | DDL 触发器有性能开销 |
| Oracle LogMiner | -- | DDL 在 redo 中可见 | -- | 仅查看，不重放 |
| SQL Server | Transactional Replication | 否 (默认) | `sp_changepublication @property=N'replicate_ddl', @value=1` | 见下文 |
| SQL Server | Merge Replication | 部分 (限于 schema) | -- | -- |
| DB2 | SQL Replication / Q Replication | 否 | DDL 需手动 apply | -- |
| Snowflake | Database Replication | 是 | 自动 | 整库复制 |
| ClickHouse | MaterializedPostgreSQL | 否 | -- | 实验性 |
| ClickHouse | ON CLUSTER DDL | 是 (主动多节点执行) | `ON CLUSTER` 子句 | 不是订阅式 |
| Hive | REPL DUMP / REPL LOAD | 是 | 库级别快照 | -- |
| Databricks | Delta Sharing | 否 (仅数据) | -- | 共享只读 |
| CockroachDB | CHANGEFEED | 否 | -- | 仅 DML 事件 |
| TiDB | TiCDC | 是 (4.0.10+) | `enable-ddl-replication=true` (默认) | -- |
| OceanBase | OBCDC | 是 | 默认 | -- |
| YugabyteDB | xCluster | 否 | DDL 需在两端手动执行 | -- |
| SingleStore | Pipelines | -- | 不适用 | 入口侧 |
| Materialize | 上游 PG/MySQL 解码 | 跟随源端 | -- | -- |
| RisingWave | 上游 PG/MySQL 解码 | 跟随源端 | -- | -- |
| Vitess | VReplication | 部分 (online schema change) | `OnlineDDL` 工作流 | 见下文 |
| Galera Cluster | wsrep + TOI | 是 (TOI 全局执行) | 默认 | RSU 模式不复制 |
| Spanner | -- (内部) | 是 (DDL 是分布式协议) | -- | -- |
| MongoDB | oplog | 是 | DDL 写 op 的 op-type | 仅基本 DDL |
| Cassandra | schema migration | 是 (gossip 同步 schema) | 默认 | -- |
| Debezium (PG) | logical decoding | 否 (DDL 不在 pgoutput) | DDL extractor 单独捕获 | 见下文 |
| Debezium (MySQL) | binlog | 是 (DDL 包含在 binlog) | DDL 写入 schema history topic | -- |
| Maxwell (MySQL) | binlog | 是 | 同 Debezium MySQL | -- |
| Canal (MySQL) | binlog | 是 | 同 Debezium MySQL | -- |

> 统计：约 16 个引擎/工具的逻辑复制原生携带 DDL（多数是 MySQL 系），约 14 个完全不携带 DDL 或需要繁琐的额外配置。**PostgreSQL 至今（PG 17 LTS）逻辑复制不复制 DDL** 是本表最重要的事实。

### 3. DDL 捕获机制

各引擎用什么机制把 DDL 从源端捕获出来：

| 引擎 | 捕获机制 | 是否能拿到 DDL 文本 | 是否能拿到 catalog 差异 |
|------|---------|-------------------|----------------------|
| PostgreSQL | event trigger (9.3+) | 是 (`pg_event_trigger_ddl_commands()`) | 是 (函数返回结构化结果) |
| MySQL | binlog QUERY_EVENT | 是 (DDL 原文) | 否 (需要客户端解析) |
| MariaDB | binlog QUERY_EVENT | 是 | 否 |
| Oracle | DDL trigger (`BEFORE/AFTER DDL ON SCHEMA/DATABASE`) | 是 (通过 `ora_sql_txt`) | 是 (`ora_dict_obj_*`) |
| Oracle GoldenGate | DDL 触发器 + Capture | 是 (写入 trail) | 是 |
| SQL Server | DDL trigger (`FOR/AFTER DDL_EVENTS`) | 是 (`EVENTDATA().value('//TSQLCommand/CommandText')`) | 是 (`EVENTDATA()` XML) |
| DB2 | trigger + Q Capture | 是 | 是 |
| TiDB | DDL job table (`mysql.tidb_ddl_history`) | 是 | 是 (PD 元数据) |
| CockroachDB | descriptor versioning | 否 (不暴露文本) | 是 (descriptor 差异) |
| Spanner | schema_change_listener | 否 (内部) | 是 |
| Vitess | online schema change workflow | 是 | 是 |
| Galera | wsrep_provider replication | 是 (DDL 全文广播) | -- |
| MongoDB | oplog (op: c "command") | 是 (DDL 原始命令) | -- |
| Cassandra | system_schema 表变更 + gossip | 是 (CQL 文本) | 是 |
| Snowflake | ACCOUNT_USAGE.QUERY_HISTORY | 是 (审计) | 是 (`OBJECT_DEPENDENCIES`) |
| BigQuery | INFORMATION_SCHEMA.JOBS | 是 | 是 |
| ClickHouse | system.query_log | 是 | -- |

> PostgreSQL 的 event trigger（9.3 引入，2013）是少数几个能在 DDL 提交时同时获取**原始文本**和**结构化 catalog 差异**的机制，这也是 pglogical / Bucardo / 自研复制工具能在 PG 上做 DDL 复制的基础。

### 4. Online DDL 与复制的交互

DDL 在主库可能是 online 的，在副本上是否也是 online、是否阻塞副本的读取，每个引擎差异巨大：

| 引擎 | 主库 Online DDL | 副本 DDL 是否阻塞读 | 跨副本延迟影响 |
|------|----------------|------------------|-------------|
| PostgreSQL 流复制 | `CREATE INDEX CONCURRENTLY` 等 | 阻塞 (热备只能等) | 大 DDL 延迟显著 |
| MySQL 5.7+ row-based | INPLACE / INSTANT | 副本顺序回放，仍阻塞 | gh-ost 在副本预先执行可缓解 |
| MySQL 8.0+ INSTANT | INSTANT 几乎瞬间 | INSTANT 在副本也几乎瞬间 | 推荐用 INSTANT |
| Oracle Data Guard | DBMS_REDEFINITION | 物理 standby 同步阻塞 | -- |
| SQL Server AG | ONLINE = ON | 副本可能阻塞 | 视 AG 模式 |
| CockroachDB | online schema change (F1) | 不阻塞 | 多版本 schema |
| TiDB | online DDL (类 F1) | 不阻塞 | -- |
| Spanner | online schema change | 不阻塞 | -- |
| Galera TOI | DDL 全节点同时执行 | 阻塞 (TOI) | 整集群停顿 |
| Galera RSU | 滚动升级 | 不阻塞 | 节点逐个执行 |
| Vitess | VReplication online DDL | 不阻塞 (类 gh-ost) | -- |
| ClickHouse ON CLUSTER | 异步 mutation | 副本异步执行 | 各副本独立追赶 |
| MongoDB | createIndexes 可 background | 副本逐个 apply | 副本延迟 |

### 5. DDL 过滤与白名单

是否能选择性复制 DDL（例如只复制某些表的 ALTER）：

| 引擎 | DDL 过滤支持 | 配置方式 |
|------|------------|---------|
| MySQL binlog | 是 | `replicate-do-table`, `replicate-ignore-table`, `replicate-wild-do-table` |
| MariaDB | 是 | 同 MySQL + `replicate-rewrite-db` |
| PostgreSQL logical | 不适用 (DDL 本就不复制) | -- |
| Oracle GoldenGate | 是 | `DDL INCLUDE/EXCLUDE` 子句 |
| SQL Server | 是 (publication 级别) | `sp_changepublication` |
| Debezium MySQL | 是 | `database.include.list`, `table.include.list` + DDL filter |
| Debezium PG | 不适用 | DDL 由外部工具同步 |
| TiCDC | 是 | `filter.rules` |
| OBCDC | 是 | TableWhiteList |
| Galera | 不支持 | TOI 强制全节点执行 |
| Vitess VReplication | 是 | per-keyspace / per-table |
| Spanner | 不支持 | DDL 是全库属性 |

## PostgreSQL：物理复制完美，逻辑复制不复制 DDL

PostgreSQL 是 DDL 复制讨论里最复杂、最有代表性的引擎——它有两条复制路线，对 DDL 的处理截然相反。

### 物理流复制：DDL 自动复制

PostgreSQL 的流复制（streaming replication）从 9.0 起内建，是基于 WAL 字节流的物理复制。任何写入主库的 WAL（包括 DDL 引起的 catalog 修改、heap 重写、索引重建）都会被流式发送到 standby，standby 通过 redo recovery 字节级回放：

```sql
-- 主库执行
ALTER TABLE orders ADD COLUMN priority INT DEFAULT 0;

-- 这个 DDL 在 WAL 中产生:
-- 1. pg_attribute 行的 INSERT
-- 2. pg_attrdef 行的 INSERT (DEFAULT 表达式)
-- 3. heap 表的 toast/重写记录 (PG 10 及之前) 或 pg_attribute.atthasmissing 标记 (11+)
-- 4. 必要的 invalidation message

-- standby 通过 redo 回放, 自动得到一模一样的 catalog 和数据
-- 不需要任何额外配置, 不需要 DDL 触发器
```

物理复制的优点：

1. **完全自动**：任何 DDL，包括引擎不支持逻辑复制的 DDL（VACUUM、CLUSTER、CREATE INDEX、CREATE EXTENSION），都被复制
2. **强一致**：副本是主库 WAL 的字节级镜像，没有"DDL 复制不上"的问题
3. **零配置**：不需要事件触发器、不需要 publication

物理复制的限制：

1. **必须同 major version**：PG 14 主库不能流复制到 PG 15 standby（minor version 跨度可以）
2. **必须同架构**：x86_64 主库不能流复制到 ARM64 standby（或反之），因为 WAL 中的整数字节序、对齐方式不同
3. **不能选择性复制**：要么整个集群复制，要么不复制——不能"只复制 db1，不复制 db2"
4. **Standby 只读**：不能在 standby 上写入（除非用 logical decoding）

### 逻辑复制：DDL 不复制

PG 10（2017）引入的内置逻辑复制（基于 `pgoutput` 插件）以及 PG 9.4 引入的 logical decoding 框架本身，**至今都不复制 DDL**。这是 PG 用户最常踩的坑：

```sql
-- 主库
CREATE PUBLICATION my_pub FOR TABLE orders;

-- 订阅端
CREATE SUBSCRIPTION my_sub CONNECTION '...' PUBLICATION my_pub;

-- 主库执行 DDL (新增列)
ALTER TABLE orders ADD COLUMN priority INT DEFAULT 0;

-- 订阅端: 完全不知道这件事!
-- 主库后续写入 priority 列时, 订阅端会:
--   1. 如果 priority 在订阅端不存在 -> 复制错误, 整个 subscription 停止
--   2. 如果 publish 是 (insert,update,delete,truncate) -> ERROR
--   3. 必须手动在订阅端先执行同样的 ALTER, 才能恢复
```

PG 的 logical replication 不复制 DDL 是经过深思熟虑的设计选择，不是疏忽：

1. **DDL 文本可能在订阅端非法**：例如主库的 `ALTER TABLE foo SET TABLESPACE ts1` 在订阅端如果没有 `ts1` 这个 tablespace 就会失败
2. **schema 变更可能引入冲突**：例如主库 `ALTER COLUMN x TYPE INT USING x::int`，但订阅端的同名列已经被改成了 BIGINT
3. **复制槽与 DDL 时序**：如果 DDL 改变了表 OID 或列编号，正在传输的旧事件可能引用了不存在的列
4. **跨版本兼容**：逻辑复制的卖点之一是跨大版本（PG 12 → PG 17），但 DDL 语法在不同版本可能不同（如 PG 14 引入的 `MULTIRANGE`）

社区的提案与解决方案：

```
1. PG 18 (开发中) DDL replication 提案
   - 由 EDB 团队 (Zheng Li / Hou Zhijie) 主导
   - 思路: 在主库通过 event trigger 捕获 DDL, 序列化为结构化的
     "deparse tree" (避免文本解析), 通过 logical replication 流传输
   - 订阅端用 deparse tree 反向构造 DDL 语句执行
   - 仍在 commit fest 讨论中, 截至 2025 年初尚未合入主干

2. pglogical (2nd Quadrant / EDB)
   - 第三方扩展, 支持 DDL 复制
   - 通过 event trigger + 自定义函数 pglogical.replicate_ddl_command()
   - 用户必须显式调用: SELECT pglogical.replicate_ddl_command('ALTER TABLE ...')
   - 不是隐式自动捕获

3. Bucardo
   - 基于触发器的多主复制, 但对 DDL 也是手动同步

4. 工业最佳实践
   - 使用 Flyway / Liquibase / sqitch 等 schema migration 工具
   - 在主库和所有订阅端按相同顺序、相同时机执行迁移脚本
   - 复制流只携带 DML
```

### Event Trigger：PG 9.3 引入的 DDL 捕获机制

PostgreSQL 9.3（2013 年 9 月）引入 event trigger，这是社区为 DDL 复制留下的最重要基础设施。它允许在 DDL 命令的特定阶段执行用户定义函数：

```sql
-- 三种事件:
-- ddl_command_start: DDL 开始执行前 (但 catalog 已经验证)
-- ddl_command_end:   DDL 执行完成, catalog 修改已经可见, 但事务未提交
-- sql_drop:          DROP 类语句执行后 (针对每个被删除的对象)
-- table_rewrite:     需要重写表的操作 (PG 9.5+)

-- 创建一个简单的 DDL 审计触发器
CREATE OR REPLACE FUNCTION audit_ddl()
RETURNS event_trigger AS $$
DECLARE
    obj record;
BEGIN
    FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
        INSERT INTO ddl_audit_log (
            event_time,
            user_name,
            command_tag,
            object_type,
            schema_name,
            object_identity,
            in_extension,
            command_text
        ) VALUES (
            now(),
            current_user,
            obj.command_tag,            -- 'ALTER TABLE', 'CREATE INDEX', ...
            obj.object_type,            -- 'table', 'index', ...
            obj.schema_name,
            obj.object_identity,        -- 'public.orders'
            obj.in_extension,           -- 是否由扩展引入
            current_query()             -- 当前 SQL 文本
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER audit_ddl_trigger
    ON ddl_command_end
    EXECUTE FUNCTION audit_ddl();
```

`pg_event_trigger_ddl_commands()` 返回的字段非常有价值：

| 字段 | 含义 |
|------|------|
| `classid` | 系统目录 OID（pg_class、pg_type 等） |
| `objid` | 对象 OID |
| `objsubid` | 子对象 ID（如列号） |
| `command_tag` | 命令类型（'ALTER TABLE', 'CREATE INDEX', ...） |
| `object_type` | 对象类型字符串 |
| `schema_name` | schema 名 |
| `object_identity` | 完全限定名 |
| `in_extension` | 是否在扩展定义中 |
| `command` | 内部命令结构（pg_ddl_command 类型，PG 10+） |

最关键的是 `command` 字段（PG 10 引入的 `pg_ddl_command` 类型）和配套函数 `pg_event_trigger_ddl_commands()`、`pg_get_object_address()`、`pg_identify_object_as_address()`。这套 API 让 DDL 复制的实现者可以：

1. 拿到结构化的 DDL 信息（不需要解析 SQL 文本）
2. 区分各种 ALTER 子命令（ADD COLUMN vs DROP COLUMN vs ALTER COLUMN）
3. 在订阅端基于结构化信息重构 DDL 语句

但 9.3 当时只设计了"审计"用途，没有暴露完整的 deparse tree。完整的 DDL deparse 直到 PG 18 提案（如能合入）才成为内核能力。

### Event Trigger 的限制

```
1. 不在所有 DDL 都触发
   - REINDEX, GRANT, REVOKE, COMMENT, SECURITY LABEL 不触发 ddl_command_end
   - ANALYZE, VACUUM, CLUSTER, REINDEX 不算 DDL
   - PG 13+ 的 GRANT 也开始触发, 但仍有遗漏

2. 不能在事务级别捕获 BEGIN/COMMIT
   - DDL 可能在事务里多次发生, event trigger 每次都触发
   - 需要应用层判断事务边界

3. 不能在 standby 上触发
   - 物理复制的 standby 是只读的, 永远不会执行 DDL, event trigger 无法运行
   - 这就是为什么 PG 物理复制不依赖 event trigger 也能复制 DDL

4. 在自身递归 DDL 时复杂
   - 如果 event trigger 函数本身又触发 DDL (如 CREATE TABLE), 会再次触发自己

5. 事件触发器函数失败 -> DDL 失败
   - DDL 在 ddl_command_end 触发器中失败会回滚整个 DDL 事务
   - 写得不健壮的触发器会让 DDL 系统不可用
```

## MySQL：binlog 把 DDL 当 STATEMENT 事件

MySQL 的复制模型从一开始就是逻辑复制（基于 binlog），DDL 复制是这个模型的天然部分——但实现方式有反直觉的地方。

### binlog 中的 DDL 总是 STATEMENT 格式

即使设置了 `binlog_format = ROW`，DDL 在 binlog 中仍以 `Query_log_event`（STATEMENT 类型）记录：

```
binlog 内部事件类型:
  Query_log_event:        SQL 文本 (DDL 或非事务性 DML 用)
  Table_map_log_event:    映射 table_id 到 schema.table.列 (ROW 模式)
  Write_rows_log_event:   INSERT 的行数据
  Update_rows_log_event:  UPDATE 的行数据
  Delete_rows_log_event:  DELETE 的行数据
  XID_log_event:          事务 commit 标记

DDL 总是用 Query_log_event 记录原始 SQL 文本:
  - ALTER TABLE 是 Query_log_event
  - CREATE INDEX 是 Query_log_event
  - DROP TABLE 是 Query_log_event

设计原因:
  1. DDL 不容易表达成 "行变化" (catalog 修改)
  2. 副本最简单的回放方式是直接执行 SQL
  3. 兼容历史: 5.0/5.1 时代只有 STATEMENT 模式
```

副本端的回放：

```
副本读取 Query_log_event 后:
  1. 提取 SQL 文本
  2. 设置 binlog 中带的 session 变量 (sql_mode, foreign_key_checks, ...)
  3. USE 到指定的 database
  4. 直接执行 SQL 文本

这就是为什么 MySQL 的 DDL 复制 "天然" 工作 - 副本就是个 SQL 执行器
```

### MySQL DDL 复制的隐式提交问题

MySQL 8.0 之前的 DDL **隐式提交**——开始时 commit 当前事务，结束时再开一个事务。这导致 DDL 在 binlog 里很难和前后的 DML 处于同一事务：

```sql
-- 应用代码
BEGIN;
INSERT INTO orders VALUES (1, 'A');
ALTER TABLE orders ADD COLUMN priority INT;  -- 隐式 COMMIT 上面的 INSERT
INSERT INTO orders VALUES (2, 'B');           -- 实际上在新事务里
COMMIT;

-- binlog 中的实际顺序:
--   BEGIN
--   INSERT (1, 'A')
--   COMMIT (隐式)
--   ALTER TABLE ... (Query_log_event, 单独的 statement)
--   BEGIN
--   INSERT (2, 'B')
--   COMMIT
```

副本回放时如果在 ALTER TABLE 之前崩溃恢复，可能出现"INSERT (1) 已经回放，ALTER 还没回放"的状态——副本结构和源端短暂不一致，但因为 ALTER 是后续的事件，最终会到达一致。

MySQL 8.0 引入"原子 DDL"（atomic DDL）概念，让 DDL 在 InnoDB 层面成为原子操作（要么全成要么全不成），但 binlog 层面仍然是单独的 Query_log_event。

### MySQL 的 DDL 过滤

MySQL 提供丰富的复制过滤选项，DDL 也受其影响：

```
[mysqld]
# 复制白名单 (in include list)
replicate-do-db = orders_db
replicate-do-table = orders_db.orders
replicate-do-table = orders_db.payments

# 复制黑名单
replicate-ignore-db = log_db
replicate-ignore-table = orders_db.audit_log

# 通配符 (推荐)
replicate-wild-do-table = orders_db.%      # orders_db 所有表
replicate-wild-ignore-table = log_db.%

# 库名重写
replicate-rewrite-db = src_db -> dst_db    # src_db 的事件改写到 dst_db

# 重要: DDL 的过滤行为
#   ALTER TABLE orders_db.orders -> 受 orders_db 过滤规则影响
#   USE orders_db; ALTER TABLE orders -> 受 orders_db 过滤规则影响
#   ALTER TABLE foreign_db.t -> 但当前 USE 是 orders_db -> 行为复杂!
#
# 实际行为:
#   replicate-do-db: 检查"当前数据库" (USE 后的库) 而非"对象所在库"
#   replicate-do-table: 检查"对象所在库.表"
#   两者结果可能不一致, 有过滤盲区
```

这是一个长期被诟病的 MySQL 复制行为：基于"当前数据库"的 DDL 过滤可能漏掉跨库的 DDL，建议优先使用 `replicate-wild-do-table` 这类基于完整对象名的规则。

### MySQL 8.0 的 DDL 与 GTID

GTID 模式下，每个 DDL 也分配一个 GTID。复制错误处理变得简单：

```sql
-- 副本上 DDL 失败:
SHOW REPLICA STATUS\G
--   Last_SQL_Errno: 1050
--   Last_SQL_Error: Table 'foo' already exists
--   Executed_Gtid_Set: ...

-- 跳过失败的 DDL (GTID 模式):
STOP REPLICA;
SET GTID_NEXT = 'source-uuid:23';   -- 失败的那个 GTID
BEGIN; COMMIT;                       -- 标记为已执行
SET GTID_NEXT = 'AUTOMATIC';
START REPLICA;

-- 老式的 SQL_SLAVE_SKIP_COUNTER 在 GTID 模式下无效
```

## Galera Cluster：TOI 与 RSU 两种 DDL 模式

Galera Cluster（MariaDB Galera Cluster, Percona XtraDB Cluster, MySQL Group Replication 的相似机制）是同步多主复制——任何节点的写入都要在所有节点验证后才 commit。DDL 在这种架构下有两种执行模式。

### TOI（Total Order Isolation，默认模式）

```
TOI 流程:
  1. 节点 A 收到 ALTER TABLE 请求
  2. 节点 A 不立即执行, 而是把 DDL 全文广播给集群
  3. wsrep provider (Galera) 给这个 DDL 分配一个全局序列号 (seqno)
  4. 集群所有节点 (包括 A) 在 seqno 顺序的位置上执行 DDL
  5. 所有节点同时获取 metadata lock (FTWRL 类似)
  6. DDL 在所有节点同时完成
  7. 后续的 DML 在 DDL seqno 之后被处理
```

TOI 的优点：

- **强一致**：所有节点在同一个 seqno 位置执行 DDL，没有"主库执行了，从库还没执行"的窗口
- **简单**：不需要 binlog 解析、不需要触发器
- **DDL 自动复制**：天然实现"DDL 复制"

TOI 的缺点：

- **整个集群停顿**：DDL 执行期间，所有节点都阻塞 DML（不只是源节点）
- **大表 DDL 灾难性**：100GB 表的 ALTER 锁住整个集群几小时
- **复制队列爆炸**：被阻塞的事务积压在 wsrep 队列，可能触发 flow control，进一步影响性能

### RSU（Rolling Schema Upgrade）

为了解决 TOI 大 DDL 锁集群的问题，Galera 提供 RSU 模式：

```
RSU 流程:
  1. 临时把节点切换到 RSU 模式: SET GLOBAL wsrep_OSU_method = 'RSU';
  2. 节点 A 临时退出集群 (desync from group)
  3. 在 A 上独立执行 DDL (不广播)
  4. DDL 完成后, A 重新加入集群 (state transfer 从其他节点同步)
  5. 在节点 B、C 上重复 1-4
  6. 切回 TOI: SET GLOBAL wsrep_OSU_method = 'TOI';
```

RSU 的优点：

- **集群不停顿**：每次只一个节点离线做 DDL，其他节点正常服务
- **大表友好**：不阻塞整个集群

RSU 的缺点和坑：

- **需要 schema 兼容**：DDL 期间，新结构的 A 和旧结构的 B、C 同时在线，必须保证它们能互相处理 DML
  - 兼容操作：ADD COLUMN（带默认值）、ADD INDEX
  - 不兼容操作：DROP COLUMN、CHANGE 列类型 → 必须用 TOI
- **手动操作多**：每个节点都要手动 desync、apply、resync
- **State transfer 代价高**：重新加入需要 SST/IST，大集群可能传输几十 GB

### TOI vs RSU 对比

| 维度 | TOI | RSU |
|------|-----|-----|
| 默认模式 | 是 | 否（需手动切换） |
| DDL 自动广播 | 是 | 否（每节点单独执行） |
| 集群停顿 | 是（DDL 期间整集群锁） | 否（一次只一个节点离线） |
| 数据一致性 | 强（同 seqno 执行） | 弱（短暂 schema 异构） |
| 适用 DDL 类型 | 任意 | 仅 schema 兼容的 |
| 大表（>100GB）友好 | 否 | 是 |
| 操作复杂度 | 自动 | 手动 |

### Galera DDL 的实战建议

```sql
-- 小表/快速 DDL: 用默认 TOI
ALTER TABLE small_table ADD COLUMN x INT;

-- 大表/兼容 DDL: 用 RSU
SET GLOBAL wsrep_OSU_method = 'RSU';
-- (在每个节点逐个执行)
ALTER TABLE huge_table ADD INDEX idx_phone (phone);
SET GLOBAL wsrep_OSU_method = 'TOI';

-- 大表/不兼容 DDL: 用 pt-osc / gh-ost
-- 但要小心: gh-ost 默认连接到一个节点, 它的 binlog 复制思路在 Galera 下需调整
-- 推荐 pt-osc 配合 --no-check-replication-filters
```

## Oracle GoldenGate：DDL 触发器 + Trail

Oracle 自身的 Data Guard（物理 standby）和 LogMiner 已经能处理 DDL，但跨版本、异构、双向场景里业界普遍使用 GoldenGate。GoldenGate 的 DDL 复制机制有其特殊性。

### DDL 触发器机制

GoldenGate 在源库安装后，会在源库部署若干 DDL 触发器（11g R2 之前的方式）：

```sql
-- GoldenGate 安装时自动创建的触发器 (示意)
CREATE OR REPLACE TRIGGER ggs_ddl_trigger_before
BEFORE DDL ON DATABASE
DECLARE
    sql_text  CLOB;
BEGIN
    -- 拿到 DDL 文本 (注意: DDL 触发器里 ora_sql_txt 可能跨多个分片)
    FOR i IN 1..ora_sql_txt(sql_text) LOOP
        NULL;  -- 拼接所有分片
    END LOOP;

    -- 写入 GoldenGate 自己的元数据表
    INSERT INTO ggs_marker (sql_text, ddl_op, schema_name, object_name, ...)
    VALUES (sql_text, ora_sysevent, ora_dict_obj_owner, ora_dict_obj_name, ...);
END;
/

-- DDL 执行后, GoldenGate Extract 进程读取这张元数据表 + redo
-- 把 DDL 文本和 DDL 上下文 (执行用户、schema、对象) 写入 trail 文件
-- Replicat 进程在目标端执行
```

11g R2+ 的"原生"模式（INTEGRATED CAPTURE）则不再依赖触发器，而是直接从 LogMiner 视图读取 DDL：

```
INTEGRATED CAPTURE 模式:
  1. GoldenGate 注册一个 outbound server
  2. 通过 dbms_logmnr_d 解析 redo
  3. LogMiner 视图 V$LOGMNR_CONTENTS 中的 DDL 事件被捕获
  4. 不需要 DDL 触发器, 性能更好
```

### DDL 过滤

```
GoldenGate 的 DDL 子句 (在 Extract 参数文件中):

DDL INCLUDE MAPPED        -- 只复制被 MAP 子句涵盖的对象的 DDL
DDL INCLUDE OBJTYPE 'TABLE'  -- 只复制 TABLE 相关的 DDL
DDL EXCLUDE OBJNAME hr.tmp_*  -- 排除 hr.tmp_ 开头的对象

-- 复杂示例
EXTRACT ext1
    USERID ggs, PASSWORD oracle
    EXTTRAIL ./dirdat/aa
    DDL INCLUDE MAPPED OBJTYPE 'TABLE'
    DDL INCLUDE MAPPED OBJTYPE 'INDEX'
    DDL EXCLUDE OBJNAME 'hr.audit_*'
    TABLE hr.*;
```

### GoldenGate DDL 的局限

```
1. DDL 触发器版本问题
   - 11g 及之前需要 DDL 触发器, 性能开销 (5-15%)
   - 11g R2+ 推荐 INTEGRATED CAPTURE, 但需要 Compatible 参数 ≥ 11.2

2. 不支持的 DDL
   - ALTER TABLESPACE
   - CREATE/DROP TABLESPACE
   - CREATE/ALTER USER (仅 SCHEMA-scope)
   - 某些分区维护操作

3. 跨大版本 DDL 兼容
   - Oracle 12c 的某些 DDL 在 11g 上不存在
   - 异构 (Oracle -> SQL Server) 时 DDL 几乎一定要重写
```

## SQL Server：默认不复制 DDL

SQL Server 的 transactional replication 是行级逻辑复制（类似 PG logical replication），但默认**不复制 DDL**——这是初次使用者最常困惑的地方。

### 默认行为

```sql
-- 创建 publication (默认 @replicate_ddl = 1, 但实际上有微妙差异)
EXEC sp_addpublication
    @publication = N'sales_pub',
    @replicate_ddl = 1;  -- 表面上是开的

-- 但 schema 改变是否真的同步, 取决于 article 级别的设置
EXEC sp_addarticle
    @publication = N'sales_pub',
    @article = N'orders',
    @source_object = N'orders',
    @schema_option = 0x000000000803509D;  -- 32-bit 标志位
-- @schema_option 的每一位控制是否复制不同的 schema 对象 (索引、约束、触发器、...)
```

`sp_changepublication @property = 'replicate_ddl'` 控制四类 DDL 的复制：

```
@value = 1: 复制以下 DDL
  - ALTER TABLE
  - ALTER VIEW
  - ALTER PROCEDURE
  - ALTER FUNCTION
  - ALTER TRIGGER
  - ADD/DROP COLUMN

@value = 0: 这些 DDL 不会传送到订阅端

不被复制的 DDL (无论设置如何):
  - CREATE/DROP/ALTER 不在 article 列表中的对象
  - DROP TABLE (会让订阅端的 article 失效, 必须先 sp_droparticle)
  - 索引相关 DDL (单独的 schema_option 控制)
  - 权限相关 (GRANT/REVOKE)
  - TRUNCATE TABLE (是 DDL 但不复制)
```

### Merge Replication 的 DDL

Merge replication 比 transactional 更复杂，DDL 复制能力反而更弱：

```
Merge Replication 自动复制的 DDL:
  - ALTER TABLE ADD COLUMN (NULL 列或带默认值的 NOT NULL)

不复制的 DDL:
  - DROP COLUMN
  - 改变列类型
  - 索引 DDL

原因: merge replication 基于 GUID 跟踪行变化, schema 变化容易破坏跟踪元数据
```

### Always On AG 的 DDL

SQL Server Always On Availability Group 是同步/异步物理复制（基于 transaction log shipping）。AG 副本以字节级回放 log，DDL 自动复制：

```
AG 中 DDL 行为:
  1. 主副本执行 DDL -> 写入 transaction log
  2. log block 被发送到所有 secondary
  3. secondary redo log -> 自动应用 DDL

特殊情况:
  - secondary 是 readable 的: 用户在 secondary 上的 SELECT 可能被 DDL 阻塞
    类似 PG hot standby 的 max_standby_*_delay 问题
  - secondary 上不能改变 schema (只读)
```

## CockroachDB：F1 风格的分布式 schema change

CockroachDB（以及 Spanner、TiDB 等 NewSQL）把"DDL"和"分布式 schema change"作为同一个问题来解决，没有"DDL 复制"这个独立概念——DDL 本身就是一个分布式协议，所有节点最终都会到达一致的 schema 状态。

### F1 schema change 协议

CockroachDB 的 schema change 实现参考了 Google 的 F1 论文（"Online, Asynchronous Schema Change in F1", VLDB 2013）。核心思想是 schema 多版本、状态机演进：

```
F1 schema change 状态机 (简化):

Public (旧 schema)
   ↓
Add Column 操作:
   1. DELETE_ONLY: 新列存在, 但只能用于 DELETE 时定位 (写入不带新列)
   2. WRITE_ONLY:  新列可写, 但读取仍返回 NULL/默认值 (不暴露给查询)
   3. (后台) 回填: 给所有现有行写入默认值
   4. PUBLIC:      新列对所有读写都可见

每个节点在同一时刻可能处于不同的状态版本
但任意两个相邻状态都互相兼容 (可以同时存在)
```

```sql
-- CockroachDB DDL 示例
CREATE TABLE orders (id INT PRIMARY KEY, amount DECIMAL);

-- 添加列
ALTER TABLE orders ADD COLUMN priority INT DEFAULT 0;
-- 内部: 经历 DELETE_ONLY -> WRITE_ONLY -> PUBLIC 状态
-- 此过程中, 新事务自动看到正确的状态
-- 旧事务可能仍看到旧 schema, 但写入会被自动添加新列的默认值

-- 查看 schema change 进度
SHOW JOBS WHERE job_type = 'SCHEMA CHANGE';
```

### 为什么 CockroachDB 不需要"DDL 复制"

CockroachDB 的存储层（基于 Raft 复制的 KV 范围）已经保证所有副本看到一致的字节流。DDL 修改的是系统表（descriptor），系统表的修改也通过 Raft 复制：

```
DDL 在 CRDB 中的实际执行流程:
  1. 客户端发送 ALTER TABLE 给某个 gateway 节点
  2. Gateway 启动一个 schema change job
  3. 通过 KV 事务修改 descriptor (新版本 + 状态)
  4. descriptor 修改通过 Raft 复制到所有副本
  5. 各节点的 lease holder 在租约到期时拉取新 descriptor
  6. Schema change job 推进状态机 (DELETE_ONLY -> WRITE_ONLY -> PUBLIC)
  7. 期间各节点根据 descriptor 状态决定如何处理 DML

整个过程是 "分布式协议", 不是 "复制" - 所以叫 schema change 而非 DDL replication
```

### 与传统复制的对比

```
传统 (PG/MySQL) DDL 复制问题:
  - 主库执行完 DDL, 副本可能延迟
  - 期间副本 schema 和主库不一致, 复制流可能失败
  - 副本 DDL 阻塞副本上的查询

F1/CRDB schema change 优势:
  - 没有"主库"概念, 任何节点都可以发起 schema change
  - 多版本 schema 让 schema change 期间集群可继续服务
  - DDL 不阻塞 DML

代价:
  - 实现极其复杂
  - schema change 总耗时长 (要等多个状态间隔)
  - 不可能瞬间生效 (即使 INSTANT 风格的 ADD COLUMN 也要走状态机)
```

## TiDB：通过 PD 广播 schema 版本

TiDB 的实现和 CockroachDB 思路接近，但具体机制不同。

### Schema 版本广播

```
TiDB schema change 流程:
  1. 客户端发送 DDL 给某个 TiDB server
  2. TiDB server 把 DDL 转换为 DDL job, 写入 mysql.tidb_ddl_job 表
  3. 一个 owner TiDB server (通过 etcd 选举) 负责处理 job 队列
  4. owner 推进 DDL job 的状态:
     none -> delete_only -> write_only -> write_reorg -> public
  5. 每次状态推进, owner 把新 schema 版本号写入 PD (etcd)
  6. 所有 TiDB server 监听 etcd, 拿到新版本号后:
     - 拉取 information schema 的最新版本
     - 等所有进行中的事务结束 (lease 时间)
     - 切换到新 schema 版本

Lease 机制:
  - 每个 TiDB server 持有 schema lease (默认 45 秒)
  - lease 内必须切换到最新 schema, 否则 panic
  - 这个机制保证 schema 不一致的窗口 ≤ 1 个 lease
```

### TiCDC 的 DDL 复制

TiCDC（TiDB 的 CDC 工具）会把 DDL 也作为事件传送，订阅者（如下游 MySQL、Kafka）能拿到 DDL 文本：

```
TiCDC 事件流:
  - DDL 事件包含: SQL 文本 + commit_ts + 类型
  - DML 事件包含: 行变化 + commit_ts

下游为 MySQL 时:
  TiCDC 自动在下游执行 DDL (通过 cdc cli 配置 enable_ddl_replication, 4.0.10+)

下游为 Kafka/Pulsar 时:
  DDL 作为事件发送, 消费者自行决定如何处理

下游为目标 TiDB 时:
  DDL 也通过 cdc 同步
```

### TiDB online DDL 的局限

```
1. write_reorg 阶段 (回填) 可能很长
   - 大表的 ADD INDEX 需要扫描全表, 写新索引
   - TiDB 7.5+ 引入 "fast reorg" 减少耗时

2. lease 时间是关键参数
   - 默认 45 秒, 太短可能 panic, 太长导致 DDL 慢
   - 跨数据中心部署时网络延迟可能触发问题

3. DDL 队列串行
   - 同一时刻只有一个 DDL job 在执行
   - 多个 ALTER 排队, 总耗时 = sum (而非 max)
```

## Spanner：在线 schema change

Google Spanner 把 schema change 作为分布式协议的一部分，对外不暴露"复制 DDL"概念：

```
Spanner schema change 特性:
  - DDL 是 atomic 的 (要么全成要么全失败)
  - DDL 执行期间, DML 不阻塞
  - Schema change 通过 Paxos 全局排序
  - 跨多个 region 的 schema 一致

操作示例:
  -- 新增列
  ALTER TABLE Orders ADD COLUMN Priority INT64;
  -- 不需要 ONLINE 关键字 - 默认就是 online

  -- 添加索引
  CREATE INDEX OrdersByCustomer ON Orders(CustomerId);
  -- 后台异步构建, 完成后自动可用

  -- DDL 状态查询
  SELECT * FROM INFORMATION_SCHEMA.SPANNER_STATISTICS
  WHERE catalog_name = '' AND schema_name = '';
```

Spanner 的 Change Streams（2022 引入）会暴露 DML 事件，但 DDL 不在 change streams 范围——DDL 被认为是元数据变更，由独立的接口（schema_change_listener）观察。

## Vitess：online DDL 通过 VReplication

Vitess 是 MySQL 的 sharding 中间件，DDL 复制需要跨多个 MySQL shard 进行。

### Vitess 的三种 online DDL 策略

```
Vitess online DDL 支持三种 underlying tool:
  1. gh-ost     (默认推荐, GitHub 出品)
  2. pt-osc     (Percona pt-online-schema-change)
  3. VReplication 内置 (Vitess 自研, 12+ 推荐)
```

### VReplication-based online DDL

```sql
-- 提交一个 online DDL
ALTER VITESS_MIGRATION SET CLUSTER='mycluster';
ALTER TABLE customers ADD COLUMN phone VARCHAR(20);
-- 自动转换为 online DDL job

-- 内部流程 (类 gh-ost):
-- 1. 在每个 shard 创建 ghost 表 (新结构)
-- 2. 启动 VReplication 流, 从原表复制数据到 ghost 表
-- 3. VReplication 同时捕获 binlog 增量, apply 到 ghost 表
-- 4. 数据追平后, 原子切换 (RENAME 或 cut-over)

-- 监控
SHOW VITESS_MIGRATIONS;

-- 取消
ALTER VITESS_MIGRATION '<uuid>' CANCEL;

-- 重试
ALTER VITESS_MIGRATION '<uuid>' RETRY;
```

VReplication 相对 gh-ost 的优势：

1. **不需要外部进程**：内置在 Vitess 控制平面
2. **统一的状态管理**：所有 shard 的 DDL 进度在 vtctld 中可见
3. **原子化的多 shard cut-over**：所有 shard 同时切换
4. **更好的限流**：基于 vtgate 的 throttler

### Vitess 的 DDL 局限

```
1. 不支持的 DDL 类型 (不能 online):
   - DROP TABLE (直接执行)
   - TRUNCATE
   - 复杂的分区维护
   - 涉及外键的操作

2. 跨 keyspace 的 schema 变更
   - 每个 keyspace 独立做 DDL
   - 需要协调时间窗

3. 与传统主从拓扑的冲突
   - Vitess shard 内仍是 MySQL 主从, 副本上 binlog 复制 DDL
   - 副本可能有自己的 DDL 延迟
```

## ClickHouse：ON CLUSTER 主动多节点 DDL

ClickHouse 的复制是基于 ZooKeeper/Keeper 的，DDL 通过 `ON CLUSTER` 子句显式广播：

```sql
-- 在所有 cluster 节点执行 DDL
CREATE TABLE events ON CLUSTER my_cluster (
    ts DateTime,
    user_id UInt64,
    event String
) ENGINE = ReplicatedMergeTree(...)
ORDER BY (ts, user_id);

-- 内部流程:
-- 1. 提交 DDL 到 ZooKeeper 的 task queue (/clickhouse/task_queue/ddl)
-- 2. 每个集群节点监听这个 znode
-- 3. 各节点拉取 task, 在本地执行 DDL
-- 4. 把执行结果写回 ZooKeeper
-- 5. 客户端等所有节点完成 (或超时)

-- 设置等待行为
SET distributed_ddl_task_timeout = 180;  -- 默认 180 秒
SET distributed_ddl_output_mode = 'throw';  -- throw / null_status_on_timeout / never_throw

-- ALTER 也支持
ALTER TABLE events ON CLUSTER my_cluster ADD COLUMN region String DEFAULT 'unknown';
```

ClickHouse 的设计选择：

1. **DDL 不是隐式同步的**：必须显式 `ON CLUSTER`，否则只在当前节点执行
2. **基于 ZK 而非传统复制**：DDL 通过 ZK 队列广播，不走 ReplicatedMergeTree 的复制流
3. **节点失败容忍**：某节点 DDL 失败，其他节点仍会成功，需要手动修复失败节点

## MongoDB：oplog 中的 op 命令

MongoDB 的 replica set 是基于 oplog 的逻辑复制，DDL 在 oplog 中以 "op: c"（command）类型记录：

```javascript
// oplog 条目示例 (DDL)
{
  "ts": Timestamp(1700000000, 1),
  "h": NumberLong(...),
  "v": 2,
  "op": "c",                              // command
  "ns": "mydb.$cmd",                       // 注意是 .$cmd
  "o": {
    "create": "orders",                    // 创建集合
    "idIndex": { ... }
  }
}

// 添加索引也是 command
{
  "op": "c",
  "ns": "mydb.$cmd",
  "o": {
    "createIndexes": "orders",
    "indexes": [{ "v": 2, "key": { "userId": 1 }, "name": "userId_1" }]
  }
}
```

MongoDB 的设计：

1. **DDL 自动复制**：oplog 包含所有 DDL，secondary 自动 apply
2. **不区分 DML/DDL**：都是 op，secondary 用同一套 apply 流程
3. **限制**：跨集合、跨库的事务性 DDL 弱
4. **副本 DDL 阻塞读**：`db.collection.createIndex()` 即使 background 也会在副本顺序应用

## Cassandra：gossip + schema migration

Cassandra 用 gossip 协议传播 schema 变更：

```
Cassandra schema 变更流程:
  1. 客户端在某节点执行 CREATE/ALTER (CQL)
  2. 节点更新本地 system_schema 表 (新版本 schema)
  3. 节点把 schema_version (UUID) gossip 给所有其他节点
  4. 其他节点发现自己的 schema_version 与新版本不同
  5. 触发 MigrationManager.scheduleSchemaPull()
  6. 拉取最新的 system_schema, apply
  7. 新 schema 在所有节点最终一致

特点:
  - DDL 自动传播 (gossip)
  - 最终一致, 短期内不同节点 schema 可能不同
  - 不能在 schema 不同步时执行依赖新结构的 DML

陷阱:
  - "Schema disagreement": 多个客户端并发 DDL 可能让集群陷入分裂
    每个节点看到不同的 schema 版本
  - 必须等 schema 收敛 (nodetool describecluster) 才能继续 DDL
  - CDC commitlog (3.0+) 不直接包含 DDL, 需要监控 system_schema 变更
```

## Debezium：连接器层面的 DDL 处理

Debezium 是事实标准的 CDC 框架，它对不同源数据库的 DDL 处理差异很大：

### Debezium for MySQL

```
DDL 处理:
  1. 直接读 binlog (包含 Query_log_event 即 DDL)
  2. 把 DDL 写入专门的 schema history topic (Kafka topic)
  3. 同时在内部维护一个 in-memory 的 schema 副本 (per table)
  4. 为后续的 row 事件提供正确的 column 元数据

Schema History 是关键:
  - 用于 connector 重启时重建 schema 状态
  - 不能丢, 否则 connector 无法正确解析旧的 binlog
  - Debezium 默认自己管理这个 topic, 也可以用外部存储

DDL 是否传送给下游:
  - 默认 NO (DDL 写到 schema history, 但不进 connector 主输出 topic)
  - 可以通过 include.schema.changes = true 让 connector 同时发 DDL 事件到一个独立 topic
  - 下游消费者按需处理
```

### Debezium for PostgreSQL

```
DDL 处理:
  1. PG 的 logical decoding 不输出 DDL!
  2. Debezium PG connector 完全收不到 DDL 事件
  3. 必须依赖外部机制同步 DDL:
     - 推荐: Flyway / Liquibase 在源和目标都执行迁移
     - 备选: 用 pglogical 替代 (能复制 DDL, 但 Debezium 不直接支持)
     - 最差: 应用代码暂停, 手动 DDL, 重启 connector

3. Debezium 1.6+ 可选地用 event trigger 捕获 schema change
   但即使捕获到, 也无法把 schema change 与 row 事件正确编排顺序
```

### Debezium for Oracle

```
DDL 处理:
  1. 通过 LogMiner 读 redo
  2. LogMiner V$LOGMNR_CONTENTS 中包含 DDL 事件 (OPERATION_CODE = 'DDL')
  3. Debezium 解析这些事件, 维护内部 schema 状态
  4. 同样写入 schema history topic
```

### Debezium for SQL Server

```
DDL 处理:
  1. SQL Server CDC 表本身只记录 DML
  2. Debezium SQL Server connector 通过定期检查 sys.columns 和 sys.objects 来发现 schema 变更
  3. DDL 不能实时传送, 有延迟 (取决于轮询周期)
  4. 用户必须遵循特定的 DDL 流程 (在 schema change 前后调整 capture instance)
```

## YugabyteDB：xCluster 不复制 DDL

YugabyteDB 的 xCluster（异步复制）和 Spanner 类似设计，但有重要的不同：

```
xCluster 复制 DDL 行为:
  - DDL 不在 xCluster 中传送
  - 用户必须在 source 和 target 各自手动执行同样的 DDL
  - 操作顺序错误会导致复制失败:
    错误: 先在 source ADD COLUMN, 数据写入 -> target 还没 ADD, apply 失败
    正确: 先在 target ADD COLUMN -> 再在 source ADD COLUMN -> 写入

为什么这么设计:
  - YugabyteDB DDL 本身是分布式 schema change (类 F1)
  - xCluster 是异步, 跨集群的 schema change 协调极复杂
  - 选择把责任推给用户, 简化实现

最佳实践:
  - 用 schema migration 工具 (Flyway) 作为 source of truth
  - 在 source 和 target 同时部署同样的 migration
  - 暂停 xCluster -> 在 target 执行 DDL -> 在 source 执行 DDL -> 恢复
```

## DDL 复制错误处理

复制 DDL 出错时各引擎的恢复机制差异巨大：

| 场景 | MySQL | PG 物理 | PG 逻辑 | Oracle GG | SQL Server | TiCDC | CockroachDB |
|------|-------|--------|--------|----------|-----------|------|------------|
| 副本表已存在 | 复制停止 | N/A | DML 失败 | 可配置 SKIPDDL | 复制停止 | 重试 | N/A |
| 副本缺失列 | 复制停止 | N/A | 字段映射错误 | 自动忽略 | 复制停止 | 错误 | N/A |
| 列类型不兼容 | 复制停止 | N/A | 转换失败 | 可配置 | 取决于 schema_option | 错误 | N/A |
| DDL 在副本超时 | 复制停止 | 阻塞 standby | N/A | 重试 | 阻塞 AG | 重试 | 重试 |
| 跳过失败 DDL | `SET GTID_NEXT` 跳过 | N/A | DROP/CREATE SUBSCRIPTION | DBOPTIONS DEFERREFCONST | 手动 sp_changesubstatus | `cdc cli` skip | N/A |

## 关键发现与对比总结

```
1. PostgreSQL 的逻辑复制 ≠ DDL 复制
   - 这是社区最大的认知差距
   - 用户假设 "logical replication" 包含一切, 实际只有 DML
   - PG 18 提案有望改变这一现状, 但截至 2025 年仍未合入

2. MySQL 是 DDL 复制最 "天然" 的引擎
   - binlog 把 DDL 当 STATEMENT 记录
   - 副本直接执行 SQL, 不需要任何额外配置
   - 缺点: STATEMENT 形式的 DDL 在副本回放时也会重新执行 ALTER, 大表很慢

3. 物理复制总是携带 DDL, 但有架构约束
   - PG 流复制 / Oracle Data Guard / SQL Server AG / DB2 HADR
   - 字节级回放, DDL 自动同步
   - 代价: 同版本、同架构、整库复制

4. NewSQL (CockroachDB / Spanner / TiDB / OceanBase) 没有 "DDL 复制" 概念
   - DDL 是分布式 schema change 协议
   - 多版本 schema + 状态机, 不阻塞 DML
   - F1 论文是这一流派的圣经

5. Galera 的 TOI 让大 DDL 成为整集群灾难
   - 默认模式锁全集群
   - RSU 是逃生通道, 但有兼容性约束
   - 大表 DDL 推荐 pt-osc / gh-ost 配合

6. Oracle GoldenGate 是商业 DDL 复制的事实标准
   - DDL 触发器 (老) 或 LogMiner (新) 双路径
   - 丰富的 INCLUDE/EXCLUDE 过滤
   - 跨大版本、跨数据库支持最完整

7. SQL Server transactional replication 默认不复制 DDL
   - 必须手动开 sp_changepublication @property = 'replicate_ddl'
   - 甚至开了也只复制部分 DDL (列变更, 不含索引)
   - Always On AG 是物理复制, DDL 自动同步

8. Vitess online DDL 是 sharded MySQL 的最佳实践
   - VReplication 替代 gh-ost 内置在控制平面
   - 跨 shard 的原子 cut-over
   - 不阻塞 DML

9. ClickHouse ON CLUSTER 是主动广播, 不是订阅
   - 显式语法控制 DDL 范围
   - 基于 ZooKeeper/Keeper 的任务队列
   - 容错: 部分节点失败不阻塞其他节点

10. Debezium / TiCDC / OBCDC 等 CDC 框架对 DDL 处理不一致
    - MySQL connector 自动捕获 binlog 中的 DDL
    - PG connector 完全无法捕获 DDL (因为 logical decoding 不输出)
    - 必须用外部 schema migration 工具补足
```

## 对引擎开发者的实现建议

```
1. 为新引擎设计逻辑复制时, 优先考虑 DDL 是否能复制

   选项 A: 一起复制 (MySQL 模式)
     优点: 用户体验好, 自动化程度高
     缺点: 副本回放可能阻塞, 跨版本兼容难

   选项 B: 不复制 (PG 模式)
     优点: 实现简单, 隔离性好
     缺点: 用户必须用外部工具

   选项 C: 暴露 hook 让用户自定义 (event trigger)
     优点: 灵活性最大
     缺点: 复杂度推给用户

2. DDL 在副本上要和 DML 串行还是并行
   MySQL 默认串行 (SQL 线程顺序回放)
     -> 大 DDL 阻塞副本上所有后续 DML 复制
   并行复制 (parallel replication) 模式下
     -> DDL 仍需要在所有 worker 同步点执行
   建议: 在 schema 内串行, 跨 schema 可并行

3. Schema 多版本是关键
   - 副本可能短暂处于 "旧 schema 写入旧字段, 新 schema 读取新字段" 状态
   - F1 风格的 DELETE_ONLY/WRITE_ONLY/PUBLIC 状态机是参考实现
   - 替代方案: 暂停复制流 -> 同时在所有副本 apply DDL -> 恢复

4. DDL 文本 vs 结构化表达
   - 文本: 简单, 但跨版本/跨引擎不可移植
   - 结构化 (deparse tree): 复杂, 但能支持任意目标
   - PG 18 DDL replication 提案选择了 deparse tree 路线
   - 工业建议: 内部用结构化, 对外提供文本以方便调试

5. DDL 与全局事务标识的协作
   - GTID 模式下每个 DDL 也是一个 transaction, 分配 GTID
   - 跳过失败 DDL 时, 通过 GTID 范围操作
   - LSN/SCN 模式下 DDL 在 WAL 流中有明确位置, 可重启复制

6. 容错机制
   - DDL 在副本失败 -> 提供 SKIP 命令
   - 副本表已存在 -> 提供 IF NOT EXISTS 自动转换
   - 列已存在 -> 提供 IGNORE 选项
   - 类型不兼容 -> 提供 STRICT/LAX 模式

7. 跨引擎复制时的 DDL 转换
   - 几乎不可能完全自动
   - 提供 DDL 转换器 (如 ora2pg, sql_translator) 作为最佳近似
   - 接受 "DDL 必须人工迁移" 的现实, 在工具中提供 hooks

8. 监控和可观测性
   - 提供 system 视图查询当前正在执行的 DDL 和复制状态
   - DDL 在主库和副本的耗时分别统计
   - 提供"DDL 已经传送到哪个 GTID/LSN/seqno"的可见性
```

## 对应用开发者的最佳实践

```
1. 不要假设 "复制" 包含 DDL
   - 即使在 MySQL (默认包含), 也要在切换前验证
   - 在 PG, 100% 不包含, 必须用 Flyway/Liquibase

2. 使用 schema migration 工具作为单一真相源
   - Flyway, Liquibase, sqitch, golang-migrate
   - 在主库和所有副本/异构目标都执行同样的 migration
   - 复制流只携带 DML

3. 大表 DDL 用专门的工具
   - MySQL: gh-ost / pt-osc (单库) / Vitess online DDL (sharded)
   - PostgreSQL: pg_repack 或 PG 11+ 的 ADD COLUMN 默认即时
   - Oracle: DBMS_REDEFINITION
   - 避免在主库直接 ALTER 100GB 表

4. DDL 顺序遵循 "兼容前置"
   - 添加列 / 索引: 先副本 -> 再主库
   - 删除列 / 索引: 先主库 -> 再副本
   - 改类型: 中间状态需要兼容 (新旧类型并存)

5. 监控复制延迟时也要关注 DDL 延迟
   - 副本的 SQL_thread 在执行长 DDL 时, 复制延迟会突然飙升
   - 这不是 bug, 是预期行为
   - 监控应区分 "DML 延迟" 和 "DDL 阻塞"

6. 异构复制 (跨引擎) 的 DDL 处理
   - PostgreSQL -> ClickHouse: ClickHouse 不支持 PG 的所有类型, DDL 必须重写
   - MySQL -> Snowflake: Snowflake 不支持 MySQL 的 ENUM, 必须转 VARCHAR
   - 建议: 用 schema registry 维护异构 schema 映射, DDL 触发时同步更新
```

## 参考资料

- PostgreSQL: [Logical Replication Restrictions](https://www.postgresql.org/docs/current/logical-replication-restrictions.html)
- PostgreSQL: [Event Triggers](https://www.postgresql.org/docs/current/event-triggers.html)
- PostgreSQL: [Logical Decoding](https://www.postgresql.org/docs/current/logicaldecoding.html)
- PostgreSQL DDL Replication 提案: [pgsql-hackers Logical replication of DDL](https://www.postgresql.org/message-id/flat/CAJpy0uBaRcwj4D7pyR45gpcMPnMsNhRpUcKsP41OnsLqrk96gw@mail.gmail.com)
- MySQL: [Replication and Binary Logging](https://dev.mysql.com/doc/refman/8.0/en/replication.html)
- MySQL: [Atomic DDL](https://dev.mysql.com/doc/refman/8.0/en/atomic-ddl.html)
- MariaDB: [Galera Cluster TOI/RSU](https://mariadb.com/kb/en/changes-and-improvements-in-mariadb-galera-cluster-25/)
- Galera Cluster: [DDL and OSU Methods](https://galeracluster.com/library/documentation/schema-upgrades.html)
- Oracle GoldenGate: [DDL Replication](https://docs.oracle.com/en/middleware/goldengate/core/21.3/admin/configuring-ddl-synchronization.html)
- SQL Server: [Replicate Schema Changes](https://learn.microsoft.com/en-us/sql/relational-databases/replication/publish/make-schema-changes-on-publication-databases)
- SQL Server: [Always On AG and DDL](https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/availability-group-and-ddl-statements)
- CockroachDB: [Online Schema Changes](https://www.cockroachlabs.com/docs/stable/online-schema-changes)
- F1 论文: Rae, I. et al. "Online, Asynchronous Schema Change in F1" (VLDB 2013)
- TiDB: [DDL Implementation](https://github.com/pingcap/tidb/blob/master/docs/design/2018-10-08-online-DDL.md)
- TiCDC: [DDL Replication](https://docs.pingcap.com/tidb/stable/ticdc-overview)
- Spanner: [Schema Updates](https://cloud.google.com/spanner/docs/schema-updates)
- Vitess: [Online DDL](https://vitess.io/docs/user-guides/schema-changes/managed-online-schema-changes/)
- ClickHouse: [Distributed DDL](https://clickhouse.com/docs/en/sql-reference/distributed-ddl)
- MongoDB: [Replica Set Oplog](https://www.mongodb.com/docs/manual/core/replica-set-oplog/)
- Cassandra: [Schema Migration](https://cassandra.apache.org/doc/latest/cassandra/architecture/dynamo.html#schema-disagreement)
- Debezium: [MySQL Schema History](https://debezium.io/documentation/reference/stable/connectors/mysql.html#mysql-schema-history-topic)
- Debezium: [PostgreSQL DDL Limitation](https://debezium.io/documentation/reference/stable/connectors/postgresql.html#postgresql-ddl)
- pglogical: [DDL Replication](https://github.com/2ndQuadrant/pglogical#ddl-replication)
- gh-ost: [GitHub Online Schema Migration](https://github.com/github/gh-ost)
- pt-online-schema-change: [Percona Toolkit](https://docs.percona.com/percona-toolkit/pt-online-schema-change.html)
