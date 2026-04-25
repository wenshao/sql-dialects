# 聚簇表 vs 堆表存储结构 (Clustered vs Heap Storage)

同一张订单表，在 PostgreSQL 里是无序堆积的堆表，在 MySQL InnoDB 里却是按主键严格排序的 B+ 树——这两种截然不同的物理组织方式，决定了你每次查询、更新、建索引时的 I/O 模式、空间开销和并发行为。

## 没有 SQL 标准

SQL:92 到 SQL:2023 从未对表的物理存储结构做出规定。标准只关心逻辑模型：表是行的多重集合（multiset）。至于这些行以什么方式排列在磁盘上、是否以主键排序、二级索引指向物理地址还是逻辑键值——统统是实现相关的。

因此：

1. **堆表（Heap）vs 聚簇表（Index-Organized / Clustered）** 是数据库引擎设计的核心岔路
2. **二级索引回表（secondary lookup）** 的代价模型在两种组织下完全不同
3. **行位置稳定性（row location stability）** 直接影响 MVCC、复制、CDC 设计
4. 即使同一家厂商，不同存储引擎（InnoDB vs MyISAM，Oracle Heap vs IOT）也有不同选择

本文按"默认组织方式"、"是否支持 IOT"、"CLUSTER 命令"、"二级索引格式"四个维度，对 45+ 个引擎做横向对比。

## 核心概念

### 堆表（Heap Table）

```
堆表：
  - 行按插入顺序追加到数据页（无序或近似无序）
  - 每行有一个物理标识（row location / rowid / ctid / TID / RID）
  - 所有索引（包括主键）都是独立的二级索引，指向 rowid
  - 优点：插入快、行位置稳定
  - 缺点：主键查找需两次 I/O（索引 + 堆）
```

典型代表：PostgreSQL、Oracle 默认表、SQL Server 无聚簇索引表、DB2 默认表。

### 聚簇表（Index-Organized / Clustered Index Table）

```
聚簇表：
  - 整个表就是一棵 B+ 树（或 LSM）
  - 行直接存储在聚簇键（通常是主键）的叶子节点
  - 没有独立的 rowid，二级索引指向聚簇键值
  - 优点：主键查找一次 I/O、按主键范围扫描顺序 I/O
  - 缺点：随机主键插入引发页分裂；二级索引回表需要走主键树
```

典型代表：MySQL InnoDB、SQL Server 带聚簇索引表、Oracle IOT、SQLite（默认）、TiDB clustered index、CockroachDB。

### 行位置稳定性（Row Location Stability）

```
堆表：
  - 行的 rowid 在 UPDATE 时可能保持不变（如果新值能原地更新）
  - 页分裂 / VACUUM 移动时 rowid 可能变化（PostgreSQL 通过 TID + HOT 管理）
  - Oracle 的 rowid 是伪列，应用可依赖但不建议持久化

聚簇表：
  - 主键值即位置，主键不变则"位置"不变
  - 但 UPDATE 主键会"移动"整行，代价高（等于 DELETE + INSERT）
  - 二级索引存主键值，主键变更需要所有二级索引同步更新
```

## 支持矩阵

### 默认组织方式与 IOT/聚簇索引支持

