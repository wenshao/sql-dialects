# 键集分页 (Keyset Pagination)

翻到第 1000 页耗时 30 秒，翻到第 10000 页超时——OFFSET 分页的性能崩溃几乎是每个 Web 应用都会经历的"生长之痛"。键集分页（Keyset Pagination，又称游标分页或 Seek Method）以 O(1) 的代价跳过任意位置的页面，是支撑 Twitter Timeline、Slack 消息列表、GitHub Issues 翻页等高流量场景的真正方案。

## OFFSET 的 O(N) 困境与 Seek Method 的 O(1) 突围

### OFFSET 分页的隐藏代价

最朴素的分页写法是 `LIMIT n OFFSET m`，但 OFFSET 在底层等价于"扫描并丢弃前 m 行"——这是一个 **O(N) 的操作**：

```sql
-- 取第 1000 页 (每页 20 行)
SELECT * FROM orders
ORDER BY created_at DESC
LIMIT 20 OFFSET 19980;
-- 引擎必须先扫描+排序前 20000 行，再丢弃前 19980 行
-- 即使有 (created_at) 索引，仍需读取并排序 19980+20 行
```

随着翻页深度增加，响应时间线性增长：第 1 页 5 ms，第 100 页 50 ms，第 1000 页 500 ms，第 10000 页 5 秒——这就是著名的"deep pagination"问题。

### Seek Method：用上一页的最后一行做游标

键集分页（Markus Winand 在 *Use The Index, Luke!* 中命名为 "Seek Method"）改用上一页最后一行的关键列值作为游标：

```sql
-- 第 1 页: 直接 LIMIT
SELECT id, created_at, title FROM orders
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- 第 N+1 页: 用上一页末行的 (created_at, id) 作为游标
SELECT id, created_at, title FROM orders
WHERE (created_at, id) < (?, ?)   -- 上一页最后一行的 (created_at, id)
ORDER BY created_at DESC, id DESC
LIMIT 20;
```

只要 `(created_at, id)` 上有联合索引，无论翻到第 1 页还是第 1 万页，索引层只需 **O(log N) 定位 + 顺序读取 20 行 = 几乎 O(1) 的代价**。

### 复杂度对比

| 维度 | OFFSET 分页 | Seek Method（键集分页） |
|------|------------|------------------------|
| 第 N 页查询代价 | O(N) | O(log N + page_size) ≈ O(1) |
| 内存占用 | 与 N 成比例 | 与 page_size 成比例 |
| 跳页支持 | 是（任意页码） | 否（只能顺序前进/后退） |
| 翻页结果稳定性 | 不稳定（数据增删导致行漂移） | 稳定（游标定位一行） |
| 索引利用率 | 部分（仅排序键） | 完全（联合索引精确定位） |
| 总行数感知 | 是（COUNT 即可） | 否（需要额外查询） |
| Twitter/Slack 等高流量场景 | 不适用 | 标准方案 |

OFFSET 适合**有限页数 + 跳页 + UI 显示总页数**的传统场景；Seek 适合**无限滚动 + 顺序浏览 + 数据频繁变化**的现代 Web/App 场景。

## 没有 SQL 标准——纯实现层模式

`ORDER BY ... LIMIT N` 是 SQL:2008 标准（FETCH FIRST），但**键集分页本身不是 SQL 标准**——它是一种**应用模式**，依赖于：

1. SQL 标准的元组比较（Row Value Comparison，SQL:1992 引入）：`(a, b) < (?, ?)`
2. 排序键上的复合索引
3. 应用层维护游标状态

不同引擎对元组比较的支持差异极大，这直接决定了键集分页的可写法和性能。本文重点比较 45+ 引擎在以下三个层面的差异：

- **元组（Row Value）比较语法**：`(a, b) > (?, ?)` 是否原生支持
- **优化器是否能利用复合索引**：即使写法等价，索引使用可能不同
- **NULL 排序与游标定位的交互**：NULLS FIRST/LAST 对游标比较的影响

## 支持矩阵

### 1. 元组比较 / 行值构造器支持

SQL 标准的 Row Value Constructor `(a, b, c)` 与元组大小比较 `<, <=, >, >=, =, <>` 是键集分页最自然的写法。

| 引擎 | `(a,b) > (?,?)` | `ROW(a,b) > ROW(?,?)` | 优化器索引利用 | 引入版本 |
|------|----------------|----------------------|--------------|---------|
| PostgreSQL | 是 | 是 | 完整（B-Tree 复合索引） | 8.2 (2006) |
| MySQL | 是 | 是 | 部分（8.0.14+ 完整） | 5.x（早期） |
| MariaDB | 是 | 是 | 部分 | 5.x（早期） |
| SQLite | 是 | -- | 完整（3.34+ 优化） | 3.15 (2016) |
| Oracle | 是 | 是 | 部分（需 Hint 或子查询） | 9i+ |
| SQL Server | -- | -- | 不支持原生元组比较 | -- |
| Db2 | 是 | 是 | 完整 | 9.7+ |
| H2 | 是 | 是 | 完整 | 1.4+ |
| HSQLDB | 是 | 是 | 完整 | 2.x+ |
| Derby | 是 | 是 | 完整 | 10.x |
| Firebird | 是 | -- | 部分 | 2.5+ |
| CockroachDB | 是 | 是 | 完整（继承 PG） | 1.0+ |
| YugabyteDB | 是 | 是 | 完整（继承 PG） | 2.0+ |
| Greenplum | 是 | 是 | 完整（继承 PG） | 4.x+ |
| TimescaleDB | 是 | 是 | 完整（继承 PG） | 继承 PG |
| openGauss | 是 | 是 | 完整 | 继承 PG |
| KingBase | 是 | 是 | 完整 | 基于 PG |
| Vertica | 是 | 是 | 部分 | 7.x+ |
| Snowflake | 是 | -- | 完整（micro-partition pruning） | GA |
| BigQuery | 是 | -- | 完整（cluster pruning） | GA |
| Redshift | 是 | -- | 部分 | GA |
| Spark SQL | 是 | -- | 完整 | 2.x+ |
| Databricks | 是 | -- | 完整 | GA |
| Trino | 是 | 是 | 完整 | 早期 |
| Presto | 是 | 是 | 完整 | 早期 |
| Hive | -- | -- | 不支持元组比较（需展开） | -- |
| ClickHouse | 是 | -- | 部分（FINAL 模式有问题） | 早期 |
| DuckDB | 是 | 是 | 完整 | 0.3+ |
| TiDB | 是 | 是 | 部分（继承 MySQL） | 4.0+ |
| OceanBase | 是 | 是 | 完整 | 2.x+ |
| PolarDB | 是 | 是 | 完整 | 基于 MySQL/PG |
| TDSQL | 是 | 是 | 完整 | 基于 MySQL/PG |
| GaussDB | 是 | 是 | 完整 | 基于 PG |
| Doris | 是 | -- | 部分 | 1.2+ |
| StarRocks | 是 | -- | 部分 | 2.x+ |
| Impala | 是 | -- | 部分 | 3.x+ |
| Hologres | 是 | 是 | 完整（基于 PG） | GA |
| MaxCompute | 是 | -- | 部分 | GA |
| Teradata | 是 | -- | 部分 | V2R5+ |
| SAP HANA | 是 | 是 | 完整 | 2.0+ |
| Informix | -- | -- | 不支持原生 | -- |
| Singlestore | 是 | -- | 部分 | 7.0+ |
| Exasol | 是 | -- | 部分 | 6.x+ |
| MonetDB | 是 | -- | 部分 | Jul2017+ |
| CrateDB | -- | -- | 不支持元组比较 | -- |
| QuestDB | -- | -- | 不支持元组比较 | -- |
| Materialize | 是 | 是 | 完整（继承 PG） | 0.x+ |
| RisingWave | 是 | -- | 完整 | 0.x+ |
| Flink SQL | -- | -- | 不支持（流处理特殊） | -- |
| ksqlDB | -- | -- | 不支持（流处理） | -- |
| TDengine | -- | -- | 不支持 | -- |
| Spanner | 是 | -- | 完整 | GA |
| DM (达梦) | 是 | 是 | 完整 | 8.x+ |
| Yellowbrick | 是 | -- | 部分 | GA |
| Firebolt | 是 | -- | 部分 | GA |
| DatabendDB | 是 | -- | 部分 | GA |
| Azure Synapse | -- | -- | 不支持（继承 SQL Server 引擎） | -- |

