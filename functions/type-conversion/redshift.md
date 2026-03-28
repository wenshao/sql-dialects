# Amazon Redshift: Type Conversion

> 参考资料:
> - [Redshift Documentation - CAST / CONVERT](https://docs.aws.amazon.com/redshift/latest/dg/r_CAST_function.html)


```sql
SELECT CAST(42 AS VARCHAR); SELECT CAST('42' AS INTEGER); SELECT CAST('2024-01-15' AS DATE);
SELECT 42::VARCHAR; SELECT '42'::INTEGER; SELECT '2024-01-15'::DATE;

SELECT TO_CHAR(123456.789, '999,999.99'); SELECT TO_CHAR(GETDATE(), 'YYYY-MM-DD');
SELECT TO_NUMBER('123.45', '999.99'); SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
```


CONVERT (Redshift 特有)
```sql
SELECT CONVERT(INTEGER, '42');                   -- Redshift CONVERT 语法
```


日期 / Unix 时间戳
```sql
SELECT EXTRACT(EPOCH FROM TIMESTAMP '2024-01-15 00:00:00');
SELECT TIMESTAMP 'epoch' + 1705276800 * INTERVAL '1 second';
```


更多数值转换
```sql
SELECT CAST(3.14 AS INTEGER);                        -- 3 (截断)
SELECT '100'::BIGINT;                                -- 100
SELECT CAST(3.14 AS NUMERIC(10,1));                  -- 3.1
SELECT 42::FLOAT8;                                   -- 42.0
```


布尔转换
```sql
SELECT CAST(1 AS BOOLEAN);                           -- true
SELECT 'true'::BOOLEAN;                              -- true
SELECT TRUE::INTEGER;                                -- 1
```


日期/时间格式化
```sql
SELECT TO_CHAR(GETDATE(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(GETDATE(), 'Day, DD Month YYYY');
SELECT TO_CHAR(GETDATE(), 'YYYY"年"MM"月"DD"日"');
SELECT TO_DATE('15/01/2024', 'DD/MM/YYYY');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
```


数值格式化
```sql
SELECT TO_CHAR(1234567.89, 'FM9,999,999.00');        -- '1,234,567.89'
SELECT TO_CHAR(0.15, 'FM990.00%');
SELECT TO_NUMBER('$1,234.56', 'L9,999.99');
```


CONVERT 語法
```sql
SELECT CONVERT(INTEGER, '42');                       -- 42
SELECT CONVERT(VARCHAR, 42);                         -- '42'
```


日期部分提取
```sql
SELECT DATE_PART('year', GETDATE());
SELECT DATE_PART('month', GETDATE());
SELECT DATE_PART('day', GETDATE());
```


SUPER 类型 (JSON 替代)
```sql
SELECT JSON_PARSE('{"a":1}');                        -- SUPER 类型
SELECT JSON_TYPEOF(JSON_PARSE('{"a":1}'));           -- 'object'
```


隐式转換
```sql
SELECT 1 + 1.5;                                     -- NUMERIC
SELECT 'hello' || 42::VARCHAR;                       -- 需要显式转
```


精度処理
```sql
SELECT CAST(1.0/3.0 AS NUMERIC(10,4));              -- 0.3333
SELECT ROUND(3.14159, 2);                            -- 3.14
```


错误処理（无 TRY_CAST）
CAST 失败直接报错
建议预验证：
SELECT CASE WHEN col ~ '^\d+$' THEN col::INT ELSE NULL END FROM t;

注意：Redshift 支持 CAST, ::, CONVERT
注意：支持 TO_CHAR, TO_NUMBER, TO_DATE, TO_TIMESTAMP
注意：日期格式使用 PostgreSQL 模板模式
限制：无 TRY_CAST
