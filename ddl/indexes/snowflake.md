# Snowflake: 索引（无传统索引的设计哲学）

> 参考资料:
> - [1] Snowflake - Micro-partitions & Data Clustering
>   https://docs.snowflake.com/en/user-guide/tables-clustering-micropartitions
> - [2] Snowflake - Search Optimization Service
>   https://docs.snowflake.com/en/user-guide/search-optimization-service
> - [3] Snowflake - Query Acceleration Service
>   https://docs.snowflake.com/en/user-guide/query-acceleration-service


## 1. 核心设计: 为什么 Snowflake 没有索引


 Snowflake 没有 B-tree、Hash、GIN、GiST 或任何用户创建的索引。
 这是一个有意的架构决策，而非功能缺失。

 设计理由:
   1) 列存 + 微分区裁剪 已覆盖大部分 OLAP 查询场景
   2) 索引维护成本高: 写入时更新索引 → 降低批量加载吞吐
   3) 索引需要用户选择策略（哪些列、什么类型）→ 违背"零管理"哲学
   4) 云对象存储上维护 B-tree 等随机访问结构效率极低
   5) 计算存储分离: 关闭 Warehouse 时无法更新索引

 取代索引的机制:
   (a) 微分区元数据 (Partition Pruning)
   (b) 聚簇键 (Clustering Keys)
   (c) Search Optimization Service
   (d) 物化视图 (Materialized Views)
   (e) Query Acceleration Service

## 2. 微分区: "元数据即索引"


每个表的数据自动分成 50-500 MB 的不可变微分区
每个微分区记录每列的统计信息:
- MIN / MAX 值
- NULL 计数
- 不同值计数 (NDV, Number of Distinct Values)
- 布隆过滤器 (Bloom Filter, 用于等值查询)

查询时优化器利用这些元数据跳过不相关的微分区:

```sql
SELECT * FROM orders WHERE order_date = '2024-06-15';
```

优化器检查每个微分区的 order_date MIN/MAX
如果某个微分区的 MIN > '2024-06-15' 或 MAX < '2024-06-15'，直接跳过
效果类似 B-tree 的范围裁剪，但无需用户创建和维护

查看分区裁剪效果:

```sql
SELECT query_id,
       partitions_scanned,
       partitions_total,
       ROUND(partitions_scanned / NULLIF(partitions_total, 0) * 100, 2) AS scan_pct
FROM snowflake.account_usage.query_history
WHERE query_text LIKE '%orders%'
ORDER BY start_time DESC
LIMIT 10;

```

 对引擎开发者的启示:
   微分区元数据本质上是一个稀疏索引 (Sparse Index)。
   传统数据库的"段摘要" (Segment Summary) 是类似概念（Oracle Exadata Smart Scan）。
   Delta Lake 的数据跳过 (Data Skipping) 和 Iceberg 的 Manifest 文件也采用相同策略。
   关键实现细节: 统计信息必须在写入时同步更新，延迟更新会导致裁剪失效。

## 3. 聚簇键 (Clustering Keys)


微分区裁剪的效果取决于数据在微分区间的排列。
如果 order_date 的值均匀分散在所有微分区中，裁剪效果为零。
聚簇键告诉 Snowflake 按指定列组织微分区的数据分布。


```sql
CREATE TABLE events (
    event_id   NUMBER,
    event_time TIMESTAMP_NTZ,
    user_id    NUMBER,
    event_type VARCHAR(50)
) CLUSTER BY (event_time::DATE);
```

注意: 聚簇键可以用表达式（如 event_time::DATE 将时间截断为日期）

多列聚簇:

```sql
CREATE TABLE sales (
    id      NUMBER,
    dt      DATE,
    region  VARCHAR(20),
    amount  NUMBER(10,2)
) CLUSTER BY (dt, region);
```

列的顺序影响聚簇优先级: dt 最先排列，region 次之

动态管理:

```sql
ALTER TABLE orders CLUSTER BY (order_date);
ALTER TABLE orders DROP CLUSTERING KEY;

```

查看聚簇质量:

```sql
SELECT SYSTEM$CLUSTERING_INFORMATION('events');
```

返回: average_depth, average_overlap, total_partitions 等指标
clustering_depth 越小越好（理想值为 1，表示每个分区的值域不重叠）


```sql
SELECT SYSTEM$CLUSTERING_DEPTH('events');
```

返回整体聚簇深度，越小越好

控制自动聚簇:

