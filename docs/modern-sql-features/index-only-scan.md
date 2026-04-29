# 仅索引扫描 (Index-Only Scan)

当一条查询在执行期间完全没有触碰堆 (heap) 或主表数据，所有需要的列直接从索引页读出——这就是 **Index-Only Scan**（仅索引扫描）。它不是建索引时的语法选择，而是查询执行时的技术成果：能否实现取决于索引内容、表组织方式（堆 vs 聚簇）、MVCC 可见性机制、统计信息和优化器决策五者的综合作用。一次成功的 index-only scan 通常意味着 I/O 减少 50%-95%，延迟从毫秒级降到微秒级。

## 与"覆盖索引"的边界

仅索引扫描 (index-only scan) 和覆盖索引 (covering index) 是两个常被混用、但严格意义上属于不同层次的概念：

| 概念 | 层次 | 关注点 |
|------|------|------|
| **覆盖索引 / INCLUDE** | DDL 与存储设计 | 索引能不能装下查询所需的所有列（数据布局）|
| **仅索引扫描 / Index-Only Scan** | 查询执行 | 实际执行时是否真的完全跳过了堆访问（运行时行为）|

一条覆盖索引并不必然产生 index-only scan：PostgreSQL 即使有完整的覆盖索引，如果 visibility map (VM) 不能确认行的可见性，仍然要回堆，这次执行就只是普通 Index Scan，不是 Index Only Scan。反之，没有 INCLUDE 子句的引擎（Oracle/MySQL）也能依靠复合索引或 InnoDB 聚簇索引的特性达成 index-only 的效果。本文聚焦后者——执行期的实际行为、可见性检查、扫描算子设计——而 [`covering-indexes.md`](./covering-indexes.md) 聚焦前者的语法和存储设计。

## SQL 标准立场

SQL 标准（包括 SQL:2023）从不涉及索引或扫描算子，它停留在逻辑层。Index-Only Scan、Index Fast Full Scan、Using Index、IndexReader 等都是各引擎在执行计划层的术语扩展。没有 ISO 参考语义，因此不同引擎的"index-only"含义有微妙差异（特别是 PostgreSQL 因 MVCC 引入的 visibility map 检查）。

## 为什么要有 Index-Only Scan

考虑一张 1 亿行的 `orders` 表（堆 200 GB），二级索引 `idx_user (user_id)` 仅 1.5 GB：

```sql
SELECT user_id FROM orders WHERE user_id = 42;
```

查询只需要 `user_id`，且 `user_id` 已在索引里。理论上完全不需要访问堆。但能否真正避开堆，取决于：

1. 索引叶子页里是否包含 `user_id`（B 树索引天然包含，所以是）
2. 引擎是否支持仅返回索引列而不回表（取决于优化器和算子实现）
3. MVCC 引擎下行的可见性能否在不读堆的情况下确认（取决于 visibility map / 时间戳机制）
4. 表的组织方式：聚簇表（InnoDB / SQL Server）vs 堆表（PostgreSQL / Oracle 默认）
5. 索引扫描算子是否被优化器选中（基于成本模型）

任何一个环节失败，执行就会退化为 Index Scan + Heap Fetch，性能差异往往是 10x-100x。

## 支持矩阵（综合）

### Index-Only Scan 整体支持

| 引擎 | EXPLAIN 标识 | 起始版本 | 备注 |
|------|--------------|---------|------|
| PostgreSQL | `Index Only Scan` | 9.2 (2012) | 需 visibility map 配合 |
| MySQL (InnoDB) | `Extra: Using index` | 4.0 (早期) | 聚簇索引天然覆盖 |
| MariaDB | `Extra: Using index` | 5.x+ | 同 InnoDB |
| SQLite | `USING COVERING INDEX` | 3.7+ | EXPLAIN QUERY PLAN |
| Oracle | `INDEX FAST FULL SCAN` / 无 `TABLE ACCESS BY ROWID` | 6+ (1990s) | 行存堆/IOT 均支持 |
| SQL Server | `Index Seek/Scan` 无 `Key/RID Lookup` | 2000+ | 聚簇索引即数据 |
| DB2 LUW | `IXSCAN` 无 `FETCH` | v6+ | Index-Only Access |
| DB2 z/OS | `IXSCAN` 无 `FETCH` | 早期 | Index-Only Access |
| Snowflake | -- | -- | 无传统索引概念 |
| BigQuery | -- | -- | 列存裁剪等价 |
| Redshift | -- | -- | 列存 + zone map |
| DuckDB | 列裁剪 | -- | 列存自然行为 |
| ClickHouse | 主键稀疏 + 列裁剪 | -- | 列存自然行为 |
| Trino | -- | 视连接器而定 | 无独立索引 |
| Presto | -- | 视连接器而定 | 同 Trino |
| Spark SQL | -- | -- | 列存裁剪 |
| Hive | -- | -- | 索引早期废弃 |
| Flink SQL | -- | -- | 流处理 |
| Databricks | -- | -- | Delta + Z-order |
| Teradata | `Covered Index` | V2R6+ | NUSI 直接覆盖 |
| Greenplum | `Index Only Scan` | 6+ (PG12) | 继承 PG |
| CockroachDB | `scan` (无 index join) | 18.x (统一术语) | 名义为 STORING |
| TiDB | `IndexReader` (非 `IndexLookUp`) | 3.0+ | 优化器自动识别 |
| OceanBase | `INDEX SCAN` 无回表 | 4.0+ | MySQL 兼容 |
| YugabyteDB | `Index Only Scan` | 2.0+ | LSM 存储无 VM |
| SingleStore | `Covering Index` 提示 | 7.0+ | profile 中可见 |
| Vertica | Projection 命中 | 早期 | projection 替代 |
| Impala | -- | -- | 无索引 |
| StarRocks | 物化视图命中 | 2.x | 列存 + 物化视图 |
| Doris | 物化视图命中 | 1.x | 列存 + 物化视图 |
| MonetDB | 列裁剪 | -- | 列存自然行为 |
| CrateDB | -- | -- | Lucene 倒排 |
| TimescaleDB | `Index Only Scan` | 继承 PG | chunk 级 VM |
| QuestDB | -- | -- | 时序模型 |
| Exasol | 自动索引命中 | -- | 自动索引透明 |
| SAP HANA | 列存隐式 | 2.0+ | 主存列存 |
| Informix | `Index Only` | 9.x+ | DataBlade 时代术语 |
| Firebird | 索引扫描覆盖 | 2.5+ | EXPLAIN 中标注 |
| H2 | -- | -- | 简单覆盖识别 |
| HSQLDB | -- | -- | 简单覆盖识别 |
| Derby | -- | -- | 不广泛优化 |
| Amazon Athena | -- | 同 Trino | 无独立索引 |
| Azure Synapse | 同 SQL Server | GA | 行存索引继承 SQL Server |
| Google Spanner | `Index Scan` (无 base table fetch) | GA | STORING 子句配合 |
| Materialize | -- | -- | dataflow 物化 |
| RisingWave | -- | -- | 流物化视图 |
| InfluxDB (SQL) | -- | -- | 时序列存 |
| DatabendDB | 列存裁剪 | -- | 列存 + bloom |
| Yellowbrick | 列存裁剪 | -- | MPP 列存 |
| Firebolt | 列存裁剪 | -- | aggregating index 不同模型 |

