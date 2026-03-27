-- TDSQL: Type Conversion
--
-- 参考资料:
--   [1] TDSQL Documentation
--       https://cloud.tencent.com/document/product/557

-- MySQL 兼容
SELECT CAST(42 AS CHAR); SELECT CAST('42' AS SIGNED);
SELECT CAST('3.14' AS DECIMAL(10,2)); SELECT CAST('2024-01-15' AS DATE);
SELECT CONVERT(42, CHAR); SELECT CONVERT('42', SIGNED);
SELECT CONVERT('hello' USING utf8mb4);
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d'); SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

-- 更多数值转换
SELECT CAST('100' AS UNSIGNED);                      -- 100 (无符号)
SELECT CAST(-1 AS UNSIGNED);                         -- 大正数 (溢出)
SELECT CAST(3.14 AS SIGNED);                         -- 3 (截断)
SELECT CAST(3.7 AS SIGNED);                          -- 4 (四舍五入)
SELECT CAST('3.14' AS DOUBLE);                       -- 3.14

-- 日期/时间格式化
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');      -- '2024-01-15 10:30:00'
SELECT DATE_FORMAT(NOW(), '%d/%m/%Y');               -- '15/01/2024'
SELECT DATE_FORMAT(NOW(), '%W, %M %d, %Y');          -- 'Monday, January 15, 2024'
SELECT DATE_FORMAT(NOW(), '%Y年%m月%d日');
SELECT STR_TO_DATE('15/01/2024', '%d/%m/%Y');
SELECT STR_TO_DATE('Jan 15, 2024', '%b %d, %Y');
SELECT UNIX_TIMESTAMP('2024-01-15');                 -- → Unix 时间戳
SELECT FROM_UNIXTIME(1705276800);                    -- Unix → DATETIME
SELECT FROM_UNIXTIME(1705276800, '%Y-%m-%d');        -- 自定义格式

-- 数值格式化
SELECT FORMAT(1234567.891, 2);                       -- '1,234,567.89'

-- 隐式转换规则 (MySQL 兼容，宽松)
SELECT '42' + 0;                                     -- 42 (字符串→数值)
SELECT '42abc' + 0;                                  -- 42 (截取前导数字)
SELECT 'abc' + 0;                                    -- 0 (无法转换返回 0)
SELECT CONCAT('val: ', 42);                          -- 数值隐式转字符串
SELECT IF('0', 'true', 'false');                     -- 'false' (字符串'0'是假值)
SELECT IF(0, 'true', 'false');                       -- 'false'

-- 二进制/十六进制
SELECT HEX(255);                                     -- 'FF'
SELECT UNHEX('FF');                                  -- 二进制
SELECT CONV('FF', 16, 10);                           -- '255'
SELECT BIN(10);                                      -- '1010'

-- JSON 转换 (MySQL 5.7+)
SELECT CAST('{"a":1}' AS JSON);
SELECT JSON_EXTRACT('{"a":1}', '$.a');

-- 错误处理（无 TRY_CAST，失败返回警告 + 默认值）
-- CAST 转换失败在严格模式下报错，在非严格模式下返回零值/NULL

-- 注意：TDSQL 兼容 MySQL 类型转换语法
-- 注意：隐式转换较宽松，可能产生意外结果
-- 注意：日期格式使用 MySQL 格式码 (%Y, %m, %d, %H, %i, %s)
-- 限制：无 TRY_CAST, ::, TO_NUMBER, TO_CHAR
