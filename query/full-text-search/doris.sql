-- Apache Doris: 全文搜索
--
-- 参考资料:
--   [1] Doris Documentation - Inverted Index
--       https://doris.apache.org/docs/table-design/index/

-- ============================================================
-- 1. 倒排索引全文搜索 (2.0+，Doris 核心差异化)
-- ============================================================
-- Doris 2.0 引入基于 CLucene 的倒排索引，支持真正的全文检索。
-- 这是 Doris 相比 StarRocks 的差异化功能之一(StarRocks 3.1 才跟进)。

-- 建表时创建倒排索引
CREATE TABLE articles (
    id      BIGINT NOT NULL,
    title   VARCHAR(256),
    content STRING,
    INDEX idx_title (title) USING INVERTED,
    INDEX idx_content (content) USING INVERTED PROPERTIES ("parser" = "english")
) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 16;

-- 中文分词
CREATE TABLE articles_cn (
    id BIGINT NOT NULL, title VARCHAR(256), content STRING,
    INDEX idx_title (title) USING INVERTED PROPERTIES ("parser" = "chinese"),
    INDEX idx_content (content) USING INVERTED PROPERTIES ("parser" = "chinese")
) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 16;

-- 动态添加/删除
CREATE INDEX idx_bio ON users (bio) USING INVERTED;
CREATE INDEX idx_bio_cn ON users (bio) USING INVERTED PROPERTIES ("parser" = "chinese");
DROP INDEX idx_bio ON users;

-- ============================================================
-- 2. 全文检索语法 (Doris 特有)
-- ============================================================
-- MATCH_ALL: 全部匹配(AND)
SELECT * FROM articles WHERE content MATCH_ALL 'database performance';

-- MATCH_ANY: 任意匹配(OR)
SELECT * FROM articles WHERE content MATCH_ANY 'database performance';

-- MATCH_PHRASE: 短语匹配
SELECT * FROM articles WHERE content MATCH_PHRASE 'full text search';

-- MATCH_PHRASE_PREFIX: 前缀匹配
SELECT * FROM articles WHERE content MATCH_PHRASE_PREFIX 'data';

-- ============================================================
-- 3. N-Gram Bloom Filter (LIKE 加速)
-- ============================================================
CREATE INDEX idx_email_ngram ON users (email) USING NGRAM_BF
    PROPERTIES ("gram_size" = "3");
SELECT * FROM users WHERE email LIKE '%alice%';  -- 被 NGRAM_BF 加速

-- ============================================================
-- 4. 对比其他引擎
-- ============================================================
-- Doris 2.0+:      INVERTED INDEX + MATCH_ALL/ANY/PHRASE(CLucene)
-- StarRocks 3.1+:  GIN Index(追赶中)
-- ClickHouse:       tokenbf_v1(Bloom Filter 近似，非真正倒排)
-- MySQL:            FULLTEXT INDEX + MATCH AGAINST
-- Elasticsearch:    原生倒排索引(最完整)
-- PostgreSQL:       GIN + tsvector/tsquery
