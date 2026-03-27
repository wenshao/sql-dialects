-- SQLite: 字符串类型
--
-- 参考资料:
--   [1] SQLite Documentation - Datatypes
--       https://www.sqlite.org/datatype3.html
--   [2] SQLite Documentation - String Functions
--       https://www.sqlite.org/lang_corefunc.html

-- ============================================================
-- 1. SQLite 的字符串: 只有 TEXT
-- ============================================================

-- SQLite 只有 TEXT 存储类（和 BLOB），没有 VARCHAR/CHAR/CLOB 区分。
-- 声明 VARCHAR(255) 或 CHAR(10) 都合法，但:
--   (a) 长度限制不生效（VARCHAR(10) 可以存 1000 个字符）
--   (b) 没有填充行为（CHAR(10) 不会用空格填充到 10 字符）
--   (c) 所有字符串类型名都映射到 TEXT 亲和性

CREATE TABLE example (
    name VARCHAR(100),   -- 合法但不限制长度
    code CHAR(5),        -- 合法但不填充空格
    bio  TEXT,           -- 最推荐的写法
    data CLOB            -- 合法，映射到 TEXT
);

-- 默认编码: UTF-8（内部同时支持 UTF-16，通过 API 选择）
-- 最大长度: 受 SQLITE_MAX_LENGTH 限制（默认 1,000,000,000 字节）

-- ============================================================
-- 2. 动态类型对字符串的影响
-- ============================================================

-- 任何列都可以存储字符串，即使声明为 INTEGER:
-- INSERT INTO nums (int_col) VALUES ('hello');  -- 成功!
-- SELECT typeof(int_col) FROM nums;             -- 'text'
--
-- STRICT 表（3.37.0+）会拒绝类型不匹配的值

-- 字符串比较:
-- SQLite 默认使用 BINARY 排序（二进制比较，区分大小写）
-- 可以声明 COLLATE NOCASE:
CREATE TABLE users (
    username TEXT COLLATE NOCASE    -- 大小写不敏感比较
);
-- 内置排序规则: BINARY（默认）, NOCASE, RTRIM
-- 不支持 ICU 排序规则（除非加载 ICU 扩展）

-- ============================================================
-- 3. BLOB 类型（二进制数据）
-- ============================================================

-- BLOB 是原始字节序列，不做任何编码转换
CREATE TABLE files (
    id   INTEGER PRIMARY KEY,
    name TEXT,
    data BLOB
);
-- 插入: INSERT INTO files VALUES (1, 'test', x'DEADBEEF');
-- 或通过 API 的 sqlite3_bind_blob()

-- TEXT vs BLOB:
--   TEXT: 存储时保证 UTF-8 编码，比较使用排序规则
--   BLOB: 原始字节，比较使用 memcmp（二进制比较）

-- ============================================================
-- 4. 对比与引擎开发者启示
-- ============================================================
-- SQLite 字符串的设计:
--   (1) 只有 TEXT → 极简，无 VARCHAR 长度限制
--   (2) 动态类型 → 任何列可存字符串
--   (3) 默认 UTF-8 → 现代编码选择
--   (4) 有限的排序规则 → BINARY / NOCASE / RTRIM
--
-- 对比:
--   MySQL:      VARCHAR(n)/CHAR(n)/TEXT/MEDIUMTEXT/LONGTEXT + utf8mb4
--   PostgreSQL: VARCHAR(n)/TEXT（推荐 TEXT）+ ICU 排序规则
--   ClickHouse: String（无长度限制）+ FixedString(N)
--   BigQuery:   STRING（无长度限制）
--
-- 对引擎开发者的启示:
--   现代引擎趋向于统一的 TEXT/STRING 类型（无长度限制）。
--   VARCHAR(n) 的 n 在大多数场景下只是文档化意图，不是真正的约束。
--   SQLite 和 BigQuery/ClickHouse 证明了"无长度限制的字符串类型"是可行的。
