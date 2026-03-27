-- SQLite: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] SQLite Documentation - AUTOINCREMENT
--       https://www.sqlite.org/autoinc.html
--   [2] SQLite Documentation - ROWIDs and the INTEGER PRIMARY KEY
--       https://www.sqlite.org/lang_createtable.html#rowid
--   [3] SQLite Documentation - Built-in Functions
--       https://www.sqlite.org/lang_corefunc.html

-- ============================================
-- SQLite 不支持 CREATE SEQUENCE
-- ============================================

-- ============================================
-- ROWID（SQLite 默认的行标识符）
-- 每张表都有隐式的 ROWID 列（除非 WITHOUT ROWID）
-- ============================================
CREATE TABLE users (
    id       INTEGER PRIMARY KEY,            -- 成为 ROWID 的别名
    username TEXT NOT NULL,
    email    TEXT NOT NULL
);
-- INTEGER PRIMARY KEY 自动自增（使用 ROWID）
-- 插入时 id 为 NULL 则自动生成：MAX(rowid) + 1

INSERT INTO users (id, username, email) VALUES (NULL, 'alice', 'alice@b.com');
-- id 自动分配

-- ============================================
-- AUTOINCREMENT（严格自增，不复用已删除的 ID）
-- ============================================
CREATE TABLE orders (
    id       INTEGER PRIMARY KEY AUTOINCREMENT,  -- 必须是 INTEGER
    amount   REAL
);
-- AUTOINCREMENT 与不带 AUTOINCREMENT 的区别：
-- 1. AUTOINCREMENT：保证 ID 严格递增，不复用，维护 sqlite_sequence 表
-- 2. 不带 AUTOINCREMENT：可能复用已删除的最大 ROWID
-- 3. AUTOINCREMENT 有轻微性能开销

-- sqlite_sequence 表记录每张表的最大序列值
-- SELECT * FROM sqlite_sequence WHERE name = 'orders';

-- 获取最后插入的 ROWID
SELECT last_insert_rowid();

-- ============================================
-- UUID 生成
-- SQLite 没有内置 UUID 函数
-- ============================================
-- 方法 1：使用 hex + randomblob
SELECT lower(hex(randomblob(4))) || '-' ||
       lower(hex(randomblob(2))) || '-4' ||
       substr(lower(hex(randomblob(2))),2) || '-' ||
       substr('89ab', abs(random()) % 4 + 1, 1) ||
       substr(lower(hex(randomblob(2))),2) || '-' ||
       lower(hex(randomblob(6)));

-- 方法 2：使用 uuid() 扩展（需要加载 uuid 扩展）
-- SELECT uuid();

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- 1. INTEGER PRIMARY KEY（推荐）：简单高效，自动自增
-- 2. INTEGER PRIMARY KEY AUTOINCREMENT：严格不复用 ID
-- 3. 手动模拟 UUID：适合跨数据库唯一标识
-- 4. SQLite 是嵌入式数据库，不需要分布式 ID 策略

-- 限制：
-- 不支持 CREATE SEQUENCE
-- 不支持 SERIAL / BIGSERIAL
-- 不支持 GENERATED AS IDENTITY
-- AUTOINCREMENT 只能用于 INTEGER PRIMARY KEY
-- 最大 ROWID 为 9223372036854775807，之后插入会失败
