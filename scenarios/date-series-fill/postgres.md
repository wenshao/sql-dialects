# PostgreSQL: 日期序列填充

> 参考资料:
> - [PostgreSQL Documentation - generate_series](https://www.postgresql.org/docs/current/functions-srf.html)

## generate_series: PostgreSQL 的序列生成利器

日期序列
```sql
SELECT d::DATE FROM generate_series('2024-01-01'::DATE, '2024-01-10'::DATE, '1 day') AS t(d);
```

月序列
```sql
SELECT d::DATE FROM generate_series('2024-01-01'::DATE, '2024-12-01'::DATE, '1 month') AS t(d);
```

小时序列
```sql
SELECT d FROM generate_series(
    '2024-01-01 00:00'::TIMESTAMP, '2024-01-01 23:00'::TIMESTAMP, '1 hour'
) AS t(d);
```

设计分析: generate_series 是 Set-Returning Function (SRF)
  在 FROM 子句中使用，每次调用返回多行。
  内部: 迭代器模式，不一次性生成所有行（内存可控）。
  对比其他数据库:
    MySQL:      无等价函数（需递归CTE: WITH RECURSIVE ... UNION ALL）
    Oracle:     CONNECT BY LEVEL（递归层级查询）
    SQL Server: 递归CTE 或 master.dbo.spt_values
    BigQuery:   GENERATE_DATE_ARRAY() + UNNEST()
    ClickHouse: arrayJoin(range(N))

## LEFT JOIN 填充缺失日期（核心模式）

```sql
SELECT d::DATE AS date, COALESCE(ds.amount, 0) AS amount
FROM generate_series('2024-01-01'::DATE, '2024-01-10'::DATE, '1 day') AS t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
ORDER BY d;
```

加累计和
```sql
SELECT d::DATE AS date, COALESCE(ds.amount, 0) AS amount,
       SUM(COALESCE(ds.amount, 0)) OVER (ORDER BY d) AS running_total
FROM generate_series('2024-01-01'::DATE, '2024-01-10'::DATE, '1 day') AS t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE;
```

## 用最近已知值填充（LAST_VALUE IGNORE NULLS 模拟）

PostgreSQL 不直接支持 IGNORE NULLS，需要模拟
方法: COUNT 窗口函数标记分组，再取每组第一个非 NULL 值
```sql
WITH filled AS (
    SELECT d::DATE AS date, ds.amount,
           COUNT(ds.amount) OVER (ORDER BY d) AS grp
    FROM generate_series('2024-01-01'::DATE, '2024-01-10'::DATE, '1 day') AS t(d)
    LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
)
SELECT date, FIRST_VALUE(amount) OVER (PARTITION BY grp ORDER BY date) AS filled_amount
FROM filled ORDER BY date;
```

对比:
  Oracle:     LAST_VALUE(amount IGNORE NULLS) OVER (ORDER BY date)（一行搞定）
  BigQuery:   LAST_VALUE(amount IGNORE NULLS) OVER (ORDER BY date)
  PostgreSQL: 不支持 IGNORE NULLS（需要上述模拟技巧）

## 动态日期范围（从数据中获取）

```sql
SELECT d::DATE, COALESCE(ds.amount, 0)
FROM generate_series(
    (SELECT MIN(sale_date) FROM daily_sales),
    (SELECT MAX(sale_date) FROM daily_sales), '1 day'
) AS t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE;
```

## 多维度填充（类别 x 日期 交叉）

```sql
SELECT d::DATE AS date, c.category, COALESCE(cs.amount, 0) AS amount
FROM generate_series('2024-01-01'::DATE, '2024-01-04'::DATE, '1 day') AS t(d)
CROSS JOIN (SELECT DISTINCT category FROM category_sales) c
LEFT JOIN category_sales cs ON cs.sale_date = t.d::DATE AND cs.category = c.category
ORDER BY c.category, d;
```

## 横向对比与对引擎开发者的启示

generate_series 是 PostgreSQL 独有的优势:
  (a) 不需要辅助"数字表"或"日历表"
  (b) 支持 DATE, TIMESTAMP, INTEGER, NUMERIC 类型
  (c) 迭代器模式，内存消耗可控
  新引擎应考虑内置类似的 SRF（Set-Returning Function）机制。

缺少 IGNORE NULLS 是 PostgreSQL 的已知短板:
  社区多次讨论但未纳入核心。
  workaround（COUNT分组法）虽然可行但不直观。
  新引擎建议直接支持 IGNORE NULLS（窗口函数选项）。