> 统计：约 17 个引擎在行存/B 树语义下提供严格意义的 "Index-Only Scan"；约 18 个引擎是列存或 MPP 体系，其等价实现是"列裁剪 + zone map"，与传统 index-only 概念形态不同；其余少数引擎不实现或不广泛优化。

### Visibility Map / MVCC 可见性策略

PostgreSQL 风格的堆 + MVCC 引擎需要专门的 visibility map (VM) 才能让 index-only scan 真正避开堆。其他引擎依赖不同的可见性机制。

| 引擎 | 是否需要 VM | 可见性机制 | 备注 |
|------|------------|----------|------|
| PostgreSQL | 是 | Visibility Map (`vm` fork) | all-visible bit 在 9.2 引入 |
| Greenplum | 是 (heap) / 否 (AO) | 同 PG / append-only 段 | append-only 表无 VM |
| TimescaleDB | 是 | 继承 PG VM | 每 chunk 独立 VM |
| MySQL (InnoDB) | 否 | 聚簇索引内含数据 + undo log MVCC | 二级索引覆盖时无需访问堆 |
| MariaDB (InnoDB) | 否 | 同上 | -- |
| Oracle | 否 | rollback segment + ITL (Interested Transaction List) | 行版本可在块内判定 |
| SQL Server | 否 | 聚簇索引/堆 + lock-versioned | RCSI 通过 tempdb 版本存储 |
| DB2 | 否 | 行级锁 + Currently Committed | 锁机制为主 |
| SQLite | 否 | 锁 + WAL，无并发 MVCC | 单写多读 |
| YugabyteDB | 否 | HLC + DocDB MVCC | LSM 内含版本，无 VM |
| CockroachDB | 否 | HLC + Pebble MVCC | KV 内含版本 |
| Spanner | 否 | TrueTime | 索引项含时间戳 |
| TiDB | 否 | TSO + RocksDB MVCC | TiKV 自带版本 |
| OceanBase | 否 | 多版本行 + 转储 | 内置 MVCC |
| ClickHouse | 否 | MergeTree 不可变段 + 合并 | 主键稀疏，无 VM |
| Snowflake | 否 | micro-partition 时间旅行 | 多版本不可变文件 |
| BigQuery | 否 | 列存快照 | 不可变文件 |

> 注: PostgreSQL 是行业内独一无二在 index-only scan 路径上引入 visibility map 的引擎，这与它的堆 + MVCC 设计有关。其他引擎要么数据本身随索引（聚簇）、要么 MVCC 由外部版本存储承载，无须额外 bitmap。

### 部分可见性检查（partial visibility check）

| 引擎 | 部分检查策略 | 备注 |
|------|-------------|------|
| PostgreSQL | 按页检查 VM | 页若全可见 → 无需回堆；否则回堆 |
| Greenplum | 同 PG (heap) | append-only 表段级判定 |
| YugabyteDB | 不需要 | DocDB 自含版本 |
| Oracle | ITL 块级判断 | 块内能判定可见 → 无需 rollback 检查 |
| InnoDB | 二级索引保留 trx_id + delete-mark | 部分可见的行可走 lazy 回主键 |
| SQL Server | RCSI 行版本检查 | 行版本指针在记录头 |

### 元组可见性快速判定（tuple bypass）

| 引擎 | 快速判定方式 |
|------|--------------|
| PostgreSQL | VM all-visible bit |
| InnoDB | 二级索引 page header 中的 max_trx_id |
| Oracle | 块 SCN + ITL |
| SQL Server | row version pointer |
| YugabyteDB | DocDB key 包含 hybrid time |
| CockroachDB | Pebble key 包含 timestamp |

### PRIMARY KEY 索引覆盖（聚簇 / IOT）

聚簇表的主键索引天然"覆盖"任意列查询，因为数据本身就在主键叶子节点中。

| 引擎 | 聚簇 / IOT | PK 即数据 | 二级索引经主键回表 |
|------|-----------|----------|----------------|
| MySQL InnoDB | 是 | 是 | 是（主键 lookup）|
| MariaDB InnoDB | 是 | 是 | 是 |
| SQL Server (聚簇表) | 是 | 是 | 是 |
| SQL Server (堆表) | 否 | 否 | 否（用 RID） |
| Oracle IOT | 是 | 是 | 是 |
| Oracle 普通堆 | 否 | 否 | 否（用 ROWID） |
| SQLite (默认 ROWID) | 否 | 否 | 否（用 rowid） |
| SQLite WITHOUT ROWID | 是 | 是 | 是 |
| PostgreSQL | 否 (heap) | 否 | 否（用 ctid） |
| PostgreSQL CLUSTER | 物理排序快照 | 否 | 否 |
| TiDB (聚簇表) | 是 (CLUSTERED) | 是 | 是 |
| TiDB (非聚簇) | 否 (NONCLUSTERED) | 否 | 否（用 _tidb_rowid） |
| OceanBase | 是 | 是 | 是 |
| CockroachDB | 是（PK 即 KV）| 是 | 是 |
| YugabyteDB | 是（PK 即 DocKey） | 是 | 是 |
| Spanner | 是 | 是 | 是 |
| ClickHouse | 是（主键即 ORDER BY）| 稀疏 | -- |

**关键观察**：在 InnoDB / Oracle IOT / TiDB CLUSTERED 这类**聚簇组织**的表中，"主键 = 数据本身"，因此凡是只查询主键列、或主键列加二级索引的列，都能走 index-only scan，不存在传统意义上的"回表"——因为主键索引本身就是表。

## 各引擎深度解析

### PostgreSQL — 9.2 引入 Index Only Scan + Visibility Map

PostgreSQL 在 9.2 (2012 年 9 月) 通过两个关键 commit 同时引入了 **Index Only Scan** 节点和 **Visibility Map 的 all-visible bit**，把这条优化路径打通：

- `7136a92` (2011): 添加 visibility map 的 all-visible 位
- `a2822fb` (2011): 引入 IndexOnlyScan 执行节点

在此之前（PG 9.1 及更早），即使索引包含所有需要的列，PG 也必须回堆——理由是 MVCC 下行的可见性只能通过堆元组里的 xmin/xmax 字段判断。

#### 为什么 PG 比其他堆引擎晚

Oracle、SQL Server、DB2 都在 1990 年代就支持 index-only access。PG 直到 2012 才支持，根本原因是 **MVCC 的实现差异**：

