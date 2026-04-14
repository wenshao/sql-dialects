# 覆盖索引 (Covering Indexes and INCLUDE Clause)

当一条查询的所有字段都能从索引本身获得时，数据库可以完全跳过回表 (heap access / bookmark lookup)——这就是覆盖索引 (covering index)，是 OLTP 场景中最经典也最有效的优化手段之一。一个精心设计的 `INCLUDE` 子句可以让延迟从毫秒级降到微秒级，让 QPS 提升一个数量级。

## 为什么需要覆盖索引

### 典型的回表代价

考虑一张 `orders` 表（10 亿行、200 GB 堆）与如下索引和查询：

```sql
CREATE INDEX idx_user ON orders(user_id);

SELECT order_id, amount, status
FROM orders
WHERE user_id = 42;
```

传统 B+ 树索引只存 `user_id` 与行指针 (PostgreSQL 的 ctid、InnoDB 的主键、SQL Server 的 RID 或聚簇键)。查询计划是：

1. 在 `idx_user` 上做范围扫描，得到 N 个 TID
2. 对每个 TID 做一次随机 I/O 回到堆页取 `order_id, amount, status`
3. 返回结果

如果 user 42 有 1000 行订单，第 2 步需要 1000 次随机 I/O。在 SSD 上大约 10 ms，在 HDD 上可能是 10 秒。而堆页的缓冲池命中率往往低于索引页——索引热而堆冷是 OLTP 的常态。

### 覆盖索引的解法

如果索引叶子节点里直接存有 `order_id, amount, status`，那么步骤 2 就完全可以省略。这种现象在不同引擎里有不同叫法：

- **PostgreSQL / SQL Server / DB2**: Index-Only Scan / Covering Index / INCLUDE columns
- **Oracle**: Index Fast Full Scan / Index-Only Access
- **MySQL / MariaDB**: Covering Index (使用 Extra: `Using index`)
- **CockroachDB / YugabyteDB**: STORING columns
- **SQLite**: Covering Index

实现层面也有两种风格：

1. **复合键覆盖** (composite-key covering)：把需要的列全部做成联合索引的键列。缺点是所有列都参与 B 树排序，索引变大，非等值谓词的查找效率差。
2. **INCLUDE / STORING 非键列** (non-key payload)：只在叶子节点挂 payload，不进入内部 B 树节点。非键列不参与 B 树排序、不影响唯一性约束、不做范围裁剪，只为"回表省一次 I/O"而存在。

后者是 SQL Server 2005 率先引入的经典扩展，随后 DB2、PostgreSQL、CockroachDB 等纷纷跟进。Oracle / MySQL 至今没有直接语法，只能走复合键路线。

## SQL 标准立场

SQL 标准 (包括最新的 SQL:2023) 完全不涉及索引——索引是物理存储层的概念，标准刻意保持抽象。所有 `CREATE INDEX`、`INCLUDE`、`STORING` 等语法都是厂商扩展。没有 ISO 参考语法，各家做法因此差异极大。

这与 `TABLESAMPLE`、`WINDOW` 等逻辑层特性截然不同，是纯粹的物理设计话题。

## 支持矩阵（综合）

### 显式 INCLUDE / STORING 子句支持

| 引擎 | 语法 | 起始版本 | 备注 |
|------|------|---------|------|
| PostgreSQL | `INCLUDE (...)` | 11 (2018) | B-tree 全支持, GiST 13+ |
| MySQL | -- | -- | 无，走复合键 |
| MariaDB | -- | -- | 无，走复合键 |
| SQLite | -- | -- | 无，走复合键或 WITHOUT ROWID |
| Oracle | -- | -- | 无，复合键 + index-only scan |
| SQL Server | `INCLUDE (...)` | 2005 (v9) | 最早、最完整的实现 |
| DB2 (LUW) | `INCLUDE (...)` | v7 (2000) | 仅限 UNIQUE INDEX |
| DB2 (z/OS) | `INCLUDE (...)` | v10 | 仅限 UNIQUE INDEX |
| Snowflake | -- | -- | 无索引概念 (micro-partition) |
| BigQuery | -- | -- | 无用户索引 (列存 + 分区裁剪) |
| Redshift | -- | -- | 无索引 (sort key + zone map) |
| DuckDB | -- | -- | 无 INCLUDE, 依赖 zone map |
| ClickHouse | -- | -- | 主键即覆盖 (列存) |
| Trino | -- | -- | 无索引 (连接器决定) |
| Presto | -- | -- | 同 Trino |
| Spark SQL | -- | -- | 无索引 (DPP + 列存) |
| Hive | -- | -- | 老式 bitmap/compact 废弃 |
| Flink SQL | -- | -- | 无索引 (流处理) |
| Databricks | -- | -- | 无 INCLUDE (Z-order + data skipping) |
| Teradata | -- | -- | USI/NUSI 直接支持列存放 |
| Greenplum | `INCLUDE (...)` | 7 (2023) | 继承 PostgreSQL 12 |
| CockroachDB | `STORING (...)` / `INCLUDE (...)` | 1.0 (2017) | PostgreSQL 兼容 |
| TiDB | -- | -- | 无显式子句，优化器自动识别 |
| OceanBase | -- | -- | 复合键覆盖 (MySQL 兼容) |
| YugabyteDB | `INCLUDE (...)` | 2.0 (2020) | 继承 PG 11, LSM 存储 |
| SingleStore | -- | -- | 列存覆盖，无显式子句 |
| Vertica | -- | -- | Projection 机制替代 |
| Impala | -- | -- | 无索引 |
| StarRocks | -- | -- | 无, 前缀索引 + 物化视图 |
| Doris | -- | -- | 无, 前缀索引 + 物化视图 |
| MonetDB | -- | -- | 列存，无索引 |
| CrateDB | -- | -- | Lucene 倒排 |
| TimescaleDB | `INCLUDE (...)` | 继承 PG 11 | 超表子表继承 |
| QuestDB | -- | -- | 时序模型，无二级索引 |
| Exasol | -- | -- | 自动索引 |
| SAP HANA | -- | -- | 列存 + inverted index |
| Informix | -- | -- | 无 INCLUDE |
| Firebird | -- | -- | 无 INCLUDE |
| H2 | -- | -- | 无 INCLUDE |
| HSQLDB | -- | -- | 无 INCLUDE |
| Derby | -- | -- | 无 INCLUDE |
| Amazon Athena | -- | -- | 继承 Trino, 无索引 |
| Azure Synapse | `INCLUDE (...)` | GA | 继承 SQL Server 语法（行存索引）|
| Google Spanner | `STORING (...)` | GA (2017) | 辅助索引 STORING 子句 |
| Materialize | -- | -- | 物化视图 differential dataflow |
| RisingWave | -- | -- | 流物化视图 |
| InfluxDB (SQL) | -- | -- | 时序列存 |
| DatabendDB | -- | -- | 列存 + bloom |
| Yellowbrick | -- | -- | MPP 列存 |
| Firebolt | -- | -- | aggregating/join index 不同模型 |

