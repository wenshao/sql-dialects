# 分片键与分布键 (Shard Key and Distribution Key)

在分布式数据库中，分布键（distribution key）的选择是整个系统设计中**最重要的单一决策**——它一次性决定了数据在节点间的物理布局、JOIN 是否需要 shuffle、聚合是否能下推、热点是否会出现、扩容时要搬多少 TB 数据。一个错误的分布键，可能让一个 100 节点的集群表现得比单机 PostgreSQL 还慢；而一个正确的分布键，可以让 PB 级 JOIN 变成秒级返回。

本文聚焦于**跨节点分布**（cross-node distribution），与姊妹篇 [partition-strategy-comparison.md](./partition-strategy-comparison.md) 互补——后者讨论单实例内的分区（partition），本文讨论的是数据如何被切分到不同的物理节点。两者经常被混用，但语义截然不同：分区是逻辑切分（pruning 加速），分布是物理切分（并行加速 + 数据局部性）。

## 为什么分布键如此关键

一个分布式数据库的所有性能特征，几乎都可以从分布键推导出来：

1. **数据均匀性**：分布键决定哪些行去哪个节点。坏的键 → 数据倾斜 → 单节点成为瓶颈
2. **JOIN shuffle**：两表 JOIN 时，如果按相同键分布，则可以本地 JOIN（co-located join）；否则需要跨网络 shuffle 整张表
3. **聚合下推**：GROUP BY 列与分布键一致时，每个节点本地聚合即可，无需全局合并
4. **写入热点**：递增主键作为分布键 → 所有写入打到一个节点；哈希分布 → 写入均匀
5. **扩容代价**：扩容时要重新分布数据。分布算法（一致性哈希 vs 取模）决定数据搬迁量
6. **查询并行度**：点查只命中一个节点（最快），全表查询打散到所有节点（最大并行度）

由于分布键通常**建表时确定且难以修改**，错误的选择往往意味着重建整个集群。这就是为什么 Greenplum、Redshift、Citus 等系统的官方文档都将"选择分布键"作为头号设计章节。

## 支持矩阵（综合）

### 分布语法与基础能力