| 引擎 | MVCC 元数据位置 | 索引项是否需要回堆判可见性 |
|------|----------------|----------------------|
| Oracle | rollback segment + 块 ITL | 否（块级 ITL 即可判定）|
| SQL Server | tempdb version store + row pointer | 否（指针即可判定）|
| DB2 | 锁 + Currently Committed | 否（锁即可判定）|
| **PostgreSQL** | **堆元组 xmin/xmax** | **是（必须回堆）** |

PG 把 MVCC 元数据直接塞在堆元组里，没有外置的版本存储或锁版本机制。索引项本身没有 xmin/xmax，只能通过 ctid 回堆查 xmin/xmax。9.2 的 visibility map 是"廉价的妥协"：用一个 bit 表示这一页"上次 VACUUM 之后没有被修改过"，所以**只要 VM 说这页 all-visible，就可以信任索引项不需要回堆判可见性**。

#### Visibility Map 的内部结构

```
visibility_map fork (vm 文件):
  每页 8KB，每个 byte 对应 4 个 heap 页（2 bit 一页）
  bit 0: all-visible bit (9.2+)
  bit 1: all-frozen bit (9.6+)

heap 页:
  正常的元组数据，含 xmin/xmax/cmin/cmax/ctid
```

VM 的关键约束：

1. VM 比 heap 严格滞后——只有 VACUUM/autovacuum 才会设置 all-visible 位
2. 任何 INSERT/UPDATE/DELETE 都会清除该页的 all-visible 位
3. 写入频繁的表 VM 命中率低，index-only scan 退化

#### EXPLAIN 完整示例

```sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT user_id, order_date, amount
FROM orders
WHERE user_id BETWEEN 100 AND 200;
```

理想输出：

```
Index Only Scan using idx_orders_cover on public.orders
  (cost=0.43..256.78 rows=8500 width=24)
  (actual time=0.024..3.451 rows=8731 loops=1)
  Output: user_id, order_date, amount
  Index Cond: ((orders.user_id >= 100) AND (orders.user_id <= 200))
  Heap Fetches: 0
  Buffers: shared hit=58
Planning Time: 0.123 ms
Execution Time: 4.012 ms
```

关键观察 `Heap Fetches: 0`——这才是真正的 index-only。如果是：

```
Heap Fetches: 8731
```

那么实际上每行都回堆查了一次可见性，`Index Only Scan` 的命名变成了误导。

#### Heap Fetches > 0 的常见原因

```sql
-- 原因 1: VACUUM 未运行，VM 未更新
-- 修复
VACUUM ANALYZE orders;

-- 原因 2: autovacuum_vacuum_scale_factor 太宽松，频繁更新表 VM 不新鲜
-- 修复
ALTER TABLE orders SET (autovacuum_vacuum_scale_factor = 0.05);

-- 原因 3: 表刚被批量更新，VM 几乎全部清零
-- 修复: 立即手动 VACUUM

-- 原因 4: 长事务持有快照，VACUUM 无法 freeze
-- 修复: 检查 pg_stat_activity，杀掉长事务

-- 原因 5: hot_standby_feedback 在备库延迟回放，主库无法 freeze
-- 修复: 调整 max_standby_streaming_delay
```

#### 监控 index-only scan 健康度

```sql
-- pg_stat_user_indexes 的 idx_tup_fetch 是回堆次数
SELECT
    indexrelname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch,
    CASE WHEN idx_tup_read > 0
         THEN 100.0 * idx_tup_fetch / idx_tup_read
         ELSE 0 END AS heap_fetch_pct
FROM pg_stat_user_indexes
WHERE idx_scan > 0
ORDER BY heap_fetch_pct DESC;
```

heap_fetch_pct 接近 0 表示 index-only scan 命中良好；接近 100 表示等价于普通 index scan。

### MySQL InnoDB — 聚簇索引天然覆盖

MySQL/MariaDB InnoDB 没有 PG 那样的 visibility map，因为它的设计与 PG 根本不同：**InnoDB 表本身就是聚簇索引**。

```
InnoDB 表结构:
  主键索引（聚簇索引）:
    叶子节点 = 整行数据 + 主键 + trx_id + roll_pointer

  二级索引:
    叶子节点 = 索引列 + 主键

  二级索引隐含携带主键，因此"包含主键 + 索引键"的查询天然 index-only
```

这意味着：

1. 任何只 SELECT 索引列和主键列的查询，自动 index-only
2. 二级索引项已经有 `trx_id`，可以直接判定"删除标记"和"undo log 是否需要回查"
3. 二级索引覆盖时，绝大多数情况无需访问聚簇索引（即"堆"）

```sql
-- InnoDB 经典示例
CREATE TABLE orders (
    order_id BIGINT PRIMARY KEY,
    user_id BIGINT,
    order_date DATETIME,
    amount DECIMAL(10,2),
    INDEX idx_user (user_id)  -- 叶子节点: (user_id, order_id)
);

-- 这条查询天然 index-only（user_id 在键中，order_id 是隐含主键）
EXPLAIN SELECT order_id FROM orders WHERE user_id = 42;
-- type: ref, key: idx_user, Extra: Using index

-- 这条也是 index-only
EXPLAIN SELECT user_id, order_id FROM orders WHERE user_id = 42;
-- Extra: Using index

-- 这条不是 index-only，需要回聚簇索引取 amount
EXPLAIN SELECT amount FROM orders WHERE user_id = 42;
-- Extra: NULL (即使 type 是 ref)
```

#### 二级索引 + delete-mark + 回查规则

InnoDB 的二级索引在更新时**不会**立即同步到二级索引（除非该索引的列被修改）。删除时只标记 `delete-mark`，并在合适时机由 purge 线程清理。这意味着：

```
二级索引项可能包含已删除但尚未 purge 的版本。
读取时，InnoDB 必须检查:
  1. 索引项是否 delete-mark
  2. 索引项的 trx_id 对当前快照是否可见
  3. 如果不能确定，回主键查 undo log

简化条件：
  当索引项 trx_id < min_active_trx_id（即所有活跃事务都不会看到旧版本）
  且未 delete-mark
  则可以直接信任索引项 → 真正的 index-only
```

InnoDB 在 page header 维护 `max_trx_id`，用于快速判断"这一页所有项都比某个边界 trx_id 老"。这相当于一个粗粒度的 VM——但它在索引页内嵌，不需要单独 fork。

#### EXPLAIN 中识别

```sql
EXPLAIN FORMAT=JSON
SELECT order_id, user_id FROM orders WHERE user_id = 42;
```

```json
{
  "table": {
    "table_name": "orders",
    "access_type": "ref",
    "possible_keys": ["idx_user"],
    "key": "idx_user",
    "used_columns": ["order_id", "user_id"],
    "using_index": true
  }
}
```

`using_index: true` 即为 index-only scan 命中。

### Oracle — INDEX FAST FULL SCAN 与 INDEX_FFS hint