> 统计：约 11 个引擎提供**显式** `INCLUDE` / `STORING` 子句，其余多数要么无索引概念（云数仓/列存），要么只能走复合键路线（MySQL 系）。

### 复合键覆盖（所有需要的列都进键）

这是每个支持 B 树索引的引擎都能用的路线，区别只在"是否值得"。

| 引擎 | 复合键覆盖 | 备注 |
|------|-----------|------|
| PostgreSQL | 是 | 可行但 11 之后推荐 INCLUDE |
| MySQL / MariaDB | 是 | 唯一路线 |
| SQLite | 是 | 常配合 WITHOUT ROWID |
| Oracle | 是 | 配合 index-only scan 识别 |
| SQL Server | 是 | 2005 之后推荐 INCLUDE |
| DB2 | 是 | 非唯一索引唯一路线 |
| CockroachDB | 是 | 但推荐 STORING |
| TiDB | 是 | 优化器自动识别 |
| OceanBase | 是 | MySQL 兼容唯一路线 |

### Index-only scan 识别（EXPLAIN）

| 引擎 | EXPLAIN 标识 |
|------|--------------|
| PostgreSQL | `Index Only Scan using idx_xxx` |
| MySQL | `Extra: Using index` |
| MariaDB | `Extra: Using index` |
| Oracle | `INDEX FAST FULL SCAN` / `INDEX RANGE SCAN` (无 `TABLE ACCESS BY ROWID` 即为 index-only) |
| SQL Server | `Index Seek`/`Index Scan` without `Key Lookup` / `RID Lookup` |
| DB2 | `IXSCAN` without `FETCH` operator |
| SQLite | `SEARCH ... USING COVERING INDEX idx_xxx` |
| CockroachDB | `scan` on index, no `index join` |
| TiDB | `IndexReader` (非 `IndexLookUp`) |
| YugabyteDB | `Index Only Scan` |
| SingleStore | `Covering Index` hint in profile |
| Greenplum | `Index Only Scan` |

### INCLUDE 用于 UNIQUE 索引

`CREATE UNIQUE INDEX ... INCLUDE` 是非常有价值的模式：它允许在"键列的子集"上强制唯一性约束，同时把其他列附加进来用于覆盖查询。

| 引擎 | UNIQUE + INCLUDE | 用途 |
|------|------------------|------|
| SQL Server | 是 | 标志性模式 |
| DB2 | 是 (v7+) | DB2 最初引入 INCLUDE 就是为了这个 |
| PostgreSQL | 是 (11+) | 支持，唯一性仅由键列约束 |
| CockroachDB | 是 | STORING on UNIQUE |
| YugabyteDB | 是 | 继承 PG |
| Greenplum | 是 | 继承 PG 12 |
| Azure Synapse | 是 | 继承 SQL Server |
| Spanner | 是 | UNIQUE INDEX ... STORING |
| 其他 | 无 | 只能走复合键 |

### INCLUDE 用于部分索引

| 引擎 | Partial + INCLUDE |
|------|-------------------|
| PostgreSQL | 是 (11+，与 WHERE 子句组合) |
| SQL Server | 是 (filtered index + INCLUDE) |
| CockroachDB | 是 |
| YugabyteDB | 是 |
| DB2 | 部分索引本身功能有限 |
| 其他 | 通常不支持 |

### INCLUDE 列数上限

| 引擎 | INCLUDE 最大列数 | 索引行大小限制 |
|------|-----------------|---------------|
| SQL Server | 1023 (含键列至多 1024) | ~1700 字节（非聚簇）、~900 字节（键） |
| PostgreSQL | 32 (索引列总数限制) | 1/3 of 8KB 页 ≈ 2704 字节 |
| DB2 LUW | 64 (总列数) | 页大小相关（最大 32K 页约 8101 字节）|
| CockroachDB | 实际无硬限制 | KV 值大小限制 |
| Azure Synapse | 1023 | 同 SQL Server |
| Spanner | 实际受限于 10 MB 索引行 | 10 MB |
| Greenplum | 32 | 同 PG |
| YugabyteDB | 32 | 同 PG，外加 DocDB 限制 |

## 各引擎详解

### SQL Server — INCLUDE 的诞生地 (2005)

SQL Server 2005 (v9) 引入 `CREATE INDEX ... INCLUDE` 是业界第一个把"非键列挂叶子节点"提升为一等语法的引擎。此前 SQL Server 2000 只能用复合键覆盖，但键列不能超过 16 个或 900 字节，而且 `varchar(max)`/`text`/`image`/`xml` 根本不能做键列。`INCLUDE` 一举解除了这三项限制。

```sql
-- 经典 OLTP 覆盖索引模式
CREATE NONCLUSTERED INDEX idx_orders_user_covering
    ON dbo.Orders (user_id)
    INCLUDE (order_date, amount, status, shipping_address);

-- UNIQUE + INCLUDE: 在 (tenant_id, email) 上强制唯一
-- 同时把其他常用查询列挂进叶子
CREATE UNIQUE NONCLUSTERED INDEX uq_users_tenant_email
    ON dbo.Users (tenant_id, email)
    INCLUDE (display_name, avatar_url, created_at);

-- Filtered index + INCLUDE: 只为活跃订单建覆盖索引
CREATE NONCLUSTERED INDEX idx_active_orders
    ON dbo.Orders (user_id, order_date)
    INCLUDE (amount, status)
    WHERE is_deleted = 0;
```