| 引擎 | 默认组织 | 显式聚簇表语法 | 二级索引格式 | 备注 |
|------|---------|--------------|------------|------|
| PostgreSQL | 堆 | 不支持（仅 CLUSTER 一次性重排） | ctid (6字节 TID) | 无 IOT 概念 |
| MySQL (InnoDB) | 聚簇（按 PK） | 默认即聚簇 | 主键值 | 无 PK 时用隐藏 DB_ROW_ID |
| MySQL (MyISAM) | 堆 | 不支持 | 物理偏移 (rowid) | 已是过时引擎 |
| MariaDB (InnoDB) | 聚簇（按 PK） | 默认即聚簇 | 主键值 | 与 MySQL 一致 |
| MariaDB (Aria) | 堆 | 不支持 | 物理偏移 | MyISAM 继任者 |
| SQLite | 聚簇（按 ROWID） | `WITHOUT ROWID` 按 PK 聚簇 | ROWID 或 PK | ROWID 是默认隐藏主键 |
| Oracle | 堆 | `ORGANIZATION INDEX` (IOT) | rowid 或 PK (IOT) | 支持 cluster 多表共页 |
| SQL Server | 堆 | `CLUSTERED INDEX` | rowid (堆) 或 聚簇键 (CI) | PK 默认建 CI |
| DB2 (LUW) | 堆 | MDC 多维聚簇 | RID | MDC 按多维度块聚簇 |
| DB2 (z/OS) | 堆 + 聚簇索引 | `CLUSTER` 选项 | RID | 仅"建议"物理顺序 |
| Snowflake | 微分区（无聚簇） | `CLUSTER BY` (自动重排) | -- | 无传统二级索引 |
| BigQuery | 列存（无聚簇） | `CLUSTER BY` (多达 4 列) | -- | 列式分区 + 聚簇 |
| Redshift | 列存（sort key） | `SORTKEY` | -- | 类似 BigQuery |
| DuckDB | 列存（无聚簇） | 不支持 | -- | 内部排序但无用户级聚簇 |
| ClickHouse | MergeTree (ORDER BY) | `ORDER BY` 即主键排序 | 稀疏主键索引 | 非 B+ 树，数据块内排序 |
| Trino | 连接器相关 | 连接器支持 | -- | 依赖底层存储 |
| Presto | 连接器相关 | 连接器支持 | -- | 与 Trino 类似 |
| Spark SQL | 文件式（无聚簇） | Z-ORDER (Delta/Iceberg) | -- | 数据布局优化 |
| Hive | 文件式（无聚簇） | `CLUSTERED BY` (分桶) | -- | 分桶非传统聚簇 |
| Flink SQL | 连接器相关 | -- | -- | 流处理无表结构概念 |
| Databricks | Delta Lake | `ZORDER BY` / Liquid Clustering | -- | 2024 支持 Liquid Clustering |
| Teradata | 主索引哈希分布 | Primary Index (PI) | -- | AMP 级哈希分区 |
| Greenplum | 堆 + 分布键 | `DISTRIBUTED BY` + `CLUSTER` | ctid | PG 堆 + MPP 分布 |
| CockroachDB | 聚簇（按 PK） | 默认即聚簇 | 主键值 | Raft 分布式 KV 之上 |
| TiDB | 聚簇（5.0+） | `CLUSTERED` / `NONCLUSTERED` | 主键值或 _tidb_rowid | 5.0 后默认聚簇 |
| OceanBase | 聚簇（按 PK） | 默认即聚簇 | 主键值 | LSM 树，主键排序 |
| YugabyteDB | 聚簇（按 PK） | 默认即聚簇（YSQL） | 主键值 | PG 兼容 API 但底层聚簇 |
| SingleStore | 列存（Columnstore 聚簇） | `SORT KEY` + `SHARD KEY` | -- | 列存聚簇 + 行存索引 |
| Vertica | 列存（Projection） | `ORDER BY` in projection | -- | 多 projection 多排序 |
| Impala | 文件式（无聚簇） | 依赖 Parquet/Kudu | -- | Kudu 表支持 PK 聚簇 |
| StarRocks | 列存 + Sort Key | `ORDER BY` / `DUPLICATE KEY` | -- | 多种表模型 |
| Doris | 列存 + Sort Key | `KEY` 列排序 | -- | Unique/Aggregate/Duplicate |
| MonetDB | 列存（无聚簇） | -- | -- | 按列独立存储 |
| CrateDB | 堆（Lucene 段） | -- | Lucene docid | 基于 Elasticsearch |
| TimescaleDB | 堆 + 时间分区 | 继承 PG CLUSTER | ctid | hypertable 分块 |
| QuestDB | 列存 + 时间排序 | 设计即时间聚簇 | -- | 专用时序 |
| Exasol | 列存（无聚簇） | -- | -- | 自动索引 |
| SAP HANA | 行存或列存 | 列存按插入顺序 | -- | 两种存储均支持 |
| Informix | 堆 | `CLUSTER INDEX` | rowid | 支持聚簇索引 |
| Firebird | 堆 | 不支持 | DB_KEY | 索引指向 DB_KEY |
| H2 | 堆或聚簇 | `CLUSTERED` 自 1.4 | rowid | MVStore 引擎 |
| HSQLDB | 内存表或缓存表 | 不支持 | -- | 主要是内存数据库 |
| Derby | 堆 | 不支持 | rowid | 保守的 Java 数据库 |
| Amazon Athena | S3 文件（无聚簇） | -- | -- | 依赖 Parquet/ORC 布局 |
| Azure Synapse | 堆或 CCI | `CLUSTERED COLUMNSTORE INDEX` | -- | 列存聚簇为默认 |
| Google Spanner | 聚簇（按 PK） | `INTERLEAVE IN PARENT` | 主键值 | 支持父子表交织 |
| Materialize | 物化视图（无表存储） | -- | -- | 流处理引擎 |
| RisingWave | 物化视图（状态表） | 内部按 PK | -- | 流 SQL |
| InfluxDB (SQL) | 列存 + 时间聚簇 | 设计即时间聚簇 | -- | TSM 文件 |
| DatabendDB | 列存（Parquet） | `CLUSTER BY` | -- | 云原生数仓 |
| Yellowbrick | 列存（堆） | `CLUSTER` 命令 | -- | PG 语法兼容 |
| Firebolt | 列存 + Sparse Index | `PRIMARY INDEX` | -- | 云数仓 |

> 统计：约 14 个引擎默认使用聚簇组织，约 15 个引擎默认使用堆组织，其余为列存或文件式（聚簇概念不直接适用）。

### CLUSTER 命令与物理重排

| 引擎 | 命令 | 一次性 vs 持续 | 期间锁 |
|------|------|--------------|--------|
| PostgreSQL | `CLUSTER tbl USING idx` | 一次性，后续插入不维护 | ACCESS EXCLUSIVE |
| Oracle | `ALTER TABLE ... MOVE` | 一次性 | 需重建索引 |
| SQL Server | `ALTER INDEX ... REBUILD` | 一次性，聚簇索引维护 | 可 ONLINE |
| DB2 | `REORG TABLE` | 一次性 | 可 INPLACE |
| Greenplum | `CLUSTER` | 一次性（继承 PG） | ACCESS EXCLUSIVE |
| TimescaleDB | `cluster_chunk()` | 按 chunk 一次性 | chunk 级锁 |
| Yellowbrick | `CLUSTER` | 一次性 | -- |
| Snowflake | `ALTER TABLE ... RECLUSTER` | 自动后台（Automatic Clustering） | 无阻塞 |
| BigQuery | 建表时 `CLUSTER BY` | 自动后台 | 无阻塞 |
| Databricks | `OPTIMIZE ZORDER BY` / `OPTIMIZE` | 手动触发 | 无阻塞（快照隔离） |
| Redshift | `VACUUM SORT` | 手动 | 可并发读写 |
| ClickHouse | `OPTIMIZE TABLE` | 手动，合并 parts | 无阻塞（MergeTree） |