Oracle 在 6.x 版本（1990 年前后）就引入了 **INDEX FAST FULL SCAN** —— 一种专门为 index-only 查询设计的扫描方式。它绕过 B 树的有序遍历，直接按物理块顺序扫描索引段，类似全表扫描但读的是索引而非堆。

```sql
-- 标准 INDEX FAST FULL SCAN
SELECT /*+ INDEX_FFS(o idx_user) */ user_id
FROM orders o
WHERE user_id IS NOT NULL;
```

Oracle 的执行计划：

```
| Id  | Operation              | Name        | Rows  |
|   0 | SELECT STATEMENT       |             |  1000K|
|   1 |  INDEX FAST FULL SCAN  | IDX_USER    |  1000K|
```

如果是 INDEX RANGE SCAN（范围扫描）后没有 `TABLE ACCESS BY INDEX ROWID`，同样是 index-only：

```
| Id  | Operation         | Name      |
|   0 | SELECT STATEMENT  |           |
|*  1 |  INDEX RANGE SCAN | IDX_USER  |  -- 没有回表
```

#### INDEX FAST FULL SCAN vs INDEX FULL SCAN

```
INDEX FAST FULL SCAN:
  - 按物理块顺序读取，类似全表扫描
  - 多块读 (db_file_multiblock_read_count)
  - 不保证返回顺序
  - 用于 COUNT(*) / 不需要排序的聚合

INDEX FULL SCAN:
  - 按 B 树叶子链表顺序读取
  - 单块读
  - 保证按索引顺序返回
  - 用于 ORDER BY 索引列的查询
```

#### NULL 处理细节

Oracle 的 B 树索引**不存 NULL 值的项**（除非是组合索引的非首列）。所以：

```sql
SELECT user_id FROM orders;
-- 不能用 INDEX FAST FULL SCAN（会丢 NULL 行）
-- 优化器会选 TABLE ACCESS FULL

SELECT user_id FROM orders WHERE user_id IS NOT NULL;
-- 可以用 INDEX FAST FULL SCAN

-- NOT NULL 约束让优化器自动放心
ALTER TABLE orders MODIFY user_id NOT NULL;
SELECT user_id FROM orders;
-- 可以用 INDEX FAST FULL SCAN
```

#### IOT 上的 index-only

Index Organized Table (IOT) 在 Oracle 8 引入，本质就是聚簇表——主键索引就是数据。任何 SELECT 都是 index-only：

```sql
CREATE TABLE orders_iot (
    order_id NUMBER PRIMARY KEY,
    user_id NUMBER,
    amount NUMBER
) ORGANIZATION INDEX;

SELECT * FROM orders_iot WHERE order_id = 12345;
-- INDEX UNIQUE SCAN on SYS_IOT_TOP_xxx (主键索引即数据)
```

### SQL Server — 聚簇索引即数据

SQL Server 2000+ 的所有表要么有聚簇索引（rowstore 默认）、要么是堆表。聚簇索引的叶子节点直接是数据行；堆表通过 RID 定位。

#### 聚簇索引扫描即 index-only

```sql
CREATE CLUSTERED INDEX cx_orders_id ON Orders (order_id);

SELECT order_id, amount FROM Orders WHERE order_id = 1234;
-- Clustered Index Seek (cx_orders_id) - 这就是 index-only
-- 不需要任何 lookup
```

聚簇索引本身就是数据，不存在"覆盖 vs 回表"问题。

#### 非聚簇索引 + Key/RID Lookup

```sql
CREATE NONCLUSTERED INDEX idx_user ON Orders (user_id);

SELECT amount FROM Orders WHERE user_id = 42;
```

执行计划：

```
|--Nested Loops (Inner Join)
   |--Index Seek (NonClustered) on idx_user
   |--Clustered Index Seek (cx_orders_id) -- KEY LOOKUP，回聚簇索引
```

`Key Lookup` 出现就是回表。如果在堆表上则是 `RID Lookup`。

为了避免这个 lookup，把需要的列做 INCLUDE：

```sql
CREATE NONCLUSTERED INDEX idx_user_cover
    ON Orders (user_id) INCLUDE (amount);

SELECT amount FROM Orders WHERE user_id = 42;
-- Index Seek (NonClustered) on idx_user_cover - 没有 lookup
```

由于 SQL Server 没有 PG 风格的堆 + MVCC，无需 visibility map。在快照隔离 (RCSI/SI) 下，行版本存储在 tempdb 的 version store 中，索引项可以通过 row version pointer 直接定位历史版本。

### DB2 — Index-Only Access

DB2 在 v6 (1990s) 时代就支持 **Index-Only Access**。EXPLAIN 中的 `IXSCAN` 没有跟随 `FETCH` 算子即为 index-only：

```sql
-- DB2 db2exfmt 输出示例
1) RETURN: (Return)
   Cumulative Total Cost:      6.000000
   Cumulative CPU Cost:        ...

   2) IXSCAN: (Index Scan)
      INDEX_UNIQUE: TRUE
      Index: USER1.IDX_ORDERS_USER
      Predicate: USER_ID = 42
   -- 注意：没有 FETCH 节点 → index-only
```

普通 index scan 会有：

```
1) RETURN
   2) FETCH                  -- 这一步是回表
      3) IXSCAN
```

DB2 的 `INCLUDE` 子句（仅 UNIQUE 索引）从 v7 起支持，是业界最早的 INCLUDE 实现。但即使没有 INCLUDE，复合索引同样能走 index-only。

### CockroachDB — 18.x 起统一 Index-Only 术语

CockroachDB 早期（v1.0, 2017）就支持 STORING 子句和 index-only execution，但 EXPLAIN 输出曾用 `scan` (无 `index join`) 等隐式表达。从 18.x 起统一术语：

```sql
EXPLAIN SELECT user_id, amount FROM orders WHERE user_id = 42;
```

```
distribution: full
vectorized: true
• scan
  estimated row count: 8
  table: orders@idx_orders_user_storing
  spans: [/42 - /42]
```

如果出现 `index join` 节点，表示需要回主键索引取额外列：

```
• index join
  table: orders@primary
• scan
  table: orders@idx_orders_user
  spans: [/42 - /42]
```

CockroachDB 基于 Pebble (LSM)，所有 KV 项都包含 MVCC timestamp，无需 visibility map。

### TiDB — IndexReader vs IndexLookUp

TiDB 的 EXPLAIN 输出非常清晰地区分两种执行路径：

```sql
-- 命中 index-only（IndexReader）
EXPLAIN SELECT user_id, amount FROM orders WHERE user_id = 42;
```

```
| id                         | task      | operator info                              |
| Projection                 | root      | orders.user_id, orders.amount              |
| └─IndexReader              | root      | index:IndexRangeScan                       |
|   └─IndexRangeScan         | cop[tikv] | table:orders, index:idx_cover, range:[42,42]|
```

```sql
-- 未命中 index-only（IndexLookUp）
EXPLAIN SELECT amount, status FROM orders WHERE user_id = 42;
```

