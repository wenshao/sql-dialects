# 可插拔存储引擎 (Pluggable Storage Engines)

一行 SQL 不变，底层从 B+ 树换成 LSM 树、从行存换成列存、从磁盘换成内存——这就是可插拔存储引擎赋予数据库的"换芯"能力。它是 MySQL 在 2000 年代崛起的秘密武器，也是 ClickHouse、TiDB、SingleStore 等现代数据库架构的核心。

## 没有 SQL 标准

可插拔存储引擎是**架构选择**而非 SQL 语法特性。SQL 标准（ISO/IEC 9075）只规范查询语言与逻辑数据模型，从不定义底层存储如何组织。因此本主题没有标准文本可引用，本文从架构与生态视角横向对比 45+ 数据库的存储引擎设计。

不过，部分引擎在 DDL 中暴露了存储引擎选择的语法扩展，例如：

```sql
-- MySQL/MariaDB
CREATE TABLE t (id INT) ENGINE=InnoDB;
CREATE TABLE t (id INT) ENGINE=MyRocks;
CREATE TABLE t (id INT) ENGINE=ColumnStore;

-- ClickHouse
CREATE TABLE t (id Int64) ENGINE = MergeTree() ORDER BY id;
CREATE TABLE t (id Int64) ENGINE = Log;
CREATE TABLE t (id Int64) ENGINE = Memory;

-- PostgreSQL 12+ (Table Access Method)
CREATE TABLE t (id INT) USING heap;
CREATE TABLE t (id INT) USING orioledb;

-- SQL Server
CREATE TABLE t (id INT) WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);

-- Greenplum
CREATE TABLE t (id INT) WITH (appendonly=true, orientation=column);
```

## 历史背景：MySQL 的著名架构

可插拔存储引擎的概念在 1990 年代末由 MySQL 推广至主流。MySQL 在 3.23（2000 年）已支持 MyISAM、InnoDB、HEAP（Memory）、BDB（Berkeley DB）等多个存储引擎共存，但当时是"半插拔"：每加一个引擎都要修改 MySQL 服务端源码。

真正的**可插拔存储引擎 API（pluggable storage engine API）** 于 MySQL 5.1（2008 年 GA）正式发布，第三方可以编写共享库 `.so` 形式的存储引擎，在运行时通过 `INSTALL PLUGIN` 加载。这一架构催生了：

- **InnoDB**（Innobase Oy → Oracle 收购，后成 MySQL 5.5.5+ 默认引擎）
- **TokuDB**（Tokutek，分形树）
- **MyRocks**（Facebook 2016，基于 RocksDB 的 LSM）
- **MyISAM**（古老的非事务引擎）
- **NDB Cluster**（分布式内存引擎）
- **Aria**（MariaDB 的 MyISAM 替代品）
- **Spider**（分库分表代理引擎）

跟随 MySQL 思路的还有 **MariaDB**（继承 + 扩展），**ClickHouse**（独立设计的"表引擎"概念），**PostgreSQL**（12 起的 Table Access Method API）。

而 **Oracle**、**SQL Server**、**DB2** 等传统商业数据库则采用另一条路：**单一存储引擎 + 多种内部存储格式**——同一引擎内同时支持 heap、clustered index、columnstore、in-memory 等多种物理布局，但不允许第三方插入新引擎。

## 支持矩阵（45+ 数据库）

### 1. 是否支持可插拔/多存储引擎架构

