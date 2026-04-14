# B+Tree vs LSM-Tree 存储引擎对比 (B+Tree vs LSM-Tree)

四十年来 B+Tree 是关系数据库的事实标准——直到 2006 年 Google BigTable 论文把 LSM-Tree 推向主流，整个数据库工业界开始重新思考"写优化"还是"读优化"这个根本问题。今天几乎所有现代分布式 SQL 数据库（CockroachDB / TiDB / YugabyteDB / OceanBase）都选择了 LSM 路线，而传统单机数据库（PostgreSQL / MySQL InnoDB / Oracle / SQL Server）仍然坚守 B+Tree。这不是技术优劣的问题，而是 RUM 三角的取舍。

## 历史脉络与设计哲学

### B+Tree：四十年的统治

B+Tree 由 Rudolf Bayer 和 Edward McCreight 于 1972 年发明，用于 IBM 数据库系统。其核心设计目标是：在磁盘存储介质上以最少的 I/O 完成键值查找。每个节点对应一个磁盘块（page），通常 4KB-16KB；树高一般 3-4 层即可索引十亿级数据。

B+Tree 的核心特性：

1. **就地更新（in-place update）**：写入直接修改原 page，需要 WAL（Write-Ahead Log）保证持久性
2. **平衡树结构**：所有叶子节点在同一深度，查找复杂度稳定 O(log_B N)
3. **范围扫描友好**：叶子节点通过双向链表连接，顺序读取无需回到根节点
4. **读优化**：单点查询通常 3-4 次 I/O 即可命中
5. **写放大较低**：理想情况下每次更新写入 1 个 page（约 2-3x 实际放大）

### LSM-Tree：从论文到工业革命

LSM-Tree（Log-Structured Merge-Tree）的概念由 Patrick O'Neil、Edward Cheng、Dieter Gawlick、Elizabeth O'Neil 在 1996 年的论文 *"The Log-Structured Merge-Tree (LSM-Tree)"* 中提出。原始论文的核心动机是：磁盘顺序写远比随机写快（约 100-1000 倍），如果能把所有写入转换成顺序写，写吞吐量可以提升一个数量级。

但真正改变数据库工业的是 2006 年 Google 的 BigTable 论文 *"Bigtable: A Distributed Storage System for Structured Data"*（Chang et al., OSDI 2006）。BigTable 在 GFS 之上用 LSM 思想实现了 PB 级别的可扩展键值存储，证明了：

- LSM 在写密集型工作负载（日志、时序、Web 索引）下性能远超 B+Tree
- LSM 的层次化结构天然适合分布式存储和压缩
- 通过 Bloom Filter 和块缓存可以缓解 LSM 的读放大问题

BigTable 之后的关键里程碑：

| 年份 | 事件 | 影响 |
|------|------|------|
| 1996 | O'Neil 等人发表 LSM-Tree 论文 | 学术起点 |
| 2006 | Google 发表 BigTable 论文 | LSM 工业化 |
| 2008 | HBase 0.1 (Apache) | LSM 进入 Hadoop 生态 |
| 2008 | Cassandra (Facebook 开源) | LSM 进入 NoSQL 主流 |
| 2011 | LevelDB (Google, Sanjay Ghemawat & Jeff Dean) | 嵌入式 LSM 库 |
| 2012 | RocksDB (Facebook fork LevelDB) | 工业级 LSM 引擎 |
| 2014 | InfluxDB TSM | 时序场景 LSM 变体 |
| 2015 | TiKV / CockroachDB 早期版本 | 分布式 SQL + LSM |
| 2016 | MyRocks (Facebook) | MySQL + RocksDB 进入生产 |
| 2020 | CockroachDB 20.1 切换到 Pebble | Go 原生 LSM |

LSM 改变了数据库设计的根本假设：**写入不再是"原地修改"，而是"追加新版本"**。这一思想后来还启发了 LakeHouse（Iceberg / Delta Lake / Hudi）的设计。

## 理论基础：RUM 猜想

2016 年 Boston University 的 Manos Athanassoulis 等人在论文 *"Designing Access Methods: The RUM Conjecture"*（EDBT 2016）中提出了 RUM 三角形：

> **RUM Conjecture**: 任何访问方法在 **R**ead overhead（读放大）、**U**pdate overhead（写放大）、**M**emory/space overhead（空间放大）这三个维度上不可能同时最优——优化任意两个必然牺牲第三个。

三类放大的精确定义：

- **写放大（Write Amplification, WA）**：实际写入存储介质的字节数 / 用户逻辑写入的字节数
- **读放大（Read Amplification, RA）**：一次查询实际读取的页面数 / 用户期望读取的页面数
- **空间放大（Space Amplification, SA）**：磁盘上的实际占用空间 / 用户数据的逻辑大小

### B+Tree 与 LSM 在 RUM 三角中的位置

| 维度 | B+Tree | LSM (Leveled) | LSM (Tiered) |
|------|--------|---------------|--------------|
| 读放大 | 低（O(log_B N)，3-4 次 I/O）| 中（每层一次 + Bloom filter 假阳性）| 高（每个 SSTable 都需查找）|
| 写放大 | 低（~2-3x）| 高（~10-30x）| 低（~2-10x）|
| 空间放大 | 中（内部碎片 + B-link 节点）| 低（~1.1x，写满压缩后）| 高（~2-3x，存在大量重复版本）|
| 范围扫描 | 极佳（叶子链表）| 良好（多 SSTable 归并）| 一般（更多 SSTable）|

可见 B+Tree 是"读优化 + 空间中等"，LSM Leveled 是"读+空间优化 + 写代价高"，LSM Tiered 是"写优化 + 读和空间代价高"。这正是 RUM 三角的具体体现。

