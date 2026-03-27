-- Apache Doris: Type Conversion
--
-- 参考资料:
--   [1] Apache Doris Documentation - CAST
--       https://doris.apache.org/docs/sql-manual/sql-functions/type-conversion/

SELECT CAST(42 AS VARCHAR); SELECT CAST('42' AS INT);
SELECT CAST('3.14' AS DOUBLE); SELECT CAST('3.14' AS DECIMAL(10,2));
SELECT CAST('2024-01-15' AS DATE); SELECT CAST('2024-01-15 10:30:00' AS DATETIME);

-- 格式化
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

-- 隐式转换 (MySQL 兼容)
SELECT '42' + 0; SELECT CONCAT('val: ', 42);

-- 更多数值转换
SELECT CAST('100' AS BIGINT);                        -- 100
SELECT CAST(3.14 AS INT);                            -- 3 (截断)
SELECT CAST(3.14 AS DECIMAL(10,1));                  -- 3.1
SELECT CAST(3.14 AS FLOAT);                          -- 3.14
SELECT CAST(TRUE AS INT);                            -- 1

-- 日期/时间格式化
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d');               -- '2024-01-15'
SELECT DATE_FORMAT(NOW(), '%d/%m/%Y');               -- '15/01/2024'
SELECT DATE_FORMAT(NOW(), '%W, %M %d, %Y');
SELECT STR_TO_DATE('15/01/2024', '%d/%m/%Y');
SELECT UNIX_TIMESTAMP('2024-01-15');                 -- → Unix
SELECT FROM_UNIXTIME(1705276800);                    -- Unix → DATETIME
SELECT FROM_UNIXTIME(1705276800, '%Y-%m-%d');        -- 自定义格式

-- 数值格式化
SELECT FORMAT(1234567.891, 2);                       -- 保留2位小数

-- JSON 转换 (Doris 1.2+)
SELECT CAST('{"a":1}' AS JSON);
-- SELECT json_extract(json_col, '$.a') FROM t;

-- BITMAP / HLL 类型转换
-- SELECT BITMAP_FROM_STRING('1,2,3');
-- SELECT BITMAP_TO_STRING(bitmap_col) FROM t;

-- 数组转换 (Doris 2.0+)
SELECT CAST(ARRAY(1, 2, 3) AS ARRAY<VARCHAR>);

-- 隐式转换 (MySQL 兼容)
SELECT '42' + 0;                                     -- 42
SELECT '42abc' + 0;                                  -- 42
SELECT CONCAT('val: ', 42);                          -- 隐式转字符串

-- 错误处理（无 TRY_CAST）
-- CAST 转换失败直接报错
-- 建议在导入阶段清洗数据

-- 精度处理
SELECT CAST(1.0/3.0 AS DECIMAL(10,4));              -- 0.3333
SELECT ROUND(3.14159, 2);                            -- 3.14

-- 注意：Doris 兼容 MySQL 类型转换
-- 注意：日期格式使用 MySQL 格式码 (%Y, %m, %d, %H, %i, %s)
-- 注意：BITMAP/HLL 是 Doris 特有的聚合类型
-- 限制：无 TRY_CAST, ::, CONVERT, TO_NUMBER, TO_CHAR