INCLUDE 列的关键属性：

1. **不参与 B 树排序**：内部节点只存键列，B 树高度取决于键列大小
2. **不参与唯一性约束**：`UNIQUE INDEX (a) INCLUDE (b)` 中唯一性只看 a
3. **不能用于 WHERE 裁剪**：查询 `WHERE status = 'A'` 时，status 如果在 INCLUDE 里，需要扫描整个索引而非 seek
4. **突破 900 字节键长度限制**：INCLUDE 列总大小可达 ~1700 字节
5. **允许 LOB 类型**：`varchar(max)`、`nvarchar(max)`、`xml` 都能 INCLUDE，但不能作为键

**经典陷阱**：初学者容易把所有查询列都塞进 INCLUDE，导致索引变成"表的副本"。每增加一个 INCLUDE 列，每次 UPDATE 该列都要更新索引。合理的上限是 3-5 个高频投影列。

执行计划识别：
```sql
SET STATISTICS IO ON;
SELECT order_date, amount, status
FROM Orders
WHERE user_id = 42;
-- 期望: Index Seek on idx_orders_user_covering
-- 不期望: Key Lookup 或 RID Lookup
```

如果看到 `Key Lookup`，说明查询还需要回到聚簇索引取额外列，覆盖没有生效。

### PostgreSQL — 11 版本的 INCLUDE 革命 (2018)

PostgreSQL 11 (2018 年 10 月) 通过 commit `8224de4f42c` 引入了 `INCLUDE` 子句。在此之前，想要覆盖索引只能把所有列做成复合键，缺点是：

1. B 树叶子和内部节点都存完整元组，增加 I/O
2. 影响 B 树 fillfactor 与分裂行为
3. 无法把非 btree-支持类型放进 UNIQUE 索引

PostgreSQL 11 的实现精髓在于：**INCLUDE 列只存在于叶子节点，不进入 B 树内部页**。内部节点只用键列做导航，叶子页才挂上 payload。这使得索引的内部节点保持紧凑，查询时的 B 树高度和非覆盖场景相同。

```sql
-- B-tree 覆盖索引
CREATE INDEX idx_orders_user ON orders (user_id)
    INCLUDE (order_date, amount, status);

-- UNIQUE + INCLUDE
CREATE UNIQUE INDEX uq_users_email ON users (email)
    INCLUDE (display_name, created_at);

-- Partial + INCLUDE (PG 11 起支持组合)
CREATE INDEX idx_active_orders ON orders (user_id, order_date)
    INCLUDE (amount)
    WHERE status = 'active';

-- 表达式键 + INCLUDE
CREATE INDEX idx_lower_email ON users (lower(email))
    INCLUDE (user_id, display_name);
```

**版本演进**：
- 11 (2018): B-tree 支持 INCLUDE
- 12 (2019): GiST 范围类型支持 INCLUDE (commit `c1c456e50`)
- 13 (2020): `pg_stat_statements` 支持统计 index-only scan
- 14 (2021): SP-GiST 支持 INCLUDE
- 后续版本主要优化 visibility map 命中率

**Visibility map 的微妙性**：PostgreSQL 的 MVCC 让 index-only scan 变得复杂——即使所有列都在索引里，如果行的可见性无法从 visibility map 确认，仍然需要回堆页。所以看到 `Index Only Scan` 后还要看 `Heap Fetches`：

```
Index Only Scan using idx_orders_user on orders
  (cost=0.56..8.58 rows=1 width=28) (actual time=0.015..0.016 rows=1 loops=1)
  Index Cond: (user_id = 42)
  Heap Fetches: 0   -- 关键：=0 才是真正的 index-only
```

为了保持 visibility map 的新鲜度，频繁更新的表需要配合 `VACUUM` 或 `autovacuum` 调优。

### Oracle — 没有 INCLUDE，但覆盖一样有效

Oracle 至今（23c/23ai）没有 `INCLUDE` 语法。官方立场是：复合键已经够用，而且 Oracle 的 B 树索引对复合键的处理非常高效（前缀压缩、叶块压缩）。

```sql
-- 复合键覆盖
CREATE INDEX idx_orders_covering
    ON orders (user_id, order_date, amount, status);

-- Index Organized Table (IOT) 等价全覆盖
CREATE TABLE orders_iot (
    order_id NUMBER PRIMARY KEY,
    user_id NUMBER,
    order_date DATE,
    amount NUMBER,
    status VARCHAR2(20)
) ORGANIZATION INDEX;

-- 在 IOT 上可以再建 overflow segment 分离低频列
CREATE TABLE orders_iot (
    order_id NUMBER PRIMARY KEY,
    user_id NUMBER,
    order_date DATE,
    amount NUMBER,
    status VARCHAR2(20),
    notes CLOB
) ORGANIZATION INDEX
  PCTTHRESHOLD 20
  INCLUDING status
  OVERFLOW TABLESPACE users;
```

注意最后这个 `INCLUDING` 不是 SQL Server 式的 INCLUDE，它是 IOT 用于指定"哪个列开始溢出到 overflow segment"的分界符。语法相似但语义完全不同。

**识别 index-only scan**：
```
Execution Plan
----------------------------------------------------------
Plan hash value: 12345
--------------------------------------
| Id  | Operation        | Name       |
--------------------------------------
|   0 | SELECT STATEMENT |            |
|*  1 |  INDEX RANGE SCAN| IDX_ORDERS |   <-- 没有 TABLE ACCESS BY INDEX ROWID = covering
--------------------------------------
```

只要执行计划中**没有 `TABLE ACCESS BY INDEX ROWID`**，就是 index-only scan 生效。

### MySQL / MariaDB — 只有复合键一条路