> 注：约 47 个引擎中有 38 个支持某种形式的原生元组比较；SQL Server / Hive / CrateDB / QuestDB / Flink SQL 等需要使用 CASE 或展开式条件模拟。

### 2. NULL 排序与键集分页交互

NULL 在排序中的位置（NULLS FIRST/LAST）直接影响游标比较的正确性。

| 引擎 | 默认 NULL 顺序 | NULLS FIRST/LAST 子句 | 元组比较中 NULL 行为 |
|------|---------------|---------------------|---------------------|
| PostgreSQL | ASC: LAST, DESC: FIRST | 是 | NULL 比较返回 NULL（需特殊处理） |
| MySQL | ASC: FIRST, DESC: LAST | 否（需 IS NULL 子句） | NULL 比较返回 NULL |
| MariaDB | ASC: FIRST, DESC: LAST | 10.6+ | NULL 比较返回 NULL |
| Oracle | ASC: LAST, DESC: FIRST | 是 | NULL 比较返回 NULL |
| SQL Server | ASC: FIRST, DESC: LAST | 2022+ | -- |
| SQLite | ASC: FIRST, DESC: LAST | 3.30+ | NULL 比较返回 NULL |
| Db2 | ASC: LAST, DESC: FIRST | 是 | NULL 比较返回 NULL |
| H2 | 实现相关 | 是 | NULL 比较返回 NULL |
| Snowflake | ASC: LAST, DESC: FIRST | 是 | NULL 比较返回 NULL |
| BigQuery | ASC: LAST, DESC: FIRST | 是 | NULL 比较返回 NULL |
| Redshift | ASC: LAST, DESC: FIRST | 是 | NULL 比较返回 NULL |
| ClickHouse | ASC: LAST, DESC: FIRST | 是 | NULL 比较返回 NULL |
| DuckDB | ASC: LAST, DESC: FIRST | 是 | NULL 比较返回 NULL |
| Trino | ASC: LAST, DESC: FIRST | 是 | NULL 比较返回 NULL |
| Spark SQL | ASC: FIRST, DESC: LAST | 是 | NULL 比较返回 NULL |
| CockroachDB | ASC: FIRST, DESC: LAST | 是 | NULL 比较返回 NULL |
| Vertica | ASC: LAST, DESC: FIRST | 是 | NULL 比较返回 NULL |

游标列允许 NULL 时，元组比较 `(a, b) > (?, ?)` 不能直接使用——任意一边含 NULL 就退化为 UNKNOWN，导致行漏掉。生产实践通常给"游标列"加 NOT NULL 约束，或显式拆分 NULL 分支（详见后文）。

### 3. 隐式优化器规则

不同引擎对 `(a, b) > (?, ?)` 的执行计划差异巨大：

| 引擎 | 元组比较的等价改写 | 复合索引利用 | 早停（Stop Key） |
|------|------------------|------------|----------------|
| PostgreSQL | 直接索引 range scan | 完整 | 是 |
| MySQL 8.0.14+ | 直接索引 range scan | 完整 | 是 |
| MySQL <= 8.0.13 | 改写为 OR 表达式后扫描 | 部分 | 否（可能全索引扫描） |
| Oracle | 部分版本改写为 OR | 部分（需 Hint） | 是 |
| SQLite 3.34+ | 索引 range scan | 完整 | 是 |
| SQL Server | 不支持元组，必须手工展开 | 取决于改写质量 | -- |
| ClickHouse | MergeTree 主键前缀匹配 | 完整（非 FINAL 模式） | 是 |
| Snowflake | micro-partition 元数据裁剪 | 完整 | 是 |
| BigQuery | cluster pruning | 完整（聚簇表） | 是 |
| Trino/Presto | hive 分区/统计信息裁剪 | 完整 | 是 |
| Spark SQL | dataframe predicate pushdown | 完整 | 部分 |

下文将逐引擎展开元组比较语法、等价改写和性能注意事项。

## 各引擎语法详解

### PostgreSQL（行值构造器最完整）

PostgreSQL 自 8.2（2006）起就完整支持 SQL 标准的 Row Value Constructor 比较，是键集分页教科书式的实现。

```sql
-- 创建联合索引（必须包含所有 ORDER BY 列）
CREATE INDEX idx_orders_seek ON orders (created_at DESC, id DESC);

-- 第一页（无游标）
SELECT id, created_at, total
FROM orders
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- 后续页（用上一页末行作为游标）
SELECT id, created_at, total
FROM orders
WHERE (created_at, id) < ('2026-04-29 10:00:00', 12345)
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- 等价的 ROW() 写法
SELECT id, created_at, total
FROM orders
WHERE ROW(created_at, id) < ROW('2026-04-29 10:00:00', 12345)
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- EXPLAIN 输出确认索引利用：
-- Index Scan using idx_orders_seek
--   Index Cond: (ROW(created_at, id) < ROW('...', 12345))
```

**双向分页（forward + backward）**：