| 引擎 | 可插拔/多引擎 | 默认引擎 | 备注 |
|------|--------------|----------|------|
| MySQL | 是（API） | InnoDB | 5.1+ pluggable API；5.5.5+ InnoDB 默认 |
| MariaDB | 是（API） | InnoDB | 继承 MySQL，扩展 Aria/MyRocks/ColumnStore/Spider 等 |
| PostgreSQL | 是（TAM API） | heap | 12+ Table Access Method；heap 仍是唯一生产引擎 |
| SQLite | 否 | B-tree | 单一 B-tree，但有 VFS 层可插拔 |
| Oracle | 否（多格式） | row heap | 单引擎，内部支持 In-Memory Column Store |
| SQL Server | 否（多格式） | clustered B-tree | 单引擎，内部支持 columnstore + Hekaton |
| DB2 | 否（多格式） | row | 单引擎，内部支持 BLU 列存 |
| Snowflake | 否 | micro-partition 列存 | 全托管单一存储格式 |
| BigQuery | 否 | Capacitor 列存 | 单一存储格式 |
| Redshift | 否（多格式） | 列存 | 列存为主，AQUA 缓存层 |
| DuckDB | 否 | 列存（向量化） | 单引擎，自有 DuckDB 文件格式 |
| ClickHouse | 是（表引擎） | MergeTree | 40+ 表引擎，最丰富的引擎生态 |
| Trino | 是（Connector） | 无（计算引擎） | 50+ 数据源 connector，本身不存储 |
| Presto | 是（Connector） | 无（计算引擎） | 同 Trino |
| Spark SQL | 是（DataSource） | 无（计算引擎） | DataSource v1/v2 API |
| Hive | 是（StorageHandler） | ORC/Parquet | StorageHandler API + SerDe 框架 |
| Flink SQL | 是（Connector） | 无（计算引擎） | DynamicTableFactory API |
| Databricks | 否（多格式） | Delta Lake | Delta + Parquet + 缓存层 |
| Teradata | 否 | row（PPI 分区） | 单一存储格式，可加列存表 |
| Greenplum | 是（多格式） | heap | heap + Append-Optimized + Column-Oriented + 外部表 |
| CockroachDB | 否 | Pebble (LSM) | 单一 LSM 引擎（早期 RocksDB） |
| TiDB | 是（双引擎） | TiKV | TiKV 行存（RocksDB）+ TiFlash 列存 |
| OceanBase | 否（LSM） | LSM rowstore | 单一 LSM-based 行存，无可插拔 |
| YugabyteDB | 否 | DocDB (LSM) | 单一 DocDB（基于 RocksDB） |
| SingleStore | 是（双引擎） | columnstore（7.0+） | rowstore（in-memory）+ columnstore（disk） |
| Vertica | 否 | 列存 WOS+ROS | 单一列存，WOS（写优化）→ ROS（读优化） |
| Impala | 是（StorageHandler） | Parquet/Kudu | 借用 Hive Metastore + 多种存储后端 |
| StarRocks | 否（多格式） | 列存 | 单一列存，支持 PrimaryKey/Aggregate/Duplicate 模型 |
| Doris | 否（多格式） | 列存 | 同 StarRocks |
| MonetDB | 否 | 列存 | 单一列存，BAT (Binary Association Table) 模型 |
| CrateDB | 否 | Lucene | 单一基于 Lucene 的存储 |
| TimescaleDB | 是（继承 PG） | heap + chunks | PG 扩展，heap chunks + 压缩 chunks |
| QuestDB | 否 | 列存（时间分区） | 单一列存 |
| Exasol | 否 | 列存 | 单一列存内存数据库 |
| SAP HANA | 否（多格式） | 内存列存 | 单引擎，行存 + 列存 + 文档/图扩展 |
| Informix | 是（DataBlade） | row | 古老的 DataBlade API（虚表/虚索引接口） |
| Firebird | 否 | row | 单一 Firebird 存储 |
| H2 | 是（双引擎） | MVStore（1.4+） | PageStore（旧）+ MVStore（新） |
| HSQLDB | 否（多模式） | 内存/缓存 | MEMORY/CACHED/TEXT 表类型 |
| Derby | 否 | row + B-tree | 单一存储 |
| Amazon Athena | 是（继承 Trino） | 无 | Trino 的 connector |
| Azure Synapse | 否（多格式） | 列存（CCI） | clustered columnstore index 默认 |
| Google Spanner | 否 | 行存（Colossus） | 单一存储 |
| Materialize | 否 | 内存物化视图 | 流式数据库，单一存储 |
| RisingWave | 否 | LSM (Hummock) | 单一对象存储 LSM |
| InfluxDB | 否（IOx 重写） | TSM/IOx | 3.0 用 Apache Arrow + Parquet |
| DatabendDB | 否 | 列存（Parquet on S3） | 单一对象存储 |
| Yellowbrick | 否 | 列存 | 单一列存 |
| Firebolt | 否 | F3 列存 | 单一列存 |

> 统计：约 14 个引擎提供真正的"可插拔/多存储引擎"机制（API 形式），其余 30+ 引擎要么单引擎、要么单引擎内部多格式。

### 2. 行存 / 列存 / 混合 引擎覆盖

