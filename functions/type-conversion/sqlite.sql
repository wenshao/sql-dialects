-- SQLite: Type Conversion
--
-- 参考资料:
--   [1] SQLite Documentation - CAST
--       https://www.sqlite.org/lang_expr.html#castexpr
--   [2] SQLite Documentation - Type Affinity
--       https://www.sqlite.org/datatype3.html

-- ============================================================
-- CAST
-- ============================================================
SELECT CAST(42 AS TEXT);                        -- '42'
SELECT CAST('42' AS INTEGER);                   -- 42
SELECT CAST('42' AS REAL);                      -- 42.0
SELECT CAST(3.14 AS INTEGER);                   -- 3
SELECT CAST('3.14' AS REAL);                    -- 3.14
SELECT CAST(X'48656C6C6F' AS TEXT);             -- 'Hello' (BLOB → TEXT)

-- ============================================================
-- SQLite 类型亲和性 (Type Affinity)
-- ============================================================
-- SQLite 是动态类型系统，列的 "类型" 实际是亲和性建议
-- 5 种亲和性: TEXT, NUMERIC, INTEGER, REAL, BLOB
--
-- 存储类:
-- NULL    : NULL 值
-- INTEGER : 有符号整数 (1/2/3/4/6/8 字节)
-- REAL    : 8 字节浮点数
-- TEXT    : UTF-8/UTF-16 字符串
-- BLOB    : 二进制数据

-- ============================================================
-- 隐式转换 (SQLite 非常灵活)
-- ============================================================
SELECT '42' + 0;                                -- 42 (TEXT → NUMERIC)
SELECT 42 || '';                                -- '42' (INTEGER → TEXT)
SELECT typeof(42);                              -- 'integer'
SELECT typeof('42');                            -- 'text'
SELECT typeof(42.0);                            -- 'real'
SELECT typeof(NULL);                            -- 'null'
SELECT typeof(X'00');                           -- 'blob'

-- ============================================================
-- 常见转换模式
-- ============================================================
-- 字符串 ↔ 数字
SELECT CAST('123.45' AS REAL);                  -- 123.45
SELECT CAST(123.45 AS TEXT);                    -- '123.45'
SELECT '123.45' + 0;                             -- 123.45 (隐式)
SELECT 42 || '';                                -- '42' (隐式)

-- 日期处理 (SQLite 无专用日期类型)
SELECT date('2024-01-15');                       -- '2024-01-15' (TEXT)
SELECT datetime('2024-01-15 10:30:00');          -- TEXT
SELECT strftime('%Y-%m-%d', 'now');              -- '2024-01-15'
SELECT strftime('%s', 'now');                    -- Unix 时间戳 (TEXT)
SELECT CAST(strftime('%s', 'now') AS INTEGER);  -- Unix 时间戳 (INTEGER)
SELECT datetime(1705312200, 'unixepoch');        -- Unix → 日期字符串

-- 十六进制
SELECT hex('hello');                             -- '68656C6C6F'
SELECT printf('%d', 0xFF);                       -- '255'

-- ============================================================
-- printf 格式化                                       -- 3.8.3+
-- ============================================================
SELECT printf('%.2f', 3.14159);                  -- '3.14'
SELECT printf('%05d', 42);                       -- '00042'
SELECT printf('%x', 255);                        -- 'ff'

-- 版本说明：
--   SQLite 全版本  : CAST, typeof()
--   SQLite 3.8.3+  : printf()
-- 注意：SQLite 是动态类型，CAST 只是建议
-- 注意：无 DATE/DATETIME 类型，日期以 TEXT/INTEGER/REAL 存储
-- 注意：隐式转换非常灵活
-- 限制：无 TRY_CAST
-- 限制：无 CONVERT
-- 限制：无 TO_NUMBER / TO_CHAR / TO_DATE
-- 限制：无 :: 运算符