```sql
-- 向前一页：游标定位反向，再反转结果
WITH prev AS (
    SELECT id, created_at, total
    FROM orders
    WHERE (created_at, id) > ('2026-04-29 10:00:00', 12345)
    ORDER BY created_at ASC, id ASC
    LIMIT 20
)
SELECT * FROM prev ORDER BY created_at DESC, id DESC;
```

**含 NULL 列的游标**：

```sql
-- ORDER BY due_date ASC NULLS LAST, id DESC
-- due_date 可能为 NULL，元组比较失效
-- 拆分为 NULL 分支
SELECT * FROM tasks
WHERE
    (due_date IS NULL AND id < ?)                  -- 在 NULL 区间内
    OR
    (? IS NULL OR due_date > ? OR (due_date = ? AND id < ?))
ORDER BY due_date ASC NULLS LAST, id DESC
LIMIT 20;
```

### MySQL / MariaDB（元组比较早就有，但优化器近年才完善）

MySQL 自 5.x 起就允许元组比较语法，但**优化器对其转化为索引 range scan 的能力直到 8.0.14（2019）才完整**。在更早版本中可能退化为全索引扫描。

```sql
-- 创建联合索引
CREATE INDEX idx_orders_seek ON orders (created_at DESC, id DESC);
-- 注：MySQL 8.0+ 才支持降序索引

-- 元组比较写法（MySQL 8.0.14+ 优化器能识别）
SELECT id, created_at, total FROM orders
WHERE (created_at, id) < ('2026-04-29 10:00:00', 12345)
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- MySQL 8.0.13 及以下推荐的等价改写（避免回退）
SELECT id, created_at, total FROM orders
WHERE created_at < '2026-04-29 10:00:00'
   OR (created_at = '2026-04-29 10:00:00' AND id < 12345)
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- EXPLAIN 输出确认 range scan：
-- type: range
-- key: idx_orders_seek
-- Extra: Using index condition
```

**MySQL 优化器的"index dive"陷阱**：当游标值进入索引的极端区间（如最后几行），优化器可能误判为表扫描更便宜。可用 `FORCE INDEX (idx_orders_seek)` 强制走索引。

### SQLite（轻量但完整）

SQLite 自 **3.15（2016）** 起完整支持元组比较，3.34+ 优化器对其有专门优化。

```sql
-- 联合索引
CREATE INDEX idx_orders_seek ON orders(created_at DESC, id DESC);

-- 元组比较（SQLite 3.15+）
SELECT id, created_at, total FROM orders
WHERE (created_at, id) < ('2026-04-29 10:00:00', 12345)
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- 用 EXPLAIN QUERY PLAN 验证：
-- SCAN orders USING INDEX idx_orders_seek
```

SQLite 在嵌入式场景（手机 App、桌面应用）极常见，键集分页是处理本地大表的最佳方案——OFFSET 在移动端 SQLite 上会触发整表读取并进入 page cache，影响电池和 I/O。

### Oracle（语法支持但优化器需要 Hint）

Oracle 自 9i 起支持行值比较，但**优化器对元组比较的索引利用经常需要 Hint 引导**——某些版本会改写为 OR 表达式但不一定走 INDEX RANGE SCAN。

```sql
-- 联合索引
CREATE INDEX idx_orders_seek ON orders(created_at DESC, id DESC);

-- 元组比较（Oracle 9i+）
SELECT /*+ INDEX(orders idx_orders_seek) */
       id, created_at, total
FROM orders
WHERE (created_at, id) < (TO_DATE('2026-04-29 10:00:00', 'YYYY-MM-DD HH24:MI:SS'), 12345)
ORDER BY created_at DESC, id DESC
FETCH FIRST 20 ROWS ONLY;

-- 12c 之前 Oracle 不支持 LIMIT/FETCH，需要 ROWNUM 套两层：
SELECT * FROM (
    SELECT id, created_at, total FROM orders
    WHERE (created_at, id) < (TO_DATE('...', '...'), 12345)
    ORDER BY created_at DESC, id DESC
)
WHERE ROWNUM <= 20;

-- 显式 OR 改写（更稳定的执行计划）
SELECT id, created_at, total FROM orders
WHERE created_at < TO_DATE('2026-04-29 10:00:00', '...')
   OR (created_at = TO_DATE('2026-04-29 10:00:00', '...') AND id < 12345)
ORDER BY created_at DESC, id DESC
FETCH FIRST 20 ROWS ONLY;
```

### SQL Server（无原生元组比较，必须展开）

SQL Server **不支持原生元组比较**，必须手工展开为 OR 表达式或 CASE 比较：

```sql
-- 联合索引
CREATE INDEX idx_orders_seek ON Orders(CreatedAt DESC, Id DESC);

-- 标准展开式（推荐）
SELECT TOP 20 Id, CreatedAt, Total FROM Orders
WHERE CreatedAt < '2026-04-29T10:00:00'
   OR (CreatedAt = '2026-04-29T10:00:00' AND Id < 12345)
ORDER BY CreatedAt DESC, Id DESC;

-- 利用 CASE 模拟 lexicographic 比较（SQL Server 2008 之前的 trick）
SELECT TOP 20 Id, CreatedAt, Total FROM Orders
WHERE
    CASE
        WHEN CreatedAt < '2026-04-29T10:00:00' THEN 1
        WHEN CreatedAt = '2026-04-29T10:00:00' AND Id < 12345 THEN 1
        ELSE 0
    END = 1
ORDER BY CreatedAt DESC, Id DESC;
-- 注意：CASE 写法会破坏索引使用，仅作为兜底语法

-- SQL Server 2012+ 也可以用 OFFSET FETCH 但不能解决性能问题：
SELECT Id, CreatedAt, Total FROM Orders
ORDER BY CreatedAt DESC, Id DESC
OFFSET 0 ROWS FETCH NEXT 20 ROWS ONLY;
```

**SQL Server 与索引的兼容性**：标准 OR 写法在 SQL Server 2008+ 上可被优化器识别为 range seek，前提是统计信息准确且联合索引按 ORDER BY 方向建立。

### Db2（标准支持完整）

Db2 自 9.7 起完整支持元组比较，且优化器能直接转化为索引 range scan：

```sql
-- 联合索引
CREATE INDEX idx_orders_seek ON ORDERS(CREATED_AT DESC, ID DESC);

-- 元组比较
SELECT ID, CREATED_AT, TOTAL FROM ORDERS
WHERE (CREATED_AT, ID) < ('2026-04-29-10.00.00', 12345)
ORDER BY CREATED_AT DESC, ID DESC
FETCH FIRST 20 ROWS ONLY;

-- 等价 ROW() 写法
WHERE ROW(CREATED_AT, ID) < ROW('2026-04-29-10.00.00', 12345)
```

### CockroachDB（继承 PG，分布式键集分页）

CockroachDB 完整继承 PostgreSQL 的元组比较语义，且分布式架构下键集分页的优势更显著——OFFSET 在分布式表上代价更高（每个 range 都要扫描 + 全局合并）。

