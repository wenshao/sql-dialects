-- H2: 索引
--
-- 参考资料:
--   [1] H2 SQL Reference - Commands
--       https://h2database.com/html/commands.html
--   [2] H2 - Data Types
--       https://h2database.com/html/datatypes.html
--   [3] H2 - Functions
--       https://h2database.com/html/functions.html

-- B-tree 索引（默认）
CREATE INDEX idx_username ON users (username);

-- 唯一索引
CREATE UNIQUE INDEX idx_email ON users (email);

-- 复合索引
CREATE INDEX idx_city_age ON users (city, age);

-- IF NOT EXISTS
CREATE INDEX IF NOT EXISTS idx_username ON users (username);

-- Hash 索引
CREATE HASH INDEX idx_user_hash ON users (username);

-- 唯一 Hash 索引
CREATE UNIQUE HASH INDEX idx_email_hash ON users (email);

-- ============================================================
-- 主键和约束索引（自动创建）
-- ============================================================

-- PRIMARY KEY 自动创建索引
CREATE TABLE users (
    id INT PRIMARY KEY,               -- 自动创建唯一索引
    username VARCHAR(64) UNIQUE,      -- 自动创建唯一索引
    email VARCHAR(128)
);

-- ============================================================
-- 全文索引（Lucene 集成）
-- ============================================================

-- 创建全文索引
CREATE ALIAS IF NOT EXISTS FT_INIT FOR 'org.h2.fulltext.FullText.init';
CALL FT_INIT();
CALL FT_CREATE_INDEX('PUBLIC', 'ARTICLES', 'TITLE,CONTENT');

-- 全文搜索
SELECT * FROM FT_SEARCH('database performance', 10, 0);

-- 也支持 Lucene 全文索引
CREATE ALIAS IF NOT EXISTS FTL_INIT FOR 'org.h2.fulltext.FullTextLucene.init';
CALL FTL_INIT();
CALL FTL_CREATE_INDEX('PUBLIC', 'ARTICLES', 'TITLE,CONTENT');

-- ============================================================
-- 空间索引（H2 内置）
-- ============================================================

CREATE SPATIAL INDEX idx_location ON places (geom);

-- ============================================================
-- 索引管理
-- ============================================================

-- 删除索引
DROP INDEX idx_username;
DROP INDEX IF EXISTS idx_username;

-- 重建索引（无直接命令，需 DROP + CREATE）

-- 查看索引
SELECT * FROM INFORMATION_SCHEMA.INDEXES WHERE TABLE_NAME = 'USERS';

-- 注意：H2 支持 B-tree 和 Hash 两种索引类型
-- 注意：支持全文索引（内置和 Lucene 两种方式）
-- 注意：支持空间索引（SPATIAL INDEX）
-- 注意：索引名在 schema 内全局唯一
-- 注意：内存表的索引也在内存中
