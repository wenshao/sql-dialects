# Firebird: 间隙检测与岛屿问题 (Gap Detection & Islands)

> 参考资料:
> - [Firebird Documentation - Window Functions](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html#fblangref40-windowfuncs)
> - [Firebird Documentation - Common Table Expressions](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html#fblangref40-commons-cte)


## 准备数据


```sql
CREATE TABLE orders (id INTEGER NOT NULL PRIMARY KEY, info VARCHAR(100));
INSERT INTO orders (id, info) VALUES (1,'a');
INSERT INTO orders (id, info) VALUES (2,'b');
INSERT INTO orders (id, info) VALUES (3,'c');
INSERT INTO orders (id, info) VALUES (5,'e');
INSERT INTO orders (id, info) VALUES (6,'f');
INSERT INTO orders (id, info) VALUES (10,'j');
INSERT INTO orders (id, info) VALUES (11,'k');
INSERT INTO orders (id, info) VALUES (12,'l');
INSERT INTO orders (id, info) VALUES (15,'o');
```

## 使用 LAG/LEAD 查找数值间隙（Firebird 3.0+）


```sql
SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders) t
WHERE next_id - id > 1;
```

## 查找日期间隙


```sql
SELECT sale_date, next_date, DATEDIFF(DAY, sale_date, next_date) - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) t WHERE DATEDIFF(DAY, sale_date, next_date) > 1;
```

## 岛屿问题


```sql
SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders) t
GROUP BY grp ORDER BY 1;
```

## 自连接方法（兼容 Firebird 2.x）


```sql
SELECT a.id + 1 AS gap_start, MIN(b.id) - 1 AS gap_end
FROM orders a JOIN orders b ON b.id > a.id
GROUP BY a.id HAVING MIN(b.id) > a.id + 1 ORDER BY 1;
```

## 递归 CTE 生成序列（Firebird 2.1+）


```sql
WITH RECURSIVE seq(n) AS (
    SELECT MIN(id) FROM orders
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < (SELECT MAX(id) FROM orders)
)
SELECT s.n AS missing_id
FROM seq s LEFT JOIN orders o ON o.id = s.n
WHERE o.id IS NULL ORDER BY s.n;
```

## 综合示例


```sql
WITH RECURSIVE islands AS (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
),
gaps AS (
    SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders
)
SELECT 'Island' AS rtype, MIN(id) AS range_start, MAX(id) AS range_end, COUNT(*) AS size
FROM islands GROUP BY grp
UNION ALL
SELECT 'Gap', id + 1, next_id - 1, next_id - id - 1
FROM gaps WHERE next_id - id > 1
ORDER BY 2;
```

注意：窗口函数需要 Firebird 3.0+
注意：递归 CTE 从 Firebird 2.1 开始支持
注意：Firebird 使用 DATEDIFF(unit, start, end) 计算日期差值