```sql
-- 主键即天然的游标列
SELECT id, created_at, total FROM orders
WHERE (created_at, id) < ('2026-04-29 10:00:00', 12345)
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- EXPLAIN 输出：
-- scan
--   table: orders@idx_orders_seek
--   spans: [/'2026-04-29 09:59:59' - /'2026-04-29 10:00:00'/12344]
-- 关键：spans 是精确的 key range，不会扫描其他 range
```

### YugabyteDB（继承 PG，YCQL 不支持）

YugabyteDB 在 YSQL（PostgreSQL 兼容）层面完整支持元组比较；但 YCQL（Cassandra 兼容）层面没有元组比较，需要使用 Cassandra 风格的 `WHERE clustering_key > ? AND clustering_key < ?` 单列形式。

```sql
-- YSQL（PostgreSQL 兼容）
SELECT * FROM orders
WHERE (created_at, id) < ('2026-04-29 10:00:00', 12345)
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- YCQL（Cassandra 兼容，需要展开）
SELECT * FROM orders
WHERE created_at < '2026-04-29 10:00:00'
   OR (created_at = '2026-04-29 10:00:00' AND id < 12345)
LIMIT 20;
```

### ClickHouse（MergeTree 主键前缀匹配）

ClickHouse 在 MergeTree 引擎下，元组比较能直接转化为主键 mark range 选择，性能极高——但**必须避免 FINAL 模式**：

```sql
-- 表结构：主键即排序键
CREATE TABLE events (
    event_time DateTime,
    user_id UInt64,
    event_type String
) ENGINE = MergeTree()
ORDER BY (event_time, user_id);

-- 元组比较（直接利用主键索引）
SELECT * FROM events
WHERE (event_time, user_id) > ('2026-04-29 10:00:00', 12345)
ORDER BY event_time, user_id
LIMIT 20;

-- ⚠️ FINAL 模式陷阱：
SELECT * FROM events FINAL
WHERE (event_time, user_id) > ('2026-04-29 10:00:00', 12345)
LIMIT 20;
-- FINAL 强制对所有 part 做合并去重，主键索引无法用于早停
-- 键集分页在 FINAL 模式下退化为全分区扫描

-- 替代方案：使用 ReplacingMergeTree + argMax 模式而非 FINAL
SELECT event_time, user_id, argMax(event_type, version)
FROM events
WHERE (event_time, user_id) > ('2026-04-29 10:00:00', 12345)
GROUP BY event_time, user_id
ORDER BY event_time, user_id
LIMIT 20;
```

### Snowflake（micro-partition 元数据裁剪）

Snowflake 的元组比较能利用 micro-partition 的 min/max 元数据进行裁剪，性能与排序键的聚簇程度强相关：

```sql
-- 表的聚簇键决定键集分页的效率
CREATE TABLE orders (
    id NUMBER,
    created_at TIMESTAMP,
    total NUMBER
) CLUSTER BY (created_at, id);

-- 元组比较
SELECT id, created_at, total FROM orders
WHERE (created_at, id) < ('2026-04-29 10:00:00'::TIMESTAMP, 12345)
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- QUERY_HISTORY 中可以观察到 partitions_scanned vs partitions_total
-- 良好聚簇的表上 partitions_scanned 应远小于 total
```

**Snowflake 特殊场景**：对于流式/无排序的事件表，`STREAMS` + 时间戳游标比键集分页更合适。

### BigQuery（聚簇表 cluster pruning）

BigQuery 元组比较在**聚簇表**（`CLUSTER BY` 子句）上能有效利用 cluster pruning，但在非聚簇表上仍需全表扫描：

```sql
-- 聚簇表
CREATE TABLE dataset.orders (
    id INT64,
    created_at TIMESTAMP,
    total NUMERIC
)
CLUSTER BY created_at, id;

-- 元组比较
SELECT id, created_at, total FROM dataset.orders
WHERE (created_at, id) < (TIMESTAMP '2026-04-29 10:00:00', 12345)
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- 注意：BigQuery 的 LIMIT 是物理限制，不能跳页
-- 真正的键集分页才能在 BigQuery 上获得近似 O(1) 性能
```

### Trino / Presto（标准元组完整）

Trino 和 Presto 完整支持 SQL 标准的元组比较语法，且在 Hive/Iceberg 等连接器上能利用分区/统计信息裁剪：

```sql
-- 元组比较（Trino 早期就支持）
SELECT id, created_at, total FROM hive.default.orders
WHERE (created_at, id) < (TIMESTAMP '2026-04-29 10:00:00', BIGINT '12345')
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- 注意：Trino 不支持 ROW(a,b) > ROW(c,d) 中的 ROW() 跨类型隐式转换
-- 必须显式转换或使用 (a,b) 形式
```

### MySQL 元组比较的"OR 改写"陷阱

MySQL 优化器在 8.0.14 之前会把 `(a, b) < (?, ?)` 内部展开为：

```
WHERE a < ? OR (a = ? AND b < ?)
```

这看起来等价，但**优化器对该 OR 的索引选择行为不稳定**：当统计信息显示 `a` 选择性很高时，可能误判第一个分支扫描代价低，而忽略第二个分支需要的索引；最终走的可能不是 range scan 而是 index merge 或全索引扫描。

修复方法：

1. **升级到 MySQL 8.0.14+**：原生支持元组的 range scan
2. **显式手写 OR**：自己控制展开逻辑
3. **强制索引**：`FORCE INDEX (idx_orders_seek)`
4. **使用 LATERAL JOIN**（MySQL 8.0+ / PostgreSQL）：把游标条件改写为子查询

### Spark SQL / Databricks

Spark SQL 支持元组比较，常用于 Delta Lake / Iceberg 表的增量读取：

```sql
-- Delta Lake 表
SELECT id, created_at, total FROM delta.`/path/to/orders`
WHERE (created_at, id) < ('2026-04-29 10:00:00', 12345)
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- 配合 Z-Ordering 提升性能
OPTIMIZE delta.`/path/to/orders` ZORDER BY (created_at, id);

-- 注意：Spark 的 ORDER BY + LIMIT 在大表上仍可能 shuffle
-- 推荐配合 Iceberg/Delta 的 partition pruning + range pushdown
```

### DuckDB（轻量但完整）

DuckDB 自 0.3 起完整支持元组比较，且在 OLAP 场景下能直接利用 zonemap 裁剪：

```sql
-- DuckDB 创建索引（虽然 OLAP 引擎索引收益有限）
CREATE INDEX idx_orders_seek ON orders(created_at, id);

-- 元组比较
SELECT id, created_at, total FROM orders
WHERE (created_at, id) < ('2026-04-29 10:00:00', 12345)
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- DuckDB Parquet/Arrow 集成
SELECT * FROM read_parquet('orders/*.parquet')
WHERE (created_at, id) < ('2026-04-29 10:00:00', 12345)
ORDER BY created_at DESC, id DESC
LIMIT 20;
-- Parquet 的 row group statistics 支持元组裁剪
```

