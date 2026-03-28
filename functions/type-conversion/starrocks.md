# StarRocks: 类型转换

> 参考资料:
> - [1] StarRocks Documentation - CAST
>   https://docs.starrocks.io/docs/sql-reference/sql-functions/


## 1. CAST

```sql
SELECT CAST(42 AS VARCHAR), CAST('42' AS INT);
SELECT CAST('3.14' AS DECIMAL(10,2));
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST(TRUE AS INT);

```

## 2. 日期格式化

```sql
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');
SELECT UNIX_TIMESTAMP('2024-01-15');
SELECT FROM_UNIXTIME(1705276800);

```

## 3. 隐式转换

```sql
SELECT '42' + 0;
SELECT CONCAT('val: ', 42);

```

## 4. JSON 转换

```sql
SELECT CAST('{"a":1}' AS JSON);
SELECT PARSE_JSON('{"a":1}');  -- StarRocks 特有

```

## 5. StarRocks vs Doris 差异

核心转换函数相同。
StarRocks 独有: PARSE_JSON(更语义化的 JSON 构造)
两者都不支持: TRY_CAST、::、CONVERT