## 综合支持矩阵

下表覆盖 50+ 主流数据库的存储引擎选择。"默认引擎"指开箱即用的存储格式；"可选 B+Tree" 和"可选 LSM" 表示是否提供该类型的可插拔/替代引擎；"列存"作为正交分类单独列出。

| 引擎 | 默认存储引擎 | 类型 | B+Tree 可选 | LSM 可选 | 列存 | 学习索引 | Bloom Filter |
|------|------------|------|------------|---------|------|----------|-------------|
| PostgreSQL | Heap + B+Tree 二级索引 | B+Tree | 内置 | 扩展（zheap、OrioleDB）| Citus / Hydra | 实验 | BRIN / bloom 扩展 |
| MySQL InnoDB | 聚簇 B+Tree（索引组织表）| B+Tree | 内置 | MyRocks 插件 | -- | -- | InnoDB Change Buffer |
| MariaDB | InnoDB / Aria | B+Tree | 内置 | MyRocks | ColumnStore | -- | Aria bloom |
| SQLite | B-Tree（页式）| B+Tree | 内置 | -- | -- | -- | -- |
| Oracle | Heap + B+Tree | B+Tree | 内置 | -- | In-Memory Column Store | -- | Bloom Pruning |
| SQL Server | 聚簇 B+Tree / 堆 | B+Tree | 内置 | -- | Columnstore Index | -- | 是 |
| DB2 | B+Tree | B+Tree | 内置 | -- | BLU Acceleration | -- | 是 |
| Snowflake | 微分区（不可变文件）| 列存/混合 | -- | -- | 是 | -- | 是（micro-partition pruning）|
| BigQuery | Capacitor 列存 | 列存 | -- | -- | 是 | -- | 是 |
| Redshift | 列式块存储 | 列存 | -- | -- | 是 | -- | Zone Maps |
| DuckDB | 行组列存（vector）| 列存 | -- | -- | 是 | -- | Zonemap |
| ClickHouse | MergeTree | LSM-like 列存 | -- | 是 | 是 | -- | data skipping index |
| Trino | 无（计算引擎）| -- | -- | -- | 依赖底层 | -- | 依赖底层 |
| Presto | 无（计算引擎）| -- | -- | -- | 依赖底层 | -- | 依赖底层 |
| Spark SQL | 无（计算引擎）| -- | -- | -- | Parquet/ORC | -- | Parquet bloom |
| Hive | 无（依赖 HDFS）| -- | -- | -- | ORC/Parquet | -- | ORC bloom |
| Flink SQL | RocksDB（状态后端）| LSM | -- | 是 | -- | -- | 是 |
| Databricks | Delta Lake (Parquet) | 列存 | -- | -- | 是 | -- | Parquet bloom |
| Teradata | 哈希分布行存 | 行存 | -- | -- | Columnar partition | -- | -- |
| Greenplum | Heap / AO / AOCO | Heap + 列存 | 内置 | -- | 是（AOCO）| -- | -- |
| CockroachDB | Pebble (Go LSM) | LSM | -- | 内置 | -- | -- | 是 |
| TiDB | TiKV (RocksDB) + TiFlash | LSM + 列存 | -- | 内置 | TiFlash | -- | 是 |
| OceanBase | LSM-Tree (memtable + SSTable) | LSM 变体 | -- | 内置 | 是（4.x 列存）| -- | 是 |
| YugabyteDB | DocDB (RocksDB fork) | LSM | -- | 内置 | -- | -- | 是 |
| SingleStore | Rowstore（跳表）+ Columnstore（LSM 段）| 混合 | -- | 是 | 是 | -- | 是 |
| Vertica | ROS/WOS（列存 LSM 思想）| 列存 LSM-like | -- | 思想类似 | 是 | -- | -- |
| Impala | 无（依赖 HDFS / Kudu）| -- | -- | Kudu | Parquet | -- | Parquet bloom |
| StarRocks | 主键模型（Delete+Insert LSM 变体）/ 明细 | 混合 | -- | 主键模型 | 是 | -- | 是 |
| Doris | Aggregate / Unique / Duplicate | LSM 变体 + 列存 | -- | Unique 模型 | 是 | -- | 是 |
| MonetDB | BAT 列存（内存优化）| 列存 | -- | -- | 是 | -- | -- |
| CrateDB | Lucene 段（LSM-like）| LSM-like | -- | 是 | -- | -- | 是 |
| TimescaleDB | PG Heap + Hypertable chunks | B+Tree | 内置 | -- | Compression（列存）| -- | -- |
| QuestDB | Append-only 列存 | 列存 | -- | -- | 是 | -- | -- |
| Exasol | 内存列存 | 列存 | -- | -- | 是 | -- | -- |
| SAP HANA | 列存（delta + main）| 列存 LSM-like | -- | delta 段类似 | 是 | -- | -- |
| Informix | B+Tree | B+Tree | 内置 | -- | -- | -- | -- |
| Firebird | B+Tree（多版本）| B+Tree | 内置 | -- | -- | -- | -- |
| H2 | MVStore（B+Tree+MVCC）| B+Tree | 内置 | -- | -- | -- | -- |
| HSQLDB | B+Tree | B+Tree | 内置 | -- | -- | -- | -- |
| Derby | B+Tree | B+Tree | 内置 | -- | -- | -- | -- |
| Amazon Athena | 无（S3 + Trino）| -- | -- | -- | Parquet/ORC | -- | Parquet bloom |
| Azure Synapse | 列存 / 行存 | 混合 | 内置 | -- | 是 | -- | 是 |
| Google Spanner | Ressi (类 SSTable LSM) | LSM 变体 | -- | 内置 | -- | -- | 是 |
| Materialize | 增量视图（differential dataflow）| 内存 | -- | -- | -- | -- | -- |
| RisingWave | Hummock (LSM on S3) | LSM | -- | 内置 | -- | -- | 是 |
| InfluxDB | TSM（Time-Structured Merge）| LSM 变体 | -- | 内置 | 是 | -- | 是 |
| Databend | Fuse (Parquet + 元数据)  | 列存 | -- | -- | 是 | -- | bloom index |
| Yellowbrick | 列存（Kubernetes 原生）| 列存 | -- | -- | 是 | -- | -- |
| Firebolt | F3（列存 sparse index）| 列存 | -- | -- | 是 | -- | sparse index |

