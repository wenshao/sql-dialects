# Binlog 格式模式 (Binlog Format Modes)

复制日志的格式选择决定了一切：是把 SQL 语句原样存进日志（小、人类可读、但回放可能错），还是把每一行改动前后的镜像存进日志（大、二进制、但回放绝对正确），或者由引擎在两者之间自动切换？这道选择题困扰了 MySQL 二十年，也定义了所有"基于日志的复制"系统的设计空间——从 1996 年的 Replication Server 到 2024 年的 Debezium，几乎每一个产品都要在 Statement vs Row 这两端之间画线。本文系统梳理 45+ 引擎的复制日志格式：MySQL 三种 `binlog_format`、PostgreSQL 纯物理 WAL、Oracle redo log + LogMiner、SQL Server 双轨制（事务复制 vs 物理副本）、CockroachDB / TiDB / OceanBase 的 NewSQL 路线，以及 ClickHouse 这类完全没有等价物的列存引擎。

## 不存在 SQL 标准

binlog 格式选择完全是厂商私有约定。ISO/IEC 9075 从未定义"复制日志该长什么样"，也不规定"语句模式 / 行模式"这种概念。以下都是各厂商自行命名的术语：

- MySQL：`binlog_format = STATEMENT | ROW | MIXED`
- MariaDB：继承 MySQL 但默认 MIXED
- Oracle：redo log 是物理日志，逻辑解码靠 LogMiner / GoldenGate / XStream
- PostgreSQL：WAL 完全物理，逻辑层依赖 Logical Decoding API（9.4+）
- SQL Server：Transactional Replication 是命令型（statement-like），物理副本（AlwaysOn AG）传输 LSN
- CockroachDB / TiDB / OceanBase / YugabyteDB：内部 Raft/Paxos + 行级 CDC（CHANGEFEED / TiCDC / OBCDC）
- ClickHouse / Snowflake / BigQuery 这类 OLAP 引擎根本没有等价的"复制日志格式"概念

这种百花齐放的局面意味着：

1. **跨引擎不可移植**：MySQL 的 binlog 解析器无法读 PostgreSQL WAL；为 Oracle redo 写的 LogMiner 视图无法在 SQL Server 上执行。
2. **生态被连接器统一**：Debezium、Maxwell、Canal 把不同引擎的变更流翻译成统一的 JSON/Avro 格式，把"格式模式"差异隐藏在 connector 内部。
3. **术语含义模糊**：业界常说"语句级复制 / 行级复制"，但同一个词在不同引擎里指代不同机制。MySQL ROW 模式指 `ROWS_EVENT` 二进制；SQL Server "row-based" 可能指 Merge Replication 的 sync 表；CockroachDB 的"row-based changefeed"是 SQL 层结果集。

> 本文是 `logical-decoding.md`、`logical-replication-gtid.md`、`wal-archiving.md` 的姊妹篇。前者讨论"WAL/binlog 怎么解码成事件"，中者讨论"内置 Pub/Sub 与全局事务标识"，后者讨论"日志归档与 PITR"。本文聚焦 STATEMENT / ROW / MIXED 这三种"日志格式"在不同引擎里的存在/缺失/替代物。

## 核心权衡：回放正确性 vs 存储成本

### Statement-Based Replication（SBR）

把执行的 SQL 语句原样写入日志：

```sql
-- 主库执行（写入 binlog 的就是这条语句的文本）
UPDATE orders SET status = 'shipped' WHERE created_at < NOW() - INTERVAL 1 DAY;
```

**优点**：日志小（一条 UPDATE 影响 100 万行也只占几十字节）；人类可读；跨大版本回放兼容性好。

**致命缺陷**：非确定性函数会导致主从漂移。`NOW()`、`UUID()`、`RAND()`、`@@server_id`、`USER()`、未指定 ORDER BY 的 `LIMIT`、用户自定义函数（UDF）、自增列的并发分配——任何一个都可能让主从在同一条语句上得出不同结果。

### Row-Based Replication（RBR）

不记录 SQL 语句，而是记录每一行**实际变化**的前后镜像（before-image / after-image）：

```
TABLE_MAP_EVENT:    table_id=42, schema='shop', table='orders'
UPDATE_ROWS_EVENT:  table_id=42
  ROW 1:
    BEFORE: (id=1001, status='pending', updated_at='2024-01-01 10:00:00')
    AFTER:  (id=1001, status='shipped', updated_at='2024-01-02 11:30:00')
  ROW 2:
    BEFORE: (id=1002, status='pending', updated_at='2024-01-01 09:30:00')
    AFTER:  (id=1002, status='shipped', updated_at='2024-01-02 11:30:00')
  ... (再 999,998 行)
```

**优点**：回放绝对正确（无论函数多么非确定性，行的最终值在主库已经定下来）；副本结构差异容忍度高（部分列缺失也能 apply）；CDC 友好（Debezium 等直接消费）。

**代价**：日志膨胀。一条 `UPDATE ... WHERE created_at < ...` 可能从几十字节变成几百 MB；二进制格式不易直接 grep 排查；schema 变更需要正确的 `TABLE_MAP_EVENT`。

### Mixed-Based Replication（MBR）

引擎自动判断：能用 SBR 就用 SBR，遇到非确定性场景就**临时切换**到 RBR。MySQL 5.1 引入这个模式作为"二者兼得"的方案，但实际落地复杂——MySQL 内部维护一张"必须用 ROW"的语句类型清单（涉及 `UUID()`、`LOAD_FILE()`、`USER()` 等），命中即降级到 ROW，否则保持 STATEMENT。

```sql
-- 这条会以 STATEMENT 写入 binlog
UPDATE orders SET status = 'pending' WHERE id = 100;

-- 这条因为含 NOW()，MIXED 模式下会以 ROW 写入
UPDATE orders SET updated_at = NOW() WHERE status = 'pending';
```

## 支持矩阵（45+ 引擎）

### 1. 原生复制日志机制

| 引擎 | 原生复制日志 | 日志类型 | 起始版本 | 备注 |
|------|----------|---------|---------|------|
| MySQL | binary log (binlog) | 逻辑 (3 种格式) | 3.23 (2000-2001) | SBR-only → +RBR/MBR (5.1, 2008) |
| MariaDB | binary log | 逻辑 (3 种格式 + Annotate) | 继承 MySQL | 默认 MIXED |
| PostgreSQL | WAL (Write-Ahead Log) | 物理 | 7.x (流复制 9.0) | 纯物理，逻辑层另起 Logical Decoding (9.4+) |
| SQLite | -- | -- | 不支持 | 嵌入式，无原生日志复制 |
| Oracle | redo log | 物理 | v6+ (1980s) | 逻辑解码靠 LogMiner (8i, 1999) / GoldenGate / XStream |
| Oracle GoldenGate | trail file | 逻辑 (行级) | 1999 (Oracle 收购 2009) | 商业产品 |
| SQL Server | transaction log | 物理 (回放型) | 早期 | 物理副本 + 事务复制双轨 |
| DB2 | log file (LOGRETAIN/USEREXIT) | 物理 + Q Capture (逻辑) | 早期 | InfoSphere CDC / Q Replication |
| Snowflake | -- | -- | -- | 无传统复制日志，DATABASE REPLICATION 走快照 |
| BigQuery | -- | -- | -- | 无内部日志复制 |
| Redshift | -- | -- | -- | 仅有跨区快照 |
| DuckDB | -- | -- | -- | 嵌入式 |
| ClickHouse | ReplicatedMergeTree log (Keeper) | 物理片段级 | 早期 | 不是行级 binlog |
| Trino | -- | -- | -- | 查询引擎 |
| Presto | -- | -- | -- | 查询引擎 |
| Spark SQL | -- | -- | -- | 查询引擎 |
| Hive | -- | REPL DUMP (库级元数据) | 3.0 (2018) | 非行级日志 |
| Flink SQL | checkpoint / savepoint | 状态快照 | -- | 非复制日志 |
| Databricks | Delta CDF | 行级（commit log 派生） | 2021 | 类似 RBR |
| Teradata | Permanent Journal (PJ) | 物理 + 逻辑混合 | 早期 | -- |
| Greenplum | WAL per segment | 物理 | 继承 PG | -- |
| CockroachDB | Raft log + WAL (Pebble) | 物理 | 1.0 | CHANGEFEED 输出行级 |
| TiDB | Raft log + RocksDB WAL | 物理 KV | 1.0 | TiDB binlog (deprecated) → TiCDC (4.0, 2020) |
| OceanBase | Paxos clog | 物理 | 1.0 | OBCDC 兼容 binlog |
| YugabyteDB | Raft log + RocksDB WAL | 物理 KV | 早期 | xCluster + CDC |
| SingleStore (MemSQL) | -- (Pipelines 是导入侧) | -- | -- | 无对外 binlog |
| Vertica | -- | -- | -- | 无传统 binlog |
| Impala | -- | -- | -- | 查询引擎 |
| StarRocks | -- | -- | -- | 内部多副本 |
| Doris | -- | -- | -- | 内部多副本 |
| MonetDB | -- | -- | -- | -- |
| CrateDB | translog (Lucene) | 物理段级 | -- | -- |
| TimescaleDB | 继承 PG WAL | 物理 | 继承 PG | -- |
| QuestDB | WAL | 物理 | 6.6+ | 单机为主 |
| Exasol | -- | -- | -- | 内部 |
| SAP HANA | redo log | 物理 | 1.0 | 仅物理 System Replication |
| Informix | logical log | 混合 | 早期 | Enterprise Replication |
| Firebird | -- | -- | -- | 不支持 |
| H2 | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | 不支持 |
| Amazon Athena | -- | -- | -- | 查询引擎 |
| Azure Synapse | -- | -- | -- | -- |
| Google Spanner | Paxos log + Change Streams | 物理 + 逻辑 TVF | 2022 (Streams) | -- |
| Materialize | -- | -- | -- | 消费上游 binlog/WAL |
| RisingWave | -- | -- | -- | 同 Materialize |
| InfluxDB | TSM WAL | 物理 | 1.x | 单机 |
| DatabendDB | -- | -- | -- | 对象存储增量 |
| Yellowbrick | -- | -- | -- | 基于 PG |
| Firebolt | -- | -- | -- | -- |
| MongoDB | oplog | 逻辑 (BSON) | 早期 | 文档级，非 SQL binlog |
| Cassandra | commitlog | 物理 + CDC 选项 | 3.0 (2015) | -- |

