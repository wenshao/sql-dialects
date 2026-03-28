# SQLite: 间隙检测

> 参考资料:
> - [SQLite Documentation - Window Functions](https://www.sqlite.org/windowfunctions.html)
> - [SQLite Documentation - WITH clause (CTE)](https://www.sqlite.org/lang_with.html)

## 准备数据

```sql
CREATE TABLE orders (
    id    INTEGER PRIMARY KEY,
    info  TEXT
);
INSERT INTO orders (id, info) VALUES
    (1, 'a'), (2, 'b'), (3, 'c'),
    (5, 'e'), (6, 'f'),
    (10, 'j'), (11, 'k'), (12, 'l'),
    (15, 'o');

CREATE TABLE daily_sales (
    sale_date TEXT PRIMARY KEY,  -- SQLite 没有原生 DATE 类型
    amount    REAL
);
INSERT INTO daily_sales (sale_date, amount) VALUES
    ('2024-01-01', 100), ('2024-01-02', 150),
    ('2024-01-04', 200), ('2024-01-05', 120),
    ('2024-01-08', 300), ('2024-01-09', 250),
    ('2024-01-10', 180);
```

## 使用 LAG/LEAD 窗口函数查找数值间隙（SQLite 3.25+）

```sql
SELECT
    id            AS gap_start_after,
    next_id       AS gap_end_before,
    next_id - id - 1 AS gap_size
FROM (
    SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id
    FROM orders
) t
WHERE next_id - id > 1;
```

## 使用 LAG/LEAD 查找日期间隙

```sql
SELECT
    sale_date   AS last_date,
    next_date   AS next_date,
    CAST(julianday(next_date) - julianday(sale_date) - 1 AS INTEGER) AS missing_days
FROM (
    SELECT sale_date,
           LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) t
WHERE julianday(next_date) - julianday(sale_date) > 1;
```

## 岛屿问题

```sql
SELECT
    MIN(id) AS island_start,
    MAX(id) AS island_end,
    COUNT(*) AS island_size
FROM (
    SELECT id,
           id - ROW_NUMBER() OVER (ORDER BY id) AS grp
    FROM orders
) t
GROUP BY grp
ORDER BY island_start;
```

## 自连接方法（兼容旧版 SQLite）

```sql
SELECT
    a.id + 1 AS gap_start,
    MIN(b.id) - 1 AS gap_end
FROM orders a
JOIN orders b ON b.id > a.id
GROUP BY a.id
HAVING MIN(b.id) > a.id + 1
ORDER BY gap_start;
```

## 使用递归 CTE 生成序列（SQLite 3.8.3+）

```sql
WITH RECURSIVE seq(n) AS (
    SELECT MIN(id) FROM orders
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < (SELECT MAX(id) FROM orders)
)
SELECT n AS missing_id
FROM seq
LEFT JOIN orders o ON o.id = seq.n
WHERE o.id IS NULL
ORDER BY n;
```

生成日期序列
```sql
WITH RECURSIVE date_seq(d) AS (
    SELECT MIN(sale_date) FROM daily_sales
    UNION ALL
    SELECT DATE(d, '+1 day') FROM date_seq
    WHERE d < (SELECT MAX(sale_date) FROM daily_sales)
)
SELECT d AS missing_date
FROM date_seq
LEFT JOIN daily_sales ds ON ds.sale_date = date_seq.d
WHERE ds.sale_date IS NULL
ORDER BY d;
```

## 综合示例

```sql
WITH ordered AS (
    SELECT id,
           LEAD(id) OVER (ORDER BY id) AS next_id
    FROM orders
),
islands AS (
    SELECT id,
           id - ROW_NUMBER() OVER (ORDER BY id) AS grp
    FROM orders
)
SELECT 'Island' AS type,
       MIN(id)  AS range_start,
       MAX(id)  AS range_end,
       COUNT(*) AS size
FROM islands GROUP BY grp
UNION ALL
SELECT 'Gap', id + 1, next_id - 1, next_id - id - 1
FROM ordered WHERE next_id - id > 1
ORDER BY range_start;
```

注意：窗口函数需要 SQLite 3.25.0+（2018-09-15）
注意：递归 CTE 需要 SQLite 3.8.3+（2014-02-03）
注意：SQLite 没有原生日期类型，使用 TEXT 或 REAL 存储
注意：julianday() 用于日期差值计算