> PostgreSQL CLUSTER 的关键局限：**一次性**物理重排，之后新插入的行仍按堆顺序追加，需周期性重跑。

## 各引擎详解

### Oracle：Heap 默认 + IOT 可选 + Cluster 多表共页

Oracle 是三种存储组织都支持的典型引擎：

```sql
-- 1. 默认堆表
CREATE TABLE orders (
    order_id    NUMBER PRIMARY KEY,
    customer_id NUMBER,
    amount      NUMBER
);
-- 行按插入顺序追加到段（segment）中
-- PRIMARY KEY 自动创建独立 B-tree 索引，指向 rowid

-- 2. 索引组织表（Index-Organized Table, IOT）
CREATE TABLE orders_iot (
    order_id    NUMBER PRIMARY KEY,
    customer_id NUMBER,
    amount      NUMBER
) ORGANIZATION INDEX;
-- 整个表就是主键 B-tree 叶子节点
-- 二级索引通过 "logical rowid" 存主键值（非物理 rowid）

-- 3. 溢出区（OVERFLOW）：宽行优化
CREATE TABLE orders_iot2 (
    order_id    NUMBER PRIMARY KEY,
    customer_id NUMBER,
    note        VARCHAR2(4000)
) ORGANIZATION INDEX
  PCTTHRESHOLD 20
  OVERFLOW TABLESPACE users_data;
-- 行超过页 20% 时，尾部列溢出到堆段

-- 4. 簇（Cluster）：多表共享数据块
CREATE CLUSTER emp_dept_cluster (dept_id NUMBER);
CREATE INDEX emp_dept_idx ON CLUSTER emp_dept_cluster;

CREATE TABLE dept (
    dept_id NUMBER PRIMARY KEY,
    dname   VARCHAR2(50)
) CLUSTER emp_dept_cluster(dept_id);

CREATE TABLE emp (
    emp_id  NUMBER PRIMARY KEY,
    dept_id NUMBER,
    ename   VARCHAR2(50)
) CLUSTER emp_dept_cluster(dept_id);
-- 相同 dept_id 的 dept 和 emp 行存储在同一数据块
-- JOIN emp + dept ON dept_id 时无需 I/O 跨页
```

Oracle IOT 使用场景：

```sql
-- 场景 1: 查找表（lookup table），几乎所有查询都按 PK
CREATE TABLE currency_rates (
    currency_code CHAR(3) PRIMARY KEY,
    rate_to_usd   NUMBER
) ORGANIZATION INDEX;

-- 场景 2: 关联表（association table），复合主键
CREATE TABLE user_roles (
    user_id NUMBER,
    role_id NUMBER,
    granted_at DATE,
    PRIMARY KEY (user_id, role_id)
) ORGANIZATION INDEX COMPRESS 1;
-- COMPRESS 1 去重前缀 user_id，节省空间
```

Oracle rowid 格式：

```
rowid: OOOOOOFFFBBBBBBRRR
  OOOOOO = 数据对象号（segment）
  FFF    = 相对文件号
  BBBBBB = 块号
  RRR    = 行号
示例: AAASLjAAEAAAAHuAAA

IOT 的 logical rowid:
  主键值 + 可选的 guess (上次访问的物理位置，用于二级索引快速回表)
  guess 失效时回退到 B-tree 查找
```

### MySQL InnoDB：强制聚簇

InnoDB 的核心设计：**每张表必须是一棵聚簇 B+ 树**。

```sql
-- 场景 1: 显式主键
CREATE TABLE orders (
    order_id    BIGINT PRIMARY KEY,       -- 作为聚簇键
    customer_id BIGINT,
    amount      DECIMAL(10,2),
    INDEX idx_customer (customer_id)       -- 二级索引
) ENGINE=InnoDB;
-- 聚簇 B+ 树: order_id → (customer_id, amount)
-- 二级索引 idx_customer: (customer_id, order_id) → 无直接行数据

-- 场景 2: 无主键，InnoDB 隐式创建
CREATE TABLE logs (
    log_time DATETIME,
    message  TEXT
) ENGINE=InnoDB;
-- InnoDB 自动创建 6 字节 DB_ROW_ID 作为聚簇键
-- 所有表共享一个全局递增计数器（有争用）
-- 强烈建议显式定义 PRIMARY KEY

-- 场景 3: 无主键但有唯一索引
CREATE TABLE users (
    user_id  BIGINT NOT NULL,
    UNIQUE KEY uk_user (user_id),
    name     VARCHAR(100)
) ENGINE=InnoDB;
-- InnoDB 选择第一个非空唯一索引作为聚簇键（user_id）

-- 场景 4: 二级索引回表
SELECT amount FROM orders WHERE customer_id = 123;
-- 步骤:
--   1. 在 idx_customer 中找到 customer_id=123 的所有 order_id
--   2. 对每个 order_id 回到聚簇 B+ 树查找 amount
--   3. 两次 B+ 树遍历
```