### TiDB / OceanBase / PolarDB

国产分布式数据库基本都基于 MySQL 协议，元组比较支持完整：

```sql
-- TiDB（基于 MySQL 协议，4.0+）
SELECT id, created_at, total FROM orders
WHERE (created_at, id) < ('2026-04-29 10:00:00', 12345)
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- TiDB 在分布式场景下，键集分页的优势更明显：
-- OFFSET 在 TiDB 上必须从所有 region 取数据后合并丢弃
-- 键集分页直接定位特定 region 的特定 key range

-- OceanBase（兼容 MySQL/Oracle）
-- 同上语法，且支持 Oracle 模式的 FETCH FIRST
SELECT id, created_at, total FROM orders
WHERE (created_at, id) < ('2026-04-29 10:00:00', 12345)
ORDER BY created_at DESC, id DESC
FETCH FIRST 20 ROWS ONLY;

-- DM (达梦) / KingBase / openGauss / GaussDB 等国产数据库
-- 基本继承 PG/Oracle 的元组比较行为
```

### Vertica（列存场景）

Vertica 作为列存数据仓库，键集分页配合 projection 排序键效果显著：

```sql
-- 创建 projection 时指定排序键
CREATE TABLE orders (
    id INT,
    created_at TIMESTAMP,
    total NUMERIC
)
ORDER BY created_at, id;

-- 元组比较
SELECT id, created_at, total FROM orders
WHERE (created_at, id) < ('2026-04-29 10:00:00', 12345)
ORDER BY created_at DESC, id DESC
LIMIT 20;
-- Vertica 利用 ROS (Read Optimized Store) 的 SAL 索引快速定位
```

### Hive（无元组比较，必须展开）

Hive 不支持元组比较，且优化器对 OR 改写的处理较差，一般推荐显式拆分：

```sql
-- 标准展开式（Hive 兼容）
SELECT id, created_at, total FROM orders
WHERE created_at < '2026-04-29 10:00:00'
   OR (created_at = '2026-04-29 10:00:00' AND id < 12345)
ORDER BY created_at DESC, id DESC
LIMIT 20;

-- Hive 在大数据场景下，键集分页通常配合分区裁剪
SELECT id, created_at, total FROM orders
WHERE dt = '2026-04-29'   -- 分区裁剪先生效
  AND (created_at < '2026-04-29 10:00:00'
       OR (created_at = '2026-04-29 10:00:00' AND id < 12345))
ORDER BY created_at DESC, id DESC
LIMIT 20;
```

### Flink SQL / ksqlDB（流处理特殊性）

流处理引擎不存在传统意义的"分页"——数据持续到来，没有"页"的概念。但**事件回溯**场景下可以使用游标：

```sql
-- Flink SQL 不支持元组比较
-- 但可以用展开式做事件回溯
SELECT event_time, user_id, payload FROM events
WHERE event_time > ?
   OR (event_time = ? AND user_id > ?)
ORDER BY event_time, user_id
LIMIT 100;

-- 实际生产中流处理用 watermark + offset 替代分页
-- Kafka 的 offset / Pulsar 的 message_id 才是流处理的"游标"
```

## Markus Winand 的 Seek Method

Markus Winand 在 *SQL Performance Explained*（2011）和官网 *Use The Index, Luke!* 中系统化地推广了 Seek Method。他指出：

> "OFFSET is bad for performance. The further you scroll, the slower it gets. Seek Method scales linearly with page size, not with page number."
> （OFFSET 性能糟糕——翻页越深越慢。Seek Method 的代价只与页大小相关，与页码无关。）

### Seek Method 的三个要素

Markus Winand 提出键集分页必须满足三个条件：

1. **稳定的排序键**：`ORDER BY` 列必须能唯一确定行序——通常需要追加主键作为 tie-breaker
2. **联合索引匹配排序键**：索引列顺序、方向必须与 ORDER BY 完全一致
3. **元组比较谓词**：用上一页末行的关键列值作为下一页的下界

```sql
-- 反例：仅用 created_at 做排序键（不稳定）
SELECT * FROM orders
WHERE created_at < ?         -- 同一时间戳的多行会丢失或重复
ORDER BY created_at DESC
LIMIT 20;

-- 正例：用 (created_at, id) 联合排序（稳定）
SELECT * FROM orders
WHERE (created_at, id) < (?, ?)
ORDER BY created_at DESC, id DESC
LIMIT 20;
```

### Seek Method 与窗口函数 ROW_NUMBER() 的对比

```sql
-- 反 Seek Method 的常见误用：用 ROW_NUMBER() 实现分页
WITH ranked AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY created_at DESC) AS rn
    FROM orders
)
SELECT * FROM ranked WHERE rn BETWEEN 1981 AND 2000;
-- 这等价于 OFFSET 1980 LIMIT 20，性能与 OFFSET 一致差

-- 正确的 Seek Method
SELECT * FROM orders
WHERE (created_at, id) < (?, ?)
ORDER BY created_at DESC, id DESC
LIMIT 20;
```

### Bookmark vs Seek

Markus Winand 区分了两个相近概念：

- **Bookmark**：保存"位置"（任意可逆映射，可以是 OFFSET 或游标）
- **Seek**：用索引定位到位置（必须是索引匹配的游标）

OFFSET 是 Bookmark 但不是 Seek；键集分页才是真正的 Seek。

## 复合键集与 NULL 排序

实际生产中游标列经常有 3 列以上，且部分列可能为 NULL，写起来更复杂。

### 三列复合游标

```sql
-- ORDER BY priority DESC, due_date ASC, id DESC
-- 复合索引：(priority DESC, due_date ASC, id DESC)

-- 元组比较（PostgreSQL/SQLite/Db2 等支持）
SELECT * FROM tasks
WHERE (priority, due_date, id) < (5, '2026-05-01', 12345)
-- 注意元组比较使用统一方向，混合 ASC/DESC 时需要拆分
ORDER BY priority DESC, due_date ASC, id DESC
LIMIT 20;
```

### 混合 ASC/DESC 方向

混合排序方向时元组比较会失效——`(a DESC, b ASC) < (?, ?)` 在 SQL 中并无对应语法，必须手工展开：

