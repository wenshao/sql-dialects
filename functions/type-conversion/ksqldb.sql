-- ksqlDB: Type Conversion
--
-- 参考资料:
--   [1] ksqlDB Function Reference
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/scalar-functions/

SELECT CAST(42 AS VARCHAR); SELECT CAST('42' AS INTEGER);
SELECT CAST('3.14' AS DOUBLE); SELECT CAST('42' AS BIGINT);
-- ksqlDB CAST 支持: VARCHAR, INTEGER, BIGINT, DOUBLE, BOOLEAN

-- 格式化
SELECT FORMAT_DATE(ROWTIME, 'yyyy-MM-dd');
SELECT FORMAT_TIMESTAMP(ROWTIME, 'yyyy-MM-dd HH:mm:ss');
SELECT PARSE_DATE('2024-01-15', 'yyyy-MM-dd');
SELECT PARSE_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');

-- 注意：ksqlDB CAST 类型有限
-- 注意：日期使用 Java DateTimeFormatter 模式
-- 限制：无 TRY_CAST, ::, CONVERT, TO_NUMBER