MySQL InnoDB 的聚簇索引设计决定了：所有二级索引叶子存的是主键而非 RID，回表就是基于主键的 B 树查找。覆盖索引的实现只能是把需要的列全部做成联合索引键：

```sql
-- 复合键覆盖
CREATE INDEX idx_orders_user_cover
    ON orders (user_id, order_date, amount, status);

-- 主键包含的列天然覆盖
-- 在 InnoDB 中，二级索引叶子自带主键列
CREATE TABLE orders (
    order_id BIGINT PRIMARY KEY,
    user_id BIGINT,
    order_date DATETIME,
    amount DECIMAL(10,2),
    status VARCHAR(20),
    INDEX idx_user (user_id)   -- 叶子自带 order_id
);

-- 上面的查询如果只选 user_id 和 order_id 就天然被 idx_user 覆盖
SELECT order_id FROM orders WHERE user_id = 42;
-- EXPLAIN Extra: Using index
```

社区对 `INCLUDE` 语法的需求有很多年了（MySQL Bug #79635 等），但 MySQL 团队优先级一直不高。MariaDB 也尚未跟进。

MySQL 8.0 的 `functional index`（表达式索引）不支持 INCLUDE，必须把表达式键之外的列也做成键。

### DB2 — 最早引入 INCLUDE 语法 (2000)

DB2 LUW v7 (2000 年) 早在 SQL Server 2005 之前就在 `UNIQUE INDEX` 上支持 `INCLUDE`。设计动机非常直接：想在 (a, b) 上建唯一约束，但 (a, b, c) 的查询频繁——不得不在建一个单独的复合索引，现在只需要一个 UNIQUE + INCLUDE。

```sql
-- DB2 经典用法
CREATE UNIQUE INDEX uq_emp
    ON employee (emp_id)
    INCLUDE (first_name, last_name, dept_id);

-- DB2 z/OS (v10+) 同样支持
CREATE UNIQUE INDEX ADMIN.UQ_EMP
    ON ADMIN.EMPLOYEE (EMP_ID ASC)
    INCLUDE (FIRST_NAME, LAST_NAME, DEPT_ID)
    USING STOGROUP SYSDEFLT;
```

DB2 的限制比 SQL Server 更严：**只有 UNIQUE INDEX 能用 INCLUDE**。非唯一索引想覆盖只能走复合键。这是一个长期被社区诟病的设计。

### SQLite — WITHOUT ROWID + 复合键

SQLite 没有 `INCLUDE` 语法。覆盖索引的实现有两种：

```sql
-- 1. 复合键覆盖
CREATE INDEX idx_orders_cover ON orders (user_id, order_date, amount, status);

-- EXPLAIN QUERY PLAN 显示:
-- SEARCH orders USING COVERING INDEX idx_orders_cover (user_id=?)

-- 2. WITHOUT ROWID: 整张表组织为聚簇索引 (类似 Oracle IOT)
CREATE TABLE orders (
    user_id INTEGER,
    order_id INTEGER,
    order_date TEXT,
    amount REAL,
    status TEXT,
    PRIMARY KEY (user_id, order_id)
) WITHOUT ROWID;
```

SQLite 的 EXPLAIN QUERY PLAN 在覆盖生效时会明确打出 `USING COVERING INDEX` 字样，非常清晰。

### CockroachDB — STORING 从 v1.0 起 (2017)

CockroachDB 从 2017 年 v1.0 起就支持 `STORING` 子句，这个名字源自 Google Spanner。v2.1 起也兼容 PostgreSQL 11 的 `INCLUDE` 语法作为同义词。

```sql
-- STORING 写法（CockroachDB 原生）
CREATE INDEX idx_orders_user
    ON orders (user_id)
    STORING (order_date, amount, status);

-- INCLUDE 写法（PG 兼容）
CREATE INDEX idx_orders_user
    ON orders (user_id)
    INCLUDE (order_date, amount, status);

-- UNIQUE + STORING
CREATE UNIQUE INDEX uq_users_email
    ON users (email)
    STORING (display_name, avatar_url);
```

CockroachDB 的索引实现基于 KV 存储层 (RocksDB/Pebble)，每个索引项是一条 KV pair，STORING 列直接作为 value 的一部分。这个设计天然支持 INCLUDE，没有页大小约束——但索引项变大会增加 Raft 日志复制的带宽压力。

**与 Spanner 的渊源**：Google Spanner 的论文（2012）就定义了 `STORING` 子句，CockroachDB 直接采用了这个命名。Spanner 自身的 DDL：

```sql
CREATE INDEX idx_orders_user
    ON Orders (user_id)
    STORING (order_date, amount, status);
```

### YugabyteDB — PG 兼容 + LSM 存储

YugabyteDB 的 YSQL 层完整继承 PostgreSQL 11，因此 `INCLUDE` 语法原生可用。但存储层是基于 RocksDB 的 DocDB，没有 PG 的 visibility map 机制，其 MVCC 通过混合逻辑时钟 (HLC) 实现：

```sql
CREATE INDEX idx_orders_user
    ON orders (user_id)
    INCLUDE (order_date, amount, status);
```

由于不需要堆访问检查可见性，YugabyteDB 的 index-only scan 不存在 PG 的 `Heap Fetches > 0` 退化问题。

### TiDB — 无显式子句，优化器自动识别

TiDB 完全兼容 MySQL 协议和语法，也没有 `INCLUDE` 子句。但从 5.0 起，TiDB 优化器 (特别是基于 cost model 的 CBO) 在生成执行计划时会**自动检测**查询所需的投影列是否全部在某个索引中，从而选择 `IndexReader` (index-only) 而非 `IndexLookUp` (需回表)。

```sql
CREATE INDEX idx_cover ON orders (user_id, order_date, amount, status);

EXPLAIN SELECT amount, status FROM orders WHERE user_id = 42;
-- id           | task     | operator info
-- IndexReader  | root     | index:IndexRangeScan
-- IndexRangeScan| cop[tikv]| table:orders, index:idx_cover, range:[42,42]
```

看到 `IndexReader` 就是覆盖成功；看到 `IndexLookUp` 就是回表。