> 统计：约 14 个引擎提供"行级或语句级"的逻辑复制日志（MySQL 系、Oracle 商业、SQL Server 事务复制、Informix 等）；约 16 个引擎只有物理 WAL/redo（PostgreSQL 系、Oracle redo、NewSQL 内部 Raft 等）；约 15 个引擎完全没有原生复制日志（OLAP 列存、查询引擎、嵌入式）。

### 2. STATEMENT 模式支持

| 引擎 | 原生 STATEMENT 模式 | 起始版本 | 默认 | 备注 |
|------|------------------|--------|------|------|
| MySQL | 是 | 3.23 (2000-2001) → 5.1 之前唯一格式 | 5.1.5 之前默认 | 5.1 后可选 |
| MariaDB | 是 | 继承 MySQL | -- | 可切到 STATEMENT |
| Oracle GoldenGate | DDL 模式 | 1999+ | -- | DDL 走 statement，DML 走行 |
| SQL Server Transactional | command-text 形式 | 1998 (7.0) | 是 | 内部生成 INSERT/UPDATE/DELETE 命令 |
| DB2 SQL Replication | 是 (CD 表 SQL) | 早期 | -- | -- |
| PostgreSQL | -- | -- | -- | WAL 不是 statement-based |
| TiDB / CockroachDB / OceanBase / YugabyteDB | -- | -- | -- | NewSQL 一律行级 |
| ClickHouse / Snowflake / BigQuery | -- | -- | -- | 无 statement 复制概念 |

### 3. ROW 模式支持

| 引擎 | 原生 ROW 模式 | 起始版本 | 默认 | 备注 |
|------|------------|--------|------|------|
| MySQL | 是 | 5.1 (Nov 2008) | 5.7.7 起 (Apr 2015) | 默认从 STATEMENT 切到 ROW 是关键节点 |
| MariaDB | 是 | 继承 5.1 | -- | 默认 MIXED |
| Oracle GoldenGate | 是 | 1999+ | 是 | trail 默认行级 |
| Oracle LogMiner | 行级（解码后） | 8i (1999) | -- | 视图给出行前后值 |
| Oracle XStream | 是 | 11g+ | -- | LCR (Logical Change Record) 行级 |
| Oracle Streams | 是 | 9i (2001, deprecated 12c) | -- | LCR 同 XStream |
| SQL Server CDC | 是 | 2008 | -- | cdc.* 表行级 |
| SQL Server Transactional Replication | 行级（内部 sp_MS* 调用） | 1998 (7.0) | -- | 通过自动生成的存储过程发送行 |
| DB2 Q Replication | 是 | 早期 | -- | MQ 队列行级 |
| Debezium MySQL Connector | 是 (强制 ROW) | 0.x+ | -- | 必须 binlog_format=ROW |
| TiDB TiCDC | 是 | 4.0 (2020) | -- | Open Protocol 行级 |
| CockroachDB CHANGEFEED | 是 | 2.1 (2018) | -- | JSON/Avro 行级 |
| OceanBase OBCDC | 是 | 3.x (2021) | -- | 兼容 binlog 行格式 |
| YugabyteDB CDC | 是 | 2.12+ | -- | 类 PG 协议 |
| MongoDB oplog | 是 (文档级) | 早期 | 是 | BSON 文档级 |
| Databricks Delta CDF | 是 | 2021+ | -- | 类 RBR |
| MariaDB | 是 | 继承 | -- | -- |
| PostgreSQL Logical Decoding | 是 (解码后) | 9.4 (2014) | -- | output plugin 决定格式 |
| Cassandra CDC | 是 (commitlog) | 3.0 | -- | -- |
| Spanner Change Streams | 是 (TVF) | 2022 | -- | -- |

### 4. MIXED 模式支持

| 引擎 | 原生 MIXED 模式 | 起始版本 | 默认 | 备注 |
|------|--------------|--------|------|------|
| MySQL | 是 | 5.1 (2008) | -- | 与 ROW、STATEMENT 同期 |
| MariaDB | 是 | 继承 | 是 (默认) | -- |
| Oracle GoldenGate | 自动选择 (DDL 走 statement, DML 走行) | 1999+ | 是 | 不显式叫 "MIXED" |
| 其他引擎 | -- | -- | -- | 几乎独此 MySQL 系一家 |

> MIXED 是 MySQL 5.1 的妥协方案。除 MySQL/MariaDB 之外，几乎没有其他引擎采用"自动切换"的命名，多数引擎要么纯 ROW，要么纯物理日志。

### 5. 物理日志 vs 逻辑日志

| 引擎 | 物理日志 | 逻辑日志 | 解码工具 |
|------|--------|--------|--------|
| MySQL | -- (binlog 是逻辑) | binlog (STATEMENT/ROW/MIXED) | 内置（mysqlbinlog）+ Debezium/Maxwell/Canal |
| MariaDB | -- | binlog | 同 MySQL |
| PostgreSQL | WAL | -- (需 Logical Decoding 解码 WAL) | output plugin（pgoutput / wal2json / decoderbufs） |
| Oracle | redo log | -- (需 LogMiner / GoldenGate / XStream 解码) | LogMiner / GoldenGate Extract |
| SQL Server | transaction log | CDC.* 表 + Distributor | CDC / Replication Distribution Agent |
| DB2 | log files | Q Capture / SQL Replication | InfoSphere CDC |
| CockroachDB | Pebble WAL + Raft log | -- (CHANGEFEED 单独走) | 内置 CHANGEFEED |
| TiDB | RocksDB WAL + Raft log | -- (TiCDC 单独走) | TiCDC |
| OceanBase | Paxos clog | -- (OBCDC 单独走) | OBCDC |
| YugabyteDB | RocksDB WAL + Raft log | -- (CDC Connector 单独走) | xCluster + CDC |
| Spanner | Paxos log | Change Streams (TVF) | Change Streams |
| ClickHouse | ReplicatedMergeTree 元数据日志 | -- | -- |
| MongoDB | journal | oplog | Change Streams / oplog tailing |
| Cassandra | commitlog | commitlog (CDC=true) | -- |

