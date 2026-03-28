# Apache Doris: 索引

 Apache Doris: 索引

 参考资料:
   [1] Doris Documentation - Index Overview
       https://doris.apache.org/docs/table-design/index/

## 1. 索引架构: 没有 B-Tree，全是列存原生索引

 Doris 不支持 B-Tree / Hash 等传统索引。这是列存引擎的根本性设计差异。

 设计哲学:
   行存引擎(MySQL/PG): B-Tree 索引 → 定位行 → 读取整行
   列存引擎(Doris):     列存天然按列扫描 → 需要的是"跳过无关数据块"的索引

   Doris 的索引体系围绕"数据块级过滤"构建:
     前缀索引 → 定位数据块范围(类似 B-Tree 的粗粒度版本)
     Zone Map  → 按 min/max 跳过整个数据块(自动创建)
     Bloom Filter → 判断数据块中是否包含目标值
     Bitmap → 位图编码低基数列(如 status/gender)
     倒排索引 → 全文检索和等值查询(2.0+)

 对比:
   StarRocks:  几乎相同的索引体系(同源)
   ClickHouse: Zone Map(自动) + Bloom Filter + Skip Index
   BigQuery:   自动管理(用户无法创建索引)
   MySQL:      B-Tree / Hash / Full-Text / Spatial

 对引擎开发者的启示:
   列存引擎不需要 B-Tree 的原因: 列存的顺序扫描已经很快(SIMD 加速)，
   B-Tree 的随机 I/O 反而是瓶颈。"跳过数据块"比"定位单行"更重要。

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

 设计分析:
   取 Key 列的前 36 字节构建稀疏索引，每 1024 行一条索引记录。
   VARCHAR 列只取前 20 字节(避免索引膨胀)。
   最佳实践: 将高基数、短字段放在 Key 列前面。

   这本质上是 LSM-Tree 的 Block Index——类似 LevelDB 的 Index Block。

 对比:
   StarRocks: 完全相同(同源)。可通过 PROPERTIES("short_key"="1") 调整粒度。
   ClickHouse: Primary Index 类似(稀疏索引)，但基于全部 ORDER BY 列。

## 3. Bloom Filter 索引 (高基数列等值查询)

```sql
CREATE TABLE users_bf (
    id    BIGINT,
    email VARCHAR(255)
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16
PROPERTIES ("bloom_filter_columns" = "email");

```

修改 Bloom Filter 列

```sql
ALTER TABLE users SET ("bloom_filter_columns" = "email,username");

```

 设计分析:
   Bloom Filter 是通过表属性(PROPERTIES)设置的，不是 CREATE INDEX。
   每个数据块有独立的 Bloom Filter，用于等值查询时快速判断"该块是否包含目标值"。
   假阳性率约 1%，内存开销约 10 bits/key。

 对比:
   StarRocks: 相同的 PROPERTIES 方式设置(同源)
   ClickHouse: 通过 INDEX 语法: INDEX idx_email email TYPE bloom_filter GRANULARITY 1
   MySQL:     无 Bloom Filter(InnoDB 有 Adaptive Hash Index，不同概念)

## 4. Bitmap 索引 (低基数列)

```sql
CREATE INDEX idx_status ON users (status) USING BITMAP;
DROP INDEX idx_status ON users;

```

 设计分析:
   适合基数 < 10000 的列(如 status, gender, region)。
   每个不同值对应一个位图向量，查询时通过位运算高效过滤。

   与 Bitmap 聚合类型(BITMAP_UNION)不同:
     Bitmap 索引 → 加速 WHERE 条件过滤
     BITMAP 类型 → 用于 COUNT DISTINCT 预聚合

 对比:
   StarRocks: 完全相同的语法(同源)
   ClickHouse: 不支持 Bitmap 索引(但有 Set Index)
   Oracle:    支持 Bitmap Index，但不推荐用于 OLTP(锁粒度问题)

## 5. 倒排索引 (Inverted Index，2.0+，Doris 独特优势)

```sql
CREATE INDEX idx_bio ON users (bio) USING INVERTED;

```

带分词器的倒排索引

```sql
CREATE INDEX idx_bio_cn ON users (bio) USING INVERTED
    PROPERTIES ("parser" = "chinese");
CREATE INDEX idx_bio_en ON users (bio) USING INVERTED
    PROPERTIES ("parser" = "english");

```

建表时指定倒排索引

```sql
CREATE TABLE articles (
    id      BIGINT       NOT NULL,
    title   VARCHAR(256),
    content STRING,
    INDEX idx_title (title) USING INVERTED,
    INDEX idx_content (content) USING INVERTED PROPERTIES ("parser" = "chinese")
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16;

```

 设计分析:
   Doris 2.0 的倒排索引是其相比 StarRocks 的差异化功能之一。
   基于 CLucene(Lucene C++ 移植)实现，支持:
     全文检索: MATCH_ALL / MATCH_ANY / MATCH_PHRASE
     等值/范围查询加速
     中文/英文/Unicode 分词

   StarRocks 3.1 也引入了倒排索引，但 Doris 起步更早、功能更完善。

 对比:
   StarRocks:  3.1+ 支持倒排索引，但 Doris 更成熟
   ClickHouse: 无倒排索引(有 tokenbf_v1 近似实现)
   MySQL:      InnoDB Full-Text Index(基于 B-Tree 的倒排表)
   Elasticsearch: 原生倒排索引引擎，功能最完整

## 6. N-Gram Bloom Filter 索引 (2.0+)

```sql
CREATE INDEX idx_email_ngram ON users (email) USING NGRAM_BF
    PROPERTIES ("gram_size" = "3");

```

 设计分析:
   将字符串分成 N 个字符的片段(N-Gram)，用 Bloom Filter 索引。
   加速 LIKE '%keyword%' 模糊查询——无倒排索引时唯一的加速手段。

 对比: ClickHouse 的 ngrambf_v1 Index 是相同的设计。

## 7. Rollup (预聚合索引)

```sql
ALTER TABLE daily_stats ADD ROLLUP rollup_by_date (date, clicks);
SHOW ALTER TABLE ROLLUP;
DESC daily_stats ALL;
ALTER TABLE daily_stats DROP ROLLUP rollup_by_date;

```

## 8. 物化视图

```sql
CREATE MATERIALIZED VIEW mv_daily_sales AS
SELECT order_date, user_id, SUM(amount) AS total
FROM orders GROUP BY order_date, user_id;

```

异步物化视图(2.1+)

```sql
CREATE MATERIALIZED VIEW mv_stats
REFRESH COMPLETE ON SCHEDULE EVERY 1 HOUR AS
SELECT dt, COUNT(*) AS cnt FROM orders GROUP BY dt;

```

## 9. 索引选择决策树 (对引擎开发者)

查询模式           → 推荐索引
主键/排序键等值    → 前缀索引(自动)
高基数列等值       → Bloom Filter
低基数列过滤       → Bitmap 索引
全文检索/LIKE      → 倒排索引(2.0+)
LIKE '%xx%' 模糊   → N-Gram Bloom Filter
聚合查询加速       → Rollup / 物化视图
范围扫描           → Zone Map(自动)

