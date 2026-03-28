# ClickHouse: 索引（Indexes）

> 参考资料:
> - [1] ClickHouse - Data Skipping Indexes
>   https://clickhouse.com/docs/en/sql-reference/statements/alter/skipping-index
> - [2] ClickHouse - Primary Keys and Indexes
>   https://clickhouse.com/docs/en/guides/creating-tables#primary-keys
> - [3] ClickHouse - Projections
>   https://clickhouse.com/docs/en/sql-reference/statements/alter/projection


## 1. ClickHouse 索引体系总览（与传统数据库的根本区别）


 传统数据库（MySQL/PostgreSQL）: 索引定位到具体行
 ClickHouse:                     索引定位到数据块（granule）

 这个根本区别源于列式存储的数据组织方式:
   数据按 ORDER BY 排序 → 分成 data part → 每个 part 内按 granule 分块
   每个 granule 包含 index_granularity 行（默认 8192）
   索引的作用是跳过不相关的 granule，而非定位单行

## 2. 主键索引（稀疏索引 / Primary Key Index）


ORDER BY 定义数据的物理排列顺序和主键索引

```sql
CREATE TABLE users (
    id         UInt64,
    username   String,
    email      String,
    created_at DateTime
)
ENGINE = MergeTree()
ORDER BY id;              -- 按 id 排序 + 建立稀疏索引

```

PRIMARY KEY 可以与 ORDER BY 不同（必须是前缀）

```sql
CREATE TABLE orders (
    user_id    UInt64,
    order_date Date,
    amount     Decimal(10,2),
    status     String
)
ENGINE = MergeTree()
ORDER BY (user_id, order_date)    -- 排序键: 物理排列顺序
PRIMARY KEY user_id;              -- 主键: 稀疏索引的粒度

```

### 2.1 稀疏索引的工作原理

 稀疏索引 = 每 N 行记录一个索引条目（N = index_granularity = 8192）
 存储的是每个 granule 的第一行的主键值。

 查找 WHERE id = 12345:
   (1) 在稀疏索引中二分查找 → 定位到 granule
   (2) 在该 granule 的 8192 行中顺序扫描（列存，极快）

 设计 trade-off:
   优点: 索引极小（1000 万行只有 ~1200 个索引条目）
         → 整个索引可以常驻内存
   缺点: 不能做精确的单行定位
         → 点查效率低于 B+Tree（但 ClickHouse 不是为点查设计的）

 对比:
   MySQL B+Tree:  每行一个索引条目，精确定位，但索引可能几 GB
   PostgreSQL:    每行一个索引条目，类似 MySQL
   BigQuery:      无索引，全部列扫描 + 分区裁剪
   Druid:         位图索引（bitmap），定位到 segment + 行

### 2.2 ORDER BY 的选择策略

 排序键决定了哪些查询可以高效执行:
   ORDER BY (user_id, order_date)
   → WHERE user_id = X            快（前缀匹配）
   → WHERE user_id = X AND order_date = Y   快
   → WHERE order_date = Y         慢（不是前缀）

 选择原则: 低基数列在前，高基数列在后
 反直觉但正确: 低基数列使得更多数据在同一 granule 内连续存储

## 3. 数据跳过索引（Data Skipping Indexes / Secondary Indexes）


 跳过索引 = 为每组 GRANULARITY 个 granule 记录统计信息
 查询时用统计信息判断是否可以跳过这组 granule

### 3.1 minmax（记录最小最大值）

```sql
ALTER TABLE users ADD INDEX idx_age age TYPE minmax GRANULARITY 4;
```

 WHERE age BETWEEN 20 AND 30 → 跳过 min>30 或 max<20 的 granule 组
 适用场景: 有序或部分有序的数值列

### 3.2 set（记录唯一值集合）

```sql
ALTER TABLE users ADD INDEX idx_status status TYPE set(100) GRANULARITY 4;
```

 set(100) = 每组 granule 最多记录 100 个唯一值
 WHERE status = 'active' → 跳过不包含 'active' 的 granule 组
 适用场景: 低基数列（如状态、类别）

