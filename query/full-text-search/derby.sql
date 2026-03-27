-- Derby: 全文搜索
--
-- 参考资料:
--   [1] Derby SQL Reference
--       https://db.apache.org/derby/docs/10.16/ref/
--   [2] Derby Developer Guide
--       https://db.apache.org/derby/docs/10.16/devguide/

-- Derby 不支持内置全文搜索
-- 使用字符串函数和外部工具实现

-- ============================================================
-- LIKE 模糊搜索
-- ============================================================

-- 基本 LIKE
SELECT * FROM articles WHERE content LIKE '%database%';

-- 大小写不敏感（使用 UPPER/LOWER）
SELECT * FROM articles WHERE LOWER(content) LIKE '%database%';

-- 前缀搜索
SELECT * FROM articles WHERE title LIKE 'Data%';

-- 通配符
SELECT * FROM articles WHERE title LIKE '_atabase%';

-- 多条件
SELECT * FROM articles
WHERE LOWER(content) LIKE '%database%'
   OR LOWER(content) LIKE '%performance%';

-- ============================================================
-- 字符串函数辅助搜索
-- ============================================================

-- LOCATE（查找子字符串位置，>0 表示包含）
SELECT * FROM articles WHERE LOCATE('database', LOWER(content)) > 0;

-- 多关键词搜索
SELECT * FROM articles
WHERE LOCATE('database', LOWER(content)) > 0
  AND LOCATE('performance', LOWER(content)) > 0;

-- 简单相关度排序
SELECT title,
    (LENGTH(content) - LENGTH(REPLACE(LOWER(content), 'database', ''))) / LENGTH('database') AS keyword_count
FROM articles
WHERE LOCATE('database', LOWER(content)) > 0
ORDER BY keyword_count DESC;

-- ============================================================
-- 使用 Java 存储过程实现全文搜索
-- ============================================================

-- 创建 Java 方法进行全文搜索
-- public class FullTextSearch {
--     public static boolean contains(String text, String keyword) {
--         return text != null && text.toLowerCase().contains(keyword.toLowerCase());
--     }
-- }

-- 注册为 Derby 函数
-- CREATE FUNCTION FT_CONTAINS(text VARCHAR(32672), keyword VARCHAR(256))
-- RETURNS BOOLEAN
-- LANGUAGE JAVA PARAMETER STYLE JAVA
-- NO SQL
-- EXTERNAL NAME 'FullTextSearch.contains';

-- 使用自定义函数
-- SELECT * FROM articles WHERE FT_CONTAINS(content, 'database');

-- ============================================================
-- 替代方案
-- ============================================================

-- 方案 1：使用 Apache Lucene 在应用层实现
-- 方案 2：将数据同步到 Elasticsearch
-- 方案 3：使用 Derby 的 Java 存储过程封装 Lucene

-- 注意：Derby 不支持内置全文搜索
-- 注意：仅支持 LIKE 和字符串函数
-- 注意：不支持正则表达式（需要 Java 函数）
-- 注意：可通过 Java 存储过程集成 Lucene
-- 注意：大规模全文搜索建议使用专用搜索引擎