### ClickHouse — 列存模型下的隐式覆盖

ClickHouse 和大多数列存引擎一样没有"索引"这个概念——主键是稀疏的 primary index (marks)，二级索引是 data skipping index（用于跳过 granule 而非精确定位）。

```sql
CREATE TABLE orders (
    user_id UInt64,
    order_date Date,
    amount Decimal(10,2),
    status String
) ENGINE = MergeTree
ORDER BY (user_id, order_date);

-- ORDER BY 键的前缀查询天然只读必需的 granule
SELECT amount, status FROM orders WHERE user_id = 42;
-- 执行时按 user_id 做二分定位到 mark range，读对应 granule 的 user_id/amount/status 列
-- 不需要访问其他列，天然"覆盖"
```

在列存中，"覆盖"的含义变成了"只读必需列的文件"。你选的列越少，I/O 越少——这是列存的本质优势。`INCLUDE` 子句在这个模型下没有意义。

### Vertica — Projection 替代覆盖索引

Vertica 用 **projection** 机制替代传统的行存覆盖索引。一张逻辑表可以有多个物理 projection，每个 projection 有自己的列排序和列子集：

```sql
CREATE PROJECTION orders_by_user
AS
SELECT user_id, order_date, amount, status
FROM orders
ORDER BY user_id
SEGMENTED BY hash(user_id) ALL NODES;
```

查询 `WHERE user_id = 42 SELECT amount, status` 会自动路由到该 projection。这是行存"覆盖索引"在列存 MPP 中的等价物。

### SingleStore / StarRocks / Doris — 列存 + 前缀索引

SingleStore 的 columnstore 表使用 sort key + 段级元数据做裁剪，二级索引只有 hash index (rowstore)。不支持 `INCLUDE`，但查询只读需要的列是默认行为。

StarRocks / Doris 用**前缀索引** (shortkey index) 标识数据文件的前 36 字节，配合 ZoneMap 和物化视图实现覆盖效果。

### SAP HANA — 列存主存 + inverted index

HANA 的主存列存表默认所有列都能"覆盖"任何查询——因为列存天然按列组织，投影不需要额外数据结构。`CREATE INDEX` 在 HANA 里主要是构建 inverted index 加速等值查找。

### Greenplum / TimescaleDB — 继承 PostgreSQL

Greenplum 7 (2023 年) 基于 PostgreSQL 12 内核，自动继承 `INCLUDE` 子句。TimescaleDB 作为 PG 扩展也继承。超表 (hypertable) 上建的索引会在每个 chunk (子表) 上自动创建对应的 INCLUDE 索引。

```sql
-- TimescaleDB 超表
SELECT create_hypertable('metrics', 'time');

CREATE INDEX idx_device_time
    ON metrics (device_id, time DESC)
    INCLUDE (temperature, humidity);
```

### Azure Synapse — 继承 SQL Server

Synapse Dedicated SQL Pool (原 SQL DW) 继承 SQL Server 行存索引语法，包括 `INCLUDE` 和 filtered index。Synapse Serverless / Spark Pool 使用外部表，无索引。

## SQL Server INCLUDE 深度解析

### 2005 年的设计动机

SQL Server 2000 的索引有两个硬约束：

1. 索引键列最多 16 列
2. 索引键总长度最多 900 字节
3. 大对象列 (`text`, `ntext`, `image`, `varchar(max)`) 完全不能做键

当时 Microsoft 收到的最频繁请求是："我想在订单表上建一个索引，键是 (customer_id)，但希望选 ship_address、notes 等 10 个列时都不回表。" 把这些列塞进键列要么超 16 列上限，要么超 900 字节，`varchar(max)` 的 notes 根本不可能。

2005 年 v9 引入 `INCLUDE` 子句，一次性解决所有三个问题：
- 键列仍然最多 16 (后来放宽到 32)
- 键长度仍然 900 字节
- INCLUDE 列最多 1023 列，总长度最多 1700 字节
- INCLUDE 允许 LOB 类型

### 叶子节点存储格式

```
B-tree 内部节点:
  [user_id=1 | page_ptr] [user_id=5 | page_ptr] ...
  只存键列，用于导航

叶子节点:
  [user_id=1, order_date=..., amount=..., status=..., RID]
  [user_id=1, order_date=..., amount=..., status=..., RID]
  ...
  键列 + INCLUDE 列 + 行定位符
```

INCLUDE 列完全不参与 B 树排序和分裂决策，所以插入性能只取决于键列的 clustering factor。但 UPDATE INCLUDE 列会触发索引行重写。

### 经典模式：UNIQUE + INCLUDE

```sql
-- 多租户系统的典型索引
CREATE UNIQUE NONCLUSTERED INDEX uq_tenant_user_email
    ON dbo.Users (tenant_id, email)
    INCLUDE (user_id, display_name, role, last_login_at);

-- 覆盖以下查询（都不需要回聚簇索引）：
SELECT user_id, display_name FROM Users WHERE tenant_id = 1 AND email = 'a@b.com';
SELECT role FROM Users WHERE tenant_id = 1 AND email = 'a@b.com';
```

唯一性约束只由 `(tenant_id, email)` 保证，INCLUDE 列只是 payload。

### Filtered Index + INCLUDE

```sql
-- 只为未删除的活跃用户建覆盖索引
CREATE NONCLUSTERED INDEX idx_active_users
    ON dbo.Users (tenant_id, status)
    INCLUDE (email, display_name)
    WHERE is_deleted = 0 AND status = 'active';
```

相比无过滤版本，索引体积可能只有 10%-30%，维护代价对应减少。

### INCLUDE 的隐形陷阱

1. **UPDATE 放大**：每次 UPDATE status 都要同时修改索引行
2. **索引体积膨胀**：INCLUDE 多个 `varchar(500)` 会让索引接近表大小
3. **不能用于谓词**：`WHERE status = 'A'` 如果 status 只在 INCLUDE 里，仍然是 index scan 而非 index seek
4. **统计信息不完整**：INCLUDE 列不参与 index statistics 的直方图，优化器估算时不考虑