| 引擎 | DISTRIBUTE BY 语法 | 哈希分布 | 范围分布 | 列表分布 | 复制表/广播 | Co-location | 多列分布键 | 主键即分布键 | 版本 |
|------|-------------------|---------|---------|---------|-----------|------------|-----------|------------|------|
| PostgreSQL | -- | -- | -- | -- | -- | -- | -- | -- | 单机 |
| MySQL | -- | -- | -- | -- | -- | -- | -- | -- | 单机 |
| MariaDB | -- | -- | -- | -- | -- | -- | -- | -- | 单机 |
| SQLite | -- | -- | -- | -- | -- | -- | -- | -- | 单机 |
| Oracle | `BY HASH/RANGE/LIST` (Sharding 选项) | 是 | 是 | 是 | DUPLICATED | 是 | 是 | 可选 | 12.2+ |
| SQL Server | -- (PDW: `DISTRIBUTION = HASH/REPLICATE/ROUND_ROBIN`) | 是 | -- | -- | REPLICATE | 是 | -- | 可选 | PDW |
| DB2 | `DISTRIBUTE BY HASH` | 是 | -- | -- | -- | 是 | 是 | 可选 | DPF |
| Snowflake | -- (隐式) | 内部 | -- | -- | -- | 自动 | -- | -- | GA |
| BigQuery | `CLUSTER BY` (非分布) | -- | -- | -- | -- | -- | -- | -- | GA |
| Redshift | `DISTSTYLE KEY DISTKEY(col)` | 是 | -- | -- | DISTSTYLE ALL | 是 | 单列 | 可选 | GA |
| DuckDB | -- | -- | -- | -- | -- | -- | -- | -- | 单机 |
| ClickHouse | `Distributed(..., sharding_key)` | 是 | rand() | -- | -- | 手动 | 表达式 | 可选 | 早期 |
| Trino | -- (依赖底层) | 透传 | -- | -- | -- | 透传 | -- | -- | -- |
| Presto | -- (依赖底层) | 透传 | -- | -- | -- | 透传 | -- | -- | -- |
| Spark SQL | `DISTRIBUTE BY` (查询级) | 是 | `CLUSTER BY` | -- | broadcast hint | 是 | 是 | -- | 1.4+ |
| Hive | `CLUSTERED BY ... INTO N BUCKETS` | 是 | -- | -- | -- | 桶级 | 是 | -- | 0.7+ |
| Flink SQL | -- (key-by 概念) | 是 | -- | -- | broadcast | 是 | 是 | -- | -- |
| Databricks | `DISTRIBUTE BY` (查询级) | 是 | -- | -- | broadcast hint | Liquid Clustering | 是 | -- | GA |
| Teradata | `PRIMARY INDEX (col)` | 是 | -- | -- | -- | 是 | 是 | 可选 | 早期 |
| Greenplum | `DISTRIBUTED BY/REPLICATED/RANDOMLY` | 是 | -- | -- | REPLICATED | 是 | 是 | 默认 | 早期 |
| CockroachDB | -- (主键自动) | 隐式哈希 | 主键范围 | -- | `GLOBAL` 表 | 是 | 主键 | 是 | GA |
| TiDB | -- (Region 自动) | -- | 自动 | -- | -- | 部分 | -- | 是 | GA |
| OceanBase | `PARTITION BY` + 复制表 | 是 | 是 | 是 | DUPLICATE | 是 | 是 | 可选 | 早期 |
| YugabyteDB | `PRIMARY KEY (c HASH/ASC)` | 是 | 是 | -- | colocated table | 是 | 是 | 是 | GA |
| SingleStore | `SHARD KEY (col)` / `REFERENCE` | 是 | -- | -- | REFERENCE | 是 | 是 | 默认 | 早期 |
| Vertica | `SEGMENTED BY HASH(col) ALL NODES` / `UNSEGMENTED ALL NODES` | 是 | -- | -- | UNSEGMENTED | 是 | 是 | 可选 | 早期 |
| Impala | (依赖 Kudu/HDFS) | Kudu HASH | Kudu RANGE | -- | -- | 是 | 是 | 是 | 2.6+ |
| StarRocks | `DISTRIBUTED BY HASH/RANDOM` | 是 | 是 (3.0+) | -- | -- | Colocate Group | 是 | 可选 | GA |
| Doris | `DISTRIBUTED BY HASH/RANDOM` | 是 | -- | -- | -- | Colocate Group | 是 | 可选 | GA |
| MonetDB | -- | -- | -- | -- | -- | -- | -- | -- | 单机为主 |
| CrateDB | `CLUSTERED BY (col) INTO N SHARDS` | 是 | -- | -- | -- | -- | 单列 | 默认 | 早期 |
| TimescaleDB | (依赖 Citus / Multinode) | 是 | 时间 | -- | reference | 是 | 是 | 可选 | 2.x |
| QuestDB | -- | -- | -- | -- | -- | -- | -- | -- | 单机 |
| Exasol | `DISTRIBUTE BY` | 是 | -- | -- | small table replication 自动 | 是 | 是 | 可选 | 早期 |
| SAP HANA | `PARTITION BY HASH/RANGE/ROUNDROBIN` | 是 | 是 | -- | replicated table | 是 | 是 | 可选 | 早期 |
| Informix | -- (Fragmentation: BY EXPRESSION/HASH/ROUND ROBIN) | 是 | 是 | -- | -- | -- | 是 | 可选 | 早期 |
| Firebird | -- | -- | -- | -- | -- | -- | -- | -- | 单机 |
| H2 | -- | -- | -- | -- | -- | -- | -- | -- | 单机 |
| HSQLDB | -- | -- | -- | -- | -- | -- | -- | -- | 单机 |
| Derby | -- | -- | -- | -- | -- | -- | -- | -- | 单机 |
| Amazon Athena | -- (S3 文件) | -- | -- | -- | -- | -- | -- | -- | -- |
| Azure Synapse | `DISTRIBUTION = HASH/REPLICATE/ROUND_ROBIN` | 是 | -- | -- | REPLICATE | 是 | 单列 | 可选 | GA |
| Google Spanner | `INTERLEAVE IN PARENT` + 主键范围 | -- | 主键 | -- | -- | 是 | 主键 | 是 | GA |
| Materialize | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| RisingWave | (内部 vnode 分布) | 是 | -- | -- | -- | distribution key | 是 | 是 | GA |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| DatabendDB | (cluster key, 非分布) | -- | -- | -- | -- | -- | -- | -- | GA |
| Yellowbrick | `DISTRIBUTE ON (col) / REPLICATE / RANDOM` | 是 | -- | -- | REPLICATE | 是 | 是 | 可选 | GA |
| Firebolt | `PRIMARY INDEX` (类似 cluster) | -- | -- | -- | -- | -- | -- | -- | GA |

> 注: 单机数据库（PostgreSQL、MySQL、SQLite 等）本身没有跨节点分布概念，需要借助扩展（如 Citus）或中间件（如 Vitess、ShardingSphere）实现分布式。
>
> 统计：约 25 个引擎在原生层面支持显式跨节点分布键定义，约 15 个为单机数据库（不适用），其余通过外部分片层实现。

### 自动分片与重平衡

| 引擎 | 自动分片 | 重平衡 | 重平衡触发 | 数据搬迁代价 | 在线扩容 | 分片粒度 |
|------|---------|--------|----------|------------|---------|---------|
| Greenplum | -- (建表确定) | 手动 `gpexpand` | 扩容时 | 全量重分布 | 部分在线 | 按段 (segment) |
| Redshift | RA3 自动 | 自动 | 自动 | 数据存 S3，移动元数据 | 是 | RA3 自动管理 |
| Vertica | -- | 手动 `REBALANCE_CLUSTER` | 节点变更 | 取决于段策略 | 是 | segment |
| Citus | -- | `rebalance_table_shards()` | 手动 | 移动单个 shard | 是 | shard (默认 32) |
| TiDB | 是 (Region 自动分裂) | 自动 (PD 调度) | 持续 | Region 级（96MB） | 是 | Region 96MB |
| CockroachDB | 是 (Range 自动分裂) | 自动 | 持续 | Range 级（512MB 默认） | 是 | Range 512MB |
| YugabyteDB | 是 (Tablet 分裂) | 自动 | 持续 | Tablet 级 | 是 | Tablet |
| Snowflake | 是 (micropartition) | 自动 (云存储抽象) | 不需要 | 计算存储分离 | 即时 | micropartition 16MB |
| BigQuery | 是 | 自动 | -- | 不暴露 | 即时 | 内部 |
| Spanner | 是 (split 自动分裂) | 自动 | 持续 | split 级 | 是 | split |
| ClickHouse | -- | 手动 | 扩容时 | 全量 | 部分 | 手动 |
| StarRocks | -- | 手动 / 自动 (3.0+) | 节点变更 | tablet 级 | 是 | tablet |
| Doris | -- | 自动 | 节点变更 | tablet 级 | 是 | tablet |
| OceanBase | 是 | 自动 | 持续 | partition 级 | 是 | partition |
| SingleStore | -- | `REBALANCE PARTITIONS` | 手动 | partition 级 | 是 | partition |
| Azure Synapse | -- (60 个固定 distribution) | -- | -- | -- | 是 (调整 DWU) | 60 distributions |