### 默认引擎类型分布统计

| 类型 | 数量 | 代表 |
|------|------|------|
| 纯 B+Tree | 12 | PostgreSQL, MySQL, Oracle, SQL Server, DB2, SQLite, MariaDB, Informix, Firebird, H2, HSQLDB, Derby |
| LSM 或 LSM 变体 | 11 | CockroachDB, TiDB(TiKV), YugabyteDB, OceanBase, Spanner, Cassandra*, HBase*, RisingWave, InfluxDB, ClickHouse(类 LSM), CrateDB |
| 列存（非 LSM）| 13 | Snowflake, BigQuery, Redshift, DuckDB, Vertica, MonetDB, Exasol, SAP HANA, QuestDB, Yellowbrick, Firebolt, Databend, Synapse |
| 混合 / 多模 | 6 | SingleStore, StarRocks, Doris, Greenplum, TiDB(TiKV+TiFlash), TimescaleDB |
| 计算引擎（无存储）| 5 | Trino, Presto, Spark SQL, Hive, Athena, Impala |

> 注：Cassandra / HBase 是 NoSQL，未列入主表但属于经典 LSM 实现；ClickHouse MergeTree 严格说不是标准 LSM（没有 memtable，是按批 immutable 写入），但其多层归并思想与 LSM 同源。

### 压缩策略支持

| 引擎 | 底层存储 | 压缩策略 | 备注 |
|------|---------|---------|------|
| RocksDB | LSM | leveled / universal / FIFO | 默认 leveled |
| LevelDB | LSM | leveled | 经典 |
| Pebble (CockroachDB) | LSM | leveled | 仅 leveled |
| Cassandra | LSM | SizeTiered / Leveled / TimeWindow | STCS 默认 |
| HBase | LSM | Stripe / Date Tiered / Exploring | 历史上 SizeTiered |
| ScyllaDB | LSM | 同 Cassandra + Incremental | -- |
| TiKV | RocksDB | leveled | 继承 RocksDB |
| YugabyteDB DocDB | RocksDB fork | leveled + universal | 多组合 |
| OceanBase | LSM 变体 | 每日合并（major freeze）| 独有的 baseline + delta 模型 |
| RisingWave Hummock | LSM | leveled | 对象存储优化 |
| InfluxDB TSM | 时序 LSM | 时间窗口分层 | -- |
| ClickHouse MergeTree | 类 LSM | level merge + 后台合并 | 分区内归并 |

### 数据结构对比矩阵

| 维度 | B+Tree | LSM-Tree |
|------|--------|---------|
| 写入路径 | WAL → 修改 page → 刷盘 | WAL → MemTable → flush 为 SSTable → compaction |
| 读取路径 | 根 → 内部 → 叶子（稳定 3-4 次 I/O）| MemTable → L0 → L1 → ... → Lmax（多次 I/O，依赖 Bloom）|
| 更新方式 | in-place（就地修改）| out-of-place（追加新版本）|
| 删除方式 | 标记删除 + 后台合并 | 写入 tombstone，compaction 时清理 |
| 范围扫描 | 叶子链表，O(log N + k) | 多 SSTable 归并，O(L × log N + k) |
| 并发控制 | 闩锁（latch coupling）/ B-link tree | LSM 天然支持 MVCC（每个版本是独立 key）|
| WAL 必要性 | 必须（保护就地修改）| 必须（保护 memtable）|
| 后台 IO | 检查点（checkpoint） | 持续 compaction |
| 适合介质 | HDD（B+Tree 是为 HDD 设计的）| SSD（LSM 受益于 SSD 顺序写带宽）|
| 缓存策略 | Buffer Pool（按 page）| Block Cache（按 SSTable block）|
| 大 value 处理 | 行外存储（TOAST）| Key-Value Separation（BlobDB / Titan）|

### 历史背景：为什么 B+Tree 适合 HDD，LSM 适合 SSD

B+Tree 设计于 1970 年代，当时存储介质是机械硬盘（HDD）。HDD 的物理特性：

- **随机 I/O 慢**：寻道 + 旋转延迟 ~10ms（100 IOPS）
- **顺序 I/O 快**：约 100MB/s
- **随机/顺序速度比**：~1:1000

B+Tree 通过把数据分组到 page（4-16KB），把树高压缩到 3-4 层，使得任何查询都只需要 3-4 次随机 I/O。这是 HDD 时代的最优解。

而 SSD 的物理特性完全不同：

- **随机 I/O 快**：~100us（10000 IOPS）
- **顺序 I/O 极快**：~3GB/s（NVMe）
- **随机/顺序速度比**：~1:30
- **写入有寿命限制**：每个 cell 可擦写次数有限
- **写入需要 erase block**：实际写入粒度可能是 256KB 而非 4KB

