# SQL Server: 间隙检测

> 参考资料:
> - Itzik Ben-Gan - Gaps and Islands（T-SQL 经典）
> - [SQL Server - Window Functions](https://learn.microsoft.com/en-us/sql/t-sql/queries/select-over-clause-transact-sql)

## 准备数据

```sql
CREATE TABLE orders (id INT PRIMARY KEY, info NVARCHAR(100));
INSERT INTO orders VALUES
    (1,'a'),(2,'b'),(3,'c'),(5,'e'),(6,'f'),(10,'j'),(11,'k'),(12,'l'),(15,'o');
```

## LAG/LEAD 查找间隙（2012+）

```sql
SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders) t
WHERE next_id - id > 1;
```

## 岛屿问题: id - ROW_NUMBER() 分组法

核心思想: 连续的 id 减去连续的 ROW_NUMBER 得到相同的常数
```sql
SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders) t
GROUP BY grp ORDER BY island_start;
```

结果: (1,3,3), (5,6,2), (10,12,3), (15,15,1)

设计分析（对引擎开发者）:
  id - ROW_NUMBER() 法是 Itzik Ben-Gan 提出的经典算法。
  原理: 对连续序列，id 和 ROW_NUMBER 同步增长，差值恒定。
  断点处 id 跳跃但 ROW_NUMBER 不跳，差值改变 → 新的分组。
  这是一个纯数学技巧——不需要自连接，O(n log n) 时间复杂度（排序）。

## 日期间隙与日期岛屿

```sql
CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount DECIMAL(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),('2024-01-10',180);
```

日期间隙
```sql
SELECT sale_date AS last_date, next_date,
       DATEDIFF(DAY, sale_date, next_date) - 1 AS missing_days
FROM (SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
      FROM daily_sales) t
WHERE DATEDIFF(DAY, sale_date, next_date) > 1;
```

日期岛屿
```sql
SELECT MIN(sale_date) AS start_date, MAX(sale_date) AS end_date, COUNT(*) AS days
FROM (SELECT sale_date,
             DATEADD(DAY, -ROW_NUMBER() OVER (ORDER BY sale_date), sale_date) AS grp
      FROM daily_sales) t
GROUP BY grp ORDER BY start_date;
```

## 自连接方法（兼容 SQL Server 2005）

```sql
SELECT a.id + 1 AS gap_start, MIN(b.id) - 1 AS gap_end
FROM orders a INNER JOIN orders b ON b.id > a.id
GROUP BY a.id HAVING MIN(b.id) > a.id + 1
ORDER BY gap_start;
```

## 递归 CTE 生成完整序列（找缺失值）

```sql
;WITH seq AS (
    SELECT MIN(id) AS n FROM orders
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < (SELECT MAX(id) FROM orders)
)
SELECT s.n AS missing_id FROM seq s
LEFT JOIN orders o ON o.id = s.n
WHERE o.id IS NULL ORDER BY s.n
OPTION (MAXRECURSION 10000);
```

## Itzik Ben-Gan 经典方法总结

间隙 (Gaps): ROW_NUMBER 对齐法
```sql
;WITH C AS (SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM orders)
SELECT cur.id + 1 AS gap_start, nxt.id - 1 AS gap_end
FROM C cur JOIN C nxt ON nxt.rn = cur.rn + 1
WHERE nxt.id - cur.id > 1;
```

岛屿 (Islands): id - ROW_NUMBER 分组法
```sql
;WITH C AS (SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders)
SELECT MIN(id) AS start_val, MAX(id) AS end_val, COUNT(*) AS size
FROM C GROUP BY grp ORDER BY start_val;
```

对引擎开发者的启示:
  Gaps and Islands 是窗口函数的经典应用场景。
  SQL Server 社区（尤其是 Itzik Ben-Gan）在这个领域贡献了大量算法。
  引擎的窗口函数实现必须高效——这些查询在实际业务中非常常见。