> 关键观察：自动分片系统（TiDB / CockroachDB / Spanner / YugabyteDB）通常基于**range split**，无需用户指定分片数；MPP 系统（Greenplum / Redshift / Vertica）则要求建表时显式声明分布键，扩容代价更高。

## 五种分布策略

分布式数据库有五种核心策略，每个引擎都是这五种的子集组合。

### 1. 哈希分布（Hash Distribution）

最常用。对分布列计算哈希，按节点数取模或一致性哈希映射到节点。

```sql
-- Greenplum
CREATE TABLE orders (id BIGINT, user_id BIGINT, amount NUMERIC)
DISTRIBUTED BY (user_id);

-- Redshift
CREATE TABLE orders (id BIGINT, user_id BIGINT, amount NUMERIC)
DISTSTYLE KEY DISTKEY (user_id);

-- Citus
SELECT create_distributed_table('orders', 'user_id');

-- Vertica
CREATE TABLE orders (id INT, user_id INT, amount NUMERIC)
SEGMENTED BY HASH(user_id) ALL NODES;

-- StarRocks / Doris
CREATE TABLE orders (id BIGINT, user_id BIGINT, amount DECIMAL(18,2))
DISTRIBUTED BY HASH(user_id) BUCKETS 32;
```

特点：分布均匀（哈希函数好的话），点查极快（只命中一个节点），但**范围查询要扫所有节点**。

### 2. 范围分布（Range Distribution）

按分布列值的连续范围切分。常见于按时间或主键切分。

```sql
-- CockroachDB（隐式：主键就是范围分布）
CREATE TABLE events (
    ts TIMESTAMP,
    id UUID,
    payload JSONB,
    PRIMARY KEY (ts, id)
);
-- CockroachDB 自动按 ts 进行 range split

-- YugabyteDB（显式 ASC 即范围）
CREATE TABLE events (
    ts TIMESTAMP,
    id UUID,
    payload JSONB,
    PRIMARY KEY (ts ASC, id ASC)
);

-- StarRocks 3.0+
CREATE TABLE orders (id BIGINT, dt DATE, amount DECIMAL)
DISTRIBUTED BY RANGE(dt) BUCKETS 16;
```

特点：范围查询高效（只扫部分节点），但**容易产生写入热点**（递增时间戳全打到最后一个节点）。CockroachDB 用 hash-sharded index 缓解：`PRIMARY KEY (ts, id) USING HASH WITH BUCKET_COUNT = 16`。

### 3. 列表分布（List Distribution）

按列值精确匹配某个列表分到指定节点。多用于多租户场景，把租户固定到特定节点。

```sql
-- Oracle Sharding
CREATE SHARDED TABLE customers (
    id NUMBER, region VARCHAR2(20), name VARCHAR2(100)
) PARTITION BY LIST (region) (
    PARTITION p_us VALUES ('US') TABLESPACE ts_us,
    PARTITION p_eu VALUES ('EU') TABLESPACE ts_eu,
    PARTITION p_ap VALUES ('AP') TABLESPACE ts_ap
);

-- OceanBase
CREATE TABLE orders (id BIGINT, region VARCHAR(20))
PARTITION BY LIST COLUMNS(region) (
    PARTITION p1 VALUES IN ('CN'),
    PARTITION p2 VALUES IN ('US'),
    PARTITION p3 VALUES IN ('EU')
);
```

特点：业务语义清晰，地理就近访问；但维护成本高，数据可能严重倾斜。

### 4. 复制表 / 广播表（Replicated / Broadcast Table）

每个节点保存一份完整数据。适合小维度表（如国家、币种、配置）。

```sql
-- Greenplum 6.0+
CREATE TABLE country_dim (code CHAR(2), name VARCHAR(100))
DISTRIBUTED REPLICATED;

-- Redshift
CREATE TABLE country_dim (code CHAR(2), name VARCHAR(100))
DISTSTYLE ALL;

-- Vertica
CREATE TABLE country_dim (code CHAR(2), name VARCHAR(100))
UNSEGMENTED ALL NODES;

-- Citus
SELECT create_reference_table('country_dim');

-- SingleStore
CREATE REFERENCE TABLE country_dim (code CHAR(2), name VARCHAR(100));

-- OceanBase
CREATE TABLE country_dim (code CHAR(2), name VARCHAR(100)) DUPLICATE_SCOPE='cluster';

-- Azure Synapse
CREATE TABLE country_dim (...) WITH (DISTRIBUTION = REPLICATE);
```

特点：JOIN 时无需 shuffle（每个节点本地都有），但**写入要广播到所有节点**，更新昂贵。仅适合 << 1GB 的维表。

### 5. 随机 / 轮询分布（Random / Round-Robin）

无明确分布键时的兜底方案。

