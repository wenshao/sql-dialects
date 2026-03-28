# OceanBase: 类型转换

> 参考资料:
> - [OceanBase Documentation](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

```sql
SELECT CAST(42 AS CHAR); SELECT CAST('42' AS SIGNED); SELECT CAST('3.14' AS DECIMAL(10,2));
SELECT CONVERT(42, CHAR); SELECT CONVERT('42', SIGNED);
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d'); SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');

```

Oracle 模式
SELECT CAST(42 AS VARCHAR2(10)) FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD') FROM DUAL;
SELECT TO_NUMBER('123.45') FROM DUAL;
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM DUAL;

MySQL 模式: 更多转换
```sql
SELECT CAST('100' AS UNSIGNED);                      -- 100
SELECT CAST(-1 AS UNSIGNED);                         -- 大正数 (溢出)
SELECT CAST(3.7 AS SIGNED);                          -- 4
SELECT CAST('3.14' AS DOUBLE);                       -- 3.14

```

MySQL 模式: 日期/时间格式化
```sql
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT DATE_FORMAT(NOW(), '%d/%m/%Y');
SELECT DATE_FORMAT(NOW(), '%W, %M %d, %Y');
SELECT STR_TO_DATE('15/01/2024', '%d/%m/%Y');
SELECT UNIX_TIMESTAMP('2024-01-15');                 -- → Unix
SELECT FROM_UNIXTIME(1705276800);                    -- Unix → DATETIME
SELECT FORMAT(1234567.89, 2);                        -- '1,234,567.89'

```

MySQL 模式: 隐式转换
```sql
SELECT '42' + 0;                                     -- 42
SELECT '42abc' + 0;                                  -- 42 (截取前导数字)
SELECT CONCAT('val: ', 42);                          -- 隐式转字符串

```

Oracle 模式: 更多转换
SELECT CAST(42 AS VARCHAR2(10)) FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;
SELECT TO_CHAR(1234567.89, 'FM9,999,999.00') FROM DUAL;
SELECT TO_NUMBER('$1,234.56', 'L9,999.99') FROM DUAL;
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM DUAL;
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;

JSON 转换
```sql
SELECT CAST('{"a":1}' AS JSON);                      -- MySQL 模式
SELECT JSON_EXTRACT('{"a":1}', '$.a');

```

错误处理
MySQL 模式: 非严格模式下返回零值/NULL，严格模式报错
Oracle 模式: 转换失败直接报错

二进制/十六进制 (MySQL 模式)
```sql
SELECT HEX(255);                                     -- 'FF'
SELECT CONV('FF', 16, 10);                           -- '255'
SELECT BIN(10);                                      -- '1010'

```

**注意:** OceanBase 支持 MySQL 和 Oracle 两种模式
**注意:** 不同模式下类型转换语法和行为不同
**注意:** MySQL 模式的日期格式用 %Y/%m/%d
**注意:** Oracle 模式的日期格式用 YYYY/MM/DD
