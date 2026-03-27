-- TDSQL: 类型转换函数 (Type Conversion Functions)
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557
--   [3] MySQL 8.0 Reference Manual - Cast Functions and Operators
--       https://dev.mysql.com/doc/refman/8.0/en/cast-functions.html
--
-- 说明: TDSQL 是腾讯云分布式数据库，类型转换与 MySQL 完全兼容。
--       MySQL 的隐式转换规则宽松，需注意避免意外行为。

-- ============================================================
-- 1. CAST: 标准类型转换
-- ============================================================

-- 基本数值转换
SELECT CAST('42' AS SIGNED);                          -- 42（有符号整数）
SELECT CAST('42' AS UNSIGNED);                        -- 42（无符号整数）
SELECT CAST(42 AS CHAR);                              -- '42'（转字符串）
SELECT CAST('3.14' AS DECIMAL(10, 2));                -- 3.14
SELECT CAST('3.14' AS DOUBLE);                        -- 3.14
SELECT CAST(3.14 AS SIGNED);                          -- 3（截断小数部分）
SELECT CAST(3.7 AS SIGNED);                           -- 4（四舍五入）

-- 日期时间转换
SELECT CAST('2024-01-15' AS DATE);                    -- 2024-01-15
SELECT CAST('2024-01-15 10:30:00' AS DATETIME);       -- 2024-01-15 10:30:00
SELECT CAST('10:30:00' AS TIME);                      -- 10:30:00

-- 二进制转换
SELECT CAST('hello' AS BINARY);                       -- 二进制字符串

-- 无符号整数溢出
SELECT CAST(-1 AS UNSIGNED);                          -- 18446744073709551615（溢出为大正数!）

-- ============================================================
-- 2. CONVERT: MySQL 风格类型转换
-- ============================================================

-- 类型转换
SELECT CONVERT('42', SIGNED);                         -- 42
SELECT CONVERT(42, CHAR);                             -- '42'
SELECT CONVERT('3.14', DECIMAL(10, 2));               -- 3.14

-- 字符集转换
SELECT CONVERT('hello' USING utf8mb4);                -- 字符集转换
SELECT CONVERT('你好' USING gbk);                     -- GBK 编码

-- CAST vs CONVERT:
--   CAST: SQL 标准语法，ANSI 兼容
--   CONVERT: MySQL/SQL Server 专有语法，支持字符集转换
--   建议优先使用 CAST

-- ============================================================
-- 3. 日期格式化转换
-- ============================================================

SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');       -- '2024-01-15 10:30:00'
SELECT DATE_FORMAT(NOW(), '%d/%m/%Y');                -- '15/01/2024'
SELECT DATE_FORMAT(NOW(), '%W, %M %d, %Y');           -- 'Monday, January 15, 2024'
SELECT DATE_FORMAT(NOW(), '%Y年%m月%d日');              -- '2024年01月15日'

-- 字符串解析为日期
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');         -- 2024-01-15
SELECT STR_TO_DATE('15/01/2024', '%d/%m/%Y');         -- 2024-01-15
SELECT STR_TO_DATE('Jan 15, 2024', '%b %d, %Y');     -- 2024-01-15

-- 常用格式码:
--   %Y: 4位年份    %m: 2位月份    %d: 2位日期
--   %H: 24小时    %i: 分钟       %s: 秒
--   %W: 星期名    %M: 月名

-- ============================================================
-- 4. 数值格式化
-- ============================================================

SELECT FORMAT(1234567.891, 2);                        -- '1,234,567.89'（千分位）
SELECT FORMAT(1234567.891, 4);                        -- '1,234,567.8910'
SELECT FORMAT(1234567.891, 2, 'de_DE');               -- '1.234.567,89'（德语格式）

-- ============================================================
-- 5. Unix 时间戳转换
-- ============================================================

