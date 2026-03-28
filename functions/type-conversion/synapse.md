# Azure Synapse: Type Conversion

> 参考资料:
> - [Synapse SQL - CAST and CONVERT](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)


```sql
SELECT CAST(42 AS VARCHAR(10)); SELECT CAST('42' AS INT); SELECT CAST('2024-01-15' AS DATE);
```


CONVERT 带样式码
```sql
SELECT CONVERT(VARCHAR(10), GETDATE(), 120);     -- 'YYYY-MM-DD'
SELECT CONVERT(VARCHAR(10), GETDATE(), 101);     -- 'MM/DD/YYYY'
```


TRY_CAST / TRY_CONVERT
```sql
SELECT TRY_CAST('abc' AS INT);                  -- NULL
SELECT TRY_CONVERT(INT, 'abc');                  -- NULL
```


FORMAT
```sql
SELECT FORMAT(GETDATE(), 'yyyy-MM-dd');
```


更多数值转换
```sql
SELECT CAST(3.14 AS INT);                            -- 3 (截断)
SELECT CAST(3.7 AS INT);                             -- 4 (四舍五入)
SELECT CAST('100' AS BIGINT);                        -- 100
SELECT CAST(3.14 AS DECIMAL(10,1));                  -- 3.1
SELECT CAST(3.14 AS MONEY);                          -- 3.14
```


TRY_CAST / TRY_CONVERT 详细示例
```sql
SELECT TRY_CAST('hello' AS INT);                     -- NULL
SELECT TRY_CAST('2024-99-99' AS DATE);               -- NULL
SELECT TRY_CAST('3.14' AS DECIMAL(10,2));            -- 3.14
SELECT TRY_CONVERT(INT, '');                         -- NULL
SELECT TRY_CONVERT(DATE, 'not-a-date');              -- NULL
```


CONVERT 样式码详解
```sql
SELECT CONVERT(VARCHAR(10), GETDATE(), 101);         -- 'MM/DD/YYYY'
SELECT CONVERT(VARCHAR(10), GETDATE(), 103);         -- 'DD/MM/YYYY'
SELECT CONVERT(VARCHAR(10), GETDATE(), 104);         -- 'DD.MM.YYYY'
SELECT CONVERT(VARCHAR(10), GETDATE(), 111);         -- 'YYYY/MM/DD'
SELECT CONVERT(VARCHAR(10), GETDATE(), 112);         -- 'YYYYMMDD'
SELECT CONVERT(VARCHAR(19), GETDATE(), 120);         -- 'YYYY-MM-DD HH:MI:SS'
SELECT CONVERT(VARCHAR(23), GETDATE(), 126);         -- ISO 8601
```


FORMAT 格式化
```sql
SELECT FORMAT(GETDATE(), 'yyyy-MM-dd HH:mm:ss');
SELECT FORMAT(GETDATE(), 'dd/MM/yyyy');
SELECT FORMAT(GETDATE(), 'dddd, MMMM dd, yyyy');
SELECT FORMAT(1234567.89, 'N2');                     -- '1,234,567.89'
SELECT FORMAT(0.15, 'P0');                           -- '15 %'
SELECT FORMAT(1234567.89, 'C', 'en-us');             -- '$1,234,567.89'
```


隐式转換
```sql
SELECT 1 + '2';                                      -- 3 (隐式转 INT)
SELECT 'val: ' + CAST(42 AS VARCHAR);                -- 需 CAST
SELECT 1 + 1.5;                                     -- NUMERIC
```


二进制转换
```sql
SELECT CONVERT(VARBINARY(4), 255);                   -- 0x000000FF
SELECT CONVERT(INT, 0x000000FF);                     -- 255
```


注意：与 SQL Server 类型转换一致
注意：支持 CAST, CONVERT, TRY_CAST, TRY_CONVERT, FORMAT
注意：FORMAT 使用 .NET 格式字符串
注意：CONVERT 样式码是 SQL Server / Synapse 特有
限制：无 ::, TO_NUMBER, TO_CHAR