> 关键观察：MySQL 是少数把 binlog 设计成"独立于物理日志"的引擎——InnoDB redo + binlog 是两套日志，由 XA 风格的 binlog group commit 协调一致。这种设计成本是双倍写日志，但好处是 binlog 完全脱离存储引擎，可以做到跨引擎（InnoDB/MyISAM/Memory）一致复制。

## 引擎详解

### MySQL：三模式的二十年演进

MySQL 是 binlog 格式模式概念的起源地。它的三模式演进史也几乎是整个"日志复制"问题域的演进史。

**3.23 (2000-2001)：起步即 SBR**

MySQL 3.23.15（2000 年 5 月）首次引入 binlog 复制，3.23 GA 在 2001 年 1 月。当时 binlog 是纯文本式的 SQL 语句序列：

```
# at 4
#240101 10:00:00 server id 1  end_log_pos 100   Query   thread_id=1
SET TIMESTAMP=1704067200/*!*/;
UPDATE orders SET status = 'shipped' WHERE id = 100/*!*/;
```

主库写一条 UPDATE，binlog 里就存这条 UPDATE 文本（加上 `SET TIMESTAMP=` 这种伪命令尝试稳住时间），副本拉过来一字不差地执行。这套机制简单优雅，但藏雷：

- `NOW()` / `UUID()` / `RAND()` 在主从不同时刻执行得出不同值
- 自增列在并发插入时分配顺序可能与主库不同
- 用户定义函数（UDF）行为不一致
- `LIMIT` 没有 `ORDER BY` 时，行选择顺序依赖存储引擎实现

DBA 在使用 5.0 / 5.1 之前的 MySQL 复制时，几乎都要写一份"被禁的 SQL 函数清单"贴在墙上。

**5.1 (Nov 2008)：ROW 与 MIXED 同期登场**

MySQL 5.1.5（2007）引入了 `binlog_format` 系统变量，正式 GA 是 5.1.30（2008 年 11 月）。这一版本同时引入了三种格式：

- `STATEMENT`（默认，沿用 3.23 行为）
- `ROW`（新增，写 ROWS_EVENT 二进制）
- `MIXED`（新增，自动切换）

```sql
-- 5.1+ 全局或会话级切换
SET GLOBAL binlog_format = 'ROW';
SET SESSION binlog_format = 'STATEMENT';

-- 重启不丢失需写入 my.cnf
[mysqld]
binlog_format = ROW
```

ROW 模式的物理布局：

```
ROWS_EVENT 头部:
  table_id (varint)         -- 4-6 字节
  flags (uint16)            -- 2 字节，是否最后一行等
  extra_data_len (varint)   -- 元数据长度
  extra_data                -- 元数据（变长）
  num_columns (varint)      -- 列数
  columns_present_bitmap1   -- before-image 哪些列有值（位图）
  columns_present_bitmap2   -- after-image 哪些列有值（仅 UPDATE）
ROWS:
  null_bitmap_before        -- before-image NULL 位图
  before_values             -- before-image 字段编码值
  null_bitmap_after         -- after-image NULL 位图（仅 UPDATE）
  after_values              -- after-image 字段编码值
```

MIXED 模式的判断逻辑（节选）：

```
if (语句包含以下函数 OR 操作 OR 表特性):
    UUID(), USER(), CURRENT_USER(), VERSION(), CONNECTION_ID(),
    LOAD_FILE(), GET_LOCK(), RELEASE_LOCK(),
    系统变量（部分），UDF（部分），
    访问 mysql 系统库的语句，
    INSERT DELAYED 命中触发器，
    使用了 SLEEP() 等非确定性函数 → 强制 ROW
elif (能用 STATEMENT 表达且确定性):
    使用 STATEMENT
else:
    使用 ROW
```

**5.7.7 (April 2015)：默认从 STATEMENT 切到 ROW**

这是 MySQL 复制史上最重要的默认值变更。从 5.7.7 起，新安装的 MySQL `binlog_format` 默认值从 `STATEMENT` 改为 `ROW`。理由很直白：

1. SBR 的非确定性问题在生产中反复出现
2. RBR 已经稳定运行多年
3. GTID（5.6 引入）配合 RBR 才能给出真正的"幂等续点"语义
4. Group Replication（5.7 引入）只支持 ROW 模式

```sql
-- 5.7.7+ 默认行为
SHOW VARIABLES LIKE 'binlog_format';
-- +---------------+-------+
-- | Variable_name | Value |
-- +---------------+-------+
-- | binlog_format | ROW   |
-- +---------------+-------+

-- 老用户升级到 5.7.7+ 不会自动改默认值
-- 仅新初始化的实例默认 ROW
```

**8.0+：ROW 一统江湖**

8.0 起，MySQL 几乎所有新特性（CHANGE STREAM-style、JSON binlog、加密 binlog、GTID-only 模式、Clone Plugin）都假设 ROW 模式。8.4 (2024) 重命名了 `master/slave` 术语为 `source/replica`，但格式选择保持不变。

**SBR-only 限制清单（MySQL 5.7+）**

即使在 RBR 是默认的时代，仍有少量场景必须强制 STATEMENT：

```
- BACKUP DATABASE / RESTORE DATABASE 风格的语句
- LOAD DATA INFILE（5.6 之前）
- CALL 调用存储过程时，部分非确定性 UDF 仍按 STATEMENT 处理
- 临时表的某些 DDL（5.7.x 之前）
- 某些 GTID 强制场景下的 schema 改动
```

但官方建议：除非有非常具体的兼容性需求，否则永远使用 ROW。

### MariaDB：默认 MIXED 的差异

MariaDB 完整继承了 MySQL 5.1 的三模式机制，但有几点重要区别：

**默认值：MIXED 而非 ROW**

```sql
-- MariaDB 默认
SHOW VARIABLES LIKE 'binlog_format';
-- +---------------+-------+
-- | Variable_name | Value |
-- +---------------+-------+
-- | binlog_format | MIXED |
-- +---------------+-------+
```

理由：MariaDB 团队认为 MIXED 在向后兼容（老应用习惯 SBR 输出）和正确性之间是更好的妥协。但代价是 binlog 解析器（如 Debezium MariaDB Connector）必须能处理两种事件类型混杂。

**Annotate Rows Event**

MariaDB 独有的扩展：在 ROW 事件之前可选地附加一条"annotate"事件，记录原始 SQL 语句文本。这样既有 ROW 的正确性，又保留 SBR 的可读性：

```
Annotate_rows: UPDATE orders SET status = 'shipped' WHERE created_at < '2024-01-01'
Table_map:     orders
Update_rows:   (1001, 'pending') → (1001, 'shipped')
Update_rows:   (1002, 'pending') → (1002, 'shipped')
...
```

启用：

```ini
[mysqld]
binlog_format = ROW
binlog_annotate_row_events = ON
```

副本端通过 `replicate_annotate_row_events = ON` 把 annotate 写入自己的 binlog，方便审计与下游消费。

### PostgreSQL：纯物理 WAL，没有 statement-based 这回事

PostgreSQL 的 WAL（Write-Ahead Log）是**完全物理**的——记录"页号 X 的偏移 Y 写入这 N 字节"，而不是任何 SQL 语句或行级前后值。这种设计的根因：

1. PG 一开始就走"单机 + 物理流复制"路线（8.x 文件归档，9.0 流复制）
2. 物理 WAL 的回放是"再次执行同样的页修改"——和原始写入完全等价，零非确定性问题
3. 副本可以做到字节级一致，热备启动快

**关键含义**：PG 没有 SBR 这个概念，也没有 binlog_format 这个开关。

```
WAL 物理记录示例（粗略示意）:
LSN 0/1A2B3C4D:
  XLOG_HEAP_INSERT
    rel: 'public.orders' (oid=16384)
    block: 42
    offset: 12
    new tuple: <tuple binary bytes>
    
LSN 0/1A2B3C5E:
  XLOG_HEAP_UPDATE
    rel: 'public.orders'
    block: 42
    offset: 5
    old tuple: <byte offset of old tuple>
    new tuple: <new tuple binary bytes>
```

**逻辑层另起：Logical Decoding (9.4+)**