```sql
-- Greenplum
CREATE TABLE staging (...) DISTRIBUTED RANDOMLY;

-- Redshift（自动选择）
CREATE TABLE staging (...) DISTSTYLE EVEN;

-- StarRocks 2.5+
CREATE TABLE staging (...) DISTRIBUTED BY RANDOM BUCKETS 32;

-- Azure Synapse
CREATE TABLE staging (...) WITH (DISTRIBUTION = ROUND_ROBIN);
```

特点：数据均匀，但**任何 JOIN 都需要 shuffle**，性能极差。仅用于临时表 / staging 表。

## 各引擎详解

### Greenplum（DISTRIBUTED BY 的鼻祖）

Greenplum 是 MPP 数据库的代表，其 `DISTRIBUTED BY` 语法被许多后续系统（Redshift、Citus）借鉴。

```sql
-- 哈希分布（最常用）
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    amount NUMERIC,
    order_date DATE
) DISTRIBUTED BY (user_id);

-- 多列分布键
CREATE TABLE order_items (
    order_id BIGINT,
    item_id BIGINT,
    qty INT
) DISTRIBUTED BY (order_id, item_id);

-- 复制表（6.0+，适合小维表）
CREATE TABLE region (
    region_id INT, region_name TEXT
) DISTRIBUTED REPLICATED;

-- 随机分布（staging / 无主键场景）
CREATE TABLE log_raw (...) DISTRIBUTED RANDOMLY;

-- 不指定分布键时的默认行为：
--   - 有主键: 默认使用主键的第一列作为分布键
--   - 无主键: 默认 DISTRIBUTED RANDOMLY
-- 这是历史遗留——早期版本无 PK 时默认用第一列，6.0 改为 RANDOMLY
```

Greenplum 关键设计：
- **段（segment）**：每台 host 上多个 segment 进程，每个 segment 是一个独立 PostgreSQL 实例
- **数据分布**：分布键 hash → segment id（取模）
- **JOIN 优化**：相同分布键的两表可以做 co-located join（无需 motion）
- **gpexpand**：扩容工具，需要重新计算每行的目标 segment 并搬迁数据，期间可读不可写部分表

### Redshift（DISTKEY + DISTSTYLE，最经典的四选一）

Redshift 的 `DISTSTYLE` 是 AWS 数据仓库设计中最被讨论的选项之一。

```sql
-- KEY: 哈希分布
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    amount NUMERIC
)
DISTSTYLE KEY
DISTKEY (user_id)
SORTKEY (order_date);

-- ALL: 复制到所有节点（小维表）
CREATE TABLE region (region_id INT, region_name VARCHAR(50))
DISTSTYLE ALL;

-- EVEN: 轮询，无分布键
CREATE TABLE staging (...) DISTSTYLE EVEN;

-- AUTO: 由 Redshift 自动选择（2019+ 默认）
-- 小表 → ALL，写入增大后 → EVEN，再后 → KEY（如可识别）
CREATE TABLE auto_table (id BIGINT, val TEXT) DISTSTYLE AUTO;
```

#### DISTSTYLE 四种选项深度对比

**ALL（复制到所有节点）**

每个 compute node 都保存完整副本。

- 优势：与任何分布的表 JOIN 都不需要 shuffle
- 代价：存储 × 节点数；写入成本 × 节点数
- 适用：< 几百万行的维表，**只读 / 极少更新**
- 典型规模：dim_currency、dim_country、dim_calendar

**EVEN（轮询）**

按行分配，循环放到各 slice。

- 优势：完美均匀，无倾斜
- 劣势：所有 JOIN 都要 redistribute，所有 GROUP BY 也要 shuffle
- 适用：临时表、staging、无 JOIN 的纯扫描表

**KEY（按列哈希）**

最常用。指定一列作为 DISTKEY，按其哈希分布。

- 优势：相同 DISTKEY 的表 JOIN 无 shuffle（co-located）
- 关键约束：**只能单列**，不支持多列 DISTKEY
- 选键原则：
  1. 高基数（避免倾斜）
  2. JOIN 频繁的列
  3. 不是常被过滤的列（否则查询打到一个节点）
- 反例：`DISTKEY(status)` 只有 5 个值 → 严重倾斜

**AUTO（2019+ 默认）**

Redshift 根据表大小动态切换：

- 表很小：使用 ALL
- 增长后：切换到 EVEN
- 检测到合适列：可能升级为 KEY
- 切换过程对用户透明，但有迁移开销

#### 倾斜检测

```sql
-- 检查表的数据分布倾斜
SELECT slice, COUNT(*)
FROM stv_blocklist b
JOIN stv_tbl_perm p ON b.tbl = p.id
WHERE p.name = 'orders'
GROUP BY slice
ORDER BY 2 DESC;

-- 倾斜系数 > 4 就要重新选择 DISTKEY
```

### Vertica（SEGMENTED BY HASH）

Vertica 使用 segmentation 概念，与 projection（物化视图）紧密结合。

```sql
-- 默认 projection 的分布
CREATE TABLE orders (
    order_id INT, user_id INT, amount NUMERIC
)
ORDER BY order_date
SEGMENTED BY HASH(user_id) ALL NODES;

-- 复制表
CREATE TABLE region (region_id INT, name VARCHAR)
UNSEGMENTED ALL NODES;

-- 多 projection（同表不同分布键）
CREATE PROJECTION orders_by_user AS
SELECT * FROM orders
ORDER BY user_id
SEGMENTED BY HASH(user_id) ALL NODES;

CREATE PROJECTION orders_by_date AS
SELECT * FROM orders
ORDER BY order_date
SEGMENTED BY HASH(order_id) ALL NODES;
```

