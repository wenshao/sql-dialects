# Trino: 间隔检测

> 参考资料:
> - [Trino Documentation - Window Functions](https://trino.io/docs/current/functions/window.html)
> - [Trino Documentation - sequence](https://trino.io/docs/current/functions/array.html#sequence)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

## 准备数据


Trino 使用 VALUES 构造数据
CREATE TABLE orders AS SELECT * FROM (VALUES (1,'a'),(2,'b'),...) AS t(id,info);

## 使用 LAG/LEAD 查找数值间隙


```sql
SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders)
WHERE next_id - id > 1;

```

## 查找日期间隙


```sql
SELECT sale_date, next_date,
       DATE_DIFF('day', sale_date, next_date) - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) WHERE DATE_DIFF('day', sale_date, next_date) > 1;

```

## 岛屿问题


```sql
SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders)
GROUP BY grp ORDER BY island_start;

```

## 自连接方法


```sql
SELECT a.id + 1 AS gap_start, MIN(b.id) - 1 AS gap_end
FROM orders a JOIN orders b ON b.id > a.id
GROUP BY a.id HAVING MIN(b.id) > a.id + 1 ORDER BY gap_start;

```

## 使用 sequence + UNNEST（Trino 特有）


缺失的 id
```sql
SELECT s AS missing_id
FROM UNNEST(sequence(
    (SELECT MIN(id) FROM orders),
    (SELECT MAX(id) FROM orders)
)) AS t(s)
LEFT JOIN orders o ON o.id = t.s
WHERE o.id IS NULL ORDER BY s;

```

缺失的日期
```sql
SELECT s AS missing_date
FROM UNNEST(sequence(
    (SELECT MIN(sale_date) FROM daily_sales),
    (SELECT MAX(sale_date) FROM daily_sales),
    INTERVAL '1' DAY
)) AS t(s)
LEFT JOIN daily_sales ds ON ds.sale_date = t.s
WHERE ds.sale_date IS NULL ORDER BY s;

```

## 综合示例


```sql
WITH islands AS (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
),
gaps AS (
    SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders
)
SELECT 'Island' AS type, MIN(id) AS range_start, MAX(id) AS range_end, COUNT(*) AS size
FROM islands GROUP BY grp
UNION ALL
SELECT 'Gap', id + 1, next_id - 1, next_id - id - 1
FROM gaps WHERE next_id - id > 1
ORDER BY range_start;

```

**注意:** Trino 使用 sequence() 生成数组，UNNEST 展开为行
**注意:** Trino 使用 DATE_DIFF 计算日期差值（注意与其他引擎的区别）
**注意:** Trino 不支持递归 CTE
