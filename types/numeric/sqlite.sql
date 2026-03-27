-- SQLite: 数值类型
--
-- 参考资料:
--   [1] SQLite Documentation - Datatypes
--       https://www.sqlite.org/datatype3.html
--   [2] SQLite Documentation - STRICT Tables
--       https://www.sqlite.org/stricttables.html

-- ============================================================
-- 1. SQLite 的数值类型: 只有 INTEGER 和 REAL
-- ============================================================

-- SQLite 只有 5 种存储类: NULL, INTEGER, REAL, TEXT, BLOB
-- 数值相关的只有两种:
--   INTEGER: 1/2/3/4/6/8 字节有符号整数（根据值大小自动选择存储宽度）
--   REAL: 8 字节 IEEE 754 浮点数（等同于 DOUBLE）

CREATE TABLE examples (
    int_val  INTEGER,   -- 范围: -2^63 ~ 2^63-1（与 BIGINT 相同）
    real_val REAL        -- 8 字节浮点数（与 DOUBLE 相同）
);

-- 1.1 类型亲和性映射（声明的类型名 → 实际存储类）
-- 所有 INT 类名: INT, INTEGER, TINYINT, SMALLINT, MEDIUMINT, BIGINT
--   → INTEGER 亲和性
-- 所有浮点类名: REAL, DOUBLE, FLOAT
--   → REAL 亲和性
-- DECIMAL, NUMERIC: → NUMERIC 亲和性（但不保证精度!）

-- 1.2 没有真正的 DECIMAL 类型!
-- 声明 DECIMAL(10,2) 在语法上合法，但 SQLite 不强制精度:
CREATE TABLE prices (price DECIMAL(10,2));
-- INSERT INTO prices VALUES (3.14159265358979);  -- 成功! 精度不受限
-- 实际存储为 REAL（浮点数），有精度丢失风险
--
-- 这是 SQLite 最大的数值类型陷阱。
-- 对比: MySQL 的 DECIMAL(10,2) 严格保证 2 位小数精度

-- 1.3 解决方案: 整数存储分（cents）
-- 金融场景推荐用整数存储最小单位:
CREATE TABLE invoices (amount_cents INTEGER);  -- 9999 = $99.99
-- 应用层转换: amount_dollars = amount_cents / 100.0

-- ============================================================
-- 2. 动态类型对数值的影响（对引擎开发者）
-- ============================================================

-- SQLite 的动态类型意味着任何列可以存储任何类型:
-- INSERT INTO examples (int_val) VALUES ('not a number');  -- 成功!
-- INSERT INTO examples (int_val) VALUES (3.14);            -- 成功!
-- INSERT INTO examples (int_val) VALUES (x'DEADBEEF');     -- 成功!
--
-- TYPEOF() 检查实际存储类型:
SELECT typeof(42), typeof(3.14), typeof('hello'), typeof(NULL), typeof(x'AB');
-- → 'integer', 'real', 'text', 'null', 'blob'

-- STRICT 表（3.37.0+）强制类型检查:
CREATE TABLE strict_nums (
    id INTEGER PRIMARY KEY,
    count INTEGER,
    ratio REAL
) STRICT;
-- INSERT INTO strict_nums (count) VALUES ('text');  -- 报错!

-- ============================================================
-- 3. 布尔: 用 INTEGER 模拟
-- ============================================================

-- SQLite 没有 BOOLEAN 类型。用 INTEGER 0/1 模拟:
CREATE TABLE features (
    active INTEGER DEFAULT 1 CHECK (active IN (0, 1))
);
-- 对比: MySQL 的 BOOLEAN 也是 TINYINT(1) 的别名

-- ============================================================
-- 4. 整数自适应存储宽度
-- ============================================================

-- SQLite 的 INTEGER 根据值大小自动选择存储宽度:
--   值 0 → 0 字节（存储在 record header 中）
--   值 1~127 → 1 字节
--   值 128~32767 → 2 字节
--   值到 2^31-1 → 4 字节
--   值到 2^47-1 → 6 字节
--   值到 2^63-1 → 8 字节
--
-- 这是存储效率的优化: 小值不浪费大空间。
-- 对比: MySQL INT 总是 4 字节，BIGINT 总是 8 字节。

-- 没有 UNSIGNED: 范围固定为有符号 64 位整数
-- 没有 TINYINT/SMALLINT 的存储限制: 所有整数类型等价

-- ============================================================
-- 5. 对比与引擎开发者启示
-- ============================================================
-- SQLite 数值类型的设计:
--   (1) 只有 INTEGER 和 REAL → 极简但缺少 DECIMAL
--   (2) 自适应存储宽度 → 空间高效
--   (3) 动态类型 → 类型声明只是建议
--   (4) 无 UNSIGNED → 简化实现
--
-- 对引擎开发者的启示:
--   自适应存储宽度是优秀的设计（节省空间，对用户透明）。
--   但缺少 DECIMAL 类型是严重缺陷（金融场景不可用）。
--   如果设计嵌入式数据库，应该至少提供: INTEGER + REAL + DECIMAL。
