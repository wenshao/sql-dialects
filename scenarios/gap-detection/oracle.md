# Oracle: 间隙检测

> 参考资料:
> - [Oracle SQL Language Reference - Analytic Functions](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Analytic-Functions.html)

## 准备数据

```sql
CREATE TABLE orders (id NUMBER(10) PRIMARY KEY, info VARCHAR2(100));
INSERT ALL
    INTO orders VALUES (1, 'a') INTO orders VALUES (2, 'b')
    INTO orders VALUES (3, 'c') INTO orders VALUES (5, 'e')
    INTO orders VALUES (6, 'f') INTO orders VALUES (10, 'j')
    INTO orders VALUES (11, 'k') INTO orders VALUES (12, 'l')
    INTO orders VALUES (15, 'o')
SELECT 1 FROM DUAL;

CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount NUMBER(10,2));
INSERT ALL
    INTO daily_sales VALUES (DATE '2024-01-01', 100)
    INTO daily_sales VALUES (DATE '2024-01-02', 150)
    INTO daily_sales VALUES (DATE '2024-01-04', 200)
    INTO daily_sales VALUES (DATE '2024-01-05', 120)
    INTO daily_sales VALUES (DATE '2024-01-08', 300)
SELECT 1 FROM DUAL;
```

## LAG/LEAD 查找间隙

```sql
SELECT id AS gap_start_after, next_id AS gap_end_before,
       next_id - id - 1 AS gap_size
FROM (SELECT id, LEAD(id) OVER (ORDER BY id) AS next_id FROM orders)
WHERE next_id - id > 1;
```

日期间隙
```sql
SELECT sale_date AS last_date, next_date,
       next_date - sale_date - 1 AS missing_days
FROM (
    SELECT sale_date, LEAD(sale_date) OVER (ORDER BY sale_date) AS next_date
    FROM daily_sales
) WHERE next_date - sale_date > 1;
```

Oracle 的优势: DATE 相减直接得到天数（无需 DATEDIFF 函数）

## 岛屿问题: 找出连续范围

Tabibitosan 方法（id - ROW_NUMBER 产生分组标识）
```sql
SELECT MIN(id) AS island_start, MAX(id) AS island_end,
       COUNT(*) AS island_size
FROM (
    SELECT id, id - ROW_NUMBER() OVER (ORDER BY id) AS grp
    FROM orders
) GROUP BY grp ORDER BY island_start;
```

设计分析:
  Tabibitosan（旅人算法）利用了"连续数列中值-序号恒定"的数学性质。
  id: 1,2,3,5,6,10,11,12,15
  rn: 1,2,3,4,5,6,7,8,9
  差: 0,0,0,1,1,4,4,4,6  → 相同差值的行属于同一个"岛屿"

## CONNECT BY LEVEL 生成序列找缺失值（Oracle 独有）

生成完整序列，与实际数据 LEFT JOIN 找缺失
```sql
SELECT lvl AS missing_id
FROM (
    SELECT LEVEL + (SELECT MIN(id) - 1 FROM orders) AS lvl
    FROM DUAL
    CONNECT BY LEVEL <= (SELECT MAX(id) - MIN(id) + 1 FROM orders)
) seq
LEFT JOIN orders o ON o.id = seq.lvl
WHERE o.id IS NULL
ORDER BY lvl;
```

日期序列找缺失日期（MINUS 集合操作）
```sql
SELECT (SELECT MIN(sale_date) FROM daily_sales) + LEVEL - 1 AS missing_date
FROM DUAL
CONNECT BY LEVEL <= (SELECT MAX(sale_date) - MIN(sale_date) + 1 FROM daily_sales)
MINUS
SELECT sale_date FROM daily_sales
ORDER BY 1;
```

## 递归 CTE 方法（11g R2+）

```sql
WITH seq (n) AS (
    SELECT MIN(id) FROM orders
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < (SELECT MAX(id) FROM orders)
)
SELECT s.n AS missing_id
FROM seq s LEFT JOIN orders o ON o.id = s.n
WHERE o.id IS NULL ORDER BY s.n;
```

## 自连接方法（兼容 Oracle 8i+）

```sql
SELECT a.id + 1 AS gap_start, MIN(b.id) - 1 AS gap_end
FROM orders a JOIN orders b ON b.id > a.id
GROUP BY a.id
HAVING MIN(b.id) > a.id + 1
ORDER BY gap_start;
```

## 对引擎开发者的总结

1. LAG/LEAD 是间隙检测的标准方法（Oracle 8i 首创）。
2. Tabibitosan（id - ROW_NUMBER）是岛屿问题的经典解法。
3. CONNECT BY LEVEL 生成序列是 Oracle 独有的技巧。
4. DATE 相减直接得到天数是 Oracle 的便利设计，简化了日期间隙检测。
5. MINUS 集合操作（Oracle 特有关键字）可以简洁地找出缺失值。