| 引擎 | 行存引擎 | 列存引擎 | 混合行+列 | LSM 引擎 | 内存引擎 |
|------|---------|---------|----------|---------|---------|
| MySQL | InnoDB / MyISAM / NDB | -- | -- | MyRocks | MEMORY (HEAP) |
| MariaDB | InnoDB / Aria | ColumnStore | -- | MyRocks | MEMORY |
| PostgreSQL | heap | (zedstore 实验) | -- | OrioleDB（实验） | -- |
| SQLite | B-tree | -- | -- | -- | `:memory:` |
| Oracle | row heap | In-Memory Column Store (12c+) | 是（双格式） | -- | In-Memory Column Store |
| SQL Server | heap / clustered | columnstore (2012+) | 是 | -- | In-Memory OLTP (Hekaton, 2014+) |
| DB2 | row | BLU columnar (10.5+) | 是 | -- | Timestack (时序) |
| Snowflake | -- | micro-partition | -- | -- | -- |
| BigQuery | -- | Capacitor | -- | -- | -- |
| Redshift | -- | RMS 列存 | -- | -- | -- |
| DuckDB | -- | 列存 | -- | -- | in-memory mode |
| ClickHouse | Log / TinyLog | MergeTree 全家族 | -- | MergeTree（带版本） | Memory |
| Trino | (connector) | (connector) | -- | -- | -- |
| Spark SQL | (DataSource) | Parquet/ORC | Delta/Iceberg/Hudi | -- | cache table |
| Hive | TextFile | ORC / Parquet | -- | Kudu | -- |
| Databricks | -- | Delta (Parquet) | Delta | -- | Photon cache |
| Teradata | row PPI | columnar table | 是 | -- | In-Memory Optimization |
| Greenplum | heap | AOCO（Append-Only Column） | -- | -- | -- |
| CockroachDB | -- | -- | -- | Pebble | -- |
| TiDB | TiKV | TiFlash | 是 | TiKV | -- |
| OceanBase | LSM rowstore | -- | -- | 是 | MemTable |
| YugabyteDB | -- | -- | -- | DocDB (RocksDB) | -- |
| SingleStore | rowstore (内存) | columnstore (磁盘) | 是 | -- | rowstore |
| Vertica | -- | ROS / WOS | -- | -- | WOS (内存) |
| Impala | Kudu (混合) | Parquet | Kudu | Kudu | -- |
| StarRocks | -- | 列存 | -- | -- | -- |
| Doris | -- | 列存 | -- | -- | -- |
| MonetDB | -- | BAT 列存 | -- | -- | 全列内存 |
| CrateDB | -- | Lucene 列 | -- | -- | -- |
| TimescaleDB | heap chunks | 压缩 chunks（伪列存） | 是 | -- | -- |
| QuestDB | -- | 时序列存 | -- | -- | mmap |
| Exasol | -- | 列存 | -- | -- | 全内存 |
| SAP HANA | row store | column store | 是 | -- | 是（全引擎） |
| Informix | row | -- | -- | -- | -- |
| Firebird | row | -- | -- | -- | -- |
| H2 | MVStore | -- | -- | -- | MEMORY 表 |
| HSQLDB | row | -- | -- | -- | MEMORY 表 |
| Derby | row | -- | -- | -- | -- |
| Azure Synapse | heap | CCI | 是 | -- | -- |
| Google Spanner | row | -- | -- | -- | -- |
| Materialize | -- | -- | -- | -- | 是（差异数据流） |
| RisingWave | -- | -- | -- | Hummock | -- |
| InfluxDB | -- | TSM/Parquet | -- | TSM (LSM-like) | -- |
| DatabendDB | -- | Parquet | -- | -- | -- |
| Yellowbrick | -- | 列存 | -- | -- | -- |
| Firebolt | -- | F3 列存 | -- | -- | -- |

### 3. MVCC 模型与 ACID 保证

| 引擎 | MVCC 模型 | ACID 保证 | 隔离级别 |
|------|----------|----------|---------|
| MySQL InnoDB | undo log + read view | 完全 ACID | RR（默认）/RC/RU/Serializable |
| MySQL MyISAM | 无 MVCC（表锁） | 无事务 | -- |
| MySQL Memory | 无 MVCC | 无事务 | -- |
| MySQL MyRocks | snapshot（RocksDB） | 完全 ACID | RR/RC |
| MySQL NDB | 行锁 + 2PC | ACID | RC |
| MariaDB Aria | crash-safe，无 MVCC | 部分（崩溃恢复） | -- |
| MariaDB ColumnStore | 基于版本的 MVCC | ACID（批量） | snapshot |
| PostgreSQL heap | 多版本元组（in-table） | 完全 ACID | RC（默认）/RR/Serializable |
| OrioleDB | undo log（PG 风格优化） | 完全 ACID | 同 PG |
| SQLite | rollback journal / WAL | 完全 ACID | Serializable |
| Oracle | undo segment | 完全 ACID | RC（默认）/Serializable |
| SQL Server clustered | 锁 + 行版本 (2005+) | 完全 ACID | RC/Snapshot/Serializable |
| SQL Server Hekaton | 乐观 MVCC（无锁） | 完全 ACID | Snapshot/RR/Serializable |
| DB2 row | currently committed | 完全 ACID | CS（默认）/RR/RS/UR |
| DB2 BLU | 同上 | 完全 ACID | 同上 |
| ClickHouse MergeTree | part 不可变 + 版本列 | 弱（最终一致） | 无标准事务 |
| Snowflake | 时间旅行（micro-part 不可变） | 完全 ACID | RC |
| BigQuery | snapshot 隔离 | ACID（单语句） | snapshot |
| Redshift | snapshot 隔离 | 完全 ACID | Serializable |
| DuckDB | MVCC（in-memory undo） | 完全 ACID | snapshot |
| TiDB / TiKV | Percolator MVCC | 完全 ACID | snapshot/RR |
| OceanBase | LSM + multi-version | 完全 ACID | RC/RR/Serializable |
| CockroachDB | HLC + MVCC | 完全 ACID | Serializable |
| YugabyteDB | HLC + MVCC | 完全 ACID | Snapshot/Serializable |
| SingleStore rowstore | 锁 + 版本（内存） | 完全 ACID | RC |
| SingleStore columnstore | segment + 删除位图 | ACID（批） | RC |
| Vertica | epoch-based | ACID | snapshot |
| Greenplum heap | 同 PG | 完全 ACID | RC |
| Greenplum AOCO | append-only，无更新 | ACID（单事务） | snapshot |
| SAP HANA | 行存乐观 / 列存乐观 | 完全 ACID | RC/Serializable |