InnoDB 自增主键的重要性：

```sql
-- 推荐: AUTO_INCREMENT 主键（单调递增）
CREATE TABLE t1 (id BIGINT AUTO_INCREMENT PRIMARY KEY, data TEXT);
-- 新行始终追加到 B+ 树右侧，无页分裂

-- 反模式: UUID 主键
CREATE TABLE t2 (id BINARY(16) PRIMARY KEY, data TEXT);
-- UUID 随机分布，每次插入可能分裂任意中间页
-- 导致大量随机 I/O + 页利用率下降

-- 折中: UUIDv7 / ULID 时间有序
-- 或者用 AUTO_INCREMENT 做聚簇键，UUID 作为二级唯一索引
```

InnoDB 变更主键的代价：

```sql
-- UPDATE 主键等于 DELETE + INSERT
UPDATE orders SET order_id = order_id + 1000000 WHERE order_id < 100;
-- 1. 从聚簇 B+ 树删除原行
-- 2. 插入新位置
-- 3. 所有二级索引（因为存主键值）同步更新
-- 代价高，应避免
```

### PostgreSQL：堆 + ctid + 一次性 CLUSTER

PostgreSQL 坚持堆表路线，所有索引都是独立的：

```sql
-- 默认堆表
CREATE TABLE orders (
    order_id    BIGINT PRIMARY KEY,
    customer_id BIGINT,
    amount      NUMERIC
);
-- 所有索引（包括 PK）指向 ctid (block_number, tuple_offset)

-- ctid 查看
SELECT ctid, order_id FROM orders LIMIT 3;
-- ctid  | order_id
-- (0,1) | 1
-- (0,2) | 2
-- (0,3) | 3

-- ctid 不稳定: UPDATE、VACUUM FULL、CLUSTER 都可能改变 ctid
-- 应用不应持久化 ctid

-- CLUSTER 命令：一次性按索引物理重排
CLUSTER orders USING orders_pkey;
-- 等价于: 创建新表、按索引顺序插入、替换旧表
-- 持有 ACCESS EXCLUSIVE 锁，全程阻塞读写
-- 重排后新插入仍按堆顺序，不会保持聚簇

-- 查看聚簇度（correlation）
SELECT attname, correlation FROM pg_stats
WHERE tablename = 'orders' AND attname = 'order_id';
-- correlation 接近 1 或 -1 说明物理顺序与列值相关
-- 接近 0 说明完全无序
```

PostgreSQL 的 HOT（Heap-Only Tuple）更新：

```sql
-- UPDATE 不变索引列 + 新版本能放入同页 → HOT 更新
UPDATE orders SET amount = amount * 1.1 WHERE order_id = 100;
-- 新版本写入同页，旧版本标记为 HOT-updated
-- 索引无需更新（仍指向旧 ctid，通过 HOT 链查找新版本）
-- 大幅减少索引膨胀
```

PostgreSQL 无 IOT 的原因：MVCC 多版本 + 每次更新可能改变行位置，使得"索引即表"的设计与 PG 的 MVCC 模型不兼容。

### SQL Server：堆 vs 聚簇索引

SQL Server 让用户自己选择：

```sql
-- 1. 堆表（无聚簇索引）
CREATE TABLE orders_heap (
    order_id    INT IDENTITY(1,1),
    customer_id INT,
    amount      DECIMAL(10,2)
);
-- 无 PRIMARY KEY 或 PRIMARY KEY NONCLUSTERED
-- 行按物理位置 (file_id, page_id, slot_id) 标识（即 RID）
-- 所有索引存 RID

-- 2. 聚簇索引表（推荐）
CREATE TABLE orders (
    order_id    INT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    customer_id INT,
    amount      DECIMAL(10,2)
);
-- PRIMARY KEY 默认是 CLUSTERED（除非显式指定 NONCLUSTERED）
-- 表即 B+ 树，叶子节点存整行

-- 3. 显式指定
CREATE TABLE orders2 (
    order_id    INT,
    customer_id INT,
    amount      DECIMAL(10,2),
    PRIMARY KEY NONCLUSTERED (order_id),
    INDEX ix_cust CLUSTERED (customer_id)     -- 聚簇键 ≠ 主键
);
-- 聚簇键选 customer_id（按客户查询多）
-- 主键是独立的二级索引

-- 4. 列存索引（Clustered Columnstore Index, CCI）
CREATE TABLE fact_sales (
    sale_date   DATE,
    product_id  INT,
    amount      DECIMAL(10,2),
    INDEX ccix CLUSTERED COLUMNSTORE
);
-- 数仓场景，行数据按列压缩存储（rowgroup ~ 1M 行）
```

SQL Server 堆表的 RID 查找：