SELECT UNIX_TIMESTAMP('2024-01-15 10:30:00');         -- → Unix 时间戳（秒）
SELECT UNIX_TIMESTAMP();                              -- 当前 Unix 时间戳
SELECT FROM_UNIXTIME(1705276800);                     -- '2024-01-15 02:00:00'
SELECT FROM_UNIXTIME(1705276800, '%Y-%m-%d');         -- '2024-01-15'

-- ============================================================
-- 6. 进制转换
-- ============================================================

SELECT HEX(255);                                     -- 'FF'（十进制 → 十六进制）
SELECT UNHEX('FF');                                   -- 二进制字符串
SELECT CONV('FF', 16, 10);                           -- '255'（十六进制 → 十进制）
SELECT CONV('1010', 2, 10);                          -- '10'（二进制 → 十进制）
SELECT BIN(10);                                      -- '1010'（十进制 → 二进制）
SELECT OCT(10);                                      -- '12'（十进制 → 八进制）

-- ============================================================
-- 7. 隐式转换规则
-- ============================================================

-- 字符串 → 数值: 取前导数字部分
SELECT '42' + 0;                                     -- 42
SELECT '42abc' + 0;                                  -- 42（截取前导数字）
SELECT 'abc' + 0;                                    -- 0（无法转换返回 0）
SELECT '3.14' + 0;                                   -- 3.14

-- 数值 → 字符串: 自动转换
SELECT CONCAT('val: ', 42);                           -- 'val: 42'
SELECT LENGTH(12345);                                 -- 5（先转字符串再取长度）

-- 布尔上下文中的隐式转换
SELECT IF('0', 'true', 'false');                      -- 'false'（字符串 '0' 是假值!）
SELECT IF(0, 'true', 'false');                        -- 'false'
SELECT IF('', 'true', 'false');                       -- 'false'（空字符串是假值）
SELECT IF(NULL, 'true', 'false');                     -- 'false'（NULL 是假值）

-- 比较中的隐式转换（可能导致索引失效!）
-- WHERE string_col = 42  → string_col 转为数值（索引失效!）
-- WHERE string_col = '42' → 字符串比较（可使用索引）

-- ============================================================
-- 8. JSON 转换 (MySQL 5.7+)
-- ============================================================

SELECT CAST('{"a":1}' AS JSON);                       -- JSON 类型
SELECT JSON_EXTRACT('{"a":1}', '$.a');                -- 1
SELECT JSON_UNQUOTE('"hello"');                       -- 'hello'（去 JSON 引号）

-- ============================================================
-- 9. 错误处理
-- ============================================================

-- MySQL 没有 TRY_CAST / TRY_CONVERT
-- 转换失败行为取决于 SQL MODE:
--   严格模式 (STRICT_TRANS_TABLES): 报错
--   非严格模式: 返回零值/NULL + 警告

-- 安全转换模式:
SELECT CASE
    WHEN col REGEXP '^[0-9]+$' THEN CAST(col AS SIGNED)
    ELSE NULL
END AS safe_int FROM raw_data;

-- ============================================================
-- 10. 分布式环境注意事项
-- ============================================================

-- 1. 各分片 MySQL 版本和 SQL MODE 必须一致（影响转换行为）
-- 2. 字符集在各分片应统一（建议 utf8mb4）
-- 3. 隐式转换可能导致索引失效（跨分片查询性能问题）
-- 4. CAST/CONVERT 不涉及跨分片操作，在各分片独立执行

-- ============================================================
-- 11. 版本兼容性
-- ============================================================
-- MySQL 5.7 / TDSQL: CAST/CONVERT + JSON 类型
-- MySQL 8.0 / TDSQL: 支持 CAST(... AS JSON) 的增强
-- 不支持: :: 操作符、TRY_CAST、TO_NUMBER、TO_CHAR（PostgreSQL 专有）
-- 限制: 仅支持 MySQL 标准转换类型（SIGNED/UNSIGNED/CHAR/DATE/DATETIME/TIME/DECIMAL/BINARY/JSON）