这些特性使 LSM 在 SSD 上有了三大优势：

1. **顺序写远优于随机写**（即使 SSD 也是如此，因为 erase block 大小问题）
2. **减少写次数 = 延长 SSD 寿命**：LSM 的合并比 B+Tree 的 in-place update 更好控制
3. **大块顺序写带宽利用率高**：LSM 的 SSTable 通常 64MB-256MB，远大于 B+Tree 的 page

这就是为什么 RocksDB / Cassandra / HBase 等 LSM 引擎在 2010 年之后随着 SSD 普及而爆发。

## 代表引擎深度剖析

### PostgreSQL：Heap + B+Tree 二级索引

PostgreSQL 是"堆表 + 独立索引"模型的代表：

- **堆表（heap）**：表数据存储在无序的 page 中，按插入顺序追加（更新会写新版本，依赖 VACUUM 回收旧版本）
- **B+Tree 二级索引**：所有索引（包括主键）都是独立的 B+Tree，叶子节点存储 `(key, ctid)`，其中 ctid 是堆表物理位置
- **写放大**：约 2-3x（heap 一份 + 每个二级索引一份）
- **MVCC 代价**：UPDATE 实质上是 INSERT 新版本 + 标记旧版本 dead，这是 PG 的著名"双写问题"

```sql
-- PostgreSQL B+Tree 索引创建
CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    amount NUMERIC(12,2),
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_orders_user ON orders USING btree (user_id);
CREATE INDEX idx_orders_brin ON orders USING brin (created_at);  -- 块范围索引
```

PG 的 zheap（实验项目）和 OrioleDB（第三方扩展）尝试用 undo log + 索引组织表的方式解决 MVCC 双写问题，但都尚未进入主线。

### MySQL InnoDB：聚簇 B+Tree（索引组织表）

InnoDB 与 PG 形成鲜明对比：表数据本身就是按主键排序的 B+Tree，叶子节点直接存储完整行（IOT, Index-Organized Table）：

- **聚簇索引**：数据按主键物理排序存储
- **二级索引叶子节点存储主键值**（非堆表的 ctid），因此通过二级索引查询非主键列需要"回表"
- **写放大**：约 2-3x，但因为没有独立 heap 文件，空间利用率优于 PG
- **页分裂代价**：随机主键插入会导致严重的页分裂和写放大，因此 InnoDB 强烈推荐使用单调递增主键

```sql
CREATE TABLE orders (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,  -- 单调递增，避免页分裂
    user_id BIGINT NOT NULL,
    amount DECIMAL(12,2),
    created_at DATETIME,
    INDEX idx_user (user_id),
    INDEX idx_created (created_at)
) ENGINE=InnoDB;
```

### Oracle / SQL Server：堆 + B+Tree

Oracle 的默认表类型是堆表（与 PostgreSQL 类似），但也提供 IOT（Index-Organized Table）选项让用户主动选择聚簇存储；SQL Server 默认是聚簇 B+Tree（类似 InnoDB），如果不指定聚簇键就退化为堆表。所有四大商业 RDBMS（Oracle / SQL Server / DB2 / Informix）的底层都是 B+Tree，过去十年的革新主要是在 B+Tree 之上叠加列存（Oracle In-Memory Column Store / SQL Server Columnstore Index / DB2 BLU）以应对分析场景。

### RocksDB：LSM 库的事实标准

RocksDB 由 Facebook 在 2012 年从 Google 的 LevelDB fork 而来，针对 SSD 和高并发做了大量优化，是今天工业界使用最广泛的 LSM 引擎库：

- **使用者**：MyRocks (MySQL), TiKV (TiDB), CockroachDB (20.1 之前), YugabyteDB (DocDB), Kafka Streams, Flink (state backend), CrateDB 早期版本, Apache Samza, LinkedIn Venice
- **核心特性**：列族（Column Family）、prefix bloom filter、merge operator、分层压缩
- **关键参数**：write_buffer_size, max_bytes_for_level_base, level0_file_num_compaction_trigger

RocksDB 的成功证明：构建一个高质量的 LSM 引擎需要数年的工程投入，绝大多数公司直接复用比自研划算。

### TiDB / TiKV：RocksDB 之上的分布式 SQL

TiDB 的存储层 TiKV 直接基于 RocksDB：

- 每个 Region（96MB 数据范围）存储为 RocksDB 中的一段 key range
- Raft Log 也存储在 RocksDB 中（独立 Column Family）
- 通过 Pebble / TitanDB 优化大 value 存储（key-value separation）
- TiFlash（列存副本）使用 ClickHouse MergeTree 引擎，与 TiKV 通过 Raft Learner 同步

### CockroachDB：从 RocksDB 切换到 Pebble

2020 年 CockroachDB 20.1 完成了一个重大决定：把存储引擎从 RocksDB 切换到自研的 Pebble。原因：

1. **Cgo 开销**：每次调用 RocksDB 都要跨 Go/C++ 边界，CPU 和延迟都有显著开销
2. **依赖管理**：RocksDB 是大型 C++ 项目，编译、调试、嵌入复杂
3. **协议兼容**：Pebble 完全兼容 RocksDB 的 SSTable 格式和 WAL 格式，可以无缝迁移
4. **针对性优化**：Pebble 可以针对 CRDB 的具体使用模式（MVCC keys, time-bound iteration）做定制

Pebble 现在也被 etcd 等 Go 项目使用，成为 Go 生态最重要的 LSM 引擎。

### YugabyteDB：DocDB 与文档模型 LSM

Yugabyte 的存储引擎 DocDB 是 RocksDB 的深度 fork：

