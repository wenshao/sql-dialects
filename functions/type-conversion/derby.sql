-- Apache Derby: Type Conversion
--
-- 参考资料:
--   [1] Apache Derby Reference
--       https://db.apache.org/derby/docs/10.16/ref/

SELECT CAST(42 AS VARCHAR(10)); SELECT CAST('42' AS INTEGER);
SELECT CAST('3.14' AS DECIMAL(10,2)); SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('10:30:00' AS TIME);

-- 隐式转换 (Derby 较严格)
SELECT 1 + CAST('2' AS INTEGER);

-- 注意：Derby 只支持标准 CAST
-- 限制：无 CONVERT, TRY_CAST, ::, TO_NUMBER, TO_CHAR