```sql
-- 二级索引查询
SELECT amount FROM orders_heap WHERE customer_id = 123;
-- 索引存 (customer_id, RID)
-- 步骤:
--   1. 索引 B+ 树找 customer_id=123 → 获得 RID = (1:1234:5)
--   2. 直接访问 page 1234 slot 5 读整行
--   3. I/O: 1 索引 + 1 堆页

-- 聚簇索引表
SELECT amount FROM orders WHERE customer_id = 123;
-- 无 customer_id 索引时全表扫描
-- 有 customer_id 索引时: 索引存 (customer_id, order_id)
-- 步骤:
--   1. 索引 B+ 树找 customer_id=123 → 获得 order_id=456
--   2. 聚簇 B+ 树根据 order_id=456 找 amount
--   3. I/O: 1 索引遍历 + 1 聚簇遍历（每层一个页）
```

### SQLite：ROWID 默认 + WITHOUT ROWID 可选

SQLite 的所有表（除非指定 WITHOUT ROWID）都是按隐藏 ROWID 聚簇的：

```sql
-- 1. 默认 ROWID 表
CREATE TABLE orders (
    id INTEGER PRIMARY KEY,           -- 别名为 ROWID
    customer_id INTEGER,
    amount REAL
);
-- 整个表是 ROWID B-tree
-- INTEGER PRIMARY KEY 是 ROWID 的别名（不创建额外索引）

-- 2. 非整数主键 → 两个 B-tree
CREATE TABLE orders2 (
    code TEXT PRIMARY KEY,
    customer_id INTEGER,
    amount REAL
);
-- 一个 B-tree 按 ROWID 存行（SQLite 自动创建 ROWID）
-- 另一个 B-tree 按 code 映射到 ROWID（效果类似 MyISAM）

-- 3. WITHOUT ROWID 表（按 PK 聚簇）
CREATE TABLE orders3 (
    code TEXT PRIMARY KEY,
    customer_id INTEGER,
    amount REAL
) WITHOUT ROWID;
-- 整个表按 code 聚簇，单 B-tree
-- 节省空间（无 ROWID 列），访问快一倍

-- 4. WITHOUT ROWID 限制
-- - 必须有 PRIMARY KEY
-- - 不能用 INTEGER PRIMARY KEY（ROWID 别名）
-- - AUTOINCREMENT 不可用
```

WITHOUT ROWID 的性能对比（官方数据）：

```
场景: 非整数 PK 查询
  ROWID 表:        B-tree (PK → ROWID) + B-tree (ROWID → row) = 2 次查找
  WITHOUT ROWID:   单 B-tree (PK → row)                        = 1 次查找

空间节省: 通常 50% 以下，对短行（< 50 字节）效果显著
插入性能: WITHOUT ROWID 更快（少一棵 B-tree 维护）
```

### DB2：堆 + MDC 多维聚簇

DB2 默认堆表，但支持按多个维度聚簇（MDC）：

```sql
-- 1. 默认堆表
CREATE TABLE orders (
    order_id    INT NOT NULL PRIMARY KEY,
    customer_id INT,
    order_date  DATE,
    region      CHAR(2)
);

-- 2. MDC (Multi-Dimensional Clustering)
CREATE TABLE orders_mdc (
    order_id    INT NOT NULL PRIMARY KEY,
    customer_id INT,
    order_date  DATE,
    region      CHAR(2)
) ORGANIZE BY (region, MONTH(order_date));
-- 每个 (region, month) 组合分配独立的 block（extent，通常 32 页）
-- 相同维度值的行物理聚集
-- 维度上的谓词可用 block index 快速跳过

-- 3. MDC 查询
SELECT * FROM orders_mdc
WHERE region = 'US' AND order_date BETWEEN '2024-01-01' AND '2024-01-31';
-- 直接定位 (US, 2024-01) 的 blocks
-- 完全跳过其他 region 和其他月份的 blocks

-- 4. z/OS DB2 的 CLUSTER 索引（与 LUW 不同）
CREATE INDEX ix_orders_date ON orders (order_date) CLUSTER;
-- 仅"建议"的物理顺序
-- REORG 时按此索引重排，不维护持续聚簇
```

MDC 的块索引（block index）：

```
传统索引: 每行一个索引条目
MDC 块索引: 每个 block（32 页 × ~400 行 ≈ 12800 行）一个条目

100M 行、按 region 分组的表:
  B-tree 索引: ~100M 条目
  MDC 块索引: ~8000 条目（100M / 12800）
  空间节省 1000+ 倍，维度查询快 10-100 倍
```

### TiDB：5.0+ 聚簇索引

TiDB 在 5.0 之前所有表都是非聚簇（用 `_tidb_rowid` 作聚簇键），5.0 之后默认聚簇：

```sql
-- TiDB 5.0+ 默认聚簇
CREATE TABLE orders (
    order_id BIGINT PRIMARY KEY,       -- 默认 CLUSTERED
    customer_id BIGINT,
    amount DECIMAL(10,2)
);
-- 等价于:
-- PRIMARY KEY (order_id) CLUSTERED

-- 显式非聚簇（兼容 5.0 之前行为）
CREATE TABLE orders_nc (
    order_id BIGINT PRIMARY KEY NONCLUSTERED,
    customer_id BIGINT,
    amount DECIMAL(10,2)
);
-- 使用隐藏 _tidb_rowid 作聚簇键
-- 主键是独立的唯一索引

-- 全局变量控制默认行为
SET GLOBAL tidb_enable_clustered_index = ON;  -- 默认 INT_ONLY 或 ON

-- 查看表是否聚簇
SHOW CREATE TABLE orders;
-- 输出包含 /*T![clustered_index] CLUSTERED */
```