> 关键洞察：**ACID 不是引擎的属性，是引擎的设计选择**——同一数据库的不同引擎，事务能力可能从 0 到 Serializable 跨越完整谱系。例如 MySQL InnoDB 是完全 ACID，而 MyISAM 完全没有事务。

## MySQL 可插拔存储引擎深度解读

MySQL 是"可插拔存储引擎"概念的经典定义者。它把数据库抽象成两层：

```
+-------------------------------------------+
|       SQL Layer (parser, optimizer,       |
|       executor, connection, replication)  |
+-------------------------------------------+
|       Storage Engine API (handler class)  |
+-------------------------------------------+
| InnoDB | MyISAM | MEMORY | NDB | Archive  |
| CSV    | Federated | MyRocks | TokuDB ... |
+-------------------------------------------+
```

### MySQL 内置存储引擎

| 引擎 | 用途 | 数据结构 | 事务 | 锁粒度 |
|------|------|---------|------|--------|
| InnoDB | OLTP 主力 | B+ 树（聚簇索引） | 是 | 行锁 |
| MyISAM | 旧代默认（5.1 之前） | B 树 + MYD/MYI 文件 | 否 | 表锁 |
| MEMORY (HEAP) | 临时表/查找表 | 哈希 / B 树 | 否 | 表锁 |
| CSV | 与外部 CSV 文件互通 | 文本 | 否 | -- |
| ARCHIVE | 归档（zlib 压缩） | append-only | 否 | 行锁（INSERT） |
| NDB Cluster | 分布式内存 | 分布式哈希 | 是（2PC） | 行锁 |
| FEDERATED | 远程 MySQL 表代理 | 无本地存储 | 远程 | 远程 |
| BLACKHOLE | /dev/null（仅记录 binlog） | 无 | 是（binlog） | -- |
| MERGE | 多个 MyISAM 表的视图 | -- | 否 | -- |
| Performance Schema | 仪表盘内部表 | 内存 | 否 | -- |

### 第三方/扩展引擎

- **MyRocks**（Facebook，2016）：基于 RocksDB 的 LSM 引擎，写放大低，压缩率高，专为 SSD + 大写入场景设计。MariaDB 也内置 MyRocks。
- **TokuDB**（Tokutek，已停止维护）：分形树（fractal tree），写性能优于 B 树，曾用于 Percona Server。
- **Spider**：MariaDB 维护的分库分表代理引擎，把表的不同分片路由到不同 MySQL 实例。
- **CONNECT**：MariaDB 的"万能"引擎，能把表映射到 CSV/XML/JSON/ODBC/MongoDB 等外部数据源。
- **S3**：MariaDB 10.5+ 提供，把 Aria 表存到 S3，作为只读归档。

### 选择存储引擎的 DDL 语法

```sql
-- 创建表时指定引擎
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    user_id BIGINT,
    amount DECIMAL(10,2)
) ENGINE=InnoDB;

-- 同一个数据库内不同表使用不同引擎
CREATE TABLE logs (...)        ENGINE=MyRocks;   -- LSM，写密集
CREATE TABLE config (...)      ENGINE=InnoDB;    -- 事务
CREATE TABLE cache (...)       ENGINE=MEMORY;    -- 内存查找
CREATE TABLE archive_2020 (...)ENGINE=ARCHIVE;   -- 归档
CREATE TABLE remote_users (...)ENGINE=FEDERATED  -- 远程
    CONNECTION='mysql://user:pwd@remote/db/users';

-- 修改已存在表的引擎（会重写整张表）
ALTER TABLE orders ENGINE=MyRocks;

-- 查看可用引擎
SHOW ENGINES;

-- 安装/卸载引擎插件
INSTALL PLUGIN rocksdb SONAME 'ha_rocksdb.so';
UNINSTALL PLUGIN rocksdb;
```

