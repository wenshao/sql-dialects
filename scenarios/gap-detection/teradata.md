# Teradata: 间隙检测与岛屿问题 (Gap Detection & Islands)

> 参考资料:
> - [Teradata Documentation - Ordered Analytical Functions](https://docs.teradata.com/r/SQL-Functions-Expressions-and-Predicates/Ordered-Analytical-Functions)
> - [Teradata Documentation - sys_calendar](https://docs.teradata.com/r/SQL-Data-Definition-Language/Calendar-Table)


## 准备数据


```sql
CREATE TABLE orders (id INTEGER NOT NULL PRIMARY KEY, info VARCHAR(100));
INSERT INTO orders VALUES (1,'a');INSERT INTO orders VALUES (2,'b');
INSERT INTO orders VALUES (3,'c');INSERT INTO orders VALUES (5,'e');
INSERT INTO orders VALUES (6,'f');INSERT INTO orders VALUES (10,'j');
INSERT INTO orders VALUES (11,'k');INSERT INTO orders VALUES (12,'l');
INSERT INTO orders VALUES (15,'o');

CREATE TABLE daily_sales (sale_date DATE NOT NULL PRIMARY KEY, amount DECIMAL(10,2));
```


## 1. 使用 LAG/LEAD 查找数值间隙


```sql
SELECT id AS gap_start_after, next_id AS gap_end_before, next_id - id - 1 AS gap_size
FROM (
    SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders
) t WHERE next_id - id > 1;
```


## 2. 查找日期间隙


```sql
SELECT sale_date, next_date, next_date - sale_date - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) t WHERE next_date - sale_date > 1;
```


## 3. 岛屿问题


```sql
SELECT MIN(id) AS island_start, MAX(id) AS island_end, COUNT(*) AS island_size
FROM (SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp FROM orders) t
GROUP BY grp ORDER BY island_start;
```


## 4. 自连接方法


```sql
SELECT a.id + 1 AS gap_start, MIN(b.id) - 1 AS gap_end
FROM orders a JOIN orders b ON b.id > a.id
GROUP BY a.id HAVING MIN(b.id) > a.id + 1 ORDER BY gap_start;
```


## 5. 使用 sys_calendar 系统日历表（Teradata 特有）


使用 sys_calendar.calendar 生成日期序列
```sql
SELECT c.calendar_date AS missing_date
FROM sys_calendar.calendar c
WHERE c.calendar_date BETWEEN
    (SELECT MIN(sale_date) FROM daily_sales) AND
    (SELECT MAX(sale_date) FROM daily_sales)
  AND c.calendar_date NOT IN (SELECT sale_date FROM daily_sales)
ORDER BY c.calendar_date;
```


使用递归 CTE 生成数值序列
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


## 6. 综合示例 —— 使用 Teradata 的 QUALIFY 子句


```sql
SELECT id AS gap_start_after,
       LEAD(id) OVER (ORDER BY id) AS gap_end_before,
       LEAD(id) OVER (ORDER BY id) - id - 1 AS gap_size
FROM orders
QUALIFY LEAD(id) OVER (ORDER BY id) - id > 1;
```


注意：Teradata 的 QUALIFY 子句用于过滤窗口函数结果
注意：sys_calendar.calendar 是 Teradata 内置的日历表
注意：Teradata 日期直接相减返回天数差值
注意：Teradata 从 V2R6 开始支持窗口函数