- 在 RocksDB 之上实现了文档模型（嵌套 key），单个逻辑行可能对应多个物理 key
- 采用混合时间戳（HLC）作为版本号
- Bloom filter 和 block cache 大量定制
- 多个 RocksDB 实例（per tablet）

### MyRocks：MySQL + RocksDB

Facebook 在 2016 年把 RocksDB 集成进 MySQL，作为可插拔存储引擎：

- 主要驱动：Facebook 的 UDB（User Database）规模过大，InnoDB 的 SSD 写放大成本过高
- 实测：MyRocks 在 Facebook 工作负载下相比 InnoDB 节省 50% 的存储空间，写入放大降低 10x
- 代价：单点查询延迟略高（多层查找 + bloom filter），范围扫描需要归并多个 SSTable
- 现状：除了 Facebook，少数公司（如 LinkedIn）在使用，未成为 MySQL 主流

```sql
-- MyRocks 创建表（语法与 InnoDB 一致）
CREATE TABLE events (
    id BIGINT PRIMARY KEY,
    payload BLOB,
    ts BIGINT
) ENGINE=ROCKSDB;
```

### Cassandra / HBase：经典 NoSQL LSM

- **Cassandra**：默认 SizeTieredCompactionStrategy（STCS，等同于 universal），支持 LeveledCompactionStrategy（LCS，等同于 leveled）和 TimeWindowCompactionStrategy（TWCS，时序优化）
- **HBase**：基于 HFile（类似 SSTable），采用 ExploringCompactionPolicy（默认）或 StripeCompactionPolicy；与 Cassandra 不同的是 HBase 强一致

### ClickHouse MergeTree：列存 + LSM 思想

ClickHouse 的 MergeTree 引擎严格说不是 LSM，但借鉴了 LSM 的核心思想：

- 每次 INSERT 创建一个新的 part（不可变文件，列存格式）
- 后台线程不断合并相邻 part（merge），减少 part 数量
- 没有独立的 memtable（依赖批量写入）
- 主键（sparse primary index）只是排序键，不保证唯一性

```sql
CREATE TABLE events (
    user_id UInt64,
    event_time DateTime,
    event_type LowCardinality(String),
    payload String
) ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (user_id, event_time);  -- 这是排序键，不是 PK 唯一约束
```

### OceanBase：基线 + 增量的 LSM 变体

OceanBase 是 LSM 设计的一个独特变体：

- **基线数据（baseline）**：磁盘上的 SSTable，每天合并一次（major freeze）
- **增量数据（delta）**：内存中的 memtable，定期 minor freeze 转储为 SSTable
- **每日合并**：所有事务在凌晨低峰期统一做大合并，把所有 SSTable 合并成一个新的基线
- **优势**：数据库压力更可预测，避免 RocksDB 那种持续的后台 IO 抖动
- **代价**：白天读取需要在多个 SSTable + memtable 之间归并

### SingleStore：行存 + 列存混合

SingleStore（前身 MemSQL）的两种表类型：

- **Rowstore**：内存中的跳表（skip list），适合 OLTP，类似 MemSQL 早期版本
- **Columnstore**：磁盘上的列段（segment），新写入先进入"段缓冲区"（内存行存），达到阈值后转储为压缩列段——这本质上是 LSM 思想在列存上的应用
- 单表可以同时使用两种存储模式（universal storage，从 7.3 开始）

### WiredTiger（MongoDB）：B+Tree 与 LSM 双引擎

虽然 MongoDB 不在主表中（不是 SQL 数据库），但 WiredTiger 是少有的同时支持 B+Tree 和 LSM 两种存储格式的引擎：

- 默认 B+Tree（类似 InnoDB 的聚簇索引）
- 可选 LSM（早期 MongoDB 支持，3.x 之后被默认禁用）
- WiredTiger 团队的实践经验：B+Tree 对绝大多数工作负载更好，LSM 仅对极写密集场景有优势

### 学习索引（Learned Index）

2018 年 MIT 的 Tim Kraska 等人在 SIGMOD 论文 *"The Case for Learned Index Structures"* 中提出：用机器学习模型（最简单的是分段线性回归）替代 B+Tree 的内部节点。模型预测某个 key 在数组中的大致位置（±误差范围），然后做二分查找定位精确位置。

理论优势：

- **空间紧凑**：模型只需几 KB，远小于 B+Tree 的内部节点
- **查询快**：模型推理通常比多次指针追逐快
- **缓存友好**：模型常驻 CPU cache

实践障碍：

- **更新困难**：模型基于静态数据训练，更新需要重新训练或维护 delta
- **冷启动成本**：插入数据后需要等模型训练完成才能高效查询
- **分布敏感**：数据分布变化会显著降低模型精度

后续研究（ALEX, PGM-Index, RadixSpline 等）尝试解决更新问题，但截至 2026 年仍未在主流生产数据库中落地。最接近的工业应用是 Google BigTable 内部用 piecewise linear approximation 做块定位。

## LSM 压缩策略深度对比

LSM 的核心矛盾在于：MemTable 转储下来的 SSTable 数量会无限增长，必须定期合并（compaction）才能控制读取代价和空间占用。三大主流策略的取舍如下。

### Leveled Compaction（分层压缩）

LevelDB / Pebble / RocksDB 默认策略。结构特征：

- 数据组织为 L0, L1, L2, ..., Ln 多个层，每层大小是上一层的固定倍数（默认 10x）
- 除 L0 外，每层内部 SSTable 的 key range 互不重叠
- 触发条件：某层超过阈值时，挑选一个 SSTable 与下一层重叠的 SSTable 合并