### 跨引擎事务的限制

MySQL 的 XA 事务能跨多个 InnoDB 实例，但**同一事务内混用 InnoDB + MyISAM 不能保证原子性**——MyISAM 部分会立即生效且不可回滚。这是混用引擎的最大坑点。

## ClickHouse 表引擎"动物园"深度解读

ClickHouse 把"存储引擎"概念发挥到极致。每张表必须指定一个 `ENGINE`，目前内置约 40 个表引擎，按用途分为五大类。

### 1. MergeTree 家族（OLAP 主力）

```sql
CREATE TABLE events (
    ts DateTime,
    user_id UInt64,
    event String
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(ts)
ORDER BY (user_id, ts);
```

| 引擎 | 用途 |
|------|------|
| `MergeTree` | 标准列存，主键排序，分区，零事务 |
| `ReplacingMergeTree` | 后台合并时按主键去重，保留最新版本 |
| `SummingMergeTree` | 按主键求和数值列（自动聚合） |
| `AggregatingMergeTree` | 任意聚合状态合并（与物化视图配合） |
| `CollapsingMergeTree` | 通过 sign 列实现行级删除/更新 |
| `VersionedCollapsingMergeTree` | 带版本号的 Collapsing |
| `GraphiteMergeTree` | 专为 Graphite 时序数据设计 |
| `Replicated*MergeTree` | 上述每个变体都有 ZK/Keeper 副本版本 |

### 2. Log 家族（小数据快速写入）

| 引擎 | 特点 |
|------|------|
| `TinyLog` | 单文件 per column，不支持索引、并发读 |
| `StripeLog` | 单文件，支持并发读 |
| `Log` | 多文件 + mark 文件，支持并发读 |

### 3. 特殊引擎

| 引擎 | 用途 |
|------|------|
| `Memory` | 数据全部在内存，进程退出即丢失，超快 |
| `Set` | 只支持 `IN` 查询，用作子查询右侧 |
| `Join` | 预构建的 hash join 表，加速重复 JOIN |
| `Buffer` | 内存缓冲层，定期 flush 到底层表，平滑写入峰值 |
| `Dictionary` | 把外部字典表暴露成表 |
| `Distributed` | 不存数据，只做分布式路由（虚拟分片表） |
| `Merge` | 不存数据，把多张同结构表 UNION 起来 |
| `Null` | 写入即丢弃，但物化视图仍会触发（用于流式管道） |
| `URL` | 把 HTTP 端点暴露成表 |
| `File` | 把本地文件（CSV/Parquet/...）暴露成表 |
| `View` / `MaterializedView` | 视图与物化视图 |
| `LiveView`（实验） | 流式刷新视图 |
| `WindowView`（实验） | 窗口聚合视图 |

### 4. 集成引擎（外部数据源）

```sql
CREATE TABLE mysql_users (
    id UInt64, name String
) ENGINE = MySQL('host:3306', 'db', 'users', 'user', 'pwd');
```

| 引擎 | 数据源 |
|------|--------|
| `MySQL` | MySQL 表代理 |
| `PostgreSQL` | PostgreSQL 表代理 |
| `MongoDB` | MongoDB 集合 |
| `Kafka` | Kafka topic（消费者组流式读取） |
| `RabbitMQ` | RabbitMQ 队列 |
| `S3` | S3 对象（CSV/Parquet/JSON） |
| `HDFS` | HDFS 文件 |
| `JDBC` / `ODBC` | 通用 JDBC/ODBC 数据源 |
| `EmbeddedRocksDB` | 内嵌的 RocksDB KV 表（点查极快） |
| `SQLite` | SQLite 文件 |
| `Hive` | Hive 元数据表 |
| `DeltaLake` / `Hudi` / `Iceberg` | 数据湖表格式 |
| `NATS` | NATS 流 |
| `Redis` | Redis KV |

### 5. 引擎组合的威力

ClickHouse 的引擎可以"流水线"组合，例如经典的 Kafka 流式入仓管道：

```sql
-- 1) Kafka 引擎：从 Kafka 实时消费
CREATE TABLE kafka_in (
    ts DateTime, user_id UInt64, event String
) ENGINE = Kafka('broker:9092', 'events', 'ch_group', 'JSONEachRow');

-- 2) MergeTree 表：实际落盘存储
CREATE TABLE events_local (
    ts DateTime, user_id UInt64, event String
) ENGINE = MergeTree() ORDER BY (user_id, ts);

-- 3) 物化视图：把 Kafka 消息自动写入 MergeTree
CREATE MATERIALIZED VIEW kafka_to_events TO events_local AS
SELECT * FROM kafka_in;
```

