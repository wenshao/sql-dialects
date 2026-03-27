-- BigQuery: 索引（Indexes）
--
-- 参考资料:
--   [1] BigQuery SQL Reference - Search Indexes
--       https://cloud.google.com/bigquery/docs/search-index
--   [2] BigQuery Documentation - Partitioning and Clustering
--       https://cloud.google.com/bigquery/docs/partitioned-tables
--   [3] BigQuery - Vector Index
--       https://cloud.google.com/bigquery/docs/vector-index

-- ============================================================
-- 1. 为什么 BigQuery 没有传统索引（对引擎开发者）
-- ============================================================

-- BigQuery 没有 B-Tree、Hash、Bitmap 等传统索引。
-- 这不是功能缺失，而是架构设计的必然结果:
--
-- (a) 无服务器架构: 没有持久化的"服务器"来维护索引数据结构
--     传统索引需要在 INSERT/UPDATE/DELETE 时同步更新
--     BigQuery 没有常驻进程，数据直接写入 Colossus 分布式文件系统
--
-- (b) 列式存储 + 向量化扫描: Dremel 引擎本身就是为全表扫描优化的
--     列式压缩 + 向量化执行 → 扫描 TB 级数据也只需要秒级
--     B-Tree 索引在行存中减少 I/O，但列存已经大幅减少了 I/O
--
-- (c) 存储计算分离: 索引需要靠近存储来减少延迟
--     BigQuery 计算节点（slot）是临时分配的，每次查询可能分配不同节点
--     传统索引假设索引在本地磁盘上，BigQuery 无此假设
--
-- (d) Slot 调度模型: 查询被分解为数千个 slot 并行执行
--     每个 slot 扫描一小部分数据 → 分布式扫描比索引查找更适合
--
-- 替代方案: 分区裁剪 + 聚集过滤 + 搜索索引

-- ============================================================
-- 2. 分区（Partitioning）: 最重要的"索引"替代
-- ============================================================

-- 按日期列分区（最常用）
CREATE TABLE orders (
    id         INT64,
    user_id    INT64,
    amount     NUMERIC,
    order_date DATE
)
PARTITION BY order_date;

-- 按 TIMESTAMP 截断分区
CREATE TABLE events (
    id         INT64,
    event_time TIMESTAMP
)
PARTITION BY TIMESTAMP_TRUNC(event_time, DAY);
-- 支持: HOUR, DAY, MONTH, YEAR

-- 整数范围分区
CREATE TABLE logs (
    id    INT64,
    level INT64,
    msg   STRING
)
PARTITION BY RANGE_BUCKET(level, GENERATE_ARRAY(0, 100, 10));

-- 按摄入时间分区（自动管理）
CREATE TABLE raw_events (
    id   INT64,
    data STRING
)
PARTITION BY _PARTITIONDATE;

-- 分区裁剪原理:
--   SELECT * FROM orders WHERE order_date = '2024-01-15'
--   → 只读取 2024-01-15 分区的数据（其他分区完全不碰）
--   → 从 PB 级表中只读取 GB 级数据
--
-- 成本控制: 分区直接影响查询费用（按扫描量计费）
-- require_partition_filter 可以强制查询必须有分区条件

-- ============================================================
-- 3. 聚集（Clustering）: 分区内的排序优化
-- ============================================================

CREATE TABLE orders (
    id         INT64,
    user_id    INT64,
    status     STRING,
    order_date DATE
)
PARTITION BY order_date
CLUSTER BY user_id, status;       -- 最多 4 个聚集列

-- 聚集的工作原理:
--   数据在每个分区内按聚集列排序存储。
--   查询时 BigQuery 利用排序信息跳过不相关的存储块。
--
--   SELECT * FROM orders WHERE order_date = '2024-01-15' AND user_id = 123
--   → 分区裁剪: 只读 2024-01-15 分区
--   → 聚集过滤: 在分区内跳过 user_id != 123 的存储块
--
-- 聚集 vs 索引:
--   传统索引: 显式创建，精确定位行，需要维护
--   BigQuery 聚集: 声明式，近似过滤块，自动维护（后台自动重聚集）