PG 9.4 (2014) 引入了 Logical Decoding API：把物理 WAL 在内存中解码成逻辑变更（INSERT/UPDATE/DELETE 行级事件），交给 output plugin 决定输出格式：

```sql
-- 创建复制槽
SELECT pg_create_logical_replication_slot('my_slot', 'pgoutput');

-- 用 wal2json 输出 JSON 格式的行级变更
SELECT pg_create_logical_replication_slot('my_slot', 'wal2json');
```

输出形如：

```json
{
  "change": [
    {
      "kind": "update",
      "schema": "public",
      "table": "orders",
      "columnnames": ["id", "status", "updated_at"],
      "columntypes": ["integer", "text", "timestamp"],
      "columnvalues": [1001, "shipped", "2024-01-02 11:30:00"],
      "oldkeys": {
        "keynames": ["id"],
        "keytypes": ["integer"],
        "keyvalues": [1001]
      }
    }
  ]
}
```

**对应 MySQL 的术语映射**：

| MySQL 术语 | PG 等价物 |
|-----------|---------|
| binlog_format = STATEMENT | 不存在 |
| binlog_format = ROW | Logical Decoding + 任意 output plugin |
| binlog_format = MIXED | 不存在 |
| binlog file | WAL segment（物理） |
| binlog position | LSN |
| GTID | LSN + slot.confirmed_flush_lsn |

**pglogical / 内置逻辑复制 (10+)**：是基于 Logical Decoding 之上的扩展或内核功能，提供 `CREATE PUBLICATION` / `CREATE SUBSCRIPTION` DDL，但底层仍是 WAL → 行级解码 → 副本回放，**不存在"statement 模式"**。

### Oracle：redo log 物理 + LogMiner 逻辑

Oracle 的 redo log 也是物理日志，记录数据块修改的字节级 redo 向量。逻辑解码靠三套独立机制：

**1. LogMiner（8i, 1999）**

最基础的逻辑解码工具，把 redo log 翻译成 SQL 视图 `V$LOGMNR_CONTENTS`：

```sql
-- 启动 LogMiner 会话
EXEC DBMS_LOGMNR.START_LOGMNR(
    STARTSCN => 12345678,
    ENDSCN => 12356789,
    OPTIONS => DBMS_LOGMNR.DICT_FROM_ONLINE_CATALOG
);

-- 读取行级变更
SELECT scn, timestamp, sql_redo, sql_undo, operation, table_name
FROM V$LOGMNR_CONTENTS
WHERE table_name = 'ORDERS';
-- sql_redo: UPDATE "SHOP"."ORDERS" SET "STATUS" = 'shipped' WHERE "ID" = 1001
-- sql_undo: UPDATE "SHOP"."ORDERS" SET "STATUS" = 'pending' WHERE "ID" = 1001
```

`sql_redo` 是合成出的"等价 SQL"，本质上是行级的（每行一条 UPDATE），但**呈现形式接近 statement**。这种"合成 SQL"在跨数据库迁移时尤其方便（直接 apply 到目标库）。

**2. Streams（9i, 2001, deprecated 12c）**

Oracle 9i 引入的逻辑复制框架，11g/11.2 是主推方向，12c 标记 deprecated。Streams 内部的事件单元是 LCR（Logical Change Record），行级，类似 MySQL ROWS_EVENT。

```sql
-- 9i+ 的 Streams 配置（已过时，仅作历史参考）
EXEC DBMS_STREAMS_ADM.ADD_TABLE_RULES(
    table_name => 'shop.orders',
    streams_type => 'capture',
    streams_name => 'orders_capture',
    queue_name => 'streams_queue',
    include_dml => TRUE,
    include_ddl => TRUE
);
```

**3. GoldenGate（Oracle 收购于 2009，产品 1999+）**

旗舰商业逻辑复制产品。Extract 进程读 redo（或 archive log），写入 trail file；Replicat 进程读 trail，应用到目标库。trail file 默认是行级二进制格式，可配置为 JSON / Avro / XML / 分隔文本。

```bash
# Extract 配置
EXTRACT ext1
USERIDALIAS oggadmin
EXTTRAIL ./dirdat/lt
TABLE shop.orders;
TABLE shop.order_items;

# Replicat 配置
REPLICAT rep1
USERIDALIAS oggadmin
ASSUMETARGETDEFS
DISCARDFILE ./dirrpt/rep1.dsc, PURGE
MAP shop.orders, TARGET shop.orders;
```

GoldenGate 支持类似 MIXED 的混合模式：DDL 通常以 statement 形式传输，DML 默认行级，但可配置 `LOGALLSUPCOLS` 或转换为 SQL 语句。

**4. XStream（11g+）**

Oracle 商业 SDK，让 C/Java 应用直接消费 LCR 流。Debezium Oracle Connector 早期就基于 XStream（需要 GoldenGate license），后来引入 LogMiner-only 模式以避免 license 限制。

### SQL Server：双轨制（事务复制 vs 物理副本）

SQL Server 是少数同时提供"逻辑复制"和"物理复制"两套独立机制的大型商业引擎：

**1. Physical：AlwaysOn Availability Groups + Log Shipping**

物理日志传输，副本是字节级镜像。基于 LSN（`(VLF:Offset:RecordID)`）：

```sql
-- 创建 AG
CREATE AVAILABILITY GROUP MyAG
WITH (DB_FAILOVER = ON, REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1)
FOR DATABASE TestDB
REPLICA ON 'PrimaryServer' WITH (...),
        'SecondaryServer' WITH (...);
```

**2. Logical：Transactional Replication（statement-like）**

事务复制内部把每一条 INSERT/UPDATE/DELETE 翻译成对应的存储过程调用 `sp_MSins_<table>` / `sp_MSupd_<table>` / `sp_MSdel_<table>`，由 Distributor 推送给订阅方执行：

```sql
-- 每个发布表自动生成的存储过程（简化）
CREATE PROCEDURE sp_MSupd_orders
    @c1 int, @c2 nvarchar(50), @c3 datetime,
    @pkc1 int
AS
BEGIN
    UPDATE [orders] SET status = @c2, updated_at = @c3
    WHERE id = @pkc1;
END
```

这种设计接近 statement-based（实际推送的是存储过程调用 + 参数），但保证了行级粒度。

**3. Logical：Merge Replication（行级 + 冲突解决）**

更接近 RBR + 双向同步，每行带版本元数据，副本可独立修改后再 sync 回主。

**4. CDC（cdc.\* 表）**

类似 RBR：从 transaction log 读出每行变更，写入辅助表 `cdc.dbo_orders_CT`，下游通过 SQL 读取：

```sql
-- 启用表级 CDC
EXEC sys.sp_cdc_enable_table
    @source_schema = 'dbo',
    @source_name = 'orders',
    @role_name = NULL,
    @supports_net_changes = 1;

-- 查询变更
SELECT __$start_lsn, __$operation, *
FROM cdc.fn_cdc_get_all_changes_dbo_orders(@from_lsn, @to_lsn, 'all');
-- __$operation: 1=DELETE, 2=INSERT, 3=UPDATE before, 4=UPDATE after
```

### CockroachDB：Raft + WAL 物理，CHANGEFEED 行级输出

CockroachDB 的内部日志是 Raft log（共识日志）+ Pebble WAL（存储引擎 WAL）：两层都是物理日志，记录键值对的修改。**没有 statement-based 概念**。

对外暴露变更靠 CHANGEFEED：

```sql
-- 创建 changefeed
CREATE CHANGEFEED FOR TABLE orders
INTO 'kafka://broker:9092'
WITH format = 'avro',
     envelope = 'enriched',
     diff,
     resolved = '10s';
```

输出格式（Avro / JSON）是行级的，类似 RBR 但不依赖任何 binlog 文件——直接从存储层 MVCC 流出。

### TiDB：从 binlog 到 TiCDC

TiDB 早期（2.x / 3.x）有一个名为 "TiDB binlog"（Drainer + Pump）的组件，模仿 MySQL binlog 协议输出行级事件。但因为 TiDB 内部是 Raft + RocksDB，并不存在真正的"binlog"，Drainer 实际是从 TiKV 的 raft log 提取变更，**4.0 (2020) 起标记为 deprecated**，由 TiCDC 替代。