### 3.3 bloom_filter（布隆过滤器）

```sql
ALTER TABLE users ADD INDEX idx_email email TYPE bloom_filter(0.01) GRANULARITY 4;
```

### 0.01 = 假阳性率 1%（可能误判存在，但不会误判不存在）

 WHERE email = 'alice@e.com' → 跳过布隆过滤器返回"不存在"的 granule 组
 适用场景: 高基数列的等值查询

### 3.4 tokenbf_v1（分词布隆过滤器）

```sql
ALTER TABLE logs ADD INDEX idx_msg message TYPE tokenbf_v1(10240, 3, 0) GRANULARITY 4;
```

 将文本按分隔符分词，对每个词建布隆过滤器
 WHERE message LIKE '%error%' → 利用分词过滤

### 3.5 ngrambf_v1（N-gram 布隆过滤器）

```sql
ALTER TABLE logs ADD INDEX idx_ngram message TYPE ngrambf_v1(4, 10240, 3, 0) GRANULARITY 4;
```

将文本拆成 4-gram 子串，对每个子串建布隆过滤器
WHERE message LIKE '%rror%' → 利用 N-gram 过滤

建表时定义跳过索引

```sql
CREATE TABLE logs (
    timestamp DateTime,
    level     String,
    message   String,
    INDEX idx_level level TYPE set(10) GRANULARITY 4,
    INDEX idx_msg message TYPE tokenbf_v1(10240, 3, 0) GRANULARITY 4
)
ENGINE = MergeTree()
ORDER BY timestamp;

```

索引管理

```sql
ALTER TABLE users DROP INDEX idx_email;
ALTER TABLE users MATERIALIZE INDEX idx_email;             -- 对已有数据生效
ALTER TABLE users MATERIALIZE INDEX idx_email IN PARTITION '2024-01';

```

## 4. 投影（Projection，20.12+）


投影 = 按不同排序存储数据副本，查询自动路由到最优投影


```sql
ALTER TABLE orders ADD PROJECTION orders_by_date (
    SELECT * ORDER BY order_date        -- 按日期排序的副本
);
ALTER TABLE orders MATERIALIZE PROJECTION orders_by_date;

```

聚合投影（预计算聚合结果）

```sql
ALTER TABLE orders ADD PROJECTION daily_summary (
    SELECT order_date, sum(amount), count()
    GROUP BY order_date
);
ALTER TABLE orders MATERIALIZE PROJECTION daily_summary;

```

 设计分析:
   投影本质是"自动物化视图":
   - 与数据同步更新（INSERT 时自动维护）
   - 存储在同一个 data part 中（与表数据共存）
   - 查询优化器自动选择最优投影
   对比: MySQL 无类似功能; PostgreSQL 需要手动维护物化视图
   对比: BigQuery 的 CLUSTER BY 类似但只有一种排序，投影可以有多种

## 5. 全文索引（实验性）


23.1+ inverted 类型，24.1+ 更名为 full_text

```sql
ALTER TABLE docs ADD INDEX idx_content content TYPE full_text GRANULARITY 1;

```

 对比:
   MySQL:      InnoDB FULLTEXT INDEX（5.6+）
   PostgreSQL: GIN + tsvector（最成熟的全文搜索）
   SQLite:     FTS5 虚拟表
   BigQuery:   SEARCH INDEX + SEARCH() 函数

## 6. 引擎开发者启示

ClickHouse 索引体系的核心设计原则:
(1) 稀疏索引 + 列存 = 索引极小但足够（不需要逐行索引）
(2) 跳过索引 = 统计信息辅助过滤（概率性，不精确）
(3) 投影 = 多种物理排序共存（空间换时间）
(4) 没有 B+Tree 索引（因为 OLAP 不需要逐行定位）

如果设计 OLAP 引擎:
不需要 B+Tree（开销太大，OLAP 查询扫描大量行）
稀疏索引 + 跳过索引 是更好的选择
投影是杀手级功能，但需要权衡额外存储开销

