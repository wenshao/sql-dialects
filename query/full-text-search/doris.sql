-- Apache Doris: 全文搜索
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- Doris 2.0+ 支持倒排索引实现全文搜索

-- ============================================================
-- 创建倒排索引
-- ============================================================

-- 建表时创建
CREATE TABLE articles (
    id      BIGINT NOT NULL,
    title   VARCHAR(256),
    content STRING,
    INDEX idx_title (title) USING INVERTED,
    INDEX idx_content (content) USING INVERTED PROPERTIES ("parser" = "english")
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16;

-- 中文分词器
CREATE TABLE articles_cn (
    id      BIGINT NOT NULL,
    title   VARCHAR(256),
    content STRING,
    INDEX idx_title (title) USING INVERTED PROPERTIES ("parser" = "chinese"),
    INDEX idx_content (content) USING INVERTED PROPERTIES ("parser" = "chinese")
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16;

-- 对已有表添加倒排索引
CREATE INDEX idx_bio ON users (bio) USING INVERTED;
CREATE INDEX idx_bio_cn ON users (bio) USING INVERTED PROPERTIES ("parser" = "chinese");

-- 删除倒排索引
DROP INDEX idx_bio ON users;

-- ============================================================
-- MATCH_ALL（全部匹配，类似 AND）
-- ============================================================

SELECT * FROM articles
WHERE content MATCH_ALL 'database performance';
-- 同时包含 "database" 和 "performance"

-- ============================================================
-- MATCH_ANY（任意匹配，类似 OR）
-- ============================================================

SELECT * FROM articles
WHERE content MATCH_ANY 'database performance';
-- 包含 "database" 或 "performance"

-- ============================================================
-- MATCH_PHRASE（短语匹配）
-- ============================================================

SELECT * FROM articles
WHERE content MATCH_PHRASE 'full text search';
-- 包含完整短语 "full text search"

-- ============================================================
-- MATCH_PHRASE_PREFIX（前缀短语匹配）
-- ============================================================

SELECT * FROM articles
WHERE content MATCH_PHRASE_PREFIX 'data';
-- 匹配以 "data" 开头的词（database, dataflow 等）

-- ============================================================
-- LIKE 查询（通过倒排索引加速）
-- ============================================================

-- 如果有倒排索引，LIKE 查询也可以被加速
SELECT * FROM articles WHERE title LIKE '%database%';

-- ============================================================
-- 不使用倒排索引的替代方案
-- ============================================================

-- 使用 LIKE（无索引时全表扫描）
SELECT * FROM articles WHERE content LIKE '%database%';

-- 使用正则
SELECT * FROM articles WHERE content REGEXP 'database|performance';

-- ============================================================
-- N-Gram Bloom Filter（模糊匹配加速）
-- ============================================================

CREATE INDEX idx_email_ngram ON users (email) USING NGRAM_BF
    PROPERTIES ("gram_size" = "3");

-- 加速 LIKE 查询
SELECT * FROM users WHERE email LIKE '%alice%';

-- 注意：倒排索引是 Doris 2.0+ 新增功能
-- 注意：支持 english, chinese, unicode 三种分词器
-- 注意：MATCH_ALL / MATCH_ANY / MATCH_PHRASE 是 Doris 特有语法
-- 注意：倒排索引支持等值查询、范围查询和全文检索
