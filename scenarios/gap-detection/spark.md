# Spark SQL: 间隙检测与岛屿问题 (Gap Detection & Islands)

> 参考资料:
> - [1] Spark SQL - Window Functions
>   https://spark.apache.org/docs/latest/sql-ref-functions-builtin.html#window-functions


## 示例数据

```sql
CREATE TEMPORARY VIEW orders AS
SELECT * FROM VALUES (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),
    (10,'j'),(11,'k'),(12,'l'),(15,'o') AS t(id, info);

CREATE TEMPORARY VIEW daily_sales AS
SELECT * FROM VALUES
    (DATE '2024-01-01', 100),(DATE '2024-01-02', 150),(DATE '2024-01-04', 200),
    (DATE '2024-01-05', 120),(DATE '2024-01-08', 300),(DATE '2024-01-09', 250),
    (DATE '2024-01-10', 180) AS t(sale_date, amount);

```

## 1. LAG/LEAD 检测数值间隙

```sql
SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (
    SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders
) WHERE next_id - id > 1;

```

## 2. 检测日期间隙

```sql
SELECT sale_date, next_date, DATEDIFF(next_date, sale_date) - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) WHERE DATEDIFF(next_date, sale_date) > 1;

```

## 3. 岛屿问题（连续序列识别）

```sql
SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
) GROUP BY grp ORDER BY island_start;

```

 原理: id - ROW_NUMBER() 在连续序列中产生相同的值（常数差）
 这是经典的"岛屿与间隙"算法，适用于所有 SQL 引擎

## 4. 日期岛屿

```sql
SELECT MIN(sale_date) AS island_start, MAX(sale_date) AS island_end,
       COUNT(*) AS days_count
FROM (
    SELECT sale_date,
           DATEDIFF(sale_date, DATE '1970-01-01')
           - ROW_NUMBER() OVER (ORDER BY sale_date) AS grp
    FROM daily_sales
) GROUP BY grp ORDER BY island_start;

```

## 5. SEQUENCE + EXPLODE 查找缺失值


缺失的 ID

```sql
SELECT col AS missing_id
FROM (
    SELECT EXPLODE(SEQUENCE(
        (SELECT MIN(id) FROM orders),
        (SELECT MAX(id) FROM orders)
    )) AS col
) s
LEFT JOIN orders o ON o.id = s.col
WHERE o.id IS NULL ORDER BY col;

```

缺失的日期

```sql
SELECT col AS missing_date
FROM (
    SELECT EXPLODE(SEQUENCE(
        (SELECT MIN(sale_date) FROM daily_sales),
        (SELECT MAX(sale_date) FROM daily_sales),
        INTERVAL 1 DAY
    )) AS col
) s
LEFT JOIN daily_sales ds ON ds.sale_date = s.col
WHERE ds.sale_date IS NULL ORDER BY col;

```

## 6. 自连接方法（不使用窗口函数）

```sql
SELECT a.id + 1 AS gap_start, MIN(b.id) - 1 AS gap_end
FROM orders a JOIN orders b ON b.id > a.id
GROUP BY a.id HAVING MIN(b.id) > a.id + 1 ORDER BY gap_start;

```

## 7. 综合: 岛屿与间隙统一视图

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

## 8. 版本演进

Spark 2.0: LAG/LEAD, ROW_NUMBER 窗口函数
Spark 2.4: SEQUENCE 函数（EXPLODE 查找缺失值）
Spark 3.4: 递归 CTE（可用于更复杂的间隙填充）

限制:
SEQUENCE 生成数组，大范围可能导致内存问题
岛屿算法需要全局排序（无 PARTITION BY 时单分区执行）
Spark 3.4 之前无递归 CTE（某些复杂间隙模式无法处理）