TiDB 聚簇索引的性能影响：

```
场景                       非聚簇（<5.0）       聚簇（5.0+）
-------------------------  ------------------   -----------------
PK 查找                     2 次 KV (索引 + 行)   1 次 KV
PK 范围扫描                 随机 I/O             顺序 I/O
二级索引查找                索引 + _tidb_rowid + 行   索引 + PK + 行
INSERT                      写 2 KV (行 + PK索引)  写 1 KV
主键更新                    不允许                等于 DELETE + INSERT
```

### CockroachDB：永远聚簇

CockroachDB 所有表都是聚簇的，并且存储在 Raft 复制的分布式 KV 上：

```sql
-- 默认聚簇（无其他选择）
CREATE TABLE orders (
    order_id BIGINT PRIMARY KEY,
    customer_id BIGINT,
    amount DECIMAL(10,2)
);
-- KV 映射:
--   /orders/primary/<order_id>/customer_id
--   /orders/primary/<order_id>/amount

-- 无主键时自动创建 rowid
CREATE TABLE logs (
    message TEXT,
    ts TIMESTAMP
);
-- 自动添加 rowid BIGINT DEFAULT unique_rowid() PRIMARY KEY
-- unique_rowid() 是基于节点 ID + 时间戳 + 序号的 64-bit 值

-- PK 顺序影响数据分布
-- 反模式: 自增 PK 在分布式环境中导致热点
CREATE TABLE events (
    id SERIAL PRIMARY KEY,     -- 顺序写入集中在最右 range 上
    data TEXT
);

-- 推荐: 哈希前缀打散
CREATE TABLE events2 (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    data TEXT
);

-- 或者显式哈希分片
CREATE TABLE events3 (
    shard INT8 NOT VISIBLE AS (abs(mod(id, 16))) STORED,
    id SERIAL,
    data TEXT,
    PRIMARY KEY (shard, id)
) USING HASH WITH BUCKET_COUNT = 16;
```

### Google Spanner：Interleaved 层次聚簇

Spanner 支持将子表行与父表行交织存储：

```sql
-- 父表
CREATE TABLE Customers (
    CustomerId INT64 NOT NULL,
    Name STRING(100)
) PRIMARY KEY (CustomerId);

-- 子表交织在父表
CREATE TABLE Orders (
    CustomerId INT64 NOT NULL,      -- 必须是父表 PK 前缀
    OrderId INT64 NOT NULL,
    Amount NUMERIC
) PRIMARY KEY (CustomerId, OrderId),
  INTERLEAVE IN PARENT Customers ON DELETE CASCADE;

-- 物理存储（Spanner split 内）:
--   Customers(100) → Name
--   Orders(100, 1) → Amount
--   Orders(100, 2) → Amount
--   Customers(101) → Name
--   Orders(101, 1) → Amount
--
-- 父子行物理相邻，JOIN + 同 customer 的查询极快

-- JOIN 查询
SELECT c.Name, o.Amount
FROM Customers c JOIN Orders o ON c.CustomerId = o.CustomerId
WHERE c.CustomerId = 100;
-- 单次 range 读即可获得所有相关行
```

### SingleStore：Columnstore 聚簇

SingleStore（原 MemSQL）的列存表按排序键聚簇：

```sql
-- 列存聚簇表（默认）
CREATE TABLE orders (
    order_id    BIGINT,
    customer_id BIGINT,
    order_date  DATE,
    amount      DECIMAL(10,2),
    SORT KEY (order_date),       -- 列存按 order_date 排序
    SHARD KEY (customer_id)      -- 分布键
);
-- 数据按 order_date 物理排序（方便范围扫描和压缩）
-- 按 customer_id 哈希分布到多节点

-- 行存表（内存优化）
CREATE TABLE cache (
    key VARCHAR(100),
    value VARCHAR(4000),
    PRIMARY KEY (key)
) ROWSTORE;
-- 纯内存行存，按 PK 哈希索引
```

## 对比与取舍

### 聚簇 vs 堆：核心权衡

| 维度 | 堆表 | 聚簇表 |
|------|------|--------|
| PK 查找 I/O | 2 次（索引 + 堆） | 1 次（聚簇树） |
| PK 范围扫描 | 可能随机 I/O（除非按 CLUSTER） | 顺序 I/O |
| 插入 | 追加，代价稳定 | PK 位置决定，可能页分裂 |
| 更新非键列 | 原地或 HOT | 原地（InnoDB 不影响二级索引） |
| 更新键列 | 代价低 | 代价高（移动行 + 更新所有二级索引） |
| 二级索引回表 | 直接按 rowid | 通过 PK 再查聚簇树 |
| 二级索引大小 | 存 rowid（紧凑） | 存 PK 值（PK 长则膨胀） |
| 行位置稳定性 | UPDATE 可能保持 | PK 不变即稳定 |
| 存储碎片化 | 易产生（需 VACUUM） | 页分裂也会产生（需 OPTIMIZE） |
| 全表扫描 | 快（顺序读堆） | 稍慢（走叶子链表） |
| 无 PK 表 | 支持 | 需要隐藏 rowid |

