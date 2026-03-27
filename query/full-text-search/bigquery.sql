-- BigQuery: 全文搜索
--
-- 参考资料:
--   [1] BigQuery - SEARCH Function
--       https://cloud.google.com/bigquery/docs/search-intro
--   [2] BigQuery - Search Indexes
--       https://cloud.google.com/bigquery/docs/search-index

-- ============================================================
-- 1. SEARCH INDEX（搜索索引）
-- ============================================================

-- 创建搜索索引
CREATE SEARCH INDEX idx_docs ON documents (content);
CREATE SEARCH INDEX idx_all ON documents (ALL COLUMNS);    -- 所有 STRING/JSON 列

-- 自定义分析器
CREATE SEARCH INDEX idx_logs ON logs (message)
OPTIONS (analyzer = 'LOG_ANALYZER');
-- LOG_ANALYZER: 按空格和标点分词（适合日志）
-- PATTERN_ANALYZER: 正则分词
-- NO_OP_ANALYZER: 不分词（精确匹配）

-- 删除搜索索引
DROP SEARCH INDEX idx_docs ON documents;

-- ============================================================
-- 2. SEARCH() 函数
-- ============================================================

-- 基本搜索
SELECT * FROM documents WHERE SEARCH(content, 'error timeout');

-- 精确短语搜索
SELECT * FROM documents WHERE SEARCH(content, '`connection timeout`');

-- 多列搜索
SELECT * FROM documents WHERE SEARCH((title, content), 'SQL tutorial');

-- 搜索所有有索引的列
SELECT * FROM documents WHERE SEARCH(documents, 'error');

-- ============================================================
-- 3. BigQuery 全文搜索的设计（对引擎开发者）
-- ============================================================

-- BigQuery 的搜索索引是异步构建的:
-- (a) 数据写入后，索引在后台自动更新
-- (b) 不影响写入性能
-- (c) 索引可能有短暂延迟（eventual consistency）
--
-- 内部实现:
-- 使用倒排索引（inverted index），集成到 Capacitor 列式存储格式中。
-- 不是独立的索引文件（与 Elasticsearch 不同）。
--
-- 成本: 搜索索引消耗额外存储空间（通常是数据大小的 50-100%）。
-- 查询: 使用搜索索引的查询扫描量显著减少 → 成本降低。

-- 对比:
--   SQLite:     FTS5 虚拟表（嵌入式全文搜索）
--   MySQL:      InnoDB FULLTEXT INDEX
--   PostgreSQL: GIN + tsvector（最灵活）
--   ClickHouse: tokenbf_v1 跳过索引 + full_text 索引
--   Elasticsearch: 专用全文搜索引擎（最强大但独立部署）

-- ============================================================
-- 4. 对比与引擎开发者启示
-- ============================================================
-- BigQuery 全文搜索的特点:
--   (1) 搜索索引是专门的索引类型（不是通用 B-Tree）
--   (2) 异步构建 → 不影响写入
--   (3) SEARCH() 函数 → 简洁的查询接口
--   (4) 分析器可选 → LOG_ANALYZER 适合日志场景
--
-- 对引擎开发者的启示:
--   云数仓不需要 Elasticsearch 级别的全文搜索。
--   简单的倒排索引 + SEARCH() 函数覆盖 80% 的日志搜索需求。
--   搜索索引应该异步构建（不影响写入吞吐量）。