Vertica 特点：
- **K-Safety**：通过 buddy projection 提供 HA，每个 segment 在多个节点有副本
- **多 projection**：同一张表可以有多个 projection，每个用不同分布键。优化器会自动选最优
- **REBALANCE_CLUSTER()**：节点变更时手动触发重平衡

### Citus（PostgreSQL 的分布式扩展）

Citus 是 Microsoft 收购的 PG 扩展，将单机 PG 变成分布式系统。

```sql
-- 创建分布式表
CREATE TABLE orders (id BIGINT, user_id BIGINT, amount NUMERIC);
SELECT create_distributed_table('orders', 'user_id');

-- 创建引用表（小维表，复制到所有 worker）
CREATE TABLE country (code CHAR(2), name TEXT);
SELECT create_reference_table('country');

-- co-location group：多张表用同一分布键，物理同位
SELECT create_distributed_table('users', 'user_id');
SELECT create_distributed_table('orders', 'user_id', colocate_with => 'users');
SELECT create_distributed_table('payments', 'user_id', colocate_with => 'users');
-- 三张表的同 user_id 行保证在同一个 worker 上 → JOIN 无 shuffle

-- 重平衡
SELECT rebalance_table_shards('orders');

-- 默认 32 个 shard，每个 shard 是 worker 上的一个普通 PG 表
SHOW citus.shard_count;
```

Citus 设计要点：
- **shard 抽象**：每张分布表被切成 32（默认）个 shard，shard 是迁移单位
- **co-location**：通过共享 shard 数和 hash 函数，确保相同分布键的不同表行物理同位
- **reference table**：复制到每个 worker，与任意分布表都可以 co-located join

### TiDB（自动 Region 分片）

TiDB 不需要显式指定分布键——所有表被自动按主键范围切成 Region（默认 96MB），由 PD（Placement Driver）调度。

```sql
-- 普通表，无需 DISTRIBUTE BY
CREATE TABLE orders (
    id BIGINT PRIMARY KEY AUTO_RANDOM,
    user_id BIGINT,
    amount DECIMAL(18,2)
);

-- AUTO_RANDOM 替代 AUTO_INCREMENT，避免单调递增主键导致写热点
-- 内部把 ID 高位打散，让 Region 分裂均匀

-- SHARD_ROW_ID_BITS：对无主键表使用 _tidb_rowid 时打散
CREATE TABLE log (data TEXT) SHARD_ROW_ID_BITS = 4;
-- 高 4 bit 随机化，分布到 16 个 Region 区间

-- PRE_SPLIT_REGIONS：预分裂 Region 避免冷启动热点
CREATE TABLE events (...) SHARD_ROW_ID_BITS = 4 PRE_SPLIT_REGIONS = 4;
```

TiDB 设计：
- **Region**：键空间按字节序切分，每个 96MB（可配）
- **自动分裂**：Region 增长超阈值时自动分裂；持续访问热点也会分裂
- **PD 调度**：监控 Region size、QPS、leader 分布，自动均衡
- **缺点**：递增主键（如 AUTO_INCREMENT）会导致所有写入打到最后一个 Region，必须用 AUTO_RANDOM 或 SHARD_ROW_ID_BITS

### CockroachDB（主键 Range 分布）

CockroachDB 使用 range 分布：所有数据按主键字节序切成 Range（默认 512MB），自动分裂迁移。

```sql
-- 主键即决定分布
CREATE TABLE orders (
    user_id INT,
    order_id INT,
    amount DECIMAL,
    PRIMARY KEY (user_id, order_id)
);
-- 按 (user_id, order_id) 字节序切分

-- hash-sharded index：主键值前加 hash bucket，避免热点
CREATE TABLE events (
    ts TIMESTAMP,
    id UUID,
    PRIMARY KEY (ts, id) USING HASH WITH BUCKET_COUNT = 16
);
-- 内部相当于 PRIMARY KEY (hash_bucket(ts) % 16, ts, id)
-- 时间递增写入会打散到 16 个不同 Range

-- locality 控制（多区域部署）
CREATE TABLE users (...) LOCALITY REGIONAL BY ROW;
ALTER TABLE users SET LOCALITY GLOBAL;  -- 全球只读高可用表
```

CockroachDB 关键特性：
- **Range 默认 512MB**：超过分裂，过小合并
- **副本**：每个 Range 通过 Raft 复制到 3+ 副本
- **multi-region**：支持 REGIONAL BY ROW（按行分配区域）和 GLOBAL（全球复制）

### YugabyteDB（HASH vs ASC，显式选择）

YugabyteDB 让用户在主键列级别**显式选择**哈希还是范围分布，这是它与 CockroachDB 的核心区别。

```sql
-- HASH：第一列哈希分布（兼容 Cassandra 风格）
CREATE TABLE orders (
    user_id INT,
    order_id INT,
    amount DECIMAL,
    PRIMARY KEY ((user_id) HASH, order_id ASC)
);
-- (user_id) 双括号 = 哈希分区列，order_id = 同 user_id 内的范围

-- ASC：纯范围分布（兼容 PostgreSQL 风格）
CREATE TABLE events (
    ts TIMESTAMP,
    id UUID,
    PRIMARY KEY (ts ASC, id ASC)
);

-- colocated table：小表共享一个 tablet，避免分布开销
CREATE DATABASE myapp WITH colocated = true;
CREATE TABLE small_dim (...);  -- 自动 colocated
CREATE TABLE large_fact (...) WITH (colocated = false);  -- 显式分布
```

