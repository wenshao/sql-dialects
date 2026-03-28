# Apache Derby: 间隙检测与岛屿问题 (Gap Detection & Islands)

> 参考资料:
> - [Apache Derby Documentation - Window Functions](https://db.apache.org/derby/docs/10.16/ref/)
> - [Apache Derby Documentation - WITH clause](https://db.apache.org/derby/docs/10.16/ref/rrefsqljwith.html)
> - ============================================================
> - 准备数据
> - ============================================================

```sql
CREATE TABLE orders (id INT NOT NULL PRIMARY KEY, info VARCHAR(100));
INSERT INTO orders VALUES (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),
    (10,'j'),(11,'k'),(12,'l'),(15,'o');

CREATE TABLE daily_sales (sale_date DATE NOT NULL PRIMARY KEY, amount DECIMAL(10,2));
```

## 使用 ROW_NUMBER 查找数值间隙（Derby 10.4+）


## Derby 10.4+ 支持 ROW_NUMBER，但不支持 LAG/LEAD

使用自连接模拟 LEAD

```sql
SELECT a.id AS gap_start_after, MIN(b.id) AS gap_end_before,
       MIN(b.id) - a.id - 1 AS gap_size
FROM orders a JOIN orders b ON b.id > a.id
GROUP BY a.id
HAVING MIN(b.id) > a.id + 1;
```

## 岛屿问题


## 使用 ROW_NUMBER（Derby 10.4+）

```sql
SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders
) t GROUP BY grp ORDER BY 1;
```

## 自连接方法（Derby 全版本兼容）


```sql
SELECT a.id + 1 AS gap_start, MIN(b.id) - 1 AS gap_end
FROM orders a JOIN orders b ON b.id > a.id
GROUP BY a.id HAVING MIN(b.id) > a.id + 1 ORDER BY 1;
```

## 递归 CTE（Derby 10.12+）


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

## 5-6. Derby 的局限性


Derby 不支持 LAG/LEAD 窗口函数
Derby 不支持 generate_series
递归 CTE 从 10.12 版本开始支持
推荐使用自连接方法进行间隙检测
注意：Derby 的窗口函数支持有限（仅 ROW_NUMBER、RANK 等排名函数）
注意：Derby 不支持 LAG/LEAD 分析函数
注意：递归 CTE 需要 Derby 10.12+
注意：自连接方法在所有 Derby 版本中可用