写放大估算：理想情况下数据要从 L0 一直向下"漂流"到 Lmax，每经过一层都要被重写一次，因此写放大约等于层数 × 每层放大系数：

```
WA_leveled ≈ (n_levels - 1) × fanout
约 6 层 × 10 = 60 在最坏情况下；实际生产环境约 10-30x
```

读放大：单点查询最多查每层一个 SSTable + L0 中所有文件，约 10-20 次磁盘 IO（通过 Bloom Filter 可大幅降低）。

空间放大：约 1.1-1.2x（最坏情况下 Lmax 占总数据 90%）。

### Tiered / Universal Compaction（分级压缩）

Cassandra STCS / RocksDB Universal / HBase 早期策略。结构特征：

- SSTable 按大小分组（tier），同一组内 SSTable 大小相近
- 当某组 SSTable 数量达到阈值（通常 4 个）时，合并为一个更大的 SSTable
- 不同组之间 SSTable 的 key range 可能完全重叠

写放大估算：每条数据会被合并 log_N 次（N 为合并因子），因此：

```
WA_tiered ≈ log_N(数据总量 / SSTable 大小)
约 2-10x（远低于 leveled）
```

读放大：单点查询可能要查所有 tier 的所有 SSTable（极端情况下数百个），严重依赖 Bloom Filter。

空间放大：高达 2-3x（同一个 key 可能在多个 SSTable 中存在不同版本）。

### FIFO Compaction

RocksDB 提供的简化策略，专为时序数据设计：

- 按文件创建时间排序
- 当总大小超过阈值时直接删除最旧的文件
- 完全没有合并开销
- 数据有 TTL，过期即丢弃

### TimeWindow / Date Tiered Compaction（时序场景）

Cassandra TWCS / HBase Date Tiered。专为时序数据设计：

- SSTable 按时间窗口（如每天一个）分组
- 只合并同一时间窗口内的 SSTable
- 时序查询通常只命中最近的窗口，读放大极小
- 适合 IoT、监控、日志场景

### 三种策略量化对比

| 策略 | 写放大 | 读放大 | 空间放大 | 适用场景 |
|------|--------|--------|---------|---------|
| Leveled | 10-30x | 低（~5）| 1.1x | 读写均衡，要求空间效率 |
| Tiered (Universal) | 2-10x | 高（~50）| 2-3x | 写密集，读可用 Bloom 缓解 |
| FIFO | ~1x | 低（仅最近文件）| 1x | 时序日志，无更新 |
| TimeWindow | 2-5x | 低（窗口内）| 1.2x | 时序数据 |

## 写放大数学：B+Tree vs LSM

让我们用具体数字看看为什么 LSM 在写密集场景下胜出。

### B+Tree 写放大

假设 page size = 16KB，单条记录 100 字节：

- 一次 INSERT：修改 1 个叶子 page + 写 WAL ≈ 16KB + 100B
- 写放大 ≈ 16384 / 100 ≈ **164x**（page 级别）
- 但因为多次写会累积到同一个 page，平摊后约 **2-3x**
- 二级索引：每个二级索引贡献额外 1-2x 的写入

### LSM Leveled 写放大

数据从 L0 流到 L6，每层 fanout = 10：

```
WA = (L1 大小 / L0 大小) + (L2 大小 / L1 大小) + ... + (L6 大小 / L5 大小)
   = 10 + 10 + 10 + 10 + 10 + 10 = 60（最坏情况）
   实际约 10-30x（合并时部分 key 已被覆盖）
```

加上 WAL 和 memtable flush：再 +1x。

### LSM Tiered 写放大

合并因子 N = 4，数据总量 100GB，初始 SSTable 64MB：

```
合并次数 ≈ log_4(100GB / 64MB) ≈ log_4(1600) ≈ 5.3
WA ≈ 5.3 + 1 (WAL) ≈ 6-8x
```

### 对比小结

| 引擎类型 | WA | 适合场景 |
|---------|-----|---------|
| B+Tree（无二级索引）| 2-3x | 通用 OLTP |
| B+Tree（5 个二级索引）| 8-15x | OLTP 重读 |
| LSM Leveled | 10-30x | 读写均衡 |
| LSM Tiered | 2-10x | 写密集（日志、时序、宽表）|
| FIFO LSM | ~1x | 纯追加 |

注意一个反直觉的事实：B+Tree 在二级索引很多时，写放大可能超过 LSM Leveled。这是 MyRocks 在 Facebook 战胜 InnoDB 的核心原因。

### 实际生产案例：Facebook 的 MyRocks 迁移

Facebook 在 2016-2017 年把 UDB（用户数据库，存储 Facebook 社交图谱的核心数据）从 InnoDB 迁移到 MyRocks。论文 *"MyRocks: LSM-Tree Database Storage Engine Serving Facebook's Social Graph"*（VLDB 2020）披露的数据：

| 指标 | InnoDB | MyRocks | 改善 |
|------|--------|---------|------|
| 存储空间 | 100% (基线) | 50% | 节省 50% |
| 写放大 | ~15x（含二级索引）| ~5x | 降低 3x |
| QPS | 100% | 110% | 提升 10% |
| P99 读延迟 | 较低 | 略高（约 +20%）| 可接受 |
| SSD 寿命 | 2 年 | 5+ 年 | 延长 2.5x |

这是 LSM 在大规模生产环境中战胜 B+Tree 的最经典案例。但需要注意：Facebook 的工作负载非常特殊（写密集 + 大量二级索引 + SSD 成本敏感），不能简单推广到所有场景。

### 实际生产案例：CockroachDB 切换到 Pebble