TiCDC 直接订阅 TiKV 的行变更流（KV change feed），输出 Open Protocol（专用 JSON）或 Canal 协议或 Avro：

```bash
# 创建 TiCDC changefeed
tiup ctl:v6.5.0 cdc cli changefeed create \
    --pd=http://pd:2379 \
    --sink-uri="kafka://broker:9092/topic?protocol=canal-json" \
    --changefeed-id="orders-cdc"
```

**没有 statement 模式**——TiCDC 只输出行级。

### OceanBase：兼容 MySQL binlog 行格式

OceanBase 内部用 Paxos clog（共识日志）作为物理日志，但 OBCDC 工具可以把 clog 翻译成**与 MySQL ROWS_EVENT 兼容的格式**，让现有 MySQL binlog 消费者（Debezium、Maxwell、Canal）零改动接入：

```bash
# OBCDC 输出 MySQL binlog 格式
obcdc --output-format=mysql-binlog \
      --binlog-dir=/var/lib/obcdc/binlog \
      --tenant=mysql_tenant
```

这是 OceanBase 兼容 MySQL 协议（不仅 SQL 语法，连复制日志格式都兼容）的极致体现。

### YugabyteDB：xCluster + CDC Connector

YugabyteDB 也是 Raft + RocksDB 架构，对外提供两种逻辑复制：

- **xCluster**：异步集群间复制，基于 Raft log 的事务有序流
- **CDC Connector**：暴露类似 PG 协议的逻辑解码，下游可用 PG output plugin 风格消费

行级，无 statement 模式。

### ClickHouse：完全没有 binlog 等价物

ClickHouse 的 ReplicatedMergeTree 通过 ZooKeeper/Keeper 同步**片段（part）级别**的元数据，而不是行级或语句级日志：

```
ReplicatedMergeTree log（在 Keeper 里）:
  /clickhouse/tables/01/orders/log/log-0000000123:
    type: GET_PART
    source_replica: replica-1
    new_part_name: 20240101_1_5_2
```

副本看到这条 log，从 source_replica HTTP 拉取整个 part 文件夹。**这是 part-level 物理复制**，没有 STATEMENT 也没有 ROW 概念。

ClickHouse 21.4+ 引入的 `MaterializedPostgreSQL` / `MaterializedMySQL` 表引擎可以**消费**上游 PG/MySQL 的逻辑流，但 ClickHouse 自己**不产出**等价的复制日志。

## MySQL binlog 格式选择：实战对比

### 存储成本对比

| 操作 | STATEMENT 大小 | ROW 大小 | 倍数 |
|------|--------------|---------|------|
| `INSERT` 单行 (10 列) | ~150 字节（SQL 文本） | ~80 字节（二进制行） | ROW 略小 |
| `INSERT ... VALUES (...), (...), ...` 1000 行 | ~30 KB（一条语句） | ~80 KB（1000 个 row event） | ROW 大 ~3x |
| `UPDATE ... WHERE` 影响 1 行 | ~80 字节 | ~150 字节（before+after） | ROW 大 2x |
| `UPDATE ... WHERE` 影响 100 万行 | ~80 字节 | ~150 MB | ROW 大 200 万倍 |
| `DELETE FROM big_table` (清空) | ~30 字节 | ~ 100% 表大小 | ROW 灾难 |
| `OPTIMIZE TABLE` / `ALTER TABLE` | DDL 文本 | 同 STATEMENT（DDL 走 statement） | 一致 |
| `INSERT ... SELECT FROM big_table` | 一条 INSERT...SELECT | 全部新行的 row event | ROW 严重大 |

### 正确性对比

| 场景 | STATEMENT | ROW | MIXED |
|------|----------|-----|------|
| `UPDATE ... SET x = NOW()` | 主从可能漂移 | 完全一致 | 自动转 ROW |
| `INSERT ... VALUES (UUID())` | 主从生成不同 UUID | 主库的 UUID 写入 binlog | 自动转 ROW |
| 涉及自增列的并发 INSERT | 顺序可能不同 | 实际值复制 | 视情况切 ROW |
| `LOAD_FILE('/path/to/file')` | 副本可能没此文件 | 文件内容序列化到 binlog | 自动转 ROW |
| `INSERT ... ON DUPLICATE KEY UPDATE` | 多次执行结果一致需谓词确定 | 主库实际行为 | 视情况 |
| 用户定义函数（UDF） | 必须主从一致版本 | 函数结果序列化 | 自动转 ROW |
| `RAND()` / `RANDOM_BYTES()` | 不一致 | 一致 | 自动转 ROW |
| `UPDATE ... ORDER BY ... LIMIT N` | 顺序依赖存储引擎 | 一致 | 自动转 ROW |
| 触发器修改另一表 | 副本上重复触发 | 主库实际效果 | 视情况 |
| 自引用更新 | 中间状态可能不一致 | 完全一致 | 视情况 |

### 性能对比

```
写入 binlog 开销（每秒 OPS）：
  STATEMENT: ~50,000 ops/s（短 SQL 事务）
  ROW:       ~30,000 ops/s（每行额外编码 + extra_data）
  MIXED:     ~40,000 ops/s（视具体语句分布）

主从延迟典型值（中等负载）：
  STATEMENT: 0.1-1 秒（语句 apply 速度快）
  ROW:       1-5 秒（逐行 apply，主键 lookup 多）
  MIXED:     0.5-3 秒
  ROW + WSREP_SLAVE_THREADS=8: 0.2-1 秒（多线程并行 apply）

崩溃恢复时间：
  STATEMENT: 较长（需要重放 SQL 解析）
  ROW:       短（直接行写入）

网络流量（GTID + 持续 sync）：
  STATEMENT: 1 MB/s（典型 OLTP）
  ROW:       10 MB/s（同负载，DML-heavy）
```

## 崩溃安全与一致性

### MySQL：binlog vs InnoDB redo 双日志协调

MySQL 的崩溃安全难点在于：InnoDB redo log（物理）和 binlog（逻辑）是**两套独立日志**。事务提交需保证两者顺序一致，否则故障切换后副本进度可能错位。

**XA 风格的 binlog group commit（5.6+）**：

```
事务 T1 提交流程:
  1. T1 写 InnoDB redo (prepare 阶段)
  2. T1 写 binlog
  3. T1 写 InnoDB redo (commit 阶段)

崩溃后恢复:
  扫 binlog → 找到 commit 记录的 GTID 集合
  扫 InnoDB redo → 处于 prepare 但未 commit 的事务
  - 如果该事务的 GTID 已在 binlog → 提交
  - 否则 → 回滚

参数控制 fsync 频率:
  sync_binlog = 1            -- 每事务 fsync binlog
  innodb_flush_log_at_trx_commit = 1  -- 每事务 fsync redo
  -- 两者皆 1 才能保证 D（durability）
```

**ROW vs STATEMENT 在崩溃恢复中的差异**：

- ROW：行级前后值已固定，回放完全确定，崩溃后副本恢复无歧义
- STATEMENT：回放依赖运行时函数结果，若主库崩溃前某条语句写了 binlog 但副本回放时函数结果不同，主从可能在崩溃恢复后漂移
- MIXED：两种风险都可能存在（取决于事件类型分布）

### PostgreSQL：物理 WAL 的天然崩溃安全

PG 物理 WAL 没有上面的双日志协调问题——只有一份 WAL，所有修改（数据页 + commit 标记）都在同一份日志里。崩溃恢复就是 redo + undo 的标准流程。

逻辑解码（CDC 订阅）的崩溃安全靠 replication slot：副本崩溃后，主库**不会**清理还未 apply 的 WAL，副本恢复后继续从 `confirmed_flush_lsn` 续点。代价是磁盘膨胀风险——副本长期下线会让 WAL 无限增长。

### Oracle：redo + undo 双结构

Oracle redo 记录所有修改，undo 段记录"如何回滚"。两者协同实现 ACID：

- 崩溃后 redo forward 完成所有已提交事务
- undo backward 回滚未提交事务
- LogMiner 解码 redo 时也读 undo（生成 `sql_undo`）

Oracle 的复制日志（GoldenGate trail / Streams LCR）是从 redo 解码出的，崩溃后只要 redo 完整就能重新解码，行为类似 RBR。

## 跨版本复制兼容性

