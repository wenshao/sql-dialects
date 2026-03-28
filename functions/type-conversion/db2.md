# DB2: Type Conversion

> 参考资料:
> - [IBM DB2 Documentation - CAST](https://www.ibm.com/docs/en/db2/11.5?topic=expressions-cast-specification)


```sql
SELECT CAST(42 AS VARCHAR(10)); SELECT CAST('42' AS INTEGER);
SELECT CAST('3.14' AS DECIMAL(10,2)); SELECT CAST('2024-01-15' AS DATE);
```

## 专用转换函数

```sql
SELECT CHAR(42);                                 -- '42' (整数→字符)
SELECT CHAR(CURRENT_DATE, ISO);                  -- 'YYYY-MM-DD' (ISO 格式)
SELECT CHAR(CURRENT_TIMESTAMP, ISO);
SELECT INTEGER('42');                            -- 42
SELECT DECIMAL('3.14', 10, 2);                   -- 3.14
SELECT DATE('2024-01-15');                       -- DATE
SELECT TIMESTAMP('2024-01-15 10:30:00');         -- TIMESTAMP
SELECT VARCHAR_FORMAT(CURRENT_TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');      -- 11.1+
SELECT TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD');      -- 11.1+
SELECT TO_NUMBER('123.45');                       -- 11.1+
```

## 隐式转换

```sql
SELECT 1 + CAST('2' AS INTEGER);                 -- DB2 隐式转换严格
```

## 更多数值转換

```sql
SELECT CAST(3.14 AS INTEGER);                        -- 3 (截断)
SELECT CAST('100' AS BIGINT);                        -- 100
SELECT CAST(3.14 AS DECIMAL(10,1));                  -- 3.1
SELECT REAL('3.14');                                 -- 3.14
SELECT DOUBLE('42');                                 -- 42.0
SELECT SMALLINT(42);                                 -- 42
```

## 日期/時間格式化

```sql
SELECT VARCHAR_FORMAT(CURRENT_TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS');
SELECT VARCHAR_FORMAT(CURRENT_TIMESTAMP, 'DD/MM/YYYY');
SELECT VARCHAR_FORMAT(CURRENT_TIMESTAMP, 'Day, DD Month YYYY');
SELECT TO_DATE('15/01/2024', 'DD/MM/YYYY');          -- 11.1+
SELECT TO_CHAR(CURRENT_DATE, 'Day, DD Month YYYY');  -- 11.1+
SELECT TIMESTAMP_FORMAT('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
```

## 日期部分提取

```sql
SELECT YEAR(CURRENT_DATE);                           -- 2024
SELECT MONTH(CURRENT_DATE);                          -- 1
SELECT DAY(CURRENT_DATE);                            -- 15
SELECT HOUR(CURRENT_TIMESTAMP);                      -- 10
```

## 区間转換

```sql
SELECT CURRENT_DATE + 1 DAY;
SELECT CURRENT_DATE - 30 DAYS;
SELECT CURRENT_TIMESTAMP + 2 HOURS;
SELECT CURRENT_DATE + 1 MONTH;
```

## 布尔 (DB2 11.1+)

```sql
SELECT CAST(1 AS BOOLEAN);                           -- 不支持（用 SMALLINT 替代）
```

## 二進制転換

```sql
SELECT CHAR(42);                                     -- '42'
SELECT CHAR(CURRENT_DATE, ISO);                      -- 'YYYY-MM-DD'
SELECT CHAR(CURRENT_DATE, USA);                      -- 'MM/DD/YYYY'
SELECT CHAR(CURRENT_DATE, EUR);                      -- 'DD.MM.YYYY'
SELECT CHAR(CURRENT_DATE, JIS);                      -- 'YYYY-MM-DD'
```

## 精度処理

```sql
SELECT CAST(1.0/3.0 AS DECIMAL(10,4));              -- 0.3333
SELECT ROUND(3.14159, 2);                            -- 3.14
SELECT TRUNCATE(3.14159, 2);                         -- 3.14
```

错误処理（无 TRY_CAST）
CAST 転換失败直接报错
建议使用 CASE + LENGTH/LOCATE 预验证
注意：DB2 有专用类型转换函数 (CHAR, INTEGER, DECIMAL, DATE 等)
注意：DB2 11.1+ 支持 TO_CHAR / TO_DATE / TO_NUMBER (Oracle 兼容)
注意：CHAR() 函数的 ISO/USA/EUR/JIS 格式是 DB2 特有
限制：无 TRY_CAST / :: / CONVERT (SQL Server 风格)
