-- SQLite: 数值类型
--
-- 参考资料:
--   [1] SQLite Documentation - Datatypes
--       https://www.sqlite.org/datatype3.html
--   [2] SQLite Documentation - Core Functions
--       https://www.sqlite.org/lang_corefunc.html

-- SQLite 只有 5 种存储类：NULL, INTEGER, REAL, TEXT, BLOB
-- 数值相关的只有 INTEGER 和 REAL

-- INTEGER: 1/2/3/4/6/8 字节（根据值大小自动选择）
-- REAL: 8 字节 IEEE 浮点数

CREATE TABLE examples (
    int_val  INTEGER,                  -- 最大 8 字节有符号整数（同 BIGINT）
    real_val REAL                      -- 8 字节浮点数（同 DOUBLE）
);

-- 类型亲和性映射:
-- INT, INTEGER, TINYINT, SMALLINT, MEDIUMINT, BIGINT → INTEGER
-- REAL, DOUBLE, FLOAT → REAL
-- DECIMAL, NUMERIC → NUMERIC 亲和性（但实际存储为 TEXT/INTEGER/REAL）

-- 注意：没有真正的 DECIMAL 类型！
-- 声明 DECIMAL(10,2) 不会强制精度
CREATE TABLE prices (price DECIMAL(10,2));  -- 合法，但不限制精度

-- 布尔：用 INTEGER 模拟（0 = FALSE, 1 = TRUE）
CREATE TABLE t (active INTEGER DEFAULT 1 CHECK (active IN (0, 1)));

-- 自增
CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT);
-- 必须是 INTEGER（不能是 INT/BIGINT），但不区分大小写

-- 注意：没有 UNSIGNED
-- 注意：整数范围固定为 -2^63 ~ 2^63-1
-- 注意：浮点精度不可控
