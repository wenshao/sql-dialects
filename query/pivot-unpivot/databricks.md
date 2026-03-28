# Databricks: PIVOT / UNPIVOT

> 参考资料:
> - [Databricks SQL Reference - PIVOT](https://docs.databricks.com/en/sql/language-manual/sql-ref-syntax-qry-select-pivot.html)
> - [Databricks SQL Reference - UNPIVOT](https://docs.databricks.com/en/sql/language-manual/sql-ref-syntax-qry-select-unpivot.html)


## PIVOT: 原生语法

基本 PIVOT
```sql
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount)
    FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4')
);
```


多聚合
```sql
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount) AS total,
    AVG(amount) AS average
    FOR quarter IN ('Q1' AS Q1, 'Q2' AS Q2, 'Q3' AS Q3, 'Q4' AS Q4)
);
```


自动推断 PIVOT 值（不指定 IN 子句中的值）
```sql
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount)
    FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4')
);
```


## PIVOT: CASE WHEN 替代方法

```sql
SELECT
    product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS Q4
FROM sales
GROUP BY product;
```


## UNPIVOT: 原生语法（Databricks Runtime 12.0+）

```sql
SELECT * FROM quarterly_sales
UNPIVOT (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);
```


INCLUDE NULLS
```sql
SELECT * FROM quarterly_sales
UNPIVOT INCLUDE NULLS (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);
```


多值 UNPIVOT
```sql
SELECT * FROM employee_contacts
UNPIVOT (
    (phone, email)
    FOR contact_type IN (
        (home_phone, home_email) AS 'Home',
        (work_phone, work_email) AS 'Work'
    )
);
```


## UNPIVOT: stack 函数替代方法

```sql
SELECT product, quarter, amount
FROM quarterly_sales
LATERAL VIEW stack(4,
    'Q1', Q1,
    'Q2', Q2,
    'Q3', Q3,
    'Q4', Q4
) AS quarter, amount;
```


## UNPIVOT: UNION ALL 替代方法

```sql
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2' AS quarter, Q2 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q3' AS quarter, Q3 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales;
```


## 注意事项

Databricks 继承 Spark SQL 的 PIVOT 支持
UNPIVOT 从 Databricks Runtime 12.0 开始原生支持
stack() 函数是 UNPIVOT 的传统替代方案
PIVOT 支持多聚合函数
UNPIVOT 默认排除 NULL 行
