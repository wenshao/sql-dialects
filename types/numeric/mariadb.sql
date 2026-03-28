-- MariaDB: 数值类型
-- 与 MySQL 完全一致
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - Numeric Data Types
--       https://mariadb.com/kb/en/numeric-data-type-overview/

-- ============================================================
-- 1. 整数类型
-- ============================================================
-- TINYINT:   1 字节, -128~127 / 0~255
-- SMALLINT:  2 字节, -32768~32767
-- MEDIUMINT: 3 字节, -8388608~8388607
-- INT:       4 字节, -2^31~2^31-1
-- BIGINT:    8 字节, -2^63~2^63-1
CREATE TABLE numeric_demo (
    tiny_val   TINYINT UNSIGNED,
    small_val  SMALLINT,
    med_val    MEDIUMINT,
    int_val    INT,
    big_val    BIGINT
);

-- ============================================================
-- 2. 定点数和浮点数
-- ============================================================
-- DECIMAL(p,s): 精确数值, p 总位数, s 小数位数
-- FLOAT:  4 字节, ~7 位有效数字
-- DOUBLE: 8 字节, ~15 位有效数字
CREATE TABLE financial (
    amount    DECIMAL(15,2),     -- 精确到分
    ratio     DOUBLE,            -- 近似值
    tax_rate  FLOAT
);
-- 金融场景务必使用 DECIMAL, 不要用 FLOAT/DOUBLE

-- ============================================================
-- 3. 显示宽度废弃
-- ============================================================
-- INT(11) 的 (11) 是显示宽度, 不影响存储
-- MariaDB 保留此语法但建议避免使用
-- MySQL 8.0.17+: 已废弃显示宽度
-- 对比: PostgreSQL 没有显示宽度概念, INTEGER 就是 4 字节

-- ============================================================
-- 4. 对引擎开发者的启示
-- ============================================================
-- MySQL/MariaDB 的 MEDIUMINT (3 字节) 是独有类型
-- 其他数据库: SMALLINT (2B) → INTEGER (4B), 没有 3 字节类型
-- MEDIUMINT 节省空间但增加了类型系统复杂度
-- 现代引擎趋势: 简化类型系统 (如 DuckDB 只有 TINYINT/SMALLINT/INTEGER/BIGINT)
-- DECIMAL 实现: 需要软件模拟的任意精度算术 (比硬件浮点慢 10-100 倍)