binlog 格式不光要现在能用，还要在跨版本升级、副本先升级再升级主、临时副本回归主等场景下保持兼容。

### MySQL：binlog 跨版本兼容矩阵

| 主库版本 | 副本版本 | STATEMENT 兼容 | ROW 兼容 | 备注 |
|---------|---------|--------------|---------|------|
| 5.5 → 5.6 | 是 | 是 | 是 | 5.6 完全向下兼容 |
| 5.6 → 5.7 | 是 | 是 | 是 | 但 5.7 引入新事件类型 |
| 5.7 → 8.0 | 通常是 | 部分（默认值变化） | 是 | 8.0 加密 binlog 不可被 5.7 副本读 |
| 8.0 → 8.4 | 是 | 是 | 是 | 8.4 移除部分老事件 |
| 跨大版本回退（如 5.7 → 5.6） | 否 | 否 | 风险高 | 不推荐 |

**关键陷阱**：

```
1. 8.0 默认 utf8mb4_0900_ai_ci collation，5.7 不识别
   → 主从 charset 必须一致
   
2. 8.0 的 JSON 部分更新（partial JSON update）事件
   → 5.7 副本无法解析，需 binlog_row_value_options=PARTIAL_JSON 关闭
   
3. GTID 格式：5.6 引入，跨版本通常 OK，但 8.0 的 mysql.gtid_executed 表结构有变
   
4. MIXED 模式下，自动切到 ROW 的判断列表在每个版本可能不同
   → 同一条语句在 5.7 走 STATEMENT，在 8.0 可能走 ROW
```

### MariaDB ↔ MySQL 跨厂商

```
MySQL → MariaDB:
  - binlog_format=ROW: 兼容（事件类型基本一致）
  - GTID 格式不同：必须用 binlog file/position 复制
  - 部分新 MySQL 事件 MariaDB 不识别

MariaDB → MySQL:
  - 反向更受限
  - Annotate Rows Event 必须关闭（MySQL 不识别）
  - MariaDB 11+ 的某些特性 MySQL 完全不兼容
```

### PostgreSQL：物理 WAL 不跨版本

物理流复制要求**主从 PG 主版本号严格一致**（13 不能复制到 14）。这是 PG 长期以来的硬约束。

**逻辑复制是跨版本升级的官方推荐方案**：

```
9.4 (Logical Decoding) → 17:
  以 PG 17 启动一个空实例
  CREATE SUBSCRIPTION 连到 9.4 主库
  initial copy + 实时同步
  切换流量
  关闭 9.4

→ 9.4 → 17 之间整整 8 个大版本，全靠逻辑复制实现零停机升级
```

跨版本时常见兼容性问题：

```
- 数据类型新增（PG 16 的 jsonb 函数变化）
- 大对象（lo_*）行为差异
- 序列对象的复制（10+ 才完整支持）
- Toast 数据类型在解码时的差异
```

## binlog_format 切换的运维风险

### 在线切换的安全规则

```sql
-- 1. 全局切换：影响所有新会话，已运行事务保持原格式
SET GLOBAL binlog_format = 'ROW';

-- 2. 会话切换：仅影响当前会话
SET SESSION binlog_format = 'ROW';

-- 3. 切换前检查正在执行的事务
SELECT * FROM information_schema.processlist WHERE State LIKE '%binlog%';

-- 4. 切换通常需要 SUPER 或 BINLOG_ADMIN 权限
GRANT BINLOG_ADMIN ON *.* TO 'admin'@'localhost';
```

**陷阱清单**：

```
1. 临时表语义差异
   STATEMENT: 临时表创建语句被复制，副本也建临时表
   ROW: 临时表的 DML 不写 binlog（5.7+），副本不知道临时表存在
   切换时正在用临时表的事务可能在副本上失败

2. 自增列分配
   STATEMENT: 副本独立按 auto_increment_increment 分配
   ROW: 副本直接使用主库分配的值
   切换瞬间可能出现冲突

3. CHANGE BINLOG_FORMAT 与 GTID 的交互
   GTID 模式下，部分 STATEMENT 事件被 GTID 强制规则拒绝
   切换前需确认 enforce_gtid_consistency 设置

4. 副本端的 replicate_*_db / replicate_*_table 过滤
   STATEMENT 事件按 default_db 过滤
   ROW 事件按表名过滤
   过滤行为可能因切换而变化
```

### 强制单一格式

生产环境通常用以下配置锁定 ROW：

```ini
[mysqld]
binlog_format = ROW
binlog_row_image = FULL          # 完整 before+after image
binlog_rows_query_log_events = ON  # 同 MariaDB 的 annotate
log_bin = /var/lib/mysql/mysql-bin
expire_logs_days = 7
sync_binlog = 1
gtid_mode = ON
enforce_gtid_consistency = ON
```

`binlog_row_image` 的三种取值：

| 取值 | before-image 包含 | after-image 包含 | 大小 | 用途 |
|------|----------------|----------------|------|------|
| `FULL`（默认） | 所有列 | 所有列 | 最大 | 跨版本兼容性最好 |
| `MINIMAL` | 仅主键 + 唯一键 | 仅修改的列 | 最小 | 节省空间，但下游消费者必须知道完整 schema |
| `NOBLOB` | 所有列除 BLOB/TEXT | 所有列除未修改的 BLOB/TEXT | 中等 | 大对象表常用 |

## binlog 格式与下游 CDC 工具的依赖

### Debezium MySQL Connector

```
要求: binlog_format = ROW
原因:
  - Debezium 必须知道每行的前后值
  - STATEMENT 模式下 Debezium 拒绝启动
  - MIXED 模式下，遇到 STATEMENT 事件 Debezium 会跳过或报错

可选配置:
  binlog_row_image = FULL  -- Debezium 强烈建议
  
原因:
  MINIMAL 模式下，Debezium 输出的事件会缺失未修改列的值
  下游消费者（Kafka Stream / Flink）做 join 会失败
```

### Maxwell

```
要求: binlog_format = ROW
特点: 输出 JSON 而非 Avro
解析所有 ROW 事件 + 部分 DDL 事件
```

### Canal

```
要求: binlog_format = ROW
特点: 阿里开源，针对 MySQL 设计
输出协议: Canal 自定义 protobuf
```

### TiCDC

```
要求: TiKV 的内部 KV change feed（无 binlog 概念）
输出格式: Open Protocol / Canal-JSON / Avro
对外协议可与 Debezium / Maxwell 兼容
```

### OBCDC

```
要求: OceanBase clog（无 binlog 概念，但输出 MySQL binlog 兼容格式）
输出: ROW 格式 binlog
让 Debezium MySQL Connector 可直接消费
```

## STATEMENT 模式的"现代复活"：审计与查询日志

虽然 RBR 是默认，但 statement 形式的"日志"在审计、查询日志、慢查询日志、SQL 重放等场景下仍然不可替代：

```
审计日志: 必须看到原始 SQL 文本（who did what）
慢查询日志: SQL 文本 + 执行计划
查询日志（general log）: 所有 SQL 文本
SQL 重放（replay tool）: 把生产 SQL 回放到测试环境

→ 这些都需要 STATEMENT 形式
→ MariaDB 的 Annotate Rows Event 是 ROW + STATEMENT 同时存在的折衷
→ MySQL 8.0 的 binlog_rows_query_log_events 选项也类似
```

启用 MySQL 8.0 的 row + query log：

```ini
[mysqld]
binlog_format = ROW
binlog_rows_query_log_events = ON
```

启用后，binlog 在 ROW 事件之前会插入 `Rows_query` 事件，记录原始 SQL 文本：

```
# at 1234
#240101 10:00:00 server id 1  end_log_pos 1300  Rows_query
# UPDATE orders SET status = 'shipped' WHERE created_at < NOW() - INTERVAL 1 DAY

# at 1300
#240101 10:00:00 server id 1  end_log_pos 1400  Table_map: shop.orders
# at 1400
#240101 10:00:00 server id 1  end_log_pos 1500  Update_rows: ...
# at 1500
#240101 10:00:00 server id 1  end_log_pos 1600  Update_rows: ...
```

## 设计争议

### 为什么 PostgreSQL 不做 statement-based 复制？

