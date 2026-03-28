# DamengDB (达梦): 间隙检测与岛屿问题 (Gap Detection & Islands)

> 参考资料:
> - [DamengDB Documentation - 分析函数](https://eco.dameng.com/document/dm/zh-cn/sql-dev/dmpl-sql-dataquery.html)
> - [DamengDB Documentation - 层次查询](https://eco.dameng.com/document/dm/zh-cn/sql-dev/dmpl-sql-dataquery.html#层次查询)
> - ============================================================
> - 准备数据
> - ============================================================

```sql
CREATE TABLE orders (id INT PRIMARY KEY, info VARCHAR(100));
INSERT INTO orders VALUES (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),
    (10,'j'),(11,'k'),(12,'l'),(15,'o');

CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount DECIMAL(10,2));
```

## 使用 LAG/LEAD 查找数值间隙


```sql
SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders)
WHERE next_id - id > 1;
```

## 查找日期间隙


```sql
SELECT sale_date, next_date, next_date - sale_date - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) WHERE next_date - sale_date > 1;
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

## 使用 CONNECT BY 生成序列（DamengDB 兼容 Oracle）


```sql
SELECT lvl AS missing_id
FROM (
    SELECT LEVEL + (SELECT MIN(id) - 1 FROM orders) AS lvl
    FROM DUAL
    CONNECT BY LEVEL <= (SELECT MAX(id) - MIN(id) + 1 FROM orders)
) seq
LEFT JOIN orders o ON o.id = seq.lvl
WHERE o.id IS NULL ORDER BY lvl;
```

## 递归 CTE 方法

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

注意：DamengDB 兼容 Oracle 语法，支持 CONNECT BY
注意：DamengDB 同时支持递归 CTE
注意：DamengDB 日期相减返回天数差值
注意：DamengDB 完整支持 LAG/LEAD 分析函数