```
| IndexLookUp        | root      |                                            |
| ├─IndexRangeScan   | cop[tikv] | table:orders, index:idx_user, range:[42,42]|
| └─TableRowIDScan   | cop[tikv] | table:orders                               |
```

TiDB 的 TiKV 节点基于 RocksDB，每个 key 包含 MVCC version (TSO)，无 visibility map。

### YugabyteDB — Index Only Scan + LSM 存储无 VM 困境

YugabyteDB 的 YSQL 完整继承 PostgreSQL 11 的 `INCLUDE` 子句，EXPLAIN 输出 `Index Only Scan`：

```sql
EXPLAIN SELECT user_id, amount FROM orders WHERE user_id = 42;
```

```
Index Only Scan using idx_orders_user on orders
  Index Cond: (user_id = 42)
```

但与 PG 不同的是：**没有 `Heap Fetches` 字段**。原因是 YugabyteDB 底层 DocDB 基于 RocksDB，所有 key 都内嵌 hybrid logical clock (HLC) 时间戳，可见性判定完全在 LSM 层完成，无需访问"堆"——因为根本没有堆。

这避免了 PG index-only scan 的最大痛点：VM 不新鲜导致 Heap Fetches > 0 退化。代价是 LSM 的写放大和 compaction 开销。

### SAP HANA — 列存隐式 index-only

HANA 是主存列存数据库，每张表的每一列独立存储。任何 SELECT 都是"读取需要的列文件"，本质上等同于 index-only scan：

```sql
SELECT user_id, amount FROM orders WHERE user_id = 42;
-- 执行: 读 user_id 列文件做过滤 → 读 amount 列文件取值
-- 不存在"回表"概念
```

HANA 的 inverted index (`CREATE INDEX`) 加速等值查找，但 index-only 与否的概念被列存模型重新定义。

### ClickHouse — 主键稀疏索引 + 列存

ClickHouse 的 MergeTree 用稀疏 primary index + ORDER BY 键定位 granule，每个 granule 默认 8192 行：

```sql
CREATE TABLE orders (
    user_id UInt64,
    order_date Date,
    amount Decimal(10,2)
) ENGINE = MergeTree
ORDER BY (user_id, order_date);

SELECT user_id, amount FROM orders WHERE user_id = 42;
-- 执行: 按 user_id 二分定位 mark range
--      读取该 mark range 内的 user_id 和 amount 列文件
-- 没有"回表"，等价于 index-only
```

ClickHouse 没有传统意义的"二级索引"，data skipping index (minmax/set/bloom_filter) 也只是过滤 granule，不参与精确定位。

### Vertica — Projection 命中即 index-only 等价

Vertica 用 projection 替代覆盖索引。每张逻辑表可以有多个物理 projection，每个 projection 是一个排序+列子集副本：

```sql
CREATE PROJECTION orders_by_user
AS SELECT user_id, order_date, amount FROM orders
ORDER BY user_id;

SELECT amount FROM orders WHERE user_id = 42;
-- 优化器自动选择 orders_by_user projection
-- 等价于 index-only scan
```

EXPLAIN 输出会显示选中的 projection 名称。

### Greenplum — 继承 PG，但 AO 表不同

Greenplum 6+ 基于 PG 12 内核，对堆表（heap）继承 PG 的 Index Only Scan 和 visibility map。但 GP 特有的 **append-only (AO)** 表：

```sql
CREATE TABLE orders_ao (...) WITH (appendonly=true, orientation=row);

CREATE INDEX idx_user ON orders_ao (user_id);

EXPLAIN SELECT user_id FROM orders_ao WHERE user_id = 42;
-- AO 表上没有 visibility map，但可以用 visibility bitmap (vis map file)
-- AO 段级可见性判断
```

AO 表对 index-only scan 的支持在不同版本有变化，建议查阅当前版本文档。

### TimescaleDB — 继承 PG，每 chunk 独立 VM

TimescaleDB 的超表（hypertable）会按时间切分成 chunks（普通 PG 表）。每个 chunk 有自己的 visibility map：

```sql
SELECT create_hypertable('metrics', 'time');

CREATE INDEX idx_metric_device
    ON metrics (device_id, time DESC);

EXPLAIN ANALYZE
SELECT device_id, time FROM metrics
WHERE device_id = 1 AND time > NOW() - INTERVAL '1 hour';
```

```
Custom Scan (ChunkAppend) on metrics
  Chunks excluded during startup: 0
  ->  Index Only Scan using idx_metric_device on _hyper_1_1_chunk
      Heap Fetches: 0
```

每个 chunk 独立 VACUUM，因此最近写入的 chunk 上 Heap Fetches 可能较高，老 chunk 较低。Timescale 提供 `compress_chunk()` 把老 chunk 转成压缩列存，等价于完全的 index-only。

## PostgreSQL Index-Only Scan 深度

### Visibility Map 的 all-visible bit

```
PostgreSQL 9.2+ 的 VM 文件结构:

每个 8 KB VM 页对应 32 K 个 heap 页（每 heap 页 2 bit）

Bit 解释:
  bit 0 - all-visible:
    该 heap 页上所有元组对所有当前快照都可见
    设置时机: VACUUM 检查后
    清除时机: 任何 INSERT/UPDATE/DELETE 触及此页

  bit 1 - all-frozen (9.6+):
    该页所有元组都已 freeze（xmin 设为 FrozenXid 或更小）
    设置时机: 激进 VACUUM
    用途: 跳过 anti-wraparound vacuum
```

#### Index-Only Scan 算法（伪代码）

```
fn index_only_scan(index, predicate) -> RowIterator:
    for index_tuple in index.scan(predicate):
        heap_page = index_tuple.tid.page
        if visibility_map.is_all_visible(heap_page):
            // 信任索引项，无需回堆
            yield project_columns(index_tuple)
        else:
            // 回堆检查可见性
            heap_tuple = heap.fetch(index_tuple.tid)
            if heap_tuple.is_visible_to(snapshot):
                yield project_columns(index_tuple)
            // 计入 Heap Fetches 计数
```

#### VM 不新鲜的恶性循环

```
1. INSERT 1000 行 → 1000 页的 all-visible bit 被清除
2. 应用执行 SELECT 走 Index Only Scan
3. 每行都触发 heap fetch（Heap Fetches: 1000）
4. 性能等同于普通 Index Scan
5. autovacuum 滞后启动，仍未刷新 VM
6. 后续查询继续退化
```

#### 调优 VM 命中率

```sql
-- 对索引常用的高频查询表，激进调度 autovacuum
ALTER TABLE orders SET (
    autovacuum_vacuum_scale_factor = 0.02,  -- 默认 0.2
    autovacuum_vacuum_threshold    = 1000,
    autovacuum_analyze_scale_factor = 0.02
);

-- 监控 VM 状态
SELECT
    schemaname,
    relname,
    n_dead_tup,
    n_live_tup,
    last_vacuum,
    last_autovacuum,
    n_dead_tup::float / NULLIF(n_live_tup, 0) AS dead_ratio
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY dead_ratio DESC;

-- 检查 VM 实际状态
SELECT relname,
       pg_visibility_map_summary(c.oid)
FROM pg_class c
WHERE relname = 'orders';
-- 输出: (all_visible, all_frozen) 页比例
```