### 二级索引的回表代价

```
堆表（SQL Server, PostgreSQL, Oracle）:
  SELECT non_indexed_col FROM t WHERE indexed_col = X;
  1. 索引 B-tree 查找 → 获得 rowid
  2. 按 rowid 直接读数据页 → 获得行
  I/O: 1 索引 + 1 堆页 = 2 页

聚簇表（MySQL InnoDB, CockroachDB, TiDB）:
  SELECT non_indexed_col FROM t WHERE indexed_col = X;
  1. 索引 B-tree 查找 → 获得 PK 值
  2. 聚簇 B-tree 查找 PK → 获得行
  I/O: 索引树深 + 聚簇树深 = ~6-8 页（取决于树深）

覆盖索引（两者通用）:
  SELECT covered_col FROM t WHERE indexed_col = X;
  索引已包含所需列 → 无需回表
  I/O: 索引深度 = ~3-4 页
```

### 写入性能对比

```
场景: 插入 1M 行，PK = 随机 UUID，3 个二级索引

InnoDB（聚簇表）:
  - 聚簇 B+ 树随机插入 → 大量页分裂
  - 每次分裂涉及 ~16KB 页 I/O
  - 3 个二级索引同样随机插入
  - 总 I/O: 4 × N 次页写 + 大量分裂
  
PostgreSQL（堆表）:
  - 行追加到当前堆页 → 近似顺序 I/O
  - PK 索引 + 3 个二级索引随机插入
  - 总 I/O: 1 堆写 + 4 × N 次索引写
  - 索引存 ctid（8 字节）比 InnoDB 存 PK（16 字节 UUID）紧凑

结论: 随机 PK 下，堆表插入快约 2-3 倍
     顺序 PK（AUTO_INCREMENT）下，两者接近
```

### 范围扫描性能对比

```
场景: SELECT * FROM orders WHERE order_date BETWEEN '2024-01-01' AND '2024-01-31'
设计: order_date 上有索引

堆表 + order_date 索引:
  - 索引扫描找到匹配的 rowid 列表
  - 按 rowid 依次读堆页
  - 如果 order_date 与物理顺序不相关 → 随机 I/O
  - PostgreSQL 的 Bitmap Index Scan 排序 rowid 后顺序读，缓解此问题

聚簇表（按 order_date 聚簇）:
  - 整个范围在 B+ 树中相邻
  - 顺序 I/O，读完即止
  - 但同时只能按一个键聚簇

SQL Server CCI（按 rowgroup 聚簇 + 元数据消除）:
  - 每个 rowgroup (~1M 行) 有 min/max
  - 跳过不匹配的 rowgroup
  - 列存压缩 + 向量化扫描
```

## 何时选聚簇、何时选堆

### 选聚簇的场景

```
1. 频繁按 PK 查找（OLTP 点查）
   → 聚簇一次 I/O，堆表两次

2. 按 PK 或聚簇键做范围扫描
   → 顺序 I/O 比随机 I/O 快 10-100 倍

3. 需要父子表物理共存（Spanner Interleaved、Oracle Cluster）
   → JOIN 无需跨块

4. 无二级索引或二级索引少
   → 聚簇的"PK 膨胀"代价低

5. 小表查找（currency rates, dimension tables）
   → IOT 节省一棵 B-tree
```

### 选堆的场景

```
1. 频繁按多个列查询（多个二级索引访问路径）
   → 堆表的二级索引紧凑（存 rowid 而非 PK）

2. 随机或无意义 PK（UUID、hash）
   → 堆表的追加写避免页分裂

3. 频繁 UPDATE 非键列
   → HOT 更新（PostgreSQL）或原地更新

4. 分析型宽表（OLAP）
   → 聚簇的叶子节点容纳整行，扫描效率反不如堆 + 列存

5. 存储多 version MVCC
   → 堆表与 MVCC 模型更兼容（PostgreSQL 设计）
```

## 关键发现

### 1. 没有银弹

三种主流路线都有生产级代表：

- **纯堆**：PostgreSQL、Oracle 默认、SQL Server 堆、DB2 默认
- **纯聚簇**：MySQL InnoDB、CockroachDB、SQLite 默认、Spanner
- **两者皆有**：Oracle（Heap + IOT）、SQL Server（Heap + CI）、TiDB（可选）

### 2. 分布式系统偏好聚簇

CockroachDB、TiDB、YugabyteDB、Spanner 都强制或默认聚簇，因为底层 KV 存储天然按键排序（RocksDB LSM、Spanner Tablet），聚簇组织与底层数据结构对齐，range 分裂、读写路径统一。

### 3. 列存引擎重新定义"聚簇"

Snowflake、BigQuery、Redshift、Databricks 这些云数仓没有传统意义的 B+ 树聚簇，而是用 `CLUSTER BY` 或 `ORDER BY` 在**微分区/文件**级别做数据布局优化，配合 min/max 元数据做谓词消除。这是"逻辑聚簇"而非"物理 B+ 树聚簇"。

### 4. 二级索引的"回表代价"决定性能分水岭

InnoDB 的二级索引回表走两次 B+ 树（索引树 → PK 树），总深度 ~6-8 页；而堆表只需 1 次索引 + 1 次堆页，共 ~4-5 页。**这是聚簇表设计最大的性能坑**，应对方法：