PG 团队从 8.x 时代就反复讨论这个问题，结论一直是"物理 WAL + 9.4 之后的逻辑解码足够"。理由：

1. **物理 WAL 的回放是确定性的**：避免了所有非确定性函数问题
2. **逻辑解码框架更灵活**：output plugin 可以输出 SQL 形式（test_decoding 插件就是 SQL 文本输出）
3. **维护两套日志的成本高**：MySQL 的 binlog + redo 双日志一直是 InnoDB 的复杂度来源
4. **CDC 生态用 wal2json / pgoutput 已经够用**

### MIXED 是不是失败的设计？

社区有声音认为 MIXED 是个"半吊子"方案：

- MIXED 的判断逻辑是 MySQL 内核维护的"黑名单"，每版都可能改变
- 同一条 SQL 在不同 MySQL 版本下可能选不同格式
- Debezium 等工具不支持 MIXED（必须 ROW）
- 5.7.7 默认改 ROW 后，MIXED 实际使用率很低

支持者认为：

- MIXED 在迁移期（从 STATEMENT 老应用切到 ROW）很有用
- 对小事务多 / 大批量更新少的负载，MIXED 的存储成本接近 STATEMENT
- 旧版本兼容性需求

### Oracle 的"统一日志"路线

Oracle 的 redo log 同时承担崩溃恢复 + 复制 + 解码 + PITR 四重角色，单日志多用是它的设计哲学。代价是 LogMiner 解码 redo 时性能开销大，且 redo 文件结构对所有新特性都形成约束。

MySQL 的双日志路线（redo + binlog）虽然冗余，但解耦了"存储引擎正确性"和"复制协议"，让 InnoDB / MyISAM / Memory 等引擎可以独立演化。

### CockroachDB / TiDB 的"无 binlog"路线

NewSQL 引擎几乎全部走"内部 Raft 物理日志 + 外部行级 CDC"路线：

```
优点:
  - Raft log 是分布式共识的天然产物
  - CDC 完全独立于存储层（输出 Kafka 等）
  - 没有"格式选择"的运维负担

缺点:
  - 跨版本兼容性靠 CDC 协议层保证
  - Raft log 不能像 binlog 一样被 mysqlbinlog 这种通用工具直接读
  - 调试时无法直接 grep 日志
```

## 核心发现

经过 45+ 引擎的横向对比，可以提炼出以下要点：

1. **STATEMENT / ROW / MIXED 是 MySQL 系特有概念**：MariaDB 完整继承，OceanBase 兼容输出，但其他主流引擎都没有显式的"格式模式"开关。

2. **PostgreSQL、Oracle、SQL Server 的 redo/WAL/transaction log 都是物理日志**：逻辑层独立实现，输出格式由插件 / 商业产品决定。

3. **NewSQL 一律行级 CDC**：CockroachDB / TiDB / OceanBase / YugabyteDB 都没有 statement 模式，输出统一是行级 JSON / Avro / 自定义协议。

4. **OLAP 列存（ClickHouse / Snowflake / BigQuery）几乎没有等价物**：要么是 part-level 物理复制（CH），要么完全托管（Snowflake、BigQuery）。

5. **MySQL 5.1 (2008) 的 ROW + MIXED 引入是分水岭**：在此之前，binlog 等同于 STATEMENT；之后才有真正的格式选择。

6. **5.7.7 (2015) 默认值切换到 ROW 是官方对 SBR 的"判决"**：实际生产中 MIXED 罕见，多数 DBA 强制 ROW。

7. **跨版本升级的"逻辑复制"路线在 PG 上更彻底**：PG 物理流复制要求大版本严格一致，逻辑复制是 8 个大版本间的桥梁；MySQL 物理升级（in-place）和逻辑升级（dump/restore 或 binlog 同步）并存。

8. **Annotate Rows Event / binlog_rows_query_log_events 是 ROW + STATEMENT 折衷**：让 ROW 模式也能保留原始 SQL 文本，方便审计、慢查询排查、SQL 重放。

9. **Debezium 等下游 CDC 工具一律要求 ROW**：实际形成了"业界标准"，MIXED 与 STATEMENT 在 CDC 场景被淘汰。

10. **OceanBase 的 OBCDC 兼容 MySQL binlog 格式是兼容路线的极致**：连复制日志格式都模拟，下游消费者零改动接入。

11. **Oracle GoldenGate 的 trail 格式 + format 选项接近 PG 的 output plugin 思路**：但属于商业生态，不开源。

12. **InfluxDB / MongoDB / Cassandra / Spanner 各有自己的"行级流"机制**：oplog（MongoDB）、commitlog CDC（Cassandra）、Change Streams（Spanner）——名字不同，本质都是 RBR 的变体。

13. **格式选择的根本权衡是回放正确性 vs 存储成本**：现代默认偏正确性（ROW）。CPU、网络、存储都比上世纪 90 年代便宜了几个数量级，使得 ROW 的成本不再敏感。

14. **崩溃安全在双日志（MySQL）和单日志（PG）下机制不同**：MySQL 靠 XA 风格的 group commit；PG 靠物理 WAL 自身的 redo + commit 一致性。

15. **MIXED 的"自动判断"逻辑跨版本不稳定**：在大型多版本部署中，跨主从版本的同一条 SQL 可能走不同格式，是隐性运维风险。

## 引擎选型建议

| 场景 | 推荐 | 理由 |
|------|------|------|
| 新建 MySQL/MariaDB 实例 | `binlog_format = ROW` | 默认就是 ROW（5.7.7+），CDC 友好 |
| 老 MySQL 5.5 / 5.6 升级 | 先全局 ROW，逐表测试 | 避免 SBR 隐患 |
| 接入 Debezium / Maxwell / Canal | 必须 ROW + binlog_row_image=FULL | 工具硬性要求 |
| 跨大版本升级 PostgreSQL | 逻辑复制 (10+) | 物理流复制不跨版本 |
| 异构数据库实时同步 | Debezium + Kafka Connect | 业界事实标准 |
| 同一引擎内副本 + 故障切换 | GTID + ROW + sync_binlog=1 | 一致性最强 |
| 审计 / 慢查询 / SQL 重放 | binlog_rows_query_log_events / Annotate Rows | 保留 SQL 文本 |
| 多主双向复制 | MySQL Group Replication / MariaDB Galera | 必须 ROW |
| 跨地域异步复制 | MySQL 异步 + GTID + ROW + 半同步 | 保护 RPO |
| OLAP 实时入仓 | TiCDC / OBCDC / Debezium → Kafka → ClickHouse | 流式管道 |
| 极致存储成本 | binlog_row_image=MINIMAL（确认下游可用） | 减少 binlog 大小 |
| BLOB/TEXT 重表 | binlog_row_image=NOBLOB | 不传输大对象 |

## 对引擎开发者的实现建议

### 1. 行级 binlog 事件结构

```
ROW_EVENT 总体结构:
  Common Header (19 字节，server_id / event_type / timestamp / log_pos)
  Post Header (event_type 相关)
  Payload:
    - TABLE_MAP_EVENT (一次会话内每张表只发一次)
    - 后续的 WRITE_ROWS / UPDATE_ROWS / DELETE_ROWS 都引用这个 table_id

TABLE_MAP_EVENT:
  table_id (varint)
  flags (uint16)
  schema_name (length-prefixed string)
  table_name (length-prefixed string)
  num_columns (varint)
  column_types (num_columns 字节)
  column_metadata (变长，根据 column_types)
  null_bitmap (ceil(num_columns/8) 字节)

UPDATE_ROWS_EVENT 单行:
  null_bitmap_before (ceil(num_columns/8) 字节)
  values_before (每列按 column_metadata 编码)
  null_bitmap_after (ceil(num_columns/8) 字节)
  values_after (每列按 column_metadata 编码)
```

### 2. 实现 ROW 模式的关键步骤

```
1. 在事务执行过程中拦截每一行变更
   - 钩子点: 存储引擎层的 row insert / update / delete 回调
   - InnoDB 用 trx_t 内的 binlog cache，事务提交时一次性 fsync

2. 生成 TABLE_MAP_EVENT
   - 第一次访问表时发出，缓存 table_id 映射
   - schema 变更时强制重发

3. 编码 before-image 和 after-image
   - INSERT: 仅 after-image
   - UPDATE: before + after
   - DELETE: 仅 before-image
   
4. 列编码细节
   - 整数: little-endian
   - 字符串: length-prefixed UTF-8
   - 时间: 按 type 不同编码（DATETIME / TIMESTAMP / DATE 各异）
   - JSON: MySQL 5.7+ 用专有二进制格式
   - 几何: WKB
```

