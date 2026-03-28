# Apache Doris: 间隙检测与岛屿问题

 Apache Doris: 间隙检测与岛屿问题

 参考资料:
   [1] Doris Documentation - Window Functions
       https://doris.apache.org/docs/sql-manual/sql-functions/window-functions/

## 1. LAG/LEAD 检测间隙

```sql
SELECT id AS gap_after, next_id AS gap_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders) t
WHERE next_id - id > 1;

```

## 2. 日期间隙

```sql
SELECT sale_date, next_date, DATEDIFF(next_date, sale_date) - 1 AS missing
FROM (SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date FROM daily_sales) t
WHERE DATEDIFF(next_date, sale_date) > 1;

```

## 3. 岛屿问题 (ROW_NUMBER 差值法)

```sql
SELECT MIN(id) AS start, MAX(id) AS end, COUNT(*) AS size
FROM (SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders) t
GROUP BY grp ORDER BY start;

```

## 4. numbers 表函数 (2.1+)

```sql
SELECT number + (SELECT MIN(id) FROM orders) AS missing_id
FROM numbers("number" = "20")
WHERE number + (SELECT MIN(id) FROM orders) <= (SELECT MAX(id) FROM orders)
  AND number + (SELECT MIN(id) FROM orders) NOT IN (SELECT id FROM orders);

```