### Index-Only Scan 的优化器决策

PG 的 cost model 对 Index Only Scan 的代价估算：

```
estimated_heap_fetches = total_index_tuples * (1 - all_visible_fraction)

cost_index_only = index_scan_cost
                + estimated_heap_fetches * random_page_cost

cost_index_scan = index_scan_cost
                + total_index_tuples * random_page_cost

// 优化器在两者之间选择
```

`all_visible_fraction` 来源于 `pg_class.relallvisible / relpages`。如果统计陈旧或 VM 退化，估算可能偏离实际，导致优化器误判。

### 部分索引 + Index Only Scan

```sql
-- 部分索引天然减小 VM 失效面
CREATE INDEX idx_active_user ON orders (user_id, amount)
WHERE status = 'active';

-- VACUUM 只需维护 status='active' 行的 VM
-- 历史归档行不影响 index-only scan 命中率
```

### Bitmap Index Scan vs Index Only Scan

```sql
-- 高选择率: PG 倾向 Bitmap Index Scan，必然回堆
EXPLAIN SELECT user_id FROM orders WHERE order_date > '2024-01-01';
-- 可能输出: Bitmap Heap Scan
--          ->  Bitmap Index Scan on idx_date

-- 低选择率: Index Only Scan 更优
EXPLAIN SELECT user_id FROM orders WHERE user_id = 42;
-- Index Only Scan using idx_user
```

Bitmap Index Scan 不能 index-only——它专为"先用索引找出 TID 集合，然后批量回堆"设计。这是 PG 处理多索引 AND/OR 的主力，但与 index-only 互斥。

## MySQL InnoDB 聚簇索引特例

InnoDB 的特殊性体现在三层：**主键即数据**、**二级索引隐含主键**、**索引项内嵌 trx_id**。这三点联合起来让 MySQL 在 90% 的常见查询场景下达到 index-only 效果，且无需 PG 那样的 visibility map。

### 二级索引的隐含覆盖

```sql
CREATE TABLE orders (
    order_id BIGINT PRIMARY KEY,
    user_id BIGINT,
    amount DECIMAL(10,2),
    status VARCHAR(20),
    INDEX idx_user (user_id)
);

-- 索引 idx_user 的叶子节点物理上存的是: (user_id, order_id)
-- order_id 是隐含主键

-- 这些查询都自然 index-only:
SELECT order_id FROM orders WHERE user_id = 42;
SELECT user_id, order_id FROM orders WHERE user_id = 42;
SELECT COUNT(*) FROM orders WHERE user_id = 42;

-- 这些查询不是 index-only（amount/status 不在索引）:
SELECT amount FROM orders WHERE user_id = 42;
SELECT order_id, status FROM orders WHERE user_id = 42;
```

### 复合索引覆盖更多场景

```sql
ALTER TABLE orders ADD INDEX idx_user_amount (user_id, amount);
-- 叶子: (user_id, amount, order_id)

-- 现在覆盖：
SELECT user_id, amount, order_id FROM orders WHERE user_id = 42;
-- Extra: Using index
```

### MVCC 与 index-only 的协同

InnoDB 二级索引项包含 `delete-mark` 位（标记此项对应行已删除但未 purge）和指向**所在页的 max_trx_id**：

```
二级索引页布局（简化）:
Page Header:
  max_trx_id: 上次修改该页的最大 trx_id

Records:
  [user_id=42, order_id=1001, delete-mark=0]
  [user_id=42, order_id=1002, delete-mark=1]  ← 已删除待 purge
  [user_id=42, order_id=1003, delete-mark=0]
```

读取规则（简化）：

```
对每个索引项:
  if 索引项的 page_max_trx_id < min_active_trx_id:
    // 该页所有项都比所有活跃事务老，可信任
    if not delete-mark:
      yield project_columns(index_tuple)  // index-only
  else:
    // 需要回主键检查 undo log
    primary_tuple = primary_index.lookup(index_tuple.pk)
    if primary_tuple.is_visible_to(snapshot):
      yield primary_tuple
```

`page_max_trx_id` 比 PG 的 VM 粒度更细（page 级别），且不需要单独的 fork 文件。代价是每次写都要更新 page header。

### Read-Only 工作负载的极端优化

对于纯读场景，MySQL 8.0 引入 `innodb_read_only` 模式，更激进地信任索引项，避免 trx_id 检查的开销。

### EXPLAIN FORMAT=TREE (8.0+)

```sql
EXPLAIN FORMAT=TREE
SELECT order_id FROM orders WHERE user_id = 42;
```

```
-> Covering index lookup on orders using idx_user (user_id=42)
   (cost=2.50 rows=10)
```

`Covering index lookup` 是 8.0 引入的术语，明确表达 index-only 命中。

## 关键发现

### 17 个引擎严格意义上的 Index-Only Scan

PostgreSQL (9.2)、MySQL InnoDB、MariaDB、Oracle、SQL Server、DB2 LUW/zOS、SQLite、CockroachDB、TiDB、OceanBase、YugabyteDB、SingleStore、Greenplum、TimescaleDB、Spanner、Teradata、Informix、Firebird、Azure Synapse 各自实现了行存/B 树场景下的 index-only 路径。其余约 18 个云数仓/列存引擎用列裁剪等价覆盖，与传统概念形态不同。

### 时间线

```
1990   Oracle v6           INDEX FAST FULL SCAN
1995   DB2 (Universal DB)  Index-Only Access
1998   Oracle 8            IOT (Index Organized Table)
2000   SQL Server 2000     聚簇索引/堆 + 非聚簇覆盖
2000   MySQL 3.23 → InnoDB 聚簇索引天然覆盖
2009   PostgreSQL 8.4      Visibility Map 引入（无 all-visible bit）
2012   PostgreSQL 9.2      Index Only Scan + all-visible bit
2017   CockroachDB v1.0    STORING + index-only
2018   PostgreSQL 11       INCLUDE 子句
2018   CockroachDB 18.x    EXPLAIN 统一术语
2020   YugabyteDB 2.0      Index Only Scan (YSQL)
```

### 三种可见性机制

引擎在 index-only scan 路径上的可见性判断主要分为三大流派：