这个三件套（Kafka + MergeTree + MV）是 ClickHouse 实时数仓的标配，等价于"无 Flink 的 Flink"。

## PostgreSQL Table Access Method (TAM) API

PostgreSQL 长期以来只有一个存储引擎——**heap**（带 MVCC 的堆表）。它的 MVCC 设计是把每个版本元组（tuple）直接写入数据页，旧版本由 `VACUUM` 异步清理。这种设计简单可靠，但导致两个长期痛点：

1. **写放大**：UPDATE 实际是 INSERT 新元组 + 标记旧元组死亡（HOT 优化只在窄场景下生效）
2. **VACUUM 痛点**：高更新负载下 dead tuple 累积、bloat、wraparound 风险

PostgreSQL 12（2019 年 10 月发布）引入了 **Table Access Method API**，允许把表的物理存储抽象为可插拔接口。

```sql
-- 12+ 语法
CREATE TABLE t (id INT) USING heap;     -- 默认
CREATE TABLE t (id INT) USING orioledb; -- 实验性 OLTP 引擎
CREATE TABLE t (id INT) USING zedstore; -- 实验性列存

-- 查看已注册的 TAM
SELECT amname, amtype FROM pg_am WHERE amtype = 't';

-- 设置默认 TAM
SET default_table_access_method = 'orioledb';
```

### 已知的 TAM 实现

| TAM | 状态 | 设计目标 |
|-----|------|---------|
| **heap** | 生产唯一 | PG 历史引擎，MVCC 元组在表内 |
| **OrioleDB** | Beta | undo log 风格 MVCC，MVCC 数据在 undo，避免 VACUUM；row-level WAL |
| **Zheap** | 已搁置 | EnterpriseDB 提出的 undo-based 引擎，开发停滞 |
| **Zedstore** | 实验 | 列存 TAM，索引组织表 |
| **Citus columnar** | 生产 | Citus 扩展提供的列式 TAM（cstore_fdw 后继） |
| **Hydra columnar** | 生产 | 基于 Citus columnar 的发行版 |
| **Bottled Water** / 其他 | 概念 | 远程/外部存储 TAM |

### TAM API 的局限

PostgreSQL 12 的 TAM API 只是"半成品"：

- 索引接口（`amapi.h`）仍假设元组使用 heap 的 `ItemPointer`（block + offset），列存或 OrioleDB 必须做 trick
- WAL 接口未全面通用化，每种 TAM 都要走自定义 RMGR
- `VACUUM`、统计、并行扫描等仍偏向 heap 假设

社区目标是让 TAM 在 PG 17/18 之后成熟，但**截至 2026 年 4 月**，heap 仍然是事实上唯一可投产的 PG 表引擎。

## 各引擎深度对比

### Oracle：单引擎 + 多格式

Oracle 没有可插拔存储引擎概念，但在 Oracle 12.1.0.2（2014）引入了 **Database In-Memory** 选项，让同一张表同时存在两种格式：

```sql
ALTER TABLE sales INMEMORY PRIORITY HIGH;
-- 此后 sales 同时驻留行格式（磁盘 + buffer cache）和列格式（IM column store，内存）
-- OLTP 走行格式，分析查询走列格式，由优化器自动选
```

这是"同一引擎，双存储格式"的典型代表，**不是**插件机制。

### SQL Server：heap / clustered / columnstore / Hekaton

SQL Server 在单一存储引擎内提供四种物理布局：

| 表类型 | 物理结构 | 适用 |
|--------|---------|------|
| heap | 无序页堆 | 大批量 INSERT |
| clustered index | 按主键 B+ 树（数据=叶子页） | OLTP 默认 |
| columnstore index | 列存 segment（rowgroup） | OLAP，2012+ |
| memory-optimized (Hekaton) | 哈希/范围索引，全内存，乐观 MVCC | 极致 OLTP，2014+ |

```sql
-- Hekaton 表
CREATE TABLE Orders (
    Id INT IDENTITY PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 1024),
    Amount DECIMAL(10,2)
) WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);

-- Clustered Columnstore Index（CCI），表本身就是列存
CREATE CLUSTERED COLUMNSTORE INDEX cci ON FactSales;
```

### DB2：BLU 列存

DB2 10.5（2013）引入 **BLU Acceleration**（BLink Ultra），与传统行存共存：