CockroachDB 在 2020 年发布 20.1 时正式把存储引擎从 RocksDB 切换到 Pebble。Cockroach Labs 公开的数据：

| 指标 | RocksDB | Pebble | 改善 |
|------|---------|--------|------|
| Cgo 调用开销 | 较高 | 0（纯 Go）| 显著 |
| 编译时间 | 慢（C++ 项目）| 快（Go module）| 数倍 |
| 内存分配 | C++ 堆 | Go heap（GC 友好）| -- |
| MVCC 优化 | 通用 | 针对 CRDB 定制 | 范围扫描快 ~30% |
| 二进制大小 | 含 librocksdb | 减小约 50MB | -- |

Pebble 的成功也带动了 etcd（v3.6 计划支持）等其他 Go 项目考虑迁移。

## Bloom Filter：LSM 读性能的救星

Bloom Filter 是 LSM 引擎不可或缺的组件。原因：单点查询在 LSM 中可能需要查找数个甚至数十个 SSTable，每次都要做磁盘 I/O 才能确认 key 是否存在——这在 B+Tree 中是一次 I/O 完成的。

Bloom Filter 让 LSM 可以以约 10 bits/key 的内存代价（约 1% 假阳率）跳过绝大多数不包含目标 key 的 SSTable：

```
未命中 SSTable 的查询代价：
不带 Bloom Filter: O(SSTable 数量 × log(SSTable 大小)) 次磁盘 I/O
带 Bloom Filter:  O(1 次内存访问 + 1% × 上面的代价)
```

实际数据：RocksDB 默认每个 SSTable 的 bloom filter 配置为 10 bits/key，假阳率约 1%。LCS 6 层加起来读放大从 ~6 降到 ~1.06。

进阶技术：

- **Prefix Bloom Filter**：只对 key 前缀建 bloom，节省内存（RocksDB 支持）
- **Ribbon Filter**：RocksDB 6.15+ 引入，比 Bloom 节省 30% 空间
- **Partitioned Bloom Filter**：把大 SSTable 的 bloom filter 分块，避免一次加载整个 filter

### Bloom Filter 配置实战

```sql
-- RocksDB 的 Bloom Filter 配置（通过 options 文件）
[CFOptions "default"]
  bloom_locality=0
  filter_policy=bloomfilter:10:false  -- 10 bits/key, full filter
  whole_key_filtering=true
  optimize_filters_for_hits=true       -- 假设大多数 key 存在
  partition_filters=true               -- 分块 filter，避免一次加载

-- TiKV 的 Bloom Filter 配置
[rocksdb.defaultcf]
  bloom-filter-bits-per-key = 10
  bloom-filter-block-based = false      -- 使用 full filter
  optimize-filters-for-hits = false
```

调优经验：

1. **bits/key 选择**：默认 10 bits/key 给出约 1% 假阳率；提到 16 bits/key 假阳率降到 0.1%，但内存翻倍
2. **whole_key vs prefix**：如果工作负载主要是前缀扫描（如 `user_id:*`），用 prefix bloom 节省内存
3. **partition_filters**：大 SSTable（>1GB）建议开启，避免单次加载 100MB+ filter 阻塞
4. **optimize_filters_for_hits**：如果绝大多数查询都能命中（如点查存在的 key），可以省略最底层的 filter

## 列存：第三条道路

需要强调的是，B+Tree vs LSM 的讨论主要在 OLTP 行存范畴。在 OLAP / 分析场景，列存（Columnar）是完全独立的第三条道路：

- **列存的优势**：列内同质数据压缩率高（通常 5-10x）、向量化执行友好、scan 性能远超行存
- **列存与 LSM 的关系**：列存通常用 LSM 思想组织段（segment），但每个段是列存格式
  - 例：ClickHouse MergeTree、SingleStore Columnstore、Vertica ROS、SAP HANA delta+main
- **列存与 B+Tree 的关系**：传统列存（DuckDB / MonetDB / Snowflake）通常没有 B+Tree，而是用 zone map / min-max index / sparse index 做粗粒度过滤

## 何时选择 B+Tree vs LSM

### 选择 B+Tree 的场景

1. **强一致 OLTP，读多写少**：电商订单、银行账户、ERP——B+Tree 的读延迟更低、更稳定
2. **大量随机点查询**：B+Tree 的 3-4 次 I/O 是确定性的，LSM 即使有 bloom 也有抖动
3. **大量范围扫描，且范围很小**：B+Tree 叶子链表是最快的小范围扫描方式
4. **数据更新频繁，但更新分布集中**：B+Tree 的 in-place update 不会产生废弃版本
5. **二级索引数量少**：B+Tree 写放大小

### 选择 LSM 的场景

1. **写密集，且写分布随机**：日志、监控、IoT、Web 索引——LSM 把随机写转成顺序写
2. **二级索引非常多**：LSM 的二级索引和主索引都共享同一个 LSM 结构，写放大不会线性增长
3. **数据不可变或追加为主**：时序数据 + FIFO 压缩可以做到接近 1x 写放大
4. **存储成本敏感**：LSM Leveled + 压缩可以做到 2-5x 压缩比，远胜 B+Tree
5. **分布式场景**：LSM 的不可变文件天然适合分布式快照、复制和迁移
6. **SSD 磨损敏感**：LSM 的顺序写减少 SSD 的擦除次数

### 何时选择混合方案

1. **HTAP（OLTP + OLAP 混合）**：TiDB（TiKV LSM + TiFlash 列存）、SingleStore、StarRocks
2. **冷热数据分层**：热数据放 B+Tree / 内存，冷数据下沉到 LSM / 列存
3. **多模型数据库**：DocDB（YugabyteDB）在 LSM 之上实现文档模型

