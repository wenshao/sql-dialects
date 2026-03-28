# Apache Doris: 日期序列填充

 Apache Doris: 日期序列填充

 参考资料:
   [1] Doris - numbers() table function
       https://doris.apache.org/docs/sql-manual/sql-functions/table-functions/numbers/

## 1. 生成日期序列 (numbers 表函数，2.1+)

```sql
SELECT DATE_ADD('2024-01-01', INTERVAL number DAY) AS d
FROM numbers("number" = "10");

```

## 2. LEFT JOIN 填零

```sql
SELECT DATE_ADD('2024-01-01', INTERVAL number DAY) AS date,
       COALESCE(ds.amount, 0) AS amount
FROM numbers("number" = "10") n
LEFT JOIN daily_sales ds ON ds.sale_date = DATE_ADD('2024-01-01', INTERVAL n.number DAY)
ORDER BY date;

```

## 3. 前向填充 (模拟 IGNORE NULLS)

COUNT 分组法:
WITH filled AS (
SELECT date, amount, COUNT(amount) OVER (ORDER BY date) AS grp FROM ...
)
SELECT date, FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY date) FROM filled;

对比:
StarRocks: 相同方案(numbers 表函数)
ClickHouse: 无 numbers()，用 arrayJoin(range(N))
BigQuery:  GENERATE_DATE_ARRAY(start, end)(最简洁)
PostgreSQL: generate_series(start, end, interval)
MySQL:     无内置序列生成(需递归 CTE 或辅助表)