### 3. 实现 STATEMENT 模式的关键步骤

```
1. 在 SQL 解析后、执行前拦截
   - 钩子点: SQL 优化器之后、执行器之前
   - 注意: 必须在 prepared statement 参数已绑定后

2. 处理非确定性函数
   - 选项 A: 拒绝执行（保守）
   - 选项 B: 警告但允许（MySQL 默认）
   - 选项 C: 自动转 ROW（MIXED 模式）

3. 处理多语句事务
   - 每条 SQL 写一个 Query event
   - 事务边界: BEGIN + Xid event 标记 commit

4. 字符集与时区处理
   - 必须在 binlog 头部记录 character_set_client / character_set_connection
   - SET TIMESTAMP 伪命令尝试稳定时间函数
```

### 4. 实现 MIXED 模式的关键步骤

```
1. 维护"unsafe statement"清单
   - 函数级别: NOW(), UUID(), USER(), VERSION(), ...
   - 操作级别: LOAD_FILE, INSERT DELAYED + 触发器, ...
   - 表级别: 系统表写入, 临时表特殊操作, ...

2. 每条 SQL 进入 binlog 写入流程时:
   if (语句是 unsafe):
       临时切换到 ROW 写入
   else:
       使用当前默认（默认是 STATEMENT）

3. 注意: MIXED 内部其实是"以 STATEMENT 为默认，必要时切到 ROW"
   - 不是"自动选最好"
   - 是"在保留 STATEMENT 优点的前提下规避错误"
```

### 5. 双日志一致性（XA 风格 group commit）

```
事务 T 提交:
  阶段 1: T 写 InnoDB redo log (prepare 标记)
          fsync redo log
  阶段 2: T 写 binlog
          fsync binlog
  阶段 3: T 写 InnoDB redo log (commit 标记)
          fsync redo log（可推迟）

崩溃恢复:
  扫 binlog 提取所有 commit 的 GTID 集合 S
  扫 InnoDB redo:
    for each prepared transaction T:
      if T.gtid in S:
        commit T
      else:
        rollback T

并发优化（group commit）:
  多个事务在阶段 2 排队，一次 fsync 写多个事务的 binlog
  显著降低 fsync 次数（O(N) → O(N/K)）
```

### 6. 跨版本兼容的事件设计

```
基本原则:
  - Common Header 字段编号永不复用
  - 新事件类型分配新的 event_type code
  - 旧版本副本遇到未知 event_type 应能跳过（不崩溃）
  - 使用 length-prefixed 编码，避免老解析器越界读

破坏兼容性的常见错误:
  - 修改已有事件的字段顺序
  - 删除字段而不更新版本号
  - 在 Common Header 之外加全局 flag
  - 强制要求新字段（应保留向后默认值）

MySQL 8.0 引入 binlog_transaction_compression（zstd）:
  压缩单个 transaction payload
  Common Header 标记是否压缩
  老副本（5.7）遇到压缩事件直接报错
  → 主从需同时升级或关闭压缩
```

### 7. CDC connector 设计

```
作为 binlog 消费者（不是产生者）:
  - 必须支持 RBR ROW 事件
  - 维护自己的 schema 缓存（从 TABLE_MAP_EVENT 抽取）
  - DDL 事件特殊处理（多数走 STATEMENT，需要解析）
  - 断点续传基于 GTID（5.6+）或 (filename, position)（旧版）

错误处理:
  - 遇到不识别的事件: 跳过 + 警告 vs 失败重启
  - schema 漂移: 重新拉取 information_schema 校验
  - 事务边界: BEGIN + Xid 之间的事件原子消费
```

### 8. 性能调优要点

```
binlog 写入瓶颈:
  - sync_binlog=1 + group commit + 高频小事务 → IOPS 瓶颈
  - 解决: 增大 group commit 等待时间（binlog_group_commit_sync_delay）
  
  - ROW 模式大事务（百万行 UPDATE）→ binlog 瞬间膨胀
  - 解决: 拆分为小事务 + 应用层批处理
  
  - binlog_row_image=FULL 在宽表上的开销
  - 解决: MINIMAL 或 NOBLOB（确认下游可用）

副本回放瓶颈:
  - 单线程 SQL 线程 → 主从延迟
  - 解决: parallel replication（5.7+ logical clock + 8.0 WRITESET）

跨地域复制瓶颈:
  - WAN 带宽 → binlog 流量
  - 解决: binlog_transaction_compression（8.0+）+ 半同步（限制 RTT 影响）
```

### 9. 测试要点

```
binlog 实现的测试矩阵:
  - 每种事件类型的编解码往返
  - 多列 / NULL / NOT NULL / 默认值组合
  - 字符集 (UTF-8 / GBK / latin1) 跨主从
  - 时区切换（mysql.time_zone_name 表）
  - 大对象（BLOB / TEXT > 1MB）
  - JSON 字段（MySQL 5.7+ 专有二进制）
  - 几何类型（POINT / POLYGON）
  - 加密 binlog（8.0+）
  - 压缩 binlog（8.0+）
  - 跨版本回放（5.7 主 → 8.0 副）
  - 跨厂商回放（MySQL 主 → MariaDB 副）
  - 崩溃注入（事务在不同阶段强制 panic）
  - 大事务（百万行 UPDATE）
  - 高并发（1000+ TPS）
  - DDL 与 DML 混合
  - 临时表 / 派生表 / CTE
  - 触发器 / 存储过程 / 函数
```

## 参考资料

- MySQL 5.1 Reference Manual: [binlog_format](https://dev.mysql.com/doc/refman/5.1/en/replication-options-binary-log.html)
- MySQL 5.7 Reference Manual: [Binary Logging Formats](https://dev.mysql.com/doc/refman/5.7/en/binary-log-formats.html)
- MySQL 5.7.7 Release Notes: [Default binlog_format Changed to ROW](https://dev.mysql.com/doc/relnotes/mysql/5.7/en/news-5-7-7.html)
- MySQL 8.0 Reference Manual: [Replication and Binary Logging](https://dev.mysql.com/doc/refman/8.0/en/replication.html)
- MariaDB Knowledge Base: [Binary Log Formats](https://mariadb.com/kb/en/binary-log-formats/)
- MariaDB Knowledge Base: [Annotate Rows Event](https://mariadb.com/kb/en/annotate_rows_log_event/)
- PostgreSQL Documentation: [Logical Decoding](https://www.postgresql.org/docs/current/logicaldecoding.html)
- PostgreSQL Documentation: [Logical Replication](https://www.postgresql.org/docs/current/logical-replication.html)
- Oracle Database Reference: [LogMiner Utility](https://docs.oracle.com/en/database/oracle/oracle-database/19/sutil/oracle-logminer-utility.html)
- Oracle GoldenGate Documentation: [Trail Files](https://docs.oracle.com/en/middleware/goldengate/core/index.html)
- SQL Server Replication: [Transactional Replication](https://learn.microsoft.com/en-us/sql/relational-databases/replication/transactional/transactional-replication)
- SQL Server: [Change Data Capture](https://learn.microsoft.com/en-us/sql/relational-databases/track-changes/about-change-data-capture-sql-server)
- TiCDC Documentation: [TiCDC Open Protocol](https://docs.pingcap.com/tidb/stable/ticdc-overview)
- CockroachDB: [CHANGEFEED](https://www.cockroachlabs.com/docs/stable/create-changefeed.html)
- OceanBase OBCDC: [OBCDC Documentation](https://en.oceanbase.com/docs/community-observer-en-10000000000829647)
- Debezium Documentation: [MySQL Connector Configuration](https://debezium.io/documentation/reference/stable/connectors/mysql.html)
- Maxwell's Daemon: [Configuration](https://maxwells-daemon.io/config/)
- Canal: [QuickStart](https://github.com/alibaba/canal/wiki/QuickStart)
- Jay Kreps, "The Log: What every software engineer should know about real-time data's unifying abstraction" (2013)
