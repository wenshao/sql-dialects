# MySQL: 类型转换

> 参考资料:
> - [MySQL 8.0 Reference Manual - CAST and CONVERT](https://dev.mysql.com/doc/refman/8.0/en/cast-functions.html)
> - [MySQL 8.0 Reference Manual - Type Conversion](https://dev.mysql.com/doc/refman/8.0/en/type-conversion.html)

## CAST

```sql
SELECT CAST(42 AS CHAR);                        -- '42'
SELECT CAST('42' AS SIGNED);                    -- 42
SELECT CAST('42' AS UNSIGNED);                  -- 42
SELECT CAST('42' AS SIGNED INTEGER);            -- 42
SELECT CAST(3.14 AS SIGNED);                    -- 3
SELECT CAST('3.14' AS DECIMAL(10,2));           -- 3.14
SELECT CAST('3.14' AS DOUBLE);                  -- 3.14        -- 8.0.17+
SELECT CAST('3.14' AS FLOAT);                   -- 3.14        -- 8.0.17+
SELECT CAST('2024-01-15' AS DATE);              -- 2024-01-15
SELECT CAST('2024-01-15 10:30:00' AS DATETIME); -- DATETIME
SELECT CAST('10:30:00' AS TIME);                -- TIME
SELECT CAST(42 AS JSON);                        -- 42 (JSON)
SELECT CAST('2024' AS YEAR);                    -- 2024        -- 8.0.17+
```

## CONVERT (MySQL 语法: CONVERT(expr, type) 或 CONVERT(expr USING charset))

```sql
SELECT CONVERT(42, CHAR);                       -- '42'
SELECT CONVERT('42', SIGNED);                   -- 42
SELECT CONVERT('3.14', DECIMAL(10,2));          -- 3.14

-- 字符集转换
SELECT CONVERT('hello' USING utf8mb4);
SELECT CONVERT('hello' USING latin1);
```

## 隐式转换规则 (MySQL 非常宽松)

MySQL 隐式转换非常积极：
```sql
SELECT '42' + 0;                                -- 42 (字符串自动转数字)
SELECT '42abc' + 0;                             -- 42 (截取前面的数字部分！)
SELECT 'abc' + 0;                               -- 0  (无法转换返回 0)
SELECT 42 = '42';                               -- 1  (TRUE，自动转换比较)
SELECT CONCAT('value: ', 42);                   -- 'value: 42' (自动转字符串)
```

## 格式化函数

FORMAT: 数字格式化
```sql
SELECT FORMAT(1234567.89, 2);                   -- '1,234,567.89'
SELECT FORMAT(1234567.89, 2, 'de_DE');          -- '1.234.567,89' (德语格式)

-- DATE_FORMAT: 日期格式化
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s'); -- '2024-01-15 10:30:00'
SELECT DATE_FORMAT(NOW(), '%W, %M %d, %Y');     -- 'Monday, January 15, 2024'

-- STR_TO_DATE: 字符串 → 日期
SELECT STR_TO_DATE('15/01/2024', '%d/%m/%Y');   -- 2024-01-15
SELECT STR_TO_DATE('Jan 15, 2024', '%b %d, %Y'); -- 2024-01-15
```

## 常见转换模式

字符串 ↔ 数字
```sql
SELECT CAST('123.45' AS DECIMAL(10,2));          -- 123.45
SELECT CAST(123.45 AS CHAR);                    -- '123.45'
SELECT '123.45' + 0;                             -- 123.45 (隐式转换)
SELECT CONCAT('', 42);                           -- '42'

-- 字符串 ↔ 日期
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST(CURDATE() AS CHAR);
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d');
```

数字 ↔ 布尔 (MySQL 中 BOOLEAN = TINYINT)
```sql
SELECT CAST(0 AS SIGNED);                       -- 0 (FALSE)
SELECT CAST(1 AS SIGNED);                       -- 1 (TRUE)

-- HEX / UNHEX
SELECT HEX('hello');                             -- '68656C6C6F'
SELECT UNHEX('68656C6C6F');                      -- 'hello'

-- BINARY 转换
SELECT CAST('hello' AS BINARY);
SELECT BINARY 'hello';                           -- BINARY 字符串
```

## 二进制/位转换

```sql
SELECT BIN(255);                                 -- '11111111'
SELECT OCT(255);                                 -- '377'
SELECT HEX(255);                                 -- 'FF'
SELECT CONV('FF', 16, 10);                       -- '255'

-- 版本说明：
--   MySQL 5.x+    : CAST, CONVERT
--   MySQL 8.0.17+ : CAST AS DOUBLE/FLOAT/YEAR
-- 注意：MySQL CONVERT 有两种形式：类型转换和字符集转换
-- 注意：MySQL 隐式转换非常宽松（'42abc'+0=42），可能导致意外结果
-- 注意：CAST 目标类型有限：SIGNED, UNSIGNED, CHAR, DATE, DATETIME, DECIMAL, JSON 等
-- 注意：FORMAT 是格式化函数而非类型转换
-- 限制：无 TRY_CAST（转换失败会警告或返回 0/NULL）
-- 限制：无 :: 运算符
-- 限制：无 TO_NUMBER / TO_CHAR / TO_DATE
```