YugabyteDB 优势：开发者明确知道每张表是哈希还是范围分布，不像 CockroachDB 全是范围（隐式有热点风险）。

### Snowflake（micropartition + 隐式分布）

Snowflake 完全隐藏分片概念。数据被自动切成 micropartition（压缩后 50-500MB），存储在云对象存储中，**不暴露分布键**。

```sql
-- 没有 DISTRIBUTE BY 语法
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    amount NUMBER(18,2),
    order_date DATE
);

-- 但可以指定 clustering key（影响 micropartition 内部组织）
CREATE TABLE orders (...) CLUSTER BY (order_date, user_id);

-- Automatic Clustering 服务在后台维护 clustering
-- 注意：clustering key 不是分布键，它影响的是数据本地性而非节点分布
```

Snowflake 关键点：
- **存算分离**：数据在 S3，计算节点（virtual warehouse）按需缓存
- **micropartition**：自动按写入顺序切分，约 16MB 压缩
- **clustering key**：类似 BigQuery 的 cluster，提升 partition pruning 效果
- **shared-nothing 假象**：底层是 shared-disk，因此不需要 DISTKEY

### BigQuery（PARTITION + CLUSTER，无显式分布键）

```sql
CREATE TABLE orders (
    order_id INT64,
    user_id INT64,
    amount NUMERIC,
    order_date DATE
)
PARTITION BY order_date
CLUSTER BY user_id, status;
```

- **PARTITION BY**：按列分区（pruning 用），最多一列
- **CLUSTER BY**：按列在分区内排序（最多 4 列）
- 数据分片由 Google 内部 Colossus 文件系统管理，不暴露
- 无 DISTKEY，无需用户决策

### Spanner（Interleaving + 主键范围）

```sql
-- 父表
CREATE TABLE Customers (
    CustomerId INT64 NOT NULL,
    Name STRING(100)
) PRIMARY KEY (CustomerId);

-- 子表 interleave 在父表内（物理同位）
CREATE TABLE Orders (
    CustomerId INT64 NOT NULL,
    OrderId INT64 NOT NULL,
    Amount NUMERIC
) PRIMARY KEY (CustomerId, OrderId),
  INTERLEAVE IN PARENT Customers ON DELETE CASCADE;
-- Customer 1 的 Orders 与 Customer 1 行物理相邻
-- Spanner 自动 split 时保证父子在同一 split
```

Spanner 设计：
- **split**：按主键范围自动切分，类似 CockroachDB
- **interleaving**：父子表物理同位，JOIN 无 shuffle
- **TrueTime**：通过原子钟保证全局一致性，跨 split 事务也快

### ClickHouse（Distributed 表 + sharding_key）

ClickHouse 的分布式是"虚拟表"模式——本地表 + Distributed 表的组合。

```sql
-- 1. 在每个节点创建本地表
CREATE TABLE orders_local ON CLUSTER my_cluster (
    order_id UInt64,
    user_id UInt64,
    amount Decimal(18,2)
) ENGINE = MergeTree()
ORDER BY order_id;

-- 2. 创建 Distributed 表（不存数据，仅路由）
CREATE TABLE orders ON CLUSTER my_cluster
AS orders_local
ENGINE = Distributed(my_cluster, default, orders_local, user_id);
-- 第四个参数 user_id 就是 sharding_key

-- 写入 Distributed 表会按 user_id 路由到对应 shard
-- 也可以用表达式：sharding_key = cityHash64(user_id) % 10
```

ClickHouse 特点：
- **无自动重平衡**：扩容时旧数据不会自动搬迁，需要手动 INSERT SELECT
- **sharding_key 可任意表达式**：rand()、cityHash64(col)、modulo
- **Replicated\*MergeTree**：通过 ZooKeeper 实现副本同步

### StarRocks / Doris（DISTRIBUTED BY HASH/RANDOM）

StarRocks（Apache Doris 的商业 fork）和 Apache Doris 共享相似语法。

```sql
-- StarRocks
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    amount DECIMAL(18,2),
    order_date DATE
)
DUPLICATE KEY(order_id)
PARTITION BY RANGE(order_date) (
    PARTITION p202401 VALUES LESS THAN ('2024-02-01'),
    PARTITION p202402 VALUES LESS THAN ('2024-03-01')
)
DISTRIBUTED BY HASH(user_id) BUCKETS 32;

-- StarRocks 2.5+ 支持 RANDOM 分布
CREATE TABLE log (...) DISTRIBUTED BY RANDOM BUCKETS 32;

-- StarRocks 3.0+ 支持自动分桶（无需指定 BUCKETS 数量）
CREATE TABLE auto (...) DISTRIBUTED BY HASH(id);

-- Colocate Group：跨表 co-location
CREATE TABLE users (...) DISTRIBUTED BY HASH(user_id) BUCKETS 32
PROPERTIES("colocate_with" = "user_group");

CREATE TABLE orders (...) DISTRIBUTED BY HASH(user_id) BUCKETS 32
PROPERTIES("colocate_with" = "user_group");
-- 同一 colocate group 的表，相同 hash 值的 tablet 在同一 BE 节点
```

### OceanBase（分区 + 主可用区）

