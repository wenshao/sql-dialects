-- StarRocks: Type Conversion
--
-- 参考资料:
--   [1] StarRocks Documentation - CAST
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/cast/

SELECT CAST(42 AS VARCHAR); SELECT CAST('42' AS INT);
SELECT CAST('3.14' AS DOUBLE); SELECT CAST('3.14' AS DECIMAL(10,2));
SELECT CAST('2024-01-15' AS DATE); SELECT CAST('2024-01-15 10:30:00' AS DATETIME);

SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

-- 隐式转换 (MySQL 兼容)
SELECT '42' + 0;

-- 更多数值转换
SELECT CAST('100' AS BIGINT);                        -- 100
SELECT CAST(3.14 AS INT);                            -- 3 (截断)
SELECT CAST(3.14 AS DECIMAL(10,1));                  -- 3.1
SELECT CAST(TRUE AS INT);                            -- 1
SELECT CAST(42 AS BOOLEAN);                          -- true

-- 日期/时间格式化
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d');               -- '2024-01-15'
SELECT DATE_FORMAT(NOW(), '%d/%m/%Y');               -- '15/01/2024'
SELECT DATE_FORMAT(NOW(), '%W, %M %d, %Y');          -- 'Monday, January 15, 2024'
SELECT STR_TO_DATE('15/01/2024', '%d/%m/%Y');
SELECT UNIX_TIMESTAMP('2024-01-15');                 -- → Unix
SELECT FROM_UNIXTIME(1705276800);                    -- Unix → DATETIME
SELECT FROM_UNIXTIME(1705276800, '%Y-%m-%d');        -- 自定义格式

-- 数值格式化
SELECT FORMAT(1234567.891, 2);                       -- 保留2位小数

-- JSON 转换 (StarRocks 2.5+)
SELECT CAST('{"a":1}' AS JSON);
SELECT PARSE_JSON('{"a":1}');
-- SELECT json_query(j, '$.a') FROM ...;

-- BITMAP / HLL 类型转换
-- SELECT BITMAP_FROM_STRING('1,2,3');
-- SELECT BITMAP_TO_STRING(bitmap_col) FROM t;

-- 隐式转换 (MySQL 兼容)
SELECT '42' + 0;                                     -- 42
SELECT '42abc' + 0;                                  -- 42
SELECT CONCAT('val: ', 42);                          -- 隐式转字符串

-- 数组转换 (StarRocks 2.5+)
SELECT [1, 2, 3];                                    -- ARRAY<INT>
SELECT CAST([1, 2, 3] AS ARRAY<VARCHAR>);

-- 错误处理（无 TRY_CAST）
-- CAST 转换失败直接报错
-- 建议在 ETL 阶段清洗数据确保类型正确

-- 注意：StarRocks 兼容 MySQL 类型转换
-- 注意：日期格式使用 MySQL 格式码 (%Y, %m, %d, %H, %i, %s)
-- 注意：支持 ARRAY, JSON, BITMAP, HLL 等高级类型
-- 限制：无 TRY_CAST, ::, CONVERT, TO_NUMBER, TO_CHAR