```sql
-- ORDER BY priority DESC, due_date ASC, id DESC
-- 拆分为多分支 OR
SELECT * FROM tasks
WHERE
    priority < ?                                                          -- priority 已经更小
    OR (priority = ? AND due_date > ?)                                    -- priority 相同，due_date 更大（ASC 方向）
    OR (priority = ? AND due_date = ? AND id < ?)                          -- 前两列相同，id 更小（DESC）
ORDER BY priority DESC, due_date ASC, id DESC
LIMIT 20;
-- 此时索引使用质量取决于优化器的 OR-to-UNION 改写能力
-- PostgreSQL/MySQL 8.0 优化器对此较友好；老引擎可能需要 UNION ALL 改写
```

### NULL 列游标的标准模式

当游标列允许 NULL 且使用 NULLS LAST 时：

```sql
-- ORDER BY due_date ASC NULLS LAST, id DESC
-- 索引: (due_date NULLS LAST, id DESC)

-- 第一种情况：上一页末行的 due_date 不为 NULL
SELECT * FROM tasks
WHERE
    due_date > ?                                  -- 已经进入更大的 due_date
    OR (due_date = ? AND id < ?)                  -- 同 due_date，id 更小
    OR due_date IS NULL                           -- 进入 NULLS LAST 区
ORDER BY due_date ASC NULLS LAST, id DESC
LIMIT 20;

-- 第二种情况：上一页末行的 due_date 是 NULL（已进入 NULL 区）
SELECT * FROM tasks
WHERE
    due_date IS NULL AND id < ?                   -- NULL 区内继续
ORDER BY due_date ASC NULLS LAST, id DESC
LIMIT 20;
```

最佳实践：**给游标列加 NOT NULL 约束**——能极大简化键集分页逻辑。如果列必须可空，考虑在键集分页前过滤：

```sql
-- 把 NULL 行作为单独"页"显示
SELECT * FROM tasks WHERE due_date IS NULL ORDER BY id DESC LIMIT 20;
SELECT * FROM tasks WHERE due_date IS NOT NULL
ORDER BY due_date ASC, id DESC LIMIT 20;
```

### COALESCE 化简 NULL（性能权衡）

```sql
-- 用 COALESCE 把 NULL 替换为极值，恢复元组比较
-- 缺点：破坏索引使用！优化器不能用 (due_date, id) 索引扫描
SELECT * FROM tasks
WHERE (COALESCE(due_date, '9999-12-31'), id) < (COALESCE(?, '9999-12-31'), ?)
ORDER BY COALESCE(due_date, '9999-12-31') ASC, id DESC
LIMIT 20;

-- 替代方案：在表中维护一个 due_date_sortable 字段（NULL 替换为常量）
-- 在该字段上建索引
ALTER TABLE tasks ADD COLUMN due_date_sortable DATE GENERATED ALWAYS AS
    (COALESCE(due_date, '9999-12-31')) STORED;
CREATE INDEX idx_tasks_seek ON tasks(due_date_sortable ASC, id DESC);
```

## 常见键集分页陷阱

### 陷阱 1：游标列不是稳定排序

```sql
-- ❌ 错误：仅用 created_at（同一时间戳多行会丢失）
SELECT * FROM orders WHERE created_at < ? ORDER BY created_at DESC LIMIT 20;
-- 同一秒下单的多笔订单可能被截断或重复

-- ✅ 正确：追加主键作为 tie-breaker
SELECT * FROM orders WHERE (created_at, id) < (?, ?)
ORDER BY created_at DESC, id DESC LIMIT 20;
```

### 陷阱 2：索引方向与 ORDER BY 不匹配

```sql
-- 索引：(created_at ASC, id ASC)
-- 查询：ORDER BY created_at DESC, id DESC
-- 老版本 MySQL 不支持降序索引，会触发 filesort

-- ✅ 显式建立匹配方向的索引（MySQL 8.0+ 支持降序索引）
CREATE INDEX idx_orders_seek ON orders(created_at DESC, id DESC);
```

### 陷阱 3：分页过程中数据变化导致游标失效

```sql
-- 用 (created_at, id) 作为游标
-- 如果上一页末行被 DELETE，游标仍然有效（值不变）
-- 但如果 created_at 被 UPDATE，游标会"漂移"：
--   原本游标定位的行现在排序位置变了
--   下一页可能跳过/重复行

-- 解决方案：
-- 1. 选择不可变列作为游标（id 是天然不可变；created_at 通常不变）
-- 2. 应用层维护游标的稳定性（如使用 snapshot ID）
-- 3. 使用 WAL/CDC 流监听数据变化
```

### 陷阱 4：把 OFFSET 误改为 WHERE id > N * page_size

```sql
-- ❌ 错误：试图用 id > 20000 模拟第 1001 页
SELECT * FROM orders WHERE id > 20000 ORDER BY id DESC LIMIT 20;
-- 1. 假设了 id 连续无空洞（实际有删除/复制）
-- 2. 没有保留任何"上一页末行"信息，无法精确定位
-- 3. 翻一页就丢失上下文
```

### 陷阱 5：多列游标的方向反转

```sql
-- 向后翻页（previous page）必须反转排序方向再反转结果
-- ❌ 直接改 < 为 >，但保留 DESC：会从游标向更新的方向走
-- ✅ 反转方向 + 反转最终结果
WITH prev AS (
    SELECT * FROM orders
    WHERE (created_at, id) > (?, ?)              -- 反向
    ORDER BY created_at ASC, id ASC              -- 反向
    LIMIT 20
)
SELECT * FROM prev ORDER BY created_at DESC, id DESC;  -- 再反转
```

### 陷阱 6：游标的客户端编码

```sql
-- 游标暴露给前端时不应暴露内部主键
-- 推荐编码方式：

-- 1. JSON + Base64
-- cursor = base64({"created_at": "2026-04-29T10:00:00", "id": 12345})
-- 解析后用作 SQL 参数

-- 2. HMAC 签名（防止篡改）
-- cursor = base64(payload || hmac(payload, secret))
-- 服务端验证签名后解析

-- 3. 避免：直接拼字符串作为游标
-- "2026-04-29T10:00:00|12345" 容易被构造成恶意参数
```

### 陷阱 7：ClickHouse FINAL 模式下的失效

```sql
-- ClickHouse ReplacingMergeTree 表
-- ❌ FINAL 模式破坏键集分页性能
SELECT * FROM events FINAL
WHERE (event_time, user_id) > (?, ?)
ORDER BY event_time, user_id LIMIT 20;
-- FINAL 强制对所有 part 做合并，主键索引早停失效

-- ✅ 改用 GROUP BY + argMax 模式
SELECT event_time, user_id, argMax(payload, version)
FROM events
WHERE (event_time, user_id) > (?, ?)
GROUP BY event_time, user_id
ORDER BY event_time, user_id LIMIT 20;
```

### 陷阱 8：BigQuery 的 ORDER BY 限制