```sql
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    amount DECIMAL(18,2)
)
PARTITION BY HASH(user_id) PARTITIONS 32;

-- 复制表（小维表）
CREATE TABLE country (
    code CHAR(2), name VARCHAR(100)
) DUPLICATE_SCOPE='cluster';

-- 表组（table group）：保证多张表的同号分区在同一节点
CREATE TABLEGROUP tg1 PARTITION BY HASH PARTITIONS 32;
CREATE TABLE users (...) TABLEGROUP tg1 PARTITION BY HASH(user_id) PARTITIONS 32;
CREATE TABLE orders (...) TABLEGROUP tg1 PARTITION BY HASH(user_id) PARTITIONS 32;
```

OceanBase 特点：
- **primary zone**：每张表可指定主可用区，写入路由到该区域
- **table group**：类似 Citus co-location，跨表分区对齐
- **paxos 副本**：跨可用区强一致

### SingleStore（SHARD KEY，主键即默认）

```sql
-- 显式 SHARD KEY
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    amount DECIMAL(18,2),
    SHARD KEY (user_id)
);

-- 不指定 SHARD KEY 时，主键自动作为 SHARD KEY
CREATE TABLE users (
    user_id BIGINT PRIMARY KEY,
    name VARCHAR(100)
);
-- 等价于 SHARD KEY (user_id)

-- REFERENCE 表（每个 leaf 节点都有一份）
CREATE REFERENCE TABLE country (
    code CHAR(2) PRIMARY KEY,
    name VARCHAR(100)
);
```

## Co-location：JOIN 消除 shuffle 的关键

**Co-location**（数据同位）是分布式数据库性能的关键优化：当两张表按相同列哈希分布且 hash 函数相同时，它们的相同 key 行物理上在同一个节点，JOIN 时不需要任何网络传输。

```sql
-- Citus 示例
SELECT create_distributed_table('users', 'user_id');
SELECT create_distributed_table('orders', 'user_id', colocate_with => 'users');

-- 这个 JOIN 不需要 shuffle：
SELECT u.name, SUM(o.amount)
FROM users u JOIN orders o ON u.user_id = o.user_id
GROUP BY u.name;
-- 每个 worker 上：本地 users 与本地 orders join，本地聚合
-- 最后只需在 coordinator 合并各 worker 的最终结果
```

### 不同 co-location 策略下的 JOIN 代价

| 策略 | 网络代价 | 适用 |
|------|---------|------|
| 同分布键 (co-located) | 0 | 最优，JOIN 时只在本地 |
| 一表广播 (broadcast) | 小表 × 节点数 | 一边是小表 / 引用表 |
| 重分布 (repartition) | 大表 shuffle | 两边都大且分布键不同 |
| 笛卡尔积 (broadcast both) | 大表 × 节点数 | 灾难，应避免 |

### co-location 实现要点

1. **同 hash 函数**：必须使用一致的 hash 实现（不同算法即使同 key 也分到不同节点）
2. **同 shard 数**：32 vs 64 即使同 hash 也无法 co-locate
3. **同 hash 列数据类型**：BIGINT 与 INT 混用可能导致 hash 不一致
4. **同副本拓扑**：副本数和节点选择策略需一致

### 哪些查询能享受 co-location

- 等值 JOIN（`a.k = b.k`，k 是分布键）
- GROUP BY 包含分布键
- DISTINCT 包含分布键
- Window 函数 PARTITION BY 包含分布键

不能享受 co-location 的：
- 范围 JOIN
- 不等值 JOIN
- 分布键不同的两表 JOIN
- 任何涉及 OUTER JOIN + 分布键为 NULL 的列

## 关键发现

### 1. 三大范式：MPP / 自动分片 / 隐藏式

经过对 45+ 数据库的分析，跨节点分布可以划分为三种范式：

- **MPP 范式**（Greenplum / Redshift / Vertica / Synapse / Citus / SingleStore / StarRocks / Doris）：建表时显式声明分布键，扩容代价高，但用户对分布有完全控制
- **自动分片范式**（TiDB / CockroachDB / Spanner / YugabyteDB / OceanBase）：基于 range / region 自动分裂，扩容透明，但需要小心主键设计避免热点
- **隐藏式**（Snowflake / BigQuery）：完全不暴露分片概念，由系统自动管理

### 2. 主键是大多数系统的隐式分布键

多数系统在用户不指定时，默认使用主键作为分布键：

- Greenplum：旧版本默认主键第一列；6.0+ 改为 RANDOMLY
- SingleStore：主键自动成为 SHARD KEY
- CockroachDB：主键决定 range 切分
- TiDB：自动分片但主键决定 region 边界
- Spanner：主键即唯一的物理顺序

这一惯例的好处是符合直觉，坏处是**单调递增主键导致写热点**——所以现代系统都提供了 hash-sharded 选项（CockroachDB `USING HASH WITH BUCKET_COUNT`、TiDB `AUTO_RANDOM`、YugabyteDB `HASH`）。

### 3. 复制表是分布式 JOIN 的"作弊码"

每个 MPP 系统都支持某种复制表：Greenplum DISTRIBUTED REPLICATED、Redshift DISTSTYLE ALL、Vertica UNSEGMENTED、Citus reference table、Synapse REPLICATE、OceanBase DUPLICATE。它们的统一价值是消除维表 JOIN 的 shuffle。但代价相同：**写入放大 N 倍**。规则：行数 < 几百万、变更不频繁的维表用复制表，其他都不行。