## PostgreSQL INCLUDE vs 复合键

### 复合键的劣势

```sql
-- 做法 A: 复合键
CREATE INDEX idx_a ON orders (user_id, order_date, amount, status);
```

所有 4 个列都参与 B 树排序。内部节点每个 entry 包含完整的 4 列元组。对于 1 亿行的表、平均元组 40 字节：

- 叶子页数 ≈ 1亿 * 40 / 8192 ≈ 500K 页 ≈ 4 GB
- 内部节点层数取决于扇出，叶子元组越大扇出越小，树越高

```sql
-- 做法 B: INCLUDE
CREATE INDEX idx_b ON orders (user_id) INCLUDE (order_date, amount, status);
```

内部节点每个 entry 只有 `user_id` (8 字节) + page_ptr (4 字节)，扇出远高于做法 A。实际测量：

- 做法 A: B 树高度 4，内部节点占索引 5%
- 做法 B: B 树高度 3，内部节点占索引 1%

对于点查 `WHERE user_id = 42`，做法 B 少读一个内部页，且 buffer cache 中内部节点命中率更高。

### 语义差异

```sql
-- 做法 A 可以支持范围查询
SELECT * FROM orders WHERE user_id = 42 AND order_date > '2024-01-01';
-- 索引可以做 index cond 同时裁剪 user_id 和 order_date

-- 做法 B 不能在 order_date 上做裁剪
-- order_date 在 INCLUDE 中，只在叶子页扫描时过滤
```

结论：**如果你真的需要在多个列上做范围裁剪，用复合键；如果只是为了避免回表，用 INCLUDE。**

### UNIQUE 上的差异

```sql
-- 做法 A: 复合键 UNIQUE
CREATE UNIQUE INDEX uq_a ON users (tenant_id, email, display_name);
-- 唯一性是 (tenant_id, email, display_name) 三元组

-- 做法 B: INCLUDE
CREATE UNIQUE INDEX uq_b ON users (tenant_id, email) INCLUDE (display_name);
-- 唯一性只是 (tenant_id, email)
```

B 才是我们要的语义——同一个 tenant 下 email 唯一，但 display_name 可以改。做法 A 是错的。

## CockroachDB STORING 子句

CockroachDB 在 2017 年 v1.0 就支持 `STORING`。它源自 Spanner 论文，和 Spanner 保持完全一致的命名：

```sql
-- 等价写法
CREATE INDEX i1 ON t (a) STORING (b, c);
CREATE INDEX i2 ON t (a) INCLUDE (b, c);  -- v2.1+ 兼容
CREATE INDEX i3 ON t (a) COVERING (b, c); -- 废弃别名
```

### 与 PostgreSQL 的差异

1. **存储层不同**：CockroachDB 基于 KV (Pebble/RocksDB)，每个索引项是一个 KV pair，STORING 列直接进 value
2. **无 visibility map**：不需要额外检查，index-only 就是 index-only
3. **支持更多键类型**：CockroachDB 的 JSON inverted index 也可以 STORING
4. **无限 STORING 列**：理论上只受 KV value 大小限制 (通常 512 KB)

### Raft 复制的代价

STORING 列会让索引 KV 变大，每次 INSERT/UPDATE 需要复制更多字节到 follower。在跨区域部署（multi-region）场景下，这是一个真实的带宽成本。建议原则：

- 点查延迟敏感：用 STORING 覆盖 2-3 个热点列
- 写入吞吐敏感：避免过度 STORING
- 冷列（notes, description）不要进 STORING

## Index-only scan 识别

### PostgreSQL 完整执行计划

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_date, amount FROM orders WHERE user_id = 42;
```

```
Index Only Scan using idx_orders_user on orders
  (cost=0.56..8.58 rows=1 width=12)
  (actual time=0.015..0.016 rows=1 loops=1)
  Index Cond: (user_id = 42)
  Heap Fetches: 0
  Buffers: shared hit=3
Planning Time: 0.082 ms
Execution Time: 0.034 ms
```

关键字段：

- **Index Only Scan**：计划节点类型，说明使用了 index-only
- **Heap Fetches: 0**：表示 visibility map 告诉 PG 这些行都可见，无需回堆
- **Buffers: shared hit=3**：只访问了 3 个索引页

如果 `Heap Fetches > 0`，意味着 PG 仍需回表检查可见性，退化为普通 index scan 的性能。

### SQL Server 执行计划

在 SSMS 图形执行计划或 `SET STATISTICS PROFILE ON` 输出中：

好：`Index Seek (NonClustered) ... [idx_xxx]` 后直接是输出
坏：`Index Seek` 后跟随 `Key Lookup (Clustered)` 或 `RID Lookup (Heap)`

### MySQL EXPLAIN

```sql
EXPLAIN SELECT order_date FROM orders WHERE user_id = 42;
```

```
+----+-------------+--------+------+---------------+---------+---------+-------+------+-------------+
| id | select_type | table  | type | possible_keys | key     | key_len | ref   | rows | Extra       |
+----+-------------+--------+------+---------------+---------+---------+-------+------+-------------+
| 1  | SIMPLE      | orders | ref  | idx_user      | idx_user| 8       | const | 10   | Using index |
+----+-------------+--------+------+---------------+---------+---------+-------+------+-------------+
```

关键：`Extra` 列里有 `Using index` 即为覆盖成功。仅 `Using where` 或无 Extra 则为回表。

### Oracle AUTOTRACE

```sql
SET AUTOTRACE TRACEONLY EXPLAIN;
SELECT order_date, amount FROM orders WHERE user_id = 42;
```

```
Execution Plan
---------------
|  0 | SELECT STATEMENT                    |
|  1 |   INDEX RANGE SCAN| IDX_ORDERS_USER |
---------------
```

没有 `TABLE ACCESS BY INDEX ROWID ORDERS` 节点就是 index-only。

### CockroachDB / TiDB / YugabyteDB

```sql
-- CockroachDB
EXPLAIN SELECT ... FROM orders WHERE user_id = 42;
-- 期望: scan (单节点) 无 index join
-- 不期望: index join 节点