```sql
CREATE TABLE sales (
    id BIGINT, sale_date DATE, amount DECIMAL(10,2)
) ORGANIZE BY COLUMN;        -- BLU 列存
-- 默认是 ORGANIZE BY ROW
```

BLU 使用 **frequency partitioning** + 字典编码 + 直接对压缩数据做 SIMD 计算，不需要传统索引。同一数据库可以行存表与列存表共存。

### TiDB：TiKV + TiFlash 双引擎

TiDB 是"双引擎"分布式架构的代表：

```
+----------------+
|     TiDB       |   <- SQL 层（无状态）
+--------+-------+
         |
   +-----+------+
   |            |
+--v---+    +---v----+
| TiKV |    | TiFlash|
| 行存  |    | 列存    |
| LSM  |    | 列式    |
+------+    +--------+
```

- **TiKV**：基于 RocksDB 的分布式 KV，行存，承载 OLTP 和点查
- **TiFlash**：列式存储，通过 Raft Learner 副本异步同步 TiKV 数据，承载 OLAP

```sql
-- 为表添加 TiFlash 副本
ALTER TABLE orders SET TIFLASH REPLICA 2;
-- 优化器自动决定走 TiKV 或 TiFlash
```

### SingleStore：rowstore + columnstore

SingleStore（前 MemSQL）支持两种引擎：

| 引擎 | 存储位置 | 用途 |
|------|---------|------|
| rowstore | 全内存 | OLTP，亚毫秒延迟 |
| columnstore | 磁盘 | OLAP，海量数据 |

```sql
CREATE TABLE hot_orders (id BIGINT, ...) USING ROWSTORE;
CREATE TABLE archive_orders (id BIGINT, ...) USING COLUMNSTORE;
```

7.0 之后默认是 columnstore（因为 rowstore 全内存代价高）。8.0+ 引入 **Universal Storage**：实际是 columnstore 之上加上类似行存的二级索引和点查能力，模糊了二者的边界。

### Vertica：WOS + ROS

Vertica 是单一列存引擎，但内部分两层：

- **WOS (Write Optimized Store)**：内存写入缓冲，按行追加
- **ROS (Read Optimized Store)**：磁盘列存，排序压缩

后台 **Tuple Mover** 把 WOS 的数据 flush 成 ROS。现代 Vertica 已弱化 WOS（直接走 DIRECT 模式入 ROS）。

### Greenplum：heap + AO + AOCO

Greenplum 在 PG heap 之上增加了两类专用表：

```sql
-- 1) Heap（同 PG）
CREATE TABLE t1 (...) WITH (appendonly=false);

-- 2) Append-Optimized 行存
CREATE TABLE t2 (...) WITH (appendonly=true, orientation=row);

-- 3) Append-Optimized 列存（AOCO）
CREATE TABLE t3 (...) WITH (
    appendonly=true,
    orientation=column,
    compresstype=zstd,
    compresslevel=5
);
```

AOCO 表不支持 UPDATE/DELETE 的高效执行（要批量改写整个 segment），适合数仓事实表的 ETL 场景。

### MariaDB：最丰富的官方引擎集

MariaDB 在 MySQL 引擎基础上增加：

- **Aria**：MyISAM 的崩溃安全替代品，作为内部临时表引擎
- **MyRocks**：与 MySQL 同源
- **ColumnStore**（前 InfiniDB）：分布式列存数据库，作为 MariaDB 的存储引擎暴露
- **Spider**：分库分表代理
- **CONNECT**：通用外部数据源连接（CSV/XML/JSON/ODBC/MongoDB）
- **S3**：把只读 Aria 表存到 S3
- **OQGRAPH**：图计算引擎
- **Sequence**：虚拟序列引擎（生成数字序列）
- **CassandraSE**：Cassandra 代理（已废弃）

```sql
CREATE TABLE huge_logs (...) ENGINE=ColumnStore;
CREATE TABLE shard_table (...) ENGINE=Spider COMMENT='wrapper "mysql", srv "shard1 shard2"';
CREATE TABLE archive (...) ENGINE=Aria;
CREATE TABLE writelog (...) ENGINE=MyRocks;
```

### ClickHouse vs Trino/Spark/Hive 的"connector"

ClickHouse 的"表引擎"和 Trino/Spark/Hive 的"connector"看似都是可插拔，但语义差别巨大：

| 维度 | ClickHouse 引擎 | Trino/Spark Connector |
|------|----------------|----------------------|
| 数据归属 | 引擎本身管理数据生命周期 | 数据归外部系统所有 |
| DDL 范围 | 创建一张本地物理表 | 创建一个映射，非物理表 |
| 写入 | 大多数引擎支持原生写入 | 多数 connector 只读或弱写入 |
| 计算下推 | 引擎与执行器深度耦合 | 计算下推由 connector 接口约束 |