```
1. Visibility Map (PG 风格)
   单独的 fork 文件，bit 表示页可见性
   依赖 VACUUM 维护
   仅 PG / Greenplum heap / TimescaleDB 使用

2. 索引内嵌时间戳 / trx_id (LSM / 聚簇风格)
   InnoDB max_trx_id, RocksDB MVCC, DocDB HLC,
   Pebble timestamp, Spanner TrueTime, ClickHouse part timestamp
   YugabyteDB / CockroachDB / TiDB / Spanner / ClickHouse

3. 外置版本存储 (锁版本 / 块级 ITL)
   Oracle 块 ITL + rollback segment
   SQL Server 行版本指针 + tempdb version store
   DB2 锁机制 + Currently Committed
```

### PostgreSQL Heap Fetches > 0 的真相

PG 的 `Index Only Scan` 名称带有误导性。Heap Fetches > 0 的执行计划在性能上等同于 `Index Scan`，但 EXPLAIN 不会改变名称。监控 `pg_stat_user_indexes.idx_tup_fetch` 是判断 index-only 健康度的真正指标。

### MySQL InnoDB 的隐含覆盖优势

InnoDB 任何二级索引隐含携带主键，凡是只查询索引列 + 主键列的查询都自然 index-only，无需 INCLUDE 子句。这是 MySQL 长期不引入 INCLUDE 语法的核心理由。在 OLTP 场景下，配合主键查找，绝大多数查询都能走 index-only。

### Oracle INDEX FAST FULL SCAN 的不可替代性

INDEX FAST FULL SCAN 是 Oracle 独有的"按物理块顺序扫描索引段"的算子，它把索引当成一个紧凑的小堆来扫，多块读 + 不保序，对 `COUNT(*)` 和不需要排序的聚合极为高效。其他引擎用 `Index Full Scan` (按 B 树叶链表) 替代，速度相差数倍。

### 列存引擎的范式差异

ClickHouse、Snowflake、BigQuery、Vertica、SAP HANA 等列存引擎的执行模型让 "index-only" 失去意义：列存天然只读必要列，不存在"回表"概念。这些引擎的优化重点是 sort key 设计和 zone map 命中率。

### 部分可见性回退的代价

当 visibility map / 索引时间戳无法确认时，回堆的代价不仅是一次随机 I/O：

```
PG: 回堆 + 找到正确版本（可能跨多个版本）
InnoDB: 回主键 + 走 undo log
Oracle: 块 ITL 不够 → rollback segment 重建
```

最坏情况下一次 index-only 查询退化为 N 次随机 I/O + 多次 undo 重建。

### 对 OLTP 调优的启示

```
1. PG: VACUUM 频率比索引设计本身更重要
2. InnoDB: 主键设计决定二级索引天然覆盖能力
3. Oracle: NOT NULL 约束让 INDEX FAST FULL SCAN 可用
4. SQL Server: INCLUDE 列覆盖 vs 聚簇索引选择
5. CockroachDB/YugabyteDB: STORING 列与 Raft 复制带宽权衡
```

## 对引擎开发者的建议

### 1. Index-Only Scan 算子设计

```
IndexOnlyScan {
    index: Index
    predicate: Expression
    projection: Vec<ColumnId>      // 必须全部在 index 中
    visibility_check: VisibilityCheck
    heap: Option<Heap>             // 仅在 visibility check 失败时使用

    fn next() -> Option<Row>:
        loop:
            index_tuple = index.next()?
            if visibility_check.can_skip_heap(index_tuple):
                // 真正的 index-only 路径
                return Some(project(index_tuple, projection))
            else:
                // 退化路径：回堆
                heap_tuple = heap.fetch(index_tuple.tid)
                if heap_tuple.is_visible():
                    return Some(project(heap_tuple, projection))
                metric.heap_fetches += 1
}
```

关键点：

- `visibility_check` 是引擎差异最大的部分
- 必须在执行计划上下文中暴露 `heap_fetches` 指标
- 优化器需要 visibility 元数据来估算回堆比例

### 2. Visibility Map / 等价机制设计

不同引擎可选的可见性结构：

```
A. 单独 fork (PG 风格):
   优点: 不增加索引/堆页大小
   缺点: 需要单独维护，VACUUM 滞后导致退化
   适用: 行存堆 + MVCC + 预期低更新率

B. 索引页 header (InnoDB 风格):
   优点: 粒度细 (page 级别)，写时同步更新
   缺点: 每次写都要更新 header，索引不能完全只读
   适用: 聚簇索引 + 行级版本

C. 索引项内嵌时间戳 (LSM 风格):
   优点: 完全自包含，无外部依赖
   缺点: 每个索引项变大，写放大显著
   适用: KV 存储 + LSM 树

D. 外置版本存储 (Oracle/SQL Server):
   优点: 索引项简洁
   缺点: 索引扫描时仍需查版本存储
   适用: 块级 MVCC + tempdb 版本
```

### 3. 优化器成本模型

```
cost_index_only_scan = index_io_cost
                     + estimated_heap_fetch_count * heap_random_io_cost
                     + index_tuple_count * index_cpu_cost

estimated_heap_fetch_count = index_tuple_count * (1 - vm_all_visible_fraction)

vm_all_visible_fraction 来源:
  - PG: pg_class.relallvisible / relpages
  - InnoDB: 估算 page_max_trx_id < min_active_trx_id 的比例
  - LSM: 估算 timestamp < snapshot 的比例

不同选择路径的成本对比:
  cost_index_scan = index_io_cost + total_tuples * heap_random_io_cost
  cost_seq_scan   = total_pages * seq_io_cost + total_tuples * cpu_cost
  cost_bitmap_scan = index_io_cost
                   + matching_pages * seq_io_cost (页排序后顺序读)
                   + filter_cpu_cost
```

### 4. EXPLAIN 输出设计

EXPLAIN 必须暴露以下信息，否则用户无法判断真实性能：

```
1. 算子名: Index Only Scan / Using Index / Covering Index Lookup
2. 索引名: 哪个索引被命中
3. 实际回堆次数: heap_fetches / row_lookups
4. 索引扫描行数 vs 返回行数
5. 谓词位置: index condition vs filter
```

### 5. 物理设计提示

```
1. PG 风格:
   - 维护索引常用列的 VACUUM 频率
   - 监控 pg_stat_user_indexes.idx_tup_fetch
   - 极端低延迟可考虑 INCLUDE + autovacuum 紧凑参数

2. InnoDB 风格:
   - 主键设计紧凑（避免 BIGINT + GUID 组合）
   - 二级索引列设计利用隐含主键
   - 避免冗余的 (col1, col2) + (col1) 索引

3. Oracle 风格:
   - 索引列 NOT NULL 约束让 INDEX FAST FULL SCAN 可用
   - IOT 用于"键即数据"的极端场景
   - INDEX_FFS hint 强制 fast full scan

4. LSM 风格:
   - STORING 列权衡 Raft 带宽 vs 查询延迟
   - 大对象不要 STORING
   - compaction 策略影响 index-only 稳定性
```

### 6. 测试覆盖清单