-- TiDB
EXPLAIN SELECT ... FROM orders WHERE user_id = 42;
-- 期望: IndexReader -> IndexRangeScan
-- 不期望: IndexLookUp

-- YugabyteDB
EXPLAIN SELECT ... FROM orders WHERE user_id = 42;
-- 期望: Index Only Scan (继承 PG)
```

## 何时该用覆盖索引

### 适用场景

1. **高频点查**：QPS > 1000 的 WHERE 等值查询
2. **固定投影**：应用层查询的列集合稳定
3. **窄投影**：覆盖 2-5 个高频列而非全表
4. **读多写少**：写放大代价可接受
5. **UNIQUE 约束 + 额外投影**：最经典的 `UNIQUE INDEX INCLUDE` 模式

### 不适用场景

1. **列很宽**：如 `varchar(4000)` 和 `text` 列不应随便 INCLUDE
2. **更新频繁**：列经常 UPDATE 会导致索引行频繁重写
3. **查询列集变化快**：应用层查询模式未稳定
4. **全表扫描更快**：小表或高选择率查询
5. **MVCC 未就绪**：PG 频繁更新表 + VM 未更新 → index-only 退化

### 与其他索引类型的组合

- **表达式索引 + INCLUDE**：`CREATE INDEX ... ON t (lower(email)) INCLUDE (user_id)` 既解决大小写不敏感查找又覆盖
- **部分索引 + INCLUDE**：只为 `status = 'active'` 的行建覆盖索引，索引大小下降 80%
- **GiST + INCLUDE** (PG 12+)：地理查询 `ST_Contains` 后返回 name、id 等，避免回表

## 设计争议

### INCLUDE 是否值得独立语法？

**支持派**：
- 明确分离"排序键"和"payload"两种语义
- 内部节点紧凑，B 树高度低
- 支持 LOB 类型作为 payload
- 让索引设计意图更清晰

**反对派**：
- 复合键已经能做，语法冗余
- 增加优化器复杂度（index-only vs composite-key 的成本模型）
- 用户容易误用，塞太多列导致索引膨胀

Oracle 和 MySQL 选择了反对派阵营，至今没有 INCLUDE。PostgreSQL 直到 11 才引入，算是中间派。

### 覆盖索引 vs 物化视图

覆盖索引的极限就是"部分表的冗余副本"，推到极致就是物化视图。两者的边界：

| 维度 | 覆盖索引 | 物化视图 |
|------|---------|---------|
| 新鲜度 | 实时 | 定期刷新（部分引擎支持增量）|
| 存储 | B 树，有序 | 可以有多种组织 |
| 更新代价 | 同步，每次 DML | 异步或手动 |
| 查询改写 | 优化器自动 | 需要显式或 Query Rewrite |
| 支持函数 | 键/INCLUDE 通常限制 | 任意 SELECT |

如果 INCLUDE 列太多，应该考虑物化视图或引入专门的"投影表"。

### 列存引擎是否需要覆盖索引？

纯列存引擎 (ClickHouse, BigQuery, Snowflake, Redshift) 几乎不需要传统意义上的覆盖索引。原因：

1. 列存天然只读必要列，I/O 天然最小
2. Zone map / min-max 元数据做粗粒度裁剪
3. 精确定位靠 sort key / clustering key

取而代之的是 sort key / projection / Z-order / bloom filter 等机制。INCLUDE 概念在列存中没有对应物。

## 对引擎开发者的建议

### 1. 优化器成本模型

INCLUDE 列的成本估算关键点：

- **索引扫描代价**：包含 INCLUDE 列后的索引行宽度
- **避免的堆访问**：估算回表次数 × 随机 I/O 代价
- **选择性估算**：INCLUDE 列不进入 histogram，需用基础表统计

```
cost_index_scan = num_index_pages * seq_page_cost
                + num_tuples * cpu_index_tuple_cost

cost_composite_scan = cost_index_scan
                    + num_matching_tuples * random_page_cost  -- 回表代价

cost_covering_scan = cost_index_scan  -- 无回表代价

// 优化器选择成本低者
```

### 2. 叶子页布局

建议把 INCLUDE 列放在叶子元组的尾部，并支持懒解析：

```
LeafTuple {
    header: 4 bytes        -- 元组头
    key_columns: variable  -- 参与 B 树排序
    tid/rid: 6 bytes       -- 行定位符
    include_columns: variable  -- 仅在 output 时解析
}
```

B 树搜索只需比较 key_columns，无需解析 include_columns，减少 CPU 开销。

### 3. UPDATE 路径优化

如果 UPDATE 只修改非 INCLUDE 列，可以完全跳过该索引的维护。引擎需要维护 column dependency graph：

```
index_dependencies = {
    'idx_orders_user_cover': {'user_id', 'order_date', 'amount', 'status'}
}

// UPDATE orders SET notes = '...' WHERE id = 1
// notes 不在任何索引中 -> 无需更新索引
```

### 4. DDL 的索引重建优化

从复合键改为 INCLUDE 等价变更时，优化器可以原地重写叶子页结构而不需要 full rebuild。CockroachDB 和 SQL Server 在部分情况下支持。

### 5. 索引体积监控

暴露索引级别的 INCLUDE 列贡献：

```sql
-- PostgreSQL
SELECT
    indexrelname,
    pg_relation_size(indexrelid) AS total_size,
    ... -- INCLUDE 列占比估算
FROM pg_stat_user_indexes;

