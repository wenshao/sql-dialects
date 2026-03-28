# TiDB: 类型转换

> 参考资料:
> - [TiDB Documentation - CAST](https://docs.pingcap.com/tidb/stable/cast-functions-and-operators)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

```sql
SELECT CAST(42 AS CHAR); SELECT CAST('42' AS SIGNED); SELECT CAST('42' AS UNSIGNED);
SELECT CAST('3.14' AS DECIMAL(10,2)); SELECT CAST('3.14' AS DOUBLE);
SELECT CAST('2024-01-15' AS DATE); SELECT CAST('2024-01-15 10:30:00' AS DATETIME);

SELECT CONVERT(42, CHAR); SELECT CONVERT('42', SIGNED);
SELECT CONVERT('hello' USING utf8mb4);

SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

```

隐式转换 (MySQL 兼容)
```sql
SELECT '42' + 0; SELECT CONCAT('val: ', 42);

```

更多数值转换
```sql
SELECT CAST('100' AS UNSIGNED);                      -- 100
SELECT CAST(-1 AS UNSIGNED);                         -- 大正数 (溢出)
SELECT CAST(3.7 AS SIGNED);                          -- 4

```

日期/时间格式化
```sql
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT DATE_FORMAT(NOW(), '%d/%m/%Y');
SELECT DATE_FORMAT(NOW(), '%W, %M %d, %Y');
SELECT STR_TO_DATE('15/01/2024', '%d/%m/%Y');
SELECT STR_TO_DATE('Jan 15, 2024', '%b %d, %Y');
SELECT UNIX_TIMESTAMP('2024-01-15');                 -- → Unix
SELECT FROM_UNIXTIME(1705276800);                    -- Unix → DATETIME
SELECT FROM_UNIXTIME(1705276800, '%Y-%m-%d');        -- 自定义格式

```

数值格式化
```sql
SELECT FORMAT(1234567.891, 2);                       -- '1,234,567.89'

```

JSON 转换
```sql
SELECT CAST('{"a":1}' AS JSON);
SELECT JSON_EXTRACT('{"a":1}', '$.a');
SELECT JSON_TYPE('{"a":1}');                         -- 'OBJECT'

```

二进制/十六进制
```sql
SELECT HEX(255);                                     -- 'FF'
SELECT UNHEX('FF');
SELECT CONV('FF', 16, 10);                           -- '255'
SELECT BIN(10);                                      -- '1010'

```

隐式转换 (MySQL 兼容，宽松)
```sql
SELECT '42' + 0;                                     -- 42
SELECT '42abc' + 0;                                  -- 42 (TiDB 警告)
SELECT CONCAT('val: ', 42);                          -- 隐式转字符串
SELECT IF('0', 'true', 'false');                     -- 'false'

```

错误处理（无 TRY_CAST）
严格模式 (sql_mode): CAST 失败报错
非严格模式: 返回零值/NULL + 警告
SET sql_mode = 'STRICT_TRANS_TABLES';

**注意:** TiDB 兼容 MySQL 类型转换
**注意:** 日期格式使用 MySQL 格式码 (%Y, %m, %d, %H, %i, %s)
**注意:** AUTO_INCREMENT 在 TiDB 中不保证连续
**限制:** 无 TRY_CAST, ::, TO_NUMBER, TO_CHAR
