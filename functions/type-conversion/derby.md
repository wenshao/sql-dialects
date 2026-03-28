# Apache Derby: Type Conversion

> 参考资料:
> - [Apache Derby Reference](https://db.apache.org/derby/docs/10.16/ref/)


```sql
SELECT CAST(42 AS VARCHAR(10)); SELECT CAST('42' AS INTEGER);
SELECT CAST('3.14' AS DECIMAL(10,2)); SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('10:30:00' AS TIME);
```

## 隐式转换 (Derby 较严格)

```sql
SELECT 1 + CAST('2' AS INTEGER);
```

## 更多数值转换

```sql
SELECT CAST(3.14 AS INTEGER);                        -- 3 (截断)
SELECT CAST(3.14 AS SMALLINT);                       -- 3
SELECT CAST(3.14 AS BIGINT);                         -- 3
SELECT CAST(3.14 AS REAL);                           -- 3.14
SELECT CAST(3.14 AS DOUBLE);                         -- 3.14
SELECT CAST(42 AS DECIMAL(10,2));                    -- 42.00
```

## 字符串 ↔ 数值

```sql
SELECT CAST(123 AS VARCHAR(10));                     -- '123'
SELECT CAST(123 AS CHAR(10));                        -- '123       '
SELECT CAST('3.14' AS DOUBLE);                       -- 3.14
SELECT CAST('100' AS BIGINT);                        -- 100
```

## 日期/时间转换

```sql
SELECT CAST('2024-01-15' AS DATE);                   -- DATE
SELECT CAST('10:30:00' AS TIME);                     -- TIME
SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);     -- TIMESTAMP
SELECT CAST(CURRENT_DATE AS VARCHAR(10));            -- '2024-01-15'
SELECT CAST(CURRENT_TIME AS VARCHAR(8));             -- '10:30:00'
SELECT CAST(CURRENT_TIMESTAMP AS VARCHAR(26));       -- 完整时间戳
```

## 日期部分提取 (Derby 方式)

```sql
SELECT YEAR(CURRENT_DATE);                           -- 2024
SELECT MONTH(CURRENT_DATE);                          -- 1
SELECT DAY(CURRENT_DATE);                            -- 15
SELECT HOUR(CURRENT_TIMESTAMP);                      -- 10
```

## 布尔转换 (Derby 10.7+)

```sql
SELECT CAST(1 AS BOOLEAN);                           -- 转换失败（不支持）
```

## 隐式转换 (Derby 非常严格)

```sql
SELECT 1 + CAST('2' AS INTEGER);                     -- 需要显式 CAST
SELECT 1 + 1.5;                                     -- DECIMAL (数值类型可隐式提升)
```

## 字符串拼接与转换

```sql
SELECT 'value: ' || CAST(42 AS VARCHAR(10));         -- 需要显式转
SELECT CAST(42 AS VARCHAR(10)) || ' items';
```

## 精度处理

```sql
SELECT CAST(1.0/3.0 AS DECIMAL(10,4));              -- 0.3333
SELECT CAST(CAST(3.14159 AS DECIMAL(10,2)) AS VARCHAR(10)); -- '3.14'
```

错误处理（无 TRY_CAST，失败直接报错）
Derby 转换失败总是抛出 SQLException
建议在应用层 (Java) 用 try-catch 处理
注意：Derby 只支持标准 CAST
注意：隐式转换极其严格
注意：日期格式化需在应用层处理（无内置格式化函数）
限制：无 CONVERT, TRY_CAST, ::, TO_NUMBER, TO_CHAR, FORMAT