-- SQL Server
SELECT ic.index_id, c.name, ic.is_included_column
FROM sys.index_columns ic
JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE ic.object_id = OBJECT_ID('dbo.Orders');
```

### 6. 测试覆盖清单

- `CREATE INDEX ... INCLUDE ()` 空 INCLUDE 列表
- 包含所有主键列的 INCLUDE（应报错或忽略）
- 包含与键列相同的列（应报错或去重）
- LOB 列 INCLUDE（SQL Server 支持，PG 不支持）
- UNIQUE + INCLUDE 下的并发插入冲突
- Partial + INCLUDE 下的 WHERE 改写
- INCLUDE 列 UPDATE 的索引维护
- Index-only scan 在 visibility/MVCC 边界下的正确性

## 关键发现

### 显式 INCLUDE 子句引擎约 11 个

在 45+ 引擎的考察中，直接支持 `INCLUDE` 或等价 `STORING` 子句的有：SQL Server (2005)、DB2 (v7, 仅 UNIQUE)、PostgreSQL (11, 2018)、CockroachDB (v1.0, 2017)、YugabyteDB (2.0)、TimescaleDB (继承 PG)、Greenplum (7)、Azure Synapse (继承 MSSQL)、Google Spanner (GA)、Oracle IOT 的 `INCLUDING` (语义不同)，以及部分小众引擎。

### 时间线

```
2000  DB2 v7         首个 INCLUDE（仅 UNIQUE）
2005  SQL Server v9  INCLUDE 一等公民，建立行业范式
2012  Google Spanner STORING 子句（论文）
2017  CockroachDB    STORING (v1.0)
2018  PostgreSQL 11  INCLUDE for B-tree
2019  PostgreSQL 12  INCLUDE for GiST
2023  Greenplum 7    继承 PostgreSQL 12 INCLUDE
```

### 两大阵营的哲学分歧

**INCLUDE 派**：SQL Server、PostgreSQL、DB2、Spanner、CockroachDB
主张：排序键与 payload 应分离，降低 B 树高度，增加表达力

**复合键派**：Oracle、MySQL、MariaDB
主张：复合键已经足够，避免语法膨胀和优化器复杂度

### INCLUDE 不能做什么

1. 不能用于 B 树排序、范围裁剪
2. 不参与唯一性约束
3. 不进入 histogram，不影响选择性估算
4. 不触发 index-only scan 以外的优化
5. 无法替代多列复合键的范围查询能力

### 列存 vs 行存的本质差异

在列存引擎（ClickHouse、Snowflake、BigQuery、Redshift、Vertica、SingleStore columnstore、StarRocks、Doris、DuckDB、Databend、Firebolt、Yellowbrick 等）中，覆盖索引的概念基本消失——列存天然只读必要列，zone map 做裁剪，sort key 定位。对于这些引擎，应从 sort key 和 projection 设计入手，而非追问"INCLUDE"。

### 经典 UNIQUE + INCLUDE 模式

最有价值的 INCLUDE 用法不是加速普通查询，而是：

```sql
CREATE UNIQUE INDEX uq_xxx
    ON t (key_subset)
    INCLUDE (other_projections);
```

一举解决"在键子集上强制唯一 + 覆盖查询"的组合需求——这是 DB2 和 SQL Server 最初引入 INCLUDE 的动机。

### MVCC 下的 index-only 陷阱

PostgreSQL 的 `Index Only Scan` 并不保证 zero heap access。频繁更新的表上 visibility map 可能不新鲜，导致每次查询仍回表。需要配合 `VACUUM` 调优或选择 LSM 存储的 YugabyteDB。

### 索引行大小限制

- SQL Server: ~1700 字节非聚簇 + 900 字节键
- PostgreSQL: 2704 字节（页的 1/3）
- DB2 LUW: 页大小相关（32KB 页约 8101 字节）
- CockroachDB: 512 KB (KV value)
- Spanner: 10 MB (索引行)

超过限制会导致 CREATE INDEX 失败，或在 SQL Server 上自动转为 B 树 off-page 存储。

### 最终选型建议

| 场景 | 推荐方案 |
|------|---------|
| OLTP 高频点查（SQL Server/PostgreSQL 系）| UNIQUE/普通 INDEX + INCLUDE 2-5 个列 |
| MySQL / MariaDB / TiDB / OceanBase | 复合键覆盖，利用 InnoDB 聚簇索引 |
| Oracle | 复合键覆盖或 IOT |
| 多租户应用 | `UNIQUE (tenant_id, key) INCLUDE (projections)` 模式 |
| 分布式 OLTP (CockroachDB/YugabyteDB) | STORING/INCLUDE，但注意 Raft 带宽 |
| 列存分析 (ClickHouse/Snowflake/BigQuery) | 不需要 INCLUDE，用 sort key / projection |
| 地理查询 | PostgreSQL GiST + INCLUDE (12+) |
| 大对象 payload | SQL Server INCLUDE (支持 LOB) |

## 参考资料

- SQL Server 文档: [CREATE INDEX (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-index-transact-sql)
- SQL Server: [Create Indexes with Included Columns](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/create-indexes-with-included-columns)
- PostgreSQL: [CREATE INDEX](https://www.postgresql.org/docs/current/sql-createindex.html) (INCLUDE clause)
- PostgreSQL commit `8224de4f42c` (2018): "Indexes with INCLUDE columns and their support in B-tree"
- DB2 LUW: [CREATE INDEX](https://www.ibm.com/docs/en/db2/11.5?topic=statements-create-index)
- DB2 z/OS: [CREATE INDEX](https://www.ibm.com/docs/en/db2-for-zos/13)
- Oracle: [Index-Organized Tables](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/indexes-and-index-organized-tables.html)
- CockroachDB: [STORING clause](https://www.cockroachlabs.com/docs/stable/create-index)
- YugabyteDB: [CREATE INDEX](https://docs.yugabyte.com/preview/api/ysql/the-sql-language/statements/ddl_create_index/)
- Google Spanner: [Secondary indexes](https://cloud.google.com/spanner/docs/secondary-indexes)
- TiDB: [Use covering indexes](https://docs.pingcap.com/tidb/stable/choose-index)
- SQLite: [Query Planning — Covering Indexes](https://www.sqlite.org/queryplanner.html)
- MySQL: [8.3.5 Column Indexes and 8.3.6 Multiple-Column Indexes](https://dev.mysql.com/doc/refman/8.0/en/multiple-column-indexes.html)
- Corbett et al. "Spanner: Google's Globally-Distributed Database" (OSDI 2012)
- 相关文档: [索引类型与创建语法](./index-types-creation.md)、[表达式索引](./expression-indexes.md)、[部分索引](./partial-indexes.md)