-- 不分区也可以聚集
CREATE TABLE users (
    id       INT64,
    country  STRING,
    city     STRING,
    username STRING
)
CLUSTER BY country, city;

-- 聚集列的选择策略:
--   优先选择查询 WHERE 条件中常用的列
--   低基数列在前（过滤掉更多数据块）
--   最多 4 列（与 ClickHouse 的 ORDER BY 多列类似）

-- ============================================================
-- 4. 搜索索引（Search Index）: BigQuery 的全文搜索
-- ============================================================

-- 对 STRING/JSON 列创建搜索索引
CREATE SEARCH INDEX idx_search ON documents (content);

-- 对所有 STRING/JSON 列创建搜索索引
CREATE SEARCH INDEX idx_all ON documents (ALL COLUMNS);

-- 自定义分析器
CREATE SEARCH INDEX idx_search ON documents (content)
OPTIONS (analyzer = 'LOG_ANALYZER');
-- LOG_ANALYZER: 按空格和标点分词（适合日志）
-- PATTERN_ANALYZER: 正则表达式分词
-- NO_OP_ANALYZER: 不分词（精确匹配）

-- 使用搜索索引查询
SELECT * FROM documents WHERE SEARCH(content, 'error timeout');
SELECT * FROM documents WHERE SEARCH(content, '`exact phrase`');

-- 删除搜索索引
DROP SEARCH INDEX idx_search ON documents;

-- 设计分析:
--   搜索索引是 BigQuery 唯一的"真正索引"（预计算的数据结构）。
--   它在后台异步构建，不影响写入性能。
--   内部实现类似倒排索引，但集成到 Capacitor 存储格式中。
--
-- 对比:
--   MySQL:      FULLTEXT INDEX（InnoDB 5.6+）
--   PostgreSQL: GIN + tsvector（最灵活）
--   ClickHouse: tokenbf_v1 / ngrambf_v1 跳过索引 + full_text 索引
--   SQLite:     FTS5 虚拟表

-- ============================================================
-- 5. 向量索引（Vector Index）: AI/ML 场景
-- ============================================================

-- 创建向量索引（用于嵌入向量的近似最近邻搜索）
CREATE VECTOR INDEX idx_embedding ON items (embedding)
OPTIONS (index_type = 'IVF', distance_type = 'COSINE');

-- 距离类型: COSINE, EUCLIDEAN, DOT_PRODUCT

-- 使用向量搜索
SELECT base.*, distance
FROM VECTOR_SEARCH(
    TABLE items,
    'embedding',
    (SELECT embedding FROM query_vectors LIMIT 1),
    top_k => 10
);

-- 设计分析:
--   向量索引反映了云数仓向 AI/ML 工作负载扩展的趋势。
--   IVF（Inverted File Index）将向量空间分区，加速近似最近邻搜索。
--   BigQuery 选择在数仓内提供向量搜索，避免用户导出数据到专用向量数据库。
--
-- 对比:
--   PostgreSQL: pgvector 扩展（HNSW/IVFFlat 索引）
--   ClickHouse: 实验性 annoy/usearch 索引
--   专用向量库: Pinecone, Weaviate, Milvus（性能更好但数据需要同步）

-- ============================================================
-- 6. 对比与引擎开发者启示
-- ============================================================
-- BigQuery 的"索引"设计哲学:
--   (1) 分区 = 粗粒度数据裁剪（最重要，影响成本）
--   (2) 聚集 = 存储块级别的排序过滤
--   (3) 搜索索引 = 全文搜索的倒排索引
--   (4) 向量索引 = AI/ML 场景的 ANN 索引
--   (5) 无 B-Tree = 列式扫描不需要逐行索引
--
-- 对引擎开发者的启示:
--   列式存储引擎不需要传统索引。分区裁剪 + 列式扫描已经足够高效。
--   但两种"索引"值得考虑:
--   - 搜索索引: 非结构化文本查询无法靠列扫描加速
--   - 向量索引: 高维空间搜索无法靠排序加速
--   这解释了为什么 BigQuery 只在这两种场景引入了索引概念。
