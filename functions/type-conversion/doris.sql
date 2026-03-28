-- Apache Doris: 类型转换
--
-- 参考资料:
--   [1] Doris Documentation - CAST
--       https://doris.apache.org/docs/sql-manual/sql-functions/type-conversion/

-- ============================================================
-- 1. CAST (唯一的显式转换方式)
-- ============================================================
SELECT CAST(42 AS VARCHAR), CAST('42' AS INT);
SELECT CAST('3.14' AS DOUBLE), CAST('3.14' AS DECIMAL(10,2));
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('2024-01-15 10:30:00' AS DATETIME);
SELECT CAST(TRUE AS INT);     -- 1
SELECT CAST(3.14 AS INT);     -- 3 (截断)

-- ============================================================
-- 2. 日期格式化
-- ============================================================
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('15/01/2024', '%d/%m/%Y');
SELECT UNIX_TIMESTAMP('2024-01-15');
SELECT FROM_UNIXTIME(1705276800, '%Y-%m-%d');

-- ============================================================
-- 3. 隐式转换 (MySQL 兼容)
-- ============================================================
SELECT '42' + 0;           -- 42
SELECT '42abc' + 0;        -- 42
SELECT CONCAT('val: ', 42); -- 隐式转字符串

-- ============================================================
-- 4. JSON 转换 (1.2+)
-- ============================================================
SELECT CAST('{"a":1}' AS JSON);

-- BITMAP / HLL 转换
-- SELECT BITMAP_FROM_STRING('1,2,3');
-- SELECT BITMAP_TO_STRING(bitmap_col) FROM t;

-- 数组转换 (2.0+)
SELECT CAST(ARRAY(1, 2, 3) AS ARRAY<VARCHAR>);

-- ============================================================
-- 5. 对比其他引擎
-- ============================================================
-- CAST 语法: 所有引擎都支持(SQL 标准)
-- :: 语法:   PostgreSQL/ClickHouse(Doris 不支持)
-- TRY_CAST:  BigQuery/Trino(转换失败返回 NULL，Doris 不支持)
-- CONVERT:   MySQL/SQL Server(Doris 不支持)
-- TO_NUMBER: Oracle(Doris 不支持)
--
-- 对引擎开发者的启示:
--   TRY_CAST 是用户友好的设计——转换失败不报错而是返回 NULL。
--   Doris/StarRocks 缺少此功能，用户需要在 ETL 层预清洗数据。
