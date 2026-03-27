-- BigQuery: 索引
--
-- 参考资料:
--   [1] BigQuery SQL Reference - Search Indexes
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/search-index
--   [2] BigQuery SQL Reference - DDL
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language

-- BigQuery 不支持传统索引
-- 查询优化通过以下机制实现：

-- ============================================================
-- 分区（Partitioning）—— 最重要的优化手段
-- ============================================================

-- 按日期列分区
CREATE TABLE orders (
    id         INT64,
    user_id    INT64,
    amount     NUMERIC(10,2),
    order_date DATE
)
PARTITION BY order_date;

-- 按 TIMESTAMP 截断分区
CREATE TABLE events (
    id         INT64,
    event_time TIMESTAMP
)
PARTITION BY TIMESTAMP_TRUNC(event_time, DAY);
-- 支持：DAY, HOUR, MONTH, YEAR

-- 整数范围分区
CREATE TABLE logs (
    id    INT64,
    level INT64
)
PARTITION BY RANGE_BUCKET(level, GENERATE_ARRAY(0, 100, 10));

-- 按摄入时间分区
CREATE TABLE events (
    id   INT64,
    data STRING
)
PARTITION BY _PARTITIONDATE;

-- ============================================================
-- 聚集（Clustering）—— 分区内的排序优化
-- ============================================================

CREATE TABLE orders (
    id         INT64,
    user_id    INT64,
    status     STRING,
    order_date DATE
)
PARTITION BY order_date
CLUSTER BY user_id, status;                 -- 最多 4 个聚集列

-- 不分区也可以聚集
CREATE TABLE users (
    id       INT64,
    country  STRING,
    city     STRING,
    username STRING
)
CLUSTER BY country, city;

-- ============================================================
-- 搜索索引（Search Index，全文搜索）
-- ============================================================

-- 对 STRING 和 JSON 列创建搜索索引
CREATE SEARCH INDEX idx_search ON documents (content);
CREATE SEARCH INDEX idx_search_all ON documents (ALL COLUMNS);

-- 使用搜索索引
SELECT * FROM documents WHERE SEARCH(content, 'keyword');

-- 删除搜索索引
DROP SEARCH INDEX idx_search ON documents;

-- ============================================================
-- 向量索引（Vector Index，用于相似度搜索）
-- ============================================================

CREATE VECTOR INDEX idx_embedding ON items (embedding)
OPTIONS (index_type = 'IVF', distance_type = 'COSINE');

-- 使用向量搜索
SELECT * FROM items
ORDER BY ML.DISTANCE(embedding, @query_vector, 'COSINE')
LIMIT 10;

-- 注意：BigQuery 没有 B-tree / Hash 等传统索引
-- 注意：分区 + 聚集是最主要的性能优化方式
-- 注意：搜索索引用于全文搜索场景
-- 注意：向量索引用于 AI/ML 嵌入向量搜索
-- 注意：BigQuery 自动管理底层存储和查询优化