```
1. 基础正确性:
   - 包含所有需要列的索引能命中 index-only
   - 缺失任意列退化为 index scan + heap fetch

2. MVCC 边界:
   - 长事务期间的可见性边界
   - VACUUM/purge 后的索引项清理
   - 快照隔离下的版本选择

3. 退化场景:
   - VM 不新鲜下的 heap_fetches 计数
   - 大批量更新后的 index-only 退化
   - 长事务持有快照阻塞 VACUUM

4. 性能基准:
   - 100% all-visible vs 0% all-visible 的延迟差
   - 不同选择率下 index-only / index scan / seq scan 的代价交叉点
   - 多列项目下 index-only 与 lookup 的比较

5. EXPLAIN 准确性:
   - heap_fetches / using_index 等字段反映真实行为
   - 错误估算导致的退化能被识别

6. 极端边界:
   - 全列 NULL 索引的 fast full scan
   - 含 LOB 列的索引扫描
   - 跨节点分布式 index-only（CockroachDB / TiDB）
```

### 7. 监控指标暴露

```
关键指标:
  index_only_hit_rate = index_only_scans / total_scans
  heap_fetch_rate = heap_fetches / index_tuples_read
  visibility_check_pass_rate = passed / total

监控阈值建议:
  heap_fetch_rate > 5%: 考虑 VACUUM 调优
  heap_fetch_rate > 50%: index-only 实际未生效
  index_only_hit_rate < 80%: 检查查询模式 / 索引设计
```

### 8. 与并发控制的交互

```
1. 行级锁定:
   - SELECT FOR UPDATE 不能 index-only（需要堆元组锁）
   - SELECT 在 read committed 下可 index-only

2. 快照隔离 vs RC:
   - SI 下的可见性判断更复杂，更依赖外置版本存储
   - RC 下索引项可见性判定通常足够

3. 副本读 (read replica):
   - PG: hot_standby_feedback 影响 VM 推进
   - 只读副本上的 index-only 可能更快（无写干扰）
```

## 总结对比矩阵

### Index-Only Scan 综合能力

| 能力 | PostgreSQL | MySQL InnoDB | Oracle | SQL Server | DB2 | CockroachDB | TiDB | YugabyteDB |
|------|-----------|--------------|--------|------------|-----|-------------|------|------------|
| Index-Only Scan | 是 (9.2+) | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| EXPLAIN 标识 | Index Only Scan | Using index | INDEX FAST FULL SCAN / 无 RID | 无 Lookup | 无 FETCH | scan w/o index join | IndexReader | Index Only Scan |
| 可见性机制 | VM | 索引页 trx_id | 块 ITL + rollback | 行版本指针 | 锁 + CC | LSM 时间戳 | RocksDB MVCC | LSM 时间戳 |
| 部分检查 | 页级 | 页级 | 块级 | 行级 | 锁级 | KV 级 | KV 级 | KV 级 |
| 主键聚簇 | 否 | 是 | IOT 是 | 是 | 否 | 是 | 可选 | 是 |
| INCLUDE 语法 | 11+ | 无 | 无 | 2005+ | UNIQUE | STORING/INCLUDE | 无 | INCLUDE |
| 写放大风险 | 低 | 中 | 中 | 中 | 中 | 高 (Raft) | 高 (Raft) | 高 (Raft) |
| 退化场景 | VM 不新鲜 | undo 重建 | rollback 重建 | tempdb 压力 | 锁等待 | -- | -- | -- |

### 选型建议

| 场景 | 推荐路径 | 原因 |
|------|---------|------|
| OLTP 高频点查 | PG INCLUDE 或 InnoDB 复合键 | 延迟敏感 + 标准成熟 |
| 写多读少 OLTP | InnoDB 隐含覆盖 | 避免 PG VM 退化 |
| 大表 COUNT 与聚合 | Oracle INDEX FAST FULL SCAN | 块级扫描效率高 |
| 多租户 SaaS | SQL Server UNIQUE INDEX INCLUDE | UNIQUE + 投影一体 |
| 分布式 OLTP | CockroachDB / YugabyteDB STORING | LSM 无 VM 困境 |
| 低延迟读副本 | PG 只读副本 + autovacuum 调优 | 主写副读分离 |
| 列存分析 | ClickHouse ORDER BY 键 / Vertica projection | 列裁剪天然 index-only |
| 实时大表分析 | TimescaleDB chunk + INCLUDE | 时间分区 + 压缩 chunk |
| 时序数据 | InfluxDB 列存裁剪 / TimescaleDB 压缩段 | 时序天然列存 |

## 参考资料

- PostgreSQL: [Index-Only Scans](https://www.postgresql.org/docs/current/indexes-index-only-scans.html)
- PostgreSQL: [Visibility Map](https://www.postgresql.org/docs/current/storage-vm.html)
- PostgreSQL Wiki: [Index-only scans](https://wiki.postgresql.org/wiki/Index-only_scans)
- PostgreSQL 9.2 Release Notes: [Index-Only Scans](https://www.postgresql.org/docs/9.2/release-9-2.html)
- PostgreSQL 8.4 Release Notes: [Visibility Map](https://www.postgresql.org/docs/8.4/release-8-4.html)
- MySQL: [InnoDB and the ACID Model](https://dev.mysql.com/doc/refman/8.0/en/mysql-acid.html)
- MySQL: [Optimizing InnoDB Queries](https://dev.mysql.com/doc/refman/8.0/en/optimizing-innodb-queries.html)
- MySQL: [EXPLAIN Output Format - Using index](https://dev.mysql.com/doc/refman/8.0/en/explain-output.html)
- Oracle: [INDEX_FFS Hint](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Comments.html#GUID-D29A98AB-1FBE-4F2D-8055-DECA4A3BC0CE)
- Oracle: [Index-Organized Tables](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/indexes-and-index-organized-tables.html)
- SQL Server: [Index Architecture](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-index-design-guide)
- SQL Server: [Read Committed Snapshot Isolation](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide)
- DB2 LUW: [Index-Only Access](https://www.ibm.com/docs/en/db2/11.5?topic=plans-index-only-access)
- CockroachDB: [Index Storage](https://www.cockroachlabs.com/docs/stable/indexes)
- TiDB: [EXPLAIN Walkthrough](https://docs.pingcap.com/tidb/stable/explain-walkthrough)
- YugabyteDB: [Index-Only Scan](https://docs.yugabyte.com/preview/explore/ysql-language-features/indexes-constraints/index-only-scan/)
- ClickHouse: [Primary Indexes](https://clickhouse.com/docs/en/optimize/sparse-primary-indexes)
- Spanner: [Secondary Indexes](https://cloud.google.com/spanner/docs/secondary-indexes)
- Vertica: [Projection Concepts](https://www.vertica.com/docs/latest/HTML/Content/Authoring/ConceptsGuide/Components/Projections.htm)
- 相关文档: [覆盖索引与 INCLUDE 子句](./covering-indexes.md)、[索引类型与创建语法](./index-types-creation.md)、[部分索引](./partial-indexes.md)、[表达式索引](./expression-indexes.md)
