# PolarDB: Type Conversion

> 参考资料:
> - [PolarDB Documentation](https://www.alibabacloud.com/help/en/polardb/)
> - PolarDB for PostgreSQL

```sql
SELECT CAST(42 AS TEXT); SELECT 42::TEXT; SELECT '42'::INTEGER;
SELECT to_char(now(), 'YYYY-MM-DD'); SELECT to_date('2024-01-15', 'YYYY-MM-DD');
```

PolarDB for MySQL
SELECT CAST(42 AS CHAR); SELECT CAST('42' AS SIGNED);
SELECT CONVERT(42, CHAR); SELECT DATE_FORMAT(NOW(), '%Y-%m-%d');
PolarDB for PostgreSQL: 更多转换

```sql
SELECT CAST(3.14 AS INTEGER);                        -- 3 (截断)
SELECT '100'::BIGINT;                                -- 100
SELECT '3.14'::NUMERIC(10,2);                        -- 3.14
SELECT CAST(1 AS BOOLEAN);                           -- true
SELECT 'true'::BOOLEAN;                              -- true
SELECT TRUE::INTEGER;                                -- 1
```

## PostgreSQL 日期/时间格式化

```sql
SELECT to_char(now(), 'YYYY-MM-DD HH24:MI:SS');
SELECT to_char(now(), 'Day, DD Month YYYY');
SELECT to_timestamp('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
SELECT to_timestamp(1705276800);                     -- Unix → TIMESTAMP
SELECT EXTRACT(EPOCH FROM now());                    -- TIMESTAMP → Unix
```

## PostgreSQL 数值格式化

```sql
SELECT to_char(1234567.89, 'FM9,999,999.00');
SELECT to_number('1,234.56', '9,999.99');
```

## PostgreSQL JSON 转换

```sql
SELECT '{"a":1}'::JSONB;
SELECT CAST('["a","b"]' AS JSONB);
```

PolarDB for MySQL: 更多转换
SELECT CAST('100' AS UNSIGNED);
SELECT CAST(-1 AS UNSIGNED);
SELECT CAST(3.7 AS SIGNED);                       -- 4
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('15/01/2024', '%d/%m/%Y');
SELECT UNIX_TIMESTAMP('2024-01-15');
SELECT FROM_UNIXTIME(1705276800);
SELECT FORMAT(1234567.89, 2);                     -- '1,234,567.89'
隐式转换
PG版: 严格，需要显式 CAST

```sql
SELECT 1 + 1.5;                                     -- NUMERIC
```

错误处理
PG版: 无 TRY_CAST，转换失败报错
MySQL版: 非严格模式下返回零值/NULL
注意：PolarDB 有 PostgreSQL 和 MySQL 两个版本
注意：转换语法取决于所用引擎版本
注意：PG版支持 CAST, ::, TO_CHAR, TO_NUMBER, TO_DATE
注意：MySQL版支持 CAST, CONVERT, DATE_FORMAT, STR_TO_DATE