Trino 的 connector 更像是"虚表 + 计算下推"，ClickHouse 的 Kafka/MySQL/S3 引擎才是真正的"内置表引擎"。

## 关键发现

1. **可插拔不等于多格式**。MySQL/MariaDB/ClickHouse 提供真正的"插件式"引擎 API（运行时加载共享库），而 Oracle/SQL Server/DB2/HANA 只是单一引擎内提供多种存储格式。前者允许第三方扩展，后者不允许。

2. **PostgreSQL TAM 仍未成熟**。12 引入 API（2019），到 2026 年仍只有 heap 是生产可用引擎。OrioleDB 是当前最有希望的下一代候选，Zheap 已搁置，Zedstore 仅实验。

3. **MySQL 是唯一靠"插件引擎"差异化的主流 OLTP 数据库**。InnoDB（事务）/MyRocks（LSM）/Memory（内存）/ARCHIVE（归档）/FEDERATED（远程）覆盖完整谱系。但跨引擎事务不原子，是混用的最大坑。

4. **ClickHouse 的引擎数量遥遥领先**。约 40 个表引擎覆盖 OLAP 列存（MergeTree 家族）、临时存储（Memory/Set/Join/Buffer）、外部集成（Kafka/MySQL/S3/Hudi/Iceberg）和管道编排（Distributed/Merge/MaterializedView）。这种"引擎即抽象"的设计哲学让 ClickHouse 成为同时是数仓、流处理器和数据湖网关的奇特存在。

5. **行 + 列双引擎是 HTAP 的标准答案**。TiDB（TiKV + TiFlash）、SingleStore（rowstore + columnstore）、SQL Server（clustered + columnstore）、DB2（行 + BLU）、Oracle（行 + IM Column Store）、SAP HANA（双引擎共生）都采用相同模式：行存负责 OLTP，列存负责 OLAP，由优化器或副本同步桥接。

6. **LSM 引擎在分布式数据库里成为默认**。CockroachDB（Pebble）、TiKV、YugabyteDB（DocDB）、OceanBase、RisingWave（Hummock）、ScyllaDB 都基于 LSM——这与单机 OLTP 的 B+ 树主导地位形成鲜明对比。原因：LSM 写放大低、压缩率高、对 SSD 友好，且天然适合追加式复制日志。

7. **MVCC 不是"有/没有"的二元问题**。PG 的 in-table 多版本元组、Oracle 的 undo segment、SQL Server Hekaton 的乐观无锁、TiDB 的 Percolator、CockroachDB 的 HLC——每种 MVCC 都有截然不同的写放大、清理代价和分布式特性。引擎选择本质上是 MVCC 模型选择。

8. **Hekaton 是商业数据库内的"引擎革命"**。SQL Server 2014 的 In-Memory OLTP 用全无锁乐观 MVCC + 编译为机器码的存储过程，实测比传统引擎快 30 倍，但商用化十年后采用率仍然偏低——可见即使最优秀的存储引擎，如果割裂应用编程模型，也难普及。

9. **数据湖时代正在重新定义"存储引擎"**。Delta Lake / Iceberg / Hudi / Paimon 这些表格式（table format）某种程度上是"运行在对象存储上的可插拔存储引擎"，被 Spark/Trino/Flink/ClickHouse/StarRocks 等多个计算引擎共享。可插拔的对象正在从"引擎"上移到"表格式"。

10. **MySQL 的可插拔 API 是 21 世纪初最被低估的架构选择**。2008 年的 MySQL 5.1 通过 storage engine API 让 InnoDB（来自 Innobase）、TokuDB、MyRocks 等独立公司/团队可以为同一个数据库内核贡献完全不同的存储设计。这种开放性间接催生了今日 MyRocks（Facebook）、TokuDB（Tokutek）、SPIDER（成本中心）等百花齐放的生态——这是 PostgreSQL 直到 2019 年才迟到追赶的设计模式。

11. **可插拔性的代价**。MySQL 的可插拔架构让 query layer 与 storage layer 通过 handler API 通信，每行数据要跨越 API 边界——这导致 InnoDB 在某些工作负载下比理论值慢 10–20%。Oracle/SQL Server 通过紧耦合换取性能。架构选择没有银弹。

12. **真正"单引擎"的现代数据库越来越少**。本文调查的 45+ 数据库中，提供某种形式的多种存储格式（行/列/内存/LSM/外部）的占绝大多数。可插拔与多格式的边界正在模糊：传统数据库通过引入新格式逼近"插件感"，新数据库（ClickHouse/Trino/Spark）则把"connector/engine"作为第一公民。**多元存储已成为新常态**。
