# Databricks: Type Conversion

> 参考资料:
> - [Databricks SQL Reference - CAST / TRY_CAST](https://docs.databricks.com/en/sql/language-manual/functions/cast.html)


```sql
SELECT CAST(42 AS STRING); SELECT CAST('42' AS INT); SELECT CAST('3.14' AS DOUBLE);
SELECT CAST('2024-01-15' AS DATE); SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);
```


TRY_CAST (安全转换)
```sql
SELECT TRY_CAST('abc' AS INT);                  -- NULL
SELECT TRY_CAST('42' AS INT);                   -- 42
SELECT TRY_CAST('bad-date' AS DATE);            -- NULL
```


格式化
```sql
SELECT DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd');
SELECT TO_DATE('2024/01/15', 'yyyy/MM/dd');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT FROM_UNIXTIME(1705276800);                -- Unix → 字符串
SELECT UNIX_TIMESTAMP('2024-01-15', 'yyyy-MM-dd'); -- → Unix
```


:: 运算符                                     -- Databricks SQL
```sql
SELECT 42::STRING; SELECT '42'::INT;
```


更多数值转换
```sql
SELECT CAST('100' AS BIGINT);                        -- 100
SELECT CAST(3.14 AS INT);                            -- 3 (截断)
SELECT CAST(3.14 AS DECIMAL(10,1));                  -- 3.1
SELECT CAST(TRUE AS INT);                            -- 1
SELECT CAST(0 AS BOOLEAN);                           -- false
```


TRY_CAST 详细示例
```sql
SELECT TRY_CAST('hello' AS INT);                     -- NULL
SELECT TRY_CAST('2024-99-99' AS DATE);               -- NULL
SELECT TRY_CAST('' AS INT);                          -- NULL
SELECT TRY_CAST('3.14' AS DECIMAL(10,2));            -- 3.14
```


日期/时间格式化
```sql
SELECT DATE_FORMAT(CURRENT_TIMESTAMP(), 'yyyy-MM-dd HH:mm:ss');
SELECT DATE_FORMAT(CURRENT_TIMESTAMP(), 'dd/MM/yyyy');
SELECT DATE_FORMAT(CURRENT_TIMESTAMP(), 'yyyy年MM月dd日');
SELECT TO_DATE('15/01/2024', 'dd/MM/yyyy');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT FROM_UNIXTIME(1705276800, 'yyyy-MM-dd HH:mm:ss');
SELECT UNIX_TIMESTAMP('2024-01-15', 'yyyy-MM-dd');
```


日期部分提取
```sql
SELECT YEAR(CURRENT_DATE());                         -- 2024
SELECT MONTH(CURRENT_DATE());                        -- 1
SELECT DAY(CURRENT_DATE());                          -- 15
```


复合类型转换
```sql
SELECT CAST(ARRAY(1, 2, 3) AS ARRAY<STRING>);
```

SELECT from_json('{"a":1}', 'a INT');
SELECT to_json(struct(1 AS a, 'hello' AS b));

精度処理
```sql
SELECT CAST(1.0/3.0 AS DECIMAL(10,4));              -- 0.3333
SELECT ROUND(3.14159, 2);                            -- 3.14
```


注意：Databricks 支持 CAST, TRY_CAST, :: 运算符
注意：日期函数使用 Java SimpleDateFormat 模式 (yyyy, MM, dd, HH, mm, ss)
注意：TRY_CAST 是处理脏数据的最佳实践
