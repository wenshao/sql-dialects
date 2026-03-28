# StarRocks: 索引

> 参考资料:
> - [1] StarRocks - CREATE INDEX
>   https://docs.starrocks.io/docs/sql-reference/sql-statements/table_bucket_part_index/CREATE_INDEX/


## 1. 索引架构: 列存原生索引体系

 StarRocks 与 Doris 同源，索引体系高度相似，但有关键差异:
   StarRocks 独有: Sort Key 与 Primary Key 分离(ORDER BY 子句)
   StarRocks 独有: Zone Map 自动创建且不可关闭
   Doris 领先:    倒排索引(2.0+)比 StarRocks(3.1+)更早、更成熟

 对引擎开发者的启示:
   列存引擎的索引设计核心是"数据块级过滤":
     Zone Map:     O(1) 判断数据块范围——最廉价也最有效
     Bloom Filter: O(k) 判断是否存在——高基数等值查询
     前缀索引:      二分查找定位数据块——排序键前缀匹配
   这三者的组合已覆盖 95% 的 OLAP 查询场景。

## 2. 前缀索引 (Short Key Index) — 自动创建

```sql
CREATE TABLE users (
    id       BIGINT       NOT NULL,
    username VARCHAR(64)  NOT NULL,
    email    VARCHAR(255)
)
DUPLICATE KEY(id, username)
DISTRIBUTED BY HASH(id) BUCKETS 16;

```

取 Key 列前 36 字节构建稀疏索引，每 1024 行一条记录。
VARCHAR 列只取前 20 字节。

调整短键索引粒度(StarRocks 独有):

```sql
CREATE TABLE t (id BIGINT, name VARCHAR(64))
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16
PROPERTIES ("short_key" = "1");

```

 设计分析:
   "short_key" = "1" 表示只取第一个 Key 列构建前缀索引。
   粒度越小，索引越精确但占用更多存储。
   Doris 也支持此属性但文档中较少提及。

## 3. Bloom Filter 索引

```sql
CREATE TABLE users_bf (
    id    BIGINT,
    email VARCHAR(255)
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16
PROPERTIES ("bloom_filter_columns" = "email");

ALTER TABLE users SET ("bloom_filter_columns" = "email,username");

```

 与 Doris 完全相同的 PROPERTIES 方式设置。
 对比 ClickHouse: CREATE TABLE ... INDEX idx email TYPE bloom_filter GRANULARITY 1

## 4. Bitmap 索引 (低基数列)

```sql
CREATE INDEX idx_status ON users (status) USING BITMAP;
DROP INDEX idx_status ON users;

```

 适合基数 < 10000 的列。与 Doris 完全相同的语法。

## 5. 倒排索引 (3.1+)

 StarRocks 3.1+ 引入倒排索引，但比 Doris 2.0 晚约一年。
 使用 GIN(Generalized Inverted Index) 命名:
 CREATE INDEX idx_content ON articles (content) USING GIN;

 对比:
   Doris 2.0+: USING INVERTED，支持 chinese/english/unicode 分词器
   StarRocks 3.1+: USING GIN，功能和分词器支持正在追赶 Doris
   ClickHouse: tokenbf_v1 / ngrambf_v1(Bloom Filter 近似)，不是真正的倒排
   Elasticsearch: 原生倒排索引引擎

 对引擎开发者的启示:
   Doris 先发的倒排索引是其差异化竞争力之一。
   StarRocks 选择 GIN 命名(与 PostgreSQL 一致)更符合 SQL 标准。

## 6. Rollup (预聚合索引)

```sql
ALTER TABLE daily_stats ADD ROLLUP rollup_by_date (date, SUM(clicks));
SHOW ALTER TABLE ROLLUP;
DESC daily_stats ALL;
ALTER TABLE daily_stats DROP ROLLUP rollup_by_date;

```

 StarRocks 3.0+ 推荐物化视图替代 Rollup:
   Rollup 限制: 仅单表聚合、列子集
   物化视图:    支持多表 JOIN、CBO 自动改写、异步刷新

## 7. 物化视图 (3.0+ 推荐)


同步物化视图

```sql
CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT order_date, user_id, SUM(amount) AS total
FROM orders GROUP BY order_date, user_id;

```

异步物化视图(2.4+)

```sql
CREATE MATERIALIZED VIEW mv_stats
REFRESH ASYNC EVERY (INTERVAL 1 HOUR) AS
SELECT dt, COUNT(*) AS cnt FROM orders GROUP BY dt;

```

 设计分析:
   StarRocks 的异步物化视图支持 CBO 自动改写(Automatic Query Rewrite)。
   查询不需要显式引用物化视图——优化器自动判断并路由。
   这比 Doris 的物化视图能力更强(Doris 2.1 也在跟进)。

 对比:
   Doris:     同步 MV + 异步 MV(2.1+)，自动改写能力弱于 StarRocks
   BigQuery:  物化视图自动刷新 + 自动改写
   ClickHouse: 物化视图是触发器语义(INSERT 触发)，不自动改写

## 8. Zone Map (自动创建，不可关闭)

 每个数据块(约 64KB~1MB)自动记录每列的 min/max 值。
 查询时通过 WHERE 条件对比 min/max，跳过不相关的数据块。
 这是列存引擎最基础也最重要的优化——对所有列自动生效。

## 9. 索引选择对比: StarRocks vs Doris

- **前缀索引**: 两者相同。StarRocks 支持 "short_key" 粒度调整。
- **Zone Map**: 两者相同。自动创建。
- **Bloom Filter**: 两者相同。PROPERTIES 方式设置。
- **Bitmap**: 两者相同。CREATE INDEX USING BITMAP。
- **倒排索引**: Doris 2.0(早) vs StarRocks 3.1(晚)。Doris 更成熟。
- **N-Gram BF**: Doris 2.0 支持，StarRocks 也支持(ngram_bf_index)。
- **Sort Key 分离**: StarRocks 独有(ORDER BY 子句)——更灵活。
- **物化视图改写**: StarRocks 更强(CBO 自动改写更成熟)。

对引擎开发者的参考:
索引设计应遵循"分层过滤"原则:
- Zone Map(最粗) → Bloom Filter(中等) → 前缀索引(精确) → 行级过滤
每一层过滤掉的数据越多，下一层的负载越小。