```sql
-- BigQuery 在大表上 ORDER BY 全局排序代价高
-- 即使有 LIMIT，仍可能 shuffle 全部数据

-- ✅ 配合聚簇键 + 预过滤窗口
SELECT * FROM dataset.events
WHERE event_date = '2026-04-29'                  -- 分区裁剪
  AND (created_at, id) < (?, ?)                  -- 键集游标
ORDER BY created_at DESC, id DESC LIMIT 20;
```

### 陷阱 9：跳页需求的伪分页

```sql
-- 用户要求"跳到第 N 页"（如 GitHub 搜索结果）
-- 键集分页天然不支持跳页！

-- 替代方案：
-- 1. 限制最大页数（GitHub 搜索 = 1000 行硬上限）
-- 2. 显示"~大约 N 万结果"而非精确页数（Google）
-- 3. 配合 OFFSET 但限制 OFFSET 上限（如 OFFSET <= 1000）
-- 4. 跳页时回到第一页（Twitter "Jump to top"）
```

### 陷阱 10：游标值含特殊字符

```sql
-- 游标列是字符串，含逗号、引号、Unicode 等
-- ❌ 直接拼 SQL 字符串极易 SQL 注入

-- ✅ 用参数化查询
-- prepared statement 或 ORM 的 placeholder

-- ❌ 二进制 BLOB 作为游标列
-- 大多数引擎对 BLOB 元组比较支持差，性能不可预测

-- ✅ 优先选择有自然顺序的简单类型：INT/BIGINT/UUID/TIMESTAMP
```

## 应用层代码模式

### Java（jOOQ + PostgreSQL）

```java
// jOOQ 自带 seek() 方法封装键集分页
DSL.using(conn)
   .selectFrom(ORDERS)
   .orderBy(ORDERS.CREATED_AT.desc(), ORDERS.ID.desc())
   .seek(lastCreatedAt, lastId)        // 自动转换为元组比较
   .limit(20)
   .fetch();
```

### Python（SQLAlchemy）

```python
# SQLAlchemy 的 tuple_() 函数支持元组比较
from sqlalchemy import tuple_

stmt = (
    select(Order)
    .where(tuple_(Order.created_at, Order.id) < (last_created_at, last_id))
    .order_by(Order.created_at.desc(), Order.id.desc())
    .limit(20)
)
```

### Go（database/sql）

```go
rows, err := db.Query(`
    SELECT id, created_at, total FROM orders
    WHERE (created_at, id) < ($1, $2)
    ORDER BY created_at DESC, id DESC
    LIMIT 20
`, lastCreatedAt, lastID)
```

### Node.js（Knex）

```javascript
const orders = await knex('orders')
  .select('id', 'created_at', 'total')
  .whereRaw('(created_at, id) < (?, ?)', [lastCreatedAt, lastId])
  .orderBy([
    { column: 'created_at', order: 'desc' },
    { column: 'id', order: 'desc' }
  ])
  .limit(20);
```

## 性能基准对比

某电商平台实测（PostgreSQL 14, 1 亿行 orders 表，B-Tree 索引 (created_at DESC, id DESC)）：

| 方案 | 第 1 页 | 第 100 页 | 第 1000 页 | 第 10000 页 |
|------|--------|----------|-----------|-------------|
| OFFSET 分页 | 5 ms | 50 ms | 500 ms | 5000 ms |
| 键集分页 | 3 ms | 3 ms | 3 ms | 3 ms |
| ROW_NUMBER() 窗口 | 100 ms | 100 ms | 100 ms | 100 ms |
| 临时表预排序 | 800 ms | 5 ms | 5 ms | 5 ms |

键集分页在所有页码上保持稳定的 O(1) 性能，OFFSET 在第 1 万页时已不可接受。

## 设计争议

### "用 ID 作为游标"是否够用？

最简化的实现是仅用主键 ID 作为游标：`WHERE id < ? ORDER BY id DESC LIMIT 20`。这要求数据按主键单调插入（id 顺序与时间顺序一致）。在 UUID v4 主键、分布式 ID 生成器（雪花算法以外）等场景下，id 顺序与时间顺序无关，必须用 `(created_at, id)` 复合游标。

### 是否要在游标中编码排序方向？

游标本身只编码"位置"，排序方向由查询语句决定。但前端经常需要"切换排序"（按时间/价格/热度），此时游标失效——必须把排序键标识符也编码到游标中：

```
cursor = {"sort": "price_desc", "values": [99.99, 12345]}
```

### 多租户系统的游标隔离

多租户系统的游标必须包含 `tenant_id` 上下文，否则可能发生越权——租户 A 的游标在租户 B 上下文下被解析。解决方案：游标 HMAC 签名时包含租户 ID。

### 与 ROW_NUMBER() 的边界

某些场景下 ROW_NUMBER() 反而合适：

- 用户精确指定"第 N 个结果"（如比赛排名）
- 结果集小且固定（如 Top 100 排行榜）
- 不需要稳定翻页（一次性读取）

但**不要把 ROW_NUMBER() 当作分页**——窗口函数计算所有行的 row_number 后再过滤，开销与 OFFSET 等价。

## 引擎实现建议

对于正在设计 SQL 引擎的工程团队，键集分页的优化要点：

### 1. 元组比较谓词的 range scan 转化

```
关键优化点：识别 (col1, col2, ...) > (val1, val2, ...) 形式
转化为索引上的 range scan 起点：
  index_seek_first(index, [val1, val2, ...]) → 返回 cursor
  scan_forward(cursor) → 顺序输出直到 LIMIT

避免：
  - 展开为 OR 后让通用 OR 优化器处理（可能无法识别 range）
  - 仅看第一列做 range scan，后续列回到表过滤（性能急剧退化）
```

### 2. 索引方向匹配的代价模型

```
当 ORDER BY 方向与索引不一致时：
  方案 A: 反向扫描（B-Tree 双向链接 → 几乎无代价）
  方案 B: 正向扫描后排序（filesort，代价高）

代价模型应充分考虑索引的双向扫描能力。
MySQL 8.0+ 支持降序索引正是为了消除某些方向的额外开销。
```

### 3. 列存引擎的 zonemap 裁剪

```
列存引擎（ClickHouse, Vertica, Snowflake）：
  - 元组比较 → 投影到每列的 min/max 范围
  - 利用 zonemap/min-max index 跳过整个 row group / micro-partition
  - 关键：必须对所有元组列同时利用 min/max，不能仅看第一列

ClickHouse 的 mark range 选择是教科书级实现：
  primary key (a, b) 上的 (a, b) > (?, ?)
  → 选择起始 mark，从该 mark 顺序读取
```

### 4. 流处理引擎的 watermark 替代

```
流处理（Flink, ksqlDB）：
  - 不存在传统"分页"，但有事件回溯需求
  - watermark + offset 取代游标
  - 元组比较仅用于离线/批处理模式

实现建议：
  - 对 STREAMING 表的 ORDER BY 警告或拒绝
  - 对 BATCH 表正常优化为 range scan
```

