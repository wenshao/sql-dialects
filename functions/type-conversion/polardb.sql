-- PolarDB: Type Conversion
--
-- 参考资料:
--   [1] PolarDB Documentation
--       https://www.alibabacloud.com/help/en/polardb/

-- PolarDB for PostgreSQL
SELECT CAST(42 AS TEXT); SELECT 42::TEXT; SELECT '42'::INTEGER;
SELECT to_char(now(), 'YYYY-MM-DD'); SELECT to_date('2024-01-15', 'YYYY-MM-DD');

-- PolarDB for MySQL
-- SELECT CAST(42 AS CHAR); SELECT CAST('42' AS SIGNED);
-- SELECT CONVERT(42, CHAR); SELECT DATE_FORMAT(NOW(), '%Y-%m-%d');

-- 注意：PolarDB 有 PostgreSQL 和 MySQL 两个版本