## 关键发现

1. **没有银弹**：RUM 三角是不可绕过的物理约束。任何引擎都是在写放大、读放大、空间放大之间做特定权衡的产物。

2. **B+Tree 仍是 OLTP 主流**：50+ 数据库中约 12 个使用纯 B+Tree 作为默认引擎，包括所有四大商业 RDBMS（Oracle / SQL Server / DB2 / Informix）和 PostgreSQL / MySQL。这并非保守，而是 B+Tree 在通用 OLTP 场景下的综合性能确实最优。

3. **LSM 是分布式 SQL 的事实标准**：所有主流 NewSQL（TiDB / CockroachDB / YugabyteDB / OceanBase / Spanner）都选择了 LSM。原因不只是写性能，更是因为 LSM 的不可变文件天然适合分布式快照、Raft 复制和故障恢复。

4. **RocksDB 是 LSM 的事实标准**：从 LevelDB 演化而来的 RocksDB 被几十个项目使用，包括 TiKV、YugabyteDB、Flink、Kafka Streams、CockroachDB（直到 2020）。这证明工业级 LSM 引擎的复杂度极高，重复造轮子代价巨大。

5. **Pebble 代表 Go 生态的成熟**：CockroachDB 在 2020 年从 RocksDB 切换到 Pebble，标志着 Go 语言生态有了媲美 C++ 的存储引擎。Pebble 不仅消除了 cgo 开销，还能针对 CRDB 的 MVCC 模式做精细优化。

6. **压缩策略比引擎选择更重要**：同一个 RocksDB，配置 leveled vs universal 可能导致写放大相差 5x、空间放大相差 3x。生产部署时选对压缩策略往往比选择 B+Tree vs LSM 影响更大。

7. **列存是第三条道路**：50+ 数据库中约 13 个采用列存为默认引擎，主要是 OLAP 系统。列存与 LSM 思想正交——很多列存引擎（ClickHouse / SingleStore / Vertica）在内部用 LSM 思想组织段。

8. **B+Tree 写放大不一定低于 LSM**：当二级索引很多时，B+Tree 的写放大可能超过 LSM Leveled。这是 Facebook 用 MyRocks 替换 InnoDB 节省 50% 存储的根本原因。

9. **Bloom Filter 是 LSM 的命脉**：没有 Bloom Filter 的 LSM 在点查询上几乎无法使用。RocksDB / Pebble 对 Bloom Filter 的精细调优（Prefix Bloom、Ribbon Filter、Partitioned Filter）是 LSM 工程实践的核心。

10. **OceanBase 的"每日合并"是独特设计**：与 RocksDB 系不同，OceanBase 把所有合并操作集中在凌晨低峰期执行，避免持续后台 IO 干扰白天的 OLTP，这是为银行核心系统专门设计的取舍。

11. **WiredTiger 的双引擎实验是反例**：MongoDB 在 3.x 提供 B+Tree 和 LSM 两种存储格式，但实际使用中绝大多数用户选择 B+Tree，LSM 选项后来被淡化。这印证了"对绝大多数工作负载，B+Tree 仍然更好"。

12. **WAL 是两种引擎共同的命门**：无论 B+Tree 还是 LSM，都需要 WAL 保证持久性。WAL 的设计（同步策略、批量提交、组提交）往往是性能瓶颈，与存储引擎的选择无关。

13. **学习索引（Learned Index）尚未实用化**：Kraska et al. 2018 提出用神经网络替代 B+Tree，理论上更紧凑、更快，但截至 2026 年仍未在主流数据库中落地。原因：训练成本、更新困难、可解释性差。

14. **LakeHouse 是 LSM 思想的延伸**：Iceberg / Delta Lake / Hudi 在对象存储上实现的 ACID 表，本质是 LSM 思想（不可变文件 + 元数据合并）在分布式文件系统上的应用。LSM 的影响早已超出单机数据库的范畴。

15. **未来的方向是分离式架构**：Aurora / Socrates / RisingWave Hummock 等分离式数据库把存储引擎拆解为"计算节点 + 共享日志 + 共享存储"，B+Tree vs LSM 的传统二分法需要重新审视。在 S3 上做 LSM（如 Hummock）和在 EBS 上做 B+Tree（如 Aurora）是两种截然不同的设计哲学。

## 参考资料

- O'Neil, P., Cheng, E., Gawlick, D., O'Neil, E. (1996). *The Log-Structured Merge-Tree (LSM-Tree)*. Acta Informatica.
- Chang, F., et al. (2006). *Bigtable: A Distributed Storage System for Structured Data*. OSDI.
- Athanassoulis, M., et al. (2016). *Designing Access Methods: The RUM Conjecture*. EDBT.
- Dong, S., et al. (2017). *Optimizing Space Amplification in RocksDB*. CIDR.
- Matsunobu, Y., Dong, S., Lee, H. (2020). *MyRocks: LSM-Tree Database Storage Engine Serving Facebook's Social Graph*. VLDB.
- Huang, D., et al. (2020). *TiDB: A Raft-based HTAP Database*. VLDB.
- CockroachDB Blog (2020). *Pebble: A RocksDB Inspired Key-Value Store Written in Go*.
- Yang, Z., et al. (2022). *OceanBase: A 707 Million tpmC Distributed Relational Database System*. VLDB.

## 相关阅读

- [可插拔存储引擎](pluggable-storage-engines.md) - 存储引擎插件化机制对比
- [采样查询 (TABLESAMPLE)](sampling-query.md) - 不同存储引擎的采样支持