### 4. Redshift DISTSTYLE AUTO 是趋势

2019 年起 Redshift 默认 AUTO，让系统根据访问模式自动切换 ALL / EVEN / KEY。这反映了行业趋势：用户不应被迫做出影响整个生命周期的不可逆决策。Snowflake 走得更远——直接不暴露分布键。BigQuery 也只让用户管 PARTITION + CLUSTER。

### 5. 多列分布键支持参差不齐

- **Redshift**: 单列 only（这是 Redshift 的一大限制）
- **Synapse**: 单列 only
- **Greenplum / Vertica / Citus / SingleStore**: 支持多列
- **OceanBase / StarRocks / Doris**: 支持多列

多列分布键的常见用途：复合业务键（如 (tenant_id, user_id)）、为了与多种 JOIN pattern 都 co-located。

### 6. 重平衡是 MPP 的阿喀琉斯之踵

| 系统 | 重平衡方式 | 在线性 |
|------|----------|-------|
| Greenplum | gpexpand 工具 | 部分在线 |
| Redshift (老 DC2) | Resize | 数小时只读 |
| Redshift RA3 | 元数据级 | 几乎即时 |
| Citus | rebalance_table_shards | 在线 |
| TiDB / CockroachDB / Spanner | PD/调度自动 | 完全在线 |
| Snowflake | 不需要 | -- |

可以看到，**自动分片系统**（TiDB / CockroachDB）和**存算分离系统**（Snowflake / Redshift RA3）解决了 MPP 时代最大的痛点：扩容停服。

### 7. ClickHouse 的设计哲学不同

ClickHouse 的 Distributed 表更像是路由层而非物理切分。用户必须自己管理：写入路由（可以直接写本地表）、副本同步（Replicated MergeTree + ZK）、扩容时的数据搬迁。这种"螺丝刀级"的控制对工程团队是负担，但对极致性能场景给了灵活性。

### 8. 选键的黄金法则

综合所有引擎的建议，分布键选择遵循以下优先级：

1. **JOIN key 优先**：优先选最大 JOIN 频率的列，让 co-located join 生效
2. **基数足够高**：避免数据倾斜（基数 < shard 数 → 必然倾斜）
3. **写入访问均匀**：避免单调递增（用 hash bucket 或 AUTO_RANDOM 缓解）
4. **WHERE 过滤考虑**：常用过滤列做分布键 → 单点查极快但全表扫不并行
5. **不可变性**：分布键变更基本等于重建表

最常见的良好选择：`user_id`、`tenant_id`、`account_id`——高基数 + JOIN 频繁 + 业务自然边界。

最常见的反面教材：`status`、`country_code`、`created_date`（分布在前几个值，严重倾斜）。

### 9. 分区 vs 分布的核心区别

参见姊妹篇 [partition-strategy-comparison.md](./partition-strategy-comparison.md)。简化记忆：

- **分区（PARTITION BY）**：单实例内的逻辑切分，主要为了 pruning
- **分布（DISTRIBUTE BY）**：跨节点的物理切分，主要为了并行 + 局部性

两者经常组合使用（如 StarRocks 的 PARTITION + DISTRIBUTED BY），分区先决定数据落到哪个时间段的桶里，分布再决定该桶的数据在哪个节点上。

## 参考资料

- Greenplum: [Distribution and Skew](https://docs.greenplum.org/6-19/admin_guide/distribution.html)
- Redshift: [Choosing a data distribution style](https://docs.aws.amazon.com/redshift/latest/dg/t_Distributing_data.html)
- Vertica: [Hash Segmentation Clause](https://docs.vertica.com/latest/en/sql-reference/statements/create-statements/create-projection/hash-segmentation-clause/)
- Citus: [Distributed Tables](https://docs.citusdata.com/en/stable/develop/api_udf.html#create-distributed-table)
- TiDB: [SHARD_ROW_ID_BITS](https://docs.pingcap.com/tidb/stable/shard-row-id-bits) / [AUTO_RANDOM](https://docs.pingcap.com/tidb/stable/auto-random)
- CockroachDB: [Hash-sharded indexes](https://www.cockroachlabs.com/docs/stable/hash-sharded-indexes.html)
- YugabyteDB: [Hash and range sharding](https://docs.yugabyte.com/preview/architecture/docdb-sharding/sharding/)
- Snowflake: [Micropartitions and Clustering](https://docs.snowflake.com/en/user-guide/tables-clustering-micropartitions)
- BigQuery: [Clustered tables](https://cloud.google.com/bigquery/docs/clustered-tables)
- Spanner: [Schema design - interleaving](https://cloud.google.com/spanner/docs/schema-and-data-model)
- ClickHouse: [Distributed Table Engine](https://clickhouse.com/docs/en/engines/table-engines/special/distributed)
- StarRocks: [Data distribution](https://docs.starrocks.io/docs/table_design/Data_distribution/)
- Doris: [Data Partitioning](https://doris.apache.org/docs/table-design/data-partitioning/data-partitioning)
- OceanBase: [Table Group](https://en.oceanbase.com/docs/common-oceanbase-database-10000000001375750)
- SingleStore: [Distributed SQL](https://docs.singlestore.com/cloud/developer-resources/functional-extensions/working-with-distributed-sql/)
- Azure Synapse: [Distributed tables design](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-tables-distribute)
- DeWitt, D. & Gray, J. "Parallel Database Systems" (1992), Communications of the ACM
