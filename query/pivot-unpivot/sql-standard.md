# SQL 标准: PIVOT / UNPIVOT 行列转换

> 参考资料:
> - [ISO/IEC 9075-2:2023 - SQL/Foundation](https://www.iso.org/standard/76584.html)
> - [Wikipedia - Pivot Table](https://en.wikipedia.org/wiki/Pivot_table)

## 注意：SQL 标准中没有 PIVOT / UNPIVOT 关键字

各数据库的实现差异巨大
以下是使用标准 SQL 实现的通用方法

## PIVOT: 行转列（CASE WHEN + GROUP BY 标准方法）

示例：将销售数据按季度转为列
原始数据: (product, quarter, amount)
目标: product | Q1 | Q2 | Q3 | Q4

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

使用 FILTER 子句（SQL:2003+，部分数据库支持）
```sql
SELECT
    product,
    SUM(amount) FILTER (WHERE quarter = 'Q1') AS Q1,
    SUM(amount) FILTER (WHERE quarter = 'Q2') AS Q2,
    SUM(amount) FILTER (WHERE quarter = 'Q3') AS Q3,
    SUM(amount) FILTER (WHERE quarter = 'Q4') AS Q4
FROM sales
GROUP BY product;
```

多列聚合的 PIVOT
```sql
SELECT
    department,
    COUNT(CASE WHEN gender = 'M' THEN 1 END) AS male_count,
    COUNT(CASE WHEN gender = 'F' THEN 1 END) AS female_count,
    AVG(CASE WHEN gender = 'M' THEN salary END) AS male_avg_salary,
    AVG(CASE WHEN gender = 'F' THEN salary END) AS female_avg_salary
FROM employees
GROUP BY department;
```

## UNPIVOT: 列转行（UNION ALL 标准方法）

示例：将季度列转回行
原始数据: (product, Q1, Q2, Q3, Q4)
目标: product | quarter | amount

```sql
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2' AS quarter, Q2 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q3' AS quarter, Q3 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales
ORDER BY product, quarter;
```

使用 VALUES 子句（SQL:2008+）配合 CROSS JOIN
```sql
SELECT s.product, v.quarter,
    CASE v.quarter
        WHEN 'Q1' THEN s.Q1
        WHEN 'Q2' THEN s.Q2
        WHEN 'Q3' THEN s.Q3
        WHEN 'Q4' THEN s.Q4
    END AS amount
FROM quarterly_sales s
CROSS JOIN (VALUES ('Q1'), ('Q2'), ('Q3'), ('Q4')) AS v(quarter);
```

## 动态 PIVOT

SQL 标准不支持动态 PIVOT
需要在应用层动态生成 SQL 语句
或使用各数据库的动态 SQL / 存储过程功能

## 注意事项

PIVOT/UNPIVOT 不是 SQL 标准的一部分
CASE WHEN + GROUP BY 是最通用的行转列方法
UNION ALL 是最通用的列转行方法
动态 PIVOT（列数不确定）无法用纯 SQL 标准实现
