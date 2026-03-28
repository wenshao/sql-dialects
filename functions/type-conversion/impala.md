# Apache Impala: Type Conversion

> 参考资料:
> - [Impala SQL Reference - Type Conversion](https://impala.apache.org/docs/build/html/topics/impala_conversion_functions.html)


```sql
SELECT CAST(42 AS STRING); SELECT CAST('42' AS INT); SELECT CAST('3.14' AS DOUBLE);
SELECT CAST('2024-01-15' AS TIMESTAMP);
```


格式化
```sql
SELECT FROM_TIMESTAMP(NOW(), 'yyyy-MM-dd HH:mm:ss');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT FROM_UNIXTIME(1705276800, 'yyyy-MM-dd');
SELECT UNIX_TIMESTAMP('2024-01-15 10:30:00');
```


隐式转换
```sql
SELECT '42' + 0;                                 -- INT
SELECT CONCAT('val: ', CAST(42 AS STRING));
```


更多数值转换
```sql
SELECT CAST('100' AS BIGINT);                        -- 100
SELECT CAST(3.14 AS INT);                            -- 3 (截断)
SELECT CAST(3.14 AS DECIMAL(10,1));                  -- 3.1
SELECT CAST(3.14 AS FLOAT);                          -- 3.14
SELECT CAST(TRUE AS INT);                            -- 1
SELECT CAST(0 AS BOOLEAN);                           -- false
```


日期/时间格式化
```sql
SELECT FROM_TIMESTAMP(NOW(), 'yyyy-MM-dd');
SELECT FROM_TIMESTAMP(NOW(), 'dd/MM/yyyy');
SELECT FROM_TIMESTAMP(NOW(), 'yyyy年MM月dd日');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT TO_TIMESTAMP('15/01/2024', 'dd/MM/yyyy');
SELECT FROM_UNIXTIME(1705276800, 'yyyy-MM-dd HH:mm:ss');
SELECT UNIX_TIMESTAMP('2024-01-15 10:30:00');
```


日期部分提取
```sql
SELECT YEAR(NOW());                                  -- 2024
SELECT MONTH(NOW());                                 -- 1
SELECT DAY(NOW());                                   -- 15
SELECT HOUR(NOW());                                  -- 10
SELECT EXTRACT(YEAR FROM NOW());
```


字符串 ↔ 数值
```sql
SELECT CAST(12345 AS STRING);                        -- '12345'
SELECT CAST('67890' AS BIGINT);                      -- 67890
SELECT CAST(3.14159 AS STRING);                      -- '3.14159'
```


精度処理
```sql
SELECT CAST(1.0/3.0 AS DECIMAL(10,4));              -- 0.3333
SELECT ROUND(3.14159, 2);                            -- 3.14
SELECT TRUNCATE(3.14159, 2);                         -- 3.14
```


隐式转換
```sql
SELECT '42' + 0;                                     -- 42 (INT)
SELECT CONCAT('val: ', CAST(42 AS STRING));          -- 需显式 CAST
SELECT 1 + 1.5;                                     -- DOUBLE
```


Kudu 表特殊注意
Kudu 表支持 UPDATE/DELETE，类型转换在 scan 时执行
非 Kudu 表只读，CAST 在查询时执行

错误处理（无 TRY_CAST）
CAST 转换失败返回 NULL (Impala 行为)
与其他数据库不同：Impala CAST 失败通常不报错而是返回 NULL

注意：Impala CAST 目标类型直接用类型名
注意：日期使用 Java SimpleDateFormat 模式 (yyyy, MM, dd, HH, mm, ss)
注意：CAST 失败通常返回 NULL 而非报错
限制：无 TRY_CAST, ::, CONVERT, TO_CHAR, TO_NUMBER