1. **覆盖索引**：让索引包含所有需要的列，避免回表
2. **短 PK**：避免长 UUID 作 PK（二级索引膨胀）
3. **索引选择性**：对低选择性列（如性别）建索引回表代价高于全表扫描

### 5. CLUSTER 命令的持续性问题

PostgreSQL、DB2、Oracle MOVE、SQL Server REBUILD 的 "CLUSTER" 语义都是**一次性物理重排**，之后新插入的数据不自动维护物理顺序。与 InnoDB/Spanner 的持续聚簇截然不同。Snowflake 的自动聚簇、BigQuery 的自动重排、Databricks 的 Liquid Clustering 是后台异步持续维护，属于第三种模型。

### 6. IOT 在工业界渗透率低

Oracle IOT 推出 20+ 年，但使用率远低于堆表。原因：

- 现代 Oracle 默认堆 + B-tree PK 的两次查找对 OLTP 足够快
- IOT 限制多（更新 PK 代价高、LOB 处理复杂、溢出机制增加复杂度）
- DBA 熟悉堆表维护（pctfree、pctused）

反观 MySQL InnoDB 没给用户选择，反而强制聚簇成为行业标杆。

### 7. 表组织与 MVCC 的耦合

- **PostgreSQL** 坚持堆的一个核心原因：新行写新位置、旧版本保留，堆天然适合"元组为单位"的 MVCC
- **InnoDB** 用回滚段（undo log）实现 MVCC，聚簇表的"位置即 PK"不受 MVCC 影响
- **Oracle** 同样用 undo，IOT 也能支持 MVCC

### 8. 分布式 PK 的热点陷阱

无论堆还是聚簇，在分布式系统中**顺序 PK**（AUTO_INCREMENT、SEQUENCE）会成为写入热点：

```
问题: 所有写入集中在最右边的 range/shard
影响: CockroachDB、TiDB、Spanner、YugabyteDB 都明确警告

解决方案:
  1. UUID 主键（InnoDB 下代价高，分布式 KV 下合理）
  2. 哈希分片（CockroachDB HASH SHARDED INDEX）
  3. 反转字节顺序（TiDB AUTO_RANDOM）
  4. 多租户 (tenant_id, local_id) 复合 PK
```

### 9. 现代文件格式的"聚簇"是数据布局

Parquet/ORC 的 row group 内排序、Iceberg 的 sort order、Delta 的 Z-Order、Databricks Liquid Clustering——这些不是传统意义的 B+ 树聚簇，而是**分区/文件内的数据布局优化**，配合文件级统计实现谓词下推裁剪。它们可以"按多个维度同时聚簇"（Z-Order 曲线、Hilbert 曲线），突破传统聚簇索引"只能按一个键"的限制。

### 10. 二级索引格式的选择决定迁移成本

从 MySQL 迁移到 PostgreSQL 时，二级索引的内部格式差异：

```
MySQL InnoDB 二级索引: (indexed_col, pk_val)
PostgreSQL 二级索引:    (indexed_col) → ctid

影响:
  - InnoDB 的 PK 越长，二级索引越大
  - PostgreSQL 的二级索引大小只取决于 indexed_col
  - 迁移到 PostgreSQL 后，如果 PK 长（UUID），二级索引空间可能显著缩小
```

## 参考资料

- Oracle: [Index-Organized Tables](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/indexes-and-index-organized-tables.html)
- Oracle: [Table Clusters](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/tables-and-table-clusters.html)
- MySQL: [Clustered and Secondary Indexes](https://dev.mysql.com/doc/refman/8.0/en/innodb-index-types.html)
- PostgreSQL: [CLUSTER](https://www.postgresql.org/docs/current/sql-cluster.html)
- PostgreSQL: [Heap-Only Tuples](https://www.postgresql.org/docs/current/storage-hot.html)
- SQL Server: [Clustered and Nonclustered Indexes](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/clustered-and-nonclustered-indexes-described)
- SQLite: [Clustered Indexes and the WITHOUT ROWID Optimization](https://www.sqlite.org/withoutrowid.html)
- DB2: [Multidimensional Clustering (MDC) Tables](https://www.ibm.com/docs/en/db2/11.5?topic=clustering-tables-mdc)
- TiDB: [Clustered Indexes](https://docs.pingcap.com/tidb/stable/clustered-indexes)
- CockroachDB: [Primary Key and Storage](https://www.cockroachlabs.com/docs/stable/primary-key)
- Google Spanner: [Schema and Data Model - Interleaved Tables](https://cloud.google.com/spanner/docs/schema-and-data-model)
- Snowflake: [Clustering Keys & Clustered Tables](https://docs.snowflake.com/en/user-guide/tables-clustering-keys)
- BigQuery: [Clustered Tables](https://cloud.google.com/bigquery/docs/clustered-tables)
- Databricks: [Liquid Clustering](https://docs.databricks.com/en/delta/clustering.html)
- SingleStore: [Columnstore Sorted Keys](https://docs.singlestore.com/db/latest/create-a-database/physical-database-schema-design/understanding-keys-and-indexes/columnstore-keys/)
- Stonebraker, M. "The Design of the Postgres Storage System" (1987)
- Graefe, G. "Modern B-Tree Techniques" (2011), Foundations and Trends in Databases
