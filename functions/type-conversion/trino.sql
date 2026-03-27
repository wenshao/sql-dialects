-- Trino: Type Conversion
--
-- 参考资料:
--   [1] Trino Documentation - Conversion Functions
--       https://trino.io/docs/current/functions/conversion.html

SELECT CAST(42 AS VARCHAR); SELECT CAST('42' AS INTEGER); SELECT CAST('42' AS BIGINT);
SELECT CAST('3.14' AS DOUBLE); SELECT CAST('3.14' AS DECIMAL(10,2));
SELECT CAST('2024-01-15' AS DATE); SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);
SELECT CAST(TRUE AS VARCHAR);

-- TRY_CAST (安全转换)
SELECT TRY_CAST('abc' AS INTEGER);              -- NULL
SELECT TRY_CAST('42' AS INTEGER);               -- 42
SELECT TRY_CAST('bad-date' AS DATE);            -- NULL

-- TRY (将错误转为 NULL)
SELECT TRY(CAST('abc' AS INTEGER));             -- NULL

-- 格式化
SELECT FORMAT('%d', 42);                         -- '42'
SELECT FORMAT_DATETIME(CURRENT_TIMESTAMP, 'yyyy-MM-dd HH:mm:ss');
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, '%Y-%m-%d %H:%i:%s');
SELECT DATE_PARSE('2024-01-15', '%Y-%m-%d');
SELECT FROM_UNIXTIME(1705276800);
SELECT TO_UNIXTIME(TIMESTAMP '2024-01-15 00:00:00');

-- 其他转换
SELECT FROM_BASE('FF', 16);                     -- 255
SELECT TO_BASE(255, 16);                         -- 'ff'
SELECT FROM_HEX('48656C6C6F');                  -- 'Hello' (bytes)
SELECT TO_HEX(CAST('Hello' AS VARBINARY));

-- 注意：Trino 支持 CAST 和 TRY_CAST
-- 注意：TRY() 函数可包裹任何表达式
-- 注意：丰富的格式化和解析函数
-- 限制：无 ::, CONVERT, TO_NUMBER, TO_CHAR
