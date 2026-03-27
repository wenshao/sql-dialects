-- MariaDB: Type Conversion
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - CAST and CONVERT
--       https://mariadb.com/kb/en/cast/
--   [2] MariaDB Knowledge Base - CONVERT
--       https://mariadb.com/kb/en/convert/

SELECT CAST(42 AS CHAR); SELECT CAST('42' AS SIGNED); SELECT CAST('42' AS UNSIGNED);
SELECT CAST('3.14' AS DECIMAL(10,2)); SELECT CAST('3.14' AS DOUBLE);
SELECT CAST('2024-01-15' AS DATE); SELECT CAST('2024-01-15 10:30:00' AS DATETIME);

-- CONVERT
SELECT CONVERT(42, CHAR); SELECT CONVERT('42', SIGNED);
SELECT CONVERT('hello' USING utf8mb4);          -- 字符集转换

-- 格式化
SELECT FORMAT(1234567.89, 2);                   -- '1,234,567.89'
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('15/01/2024', '%d/%m/%Y');

-- 隐式转换 (与 MySQL 一致，宽松)
SELECT '42' + 0; SELECT CONCAT('val: ', 42);

-- 更多数值转換
SELECT CAST('100' AS UNSIGNED);                      -- 100
SELECT CAST(-1 AS UNSIGNED);                         -- 大正数
SELECT CAST(3.7 AS SIGNED);                          -- 4
SELECT CAST('3.14' AS DOUBLE);                       -- 3.14

-- 日期/时间格式化
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT DATE_FORMAT(NOW(), '%d/%m/%Y');
SELECT DATE_FORMAT(NOW(), '%W, %M %d, %Y');
SELECT DATE_FORMAT(NOW(), '%Y年%m月%d日');
SELECT STR_TO_DATE('15/01/2024', '%d/%m/%Y');
SELECT STR_TO_DATE('Jan 15, 2024', '%b %d, %Y');
SELECT UNIX_TIMESTAMP('2024-01-15');                 -- → Unix
SELECT FROM_UNIXTIME(1705276800);                    -- Unix → DATETIME
SELECT FROM_UNIXTIME(1705276800, '%Y-%m-%d');        -- 自定义格式

-- 数值格式化
SELECT FORMAT(1234567.891, 2);                       -- '1,234,567.89'
SELECT FORMAT(1234567.891, 2, 'de_DE');              -- '1.234.567,89' (德语)

-- JSON 转換 (MariaDB 10.2+)
SELECT CAST('{"a":1}' AS JSON);                      -- 注意: MariaDB JSON 是 LONGTEXT 别名
SELECT JSON_EXTRACT('{"a":1}', '$.a');
SELECT JSON_TYPE('{"a":1}');                         -- 'OBJECT'

-- 二进制/十六进制
SELECT HEX(255);                                     -- 'FF'
SELECT UNHEX('FF');
SELECT CONV('FF', 16, 10);                           -- '255'
SELECT BIN(10);                                      -- '1010'

-- 隐式转换 (宽松)
SELECT '42' + 0;                                     -- 42
SELECT '42abc' + 0;                                  -- 42
SELECT CONCAT('val: ', 42);                          -- 隐式转字符串
SELECT IF('0', 'true', 'false');                     -- 'false'

-- 错误処理（无 TRY_CAST）
-- 严格模式: CAST 失败报错
-- 非严格模式: 返回零值/NULL + 警告

-- 注意：与 MySQL 类型转换高度兼容
-- 注意：日期格式使用 MySQL 格式码 (%Y, %m, %d, %H, %i, %s)
-- 注意：JSON 在 MariaDB 中是 LONGTEXT 的别名（与 MySQL 不同）
-- 限制：无 TRY_CAST, ::, TO_NUMBER, TO_CHAR