```sql
ALTER TABLE events SUSPEND RECLUSTER;      -- 暂停后台自动聚簇
ALTER TABLE events RESUME RECLUSTER;       -- 恢复自动聚簇
```

 自动聚簇是后台异步操作，按 credit 计费
 不保证即时生效（可能在数据写入后数小时才完成重组织）

 聚簇键选择的最佳实践:
 (a) 选择 WHERE 子句最常用的列（裁剪收益最大）
 (b) 选择基数适中的列（太低无区分度，太高导致聚簇无效）
 (c) 不超过 3-4 列（过多列增加聚簇维护成本）
 (d) 日期/时间列几乎总是好的候选（时间序列数据的天然排序）

 对比:
   BigQuery:   CLUSTER BY（最多 4 列，自动维护，语义最接近）
   Redshift:   SORTKEY / COMPOUND SORTKEY / INTERLEAVED SORTKEY
               需要手动 VACUUM SORT 维护，Snowflake 自动维护是优势
   Databricks: ZORDER BY（通过 OPTIMIZE 手动触发，不自动）
   MaxCompute: CLUSTERED BY + SORTED BY（与 Hive 一致）
   ClickHouse: ORDER BY（MergeTree 表的排序键，实际上就是聚簇键）

## 4. Search Optimization Service (Enterprise+)


为特定查询模式创建后台加速结构（类似自动管理的索引）

```sql
ALTER TABLE users ADD SEARCH OPTIMIZATION;                        -- 全表开启
ALTER TABLE users ADD SEARCH OPTIMIZATION ON EQUALITY(user_id);   -- 等值查询加速
ALTER TABLE users ADD SEARCH OPTIMIZATION ON EQUALITY(email);
ALTER TABLE users ADD SEARCH OPTIMIZATION ON SUBSTRING(username); -- LIKE '%...%' 加速
ALTER TABLE users ADD SEARCH OPTIMIZATION ON GEO(location);       -- 地理查询加速

```

删除优化:

```sql
ALTER TABLE users DROP SEARCH OPTIMIZATION ON EQUALITY(email);
ALTER TABLE users DROP SEARCH OPTIMIZATION;                       -- 全表关闭

```

 Search Optimization 的内部实现:
 系统自动为指定列构建搜索访问路径 (Search Access Path)，
 本质上是一种系统管理的辅助索引，但用户无法直接看到或控制其结构。
 成本: 后台维护消耗计算资源（按 credit 计费）+ 额外存储

 对比传统索引:
   传统索引: 用户创建、用户命名、用户选择类型、用户监控状态
   Search Opt: 系统创建、系统管理、系统维护、系统决定何时更新
   这是"零管理"哲学的体现: 用户只说"我需要加速这个查询"，系统决定怎么做

## 5. 物化视图 (Materialized Views, Enterprise+)


```sql
CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT order_date, SUM(amount) AS daily_total, COUNT(*) AS order_count
FROM orders
GROUP BY order_date;

```

 Snowflake 自动维护物化视图（源表变更后自动更新）
 查询优化器自动决定是否使用物化视图（透明查询重写）
 对比:
   Oracle:     物化视图功能最强（REFRESH FAST/COMPLETE/ON COMMIT/ON DEMAND）
   PostgreSQL: 物化视图不自动刷新（需要 REFRESH MATERIALIZED VIEW）
   BigQuery:   物化视图自动维护 + 自动查询重写（与 Snowflake 一致）
   Redshift:   物化视图自动刷新（AUTO REFRESH）

## 6. Query Acceleration Service

```sql
ALTER WAREHOUSE my_wh SET QUERY_ACCELERATION_MAX_SCALE_FACTOR = 8;
```

 将大查询的部分工作动态分发到额外的计算节点
 不是索引，而是"按需弹性算力"加速
 对比: 这是 Snowflake 特有能力，其他引擎没有等价机制

## 横向对比: 查询加速策略

| 引擎        | 主要加速手段            | 用户管理负担 |
|------|------|------|
| Snowflake   | 微分区裁剪+聚簇键+SOS   | 极低（几乎全自动） |
| BigQuery    | 分区裁剪+聚簇            | 低（类似 Snowflake） |
| Redshift    | SORTKEY+DISTKEY+传统索引  | 高（需手动 VACUUM） |
| Databricks  | 数据跳过+ZORDER+统计信息  | 中（需手动 OPTIMIZE） |
| MySQL       | B-tree/Hash/Full-text     | 高（需手动创建/分析/优化） |
| PostgreSQL  | B-tree/Hash/GIN/GiST/BRIN| 高（最灵活但最复杂） |
| Oracle      | B-tree/Bitmap/Function    | 高（但 Exadata Smart Scan 类似微分区裁剪） |

对引擎开发者的启示:
Snowflake 的"无索引"策略在 OLAP 场景下是正确的选择。
但对点查询（WHERE id = ?）和高基数列（UUID），缺少索引确实是短板。
Search Optimization Service 是对这一短板的后期补救。
Hybrid Tables (2024) 引入 B+树索引，标志着 Snowflake 承认纯列存
在 OLTP 场景的局限，开始向 HTAP 混合架构演进。