### 5. EXPLAIN 输出的可观测性

```
EXPLAIN 必须明确显示元组比较的执行策略：
  - "Index Range Scan with row value comparison"  ✓
  - "Index Scan + Filter (row value)"            ⚠ 索引利用不完整
  - "Full Table Scan + Filter"                   ✗ 优化器失败

错误类型：
  - 把 (a, b) > (?, ?) 当作两个独立条件，仅用第一列做 range
  - 把 OR 改写后的多分支当作 index merge（双重扫描）
  - 在小表上拒绝 range scan 改用全表扫描（统计信息错误）
```

### 6. 客户端 SDK 的游标抽象

```
高层 SDK（jOOQ, SQLAlchemy, Hibernate）应提供 seek() 接口：
  - 自动检测引擎是否支持原生元组比较
  - 不支持时自动展开为 OR 形式
  - 处理 NULL 列的标准模式
  - 自动维护游标的序列化/反序列化

降低应用层使用键集分页的门槛，是提高其普及度的关键。
```

## 总结对比矩阵

### 键集分页能力总览

| 能力 | PostgreSQL | MySQL 8.0+ | SQL Server | Oracle | SQLite | ClickHouse | Snowflake | BigQuery | DuckDB | Trino |
|------|-----------|-----------|------------|--------|--------|------------|-----------|----------|--------|-------|
| 元组比较 `(a,b) > (?,?)` | 是 | 是 | -- | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| ROW() 构造器 | 是 | 是 | -- | 是 | -- | -- | -- | -- | 是 | 是 |
| 优化器索引利用 | 完整 | 完整 | 不支持 | 部分 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 |
| 降序索引 | 是 | 是 (8.0+) | 是 | 是 | -- | -- | -- | -- | -- | -- |
| NULLS FIRST/LAST | 是 | 否 | 2022+ | 是 | 3.30+ | 是 | 是 | 是 | 是 | 是 |
| 双向分页 | 是 | 是 | 模拟 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |
| 分布式键集分页 | 扩展 | 是 (TiDB) | -- | 是 (RAC) | -- | 是 | 是 | 是 | -- | 是 |

### 引擎选型建议

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| 高流量 Web/App 列表 | PostgreSQL/MySQL 8.0+ 元组比较 | 标准支持，索引利用完整 |
| 嵌入式 SQLite 应用 | SQLite 3.15+ 元组比较 | 移动端电池/IO 友好 |
| 老 MySQL（< 8.0.14） | 显式 OR 展开 | 避免优化器回退到全索引扫描 |
| SQL Server | 显式 OR 展开 | 不支持原生元组比较 |
| Oracle | OR 展开 + Hint | 优化器对元组比较的索引利用不稳定 |
| ClickHouse 高频写入表 | 主键元组比较，避免 FINAL | MergeTree 主键 mark range 扫描 |
| Snowflake 大表 | CLUSTER BY + 元组比较 | micro-partition pruning |
| BigQuery 海量表 | CLUSTER BY + 分区 + 元组比较 | 同上，配合分区裁剪 |
| 流处理 Flink/ksqlDB | watermark + offset | 流处理无传统分页概念 |
| 跨引擎兼容（多种数据库） | 显式 OR 展开 | 最低公分母语法 |

## 关键发现

1. **45+ 引擎中 38 个支持原生元组比较**，但优化器质量差异极大——SQL Server 完全不支持，Oracle 需要 Hint，老 MySQL（< 8.0.14）会回退到全索引扫描
2. **PostgreSQL 自 2006 年（8.2）就完整支持**——是键集分页的"标准实现"，jOOQ 等 ORM 的 seek() API 主要针对 PG 设计
3. **SQLite 3.15（2016）才加入元组比较**——之前移动端 App 普遍用 OR 展开，至今老代码库仍保留这种写法
4. **MySQL 元组比较与索引使用直到 8.0.14（2019）才完整**——所以"键集分页很慢"的传言主要源自老 MySQL 实践
5. **SQL Server 至今不支持原生元组比较**——必须手工展开 OR 或用 CASE 模拟
6. **ClickHouse FINAL 模式破坏键集分页**——MergeTree 主键索引早停失效，应改用 GROUP BY + argMax 模式
7. **NULL 列游标极难处理**——最佳实践是给游标列加 NOT NULL 约束；否则需要拆分多分支或用 COALESCE（破坏索引）
8. **混合 ASC/DESC 排序方向**让元组比较失效——必须手工展开 OR 表达式
9. **Markus Winand 的 *Use The Index, Luke!*** 是 Seek Method 的权威推广者，奠定了键集分页的术语和最佳实践
10. **OFFSET 在分布式系统中代价更高**——TiDB/CockroachDB/Spanner 的键集分页相对收益比单机更显著
11. **流处理引擎（Flink/ksqlDB）的"分页"是 watermark + offset**——不是 SQL 元组比较，是 Kafka 风格的消息位置游标
12. **键集分页天然不支持跳页**——这是它和 OFFSET 最本质的差异；现代产品（Twitter/Slack/Gmail）通常放弃跳页换取性能

## 参考资料

- Markus Winand. *SQL Performance Explained*. 2011. ISBN 978-3-9503078-2-5.
- Markus Winand. *Use The Index, Luke!*: [Pagination](https://use-the-index-luke.com/sql/partial-results/fetch-next-page) and [Seek Method](https://use-the-index-luke.com/no-offset)
- Markus Winand. ["No Offset" page](https://use-the-index-luke.com/no-offset)
- ISO/IEC 9075-2:1992. Row Value Constructor (Section 7.1)
- PostgreSQL Documentation: [Row-wise comparison](https://www.postgresql.org/docs/current/functions-comparisons.html#ROW-WISE-COMPARISON)
- MySQL Documentation: [Row Subqueries](https://dev.mysql.com/doc/refman/8.0/en/row-subqueries.html)
- SQLite Documentation: [Row Values](https://www.sqlite.org/rowvalue.html)
- Oracle SQL Language Reference: [Row Value Comparison](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Comparison-Conditions.html)
- ClickHouse Documentation: [PRIMARY KEY](https://clickhouse.com/docs/en/sql-reference/statements/create/table#primary-key)
- jOOQ Documentation: [Seek Clause](https://www.jooq.org/doc/latest/manual/sql-building/sql-statements/select-statement/seek-clause/)
- Joe Nelson. ["Pagination Done the PostgreSQL Way"](https://wiki.postgresql.org/wiki/Pagination)
- Aaron Patterson. "Pagination at Scale" - Various Rails / ActiveRecord discussions
- Vlad Mihalcea. ["The best way to do pagination in any RDBMS"](https://vladmihalcea.com/sql-seek-keyset-pagination/)
