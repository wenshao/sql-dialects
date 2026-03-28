# SQLite: PIVOT/UNPIVOT

> 参考资料:
> - [SQLite Documentation - Aggregate Functions](https://www.sqlite.org/lang_aggfunc.html)
> - [SQLite Documentation - SELECT](https://www.sqlite.org/lang_select.html)

## 注意：SQLite 没有原生 PIVOT / UNPIVOT 语法

使用 CASE WHEN + GROUP BY 实现 PIVOT
使用 UNION ALL 实现 UNPIVOT

## 

## PIVOT: CASE WHEN + GROUP BY

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

COUNT 版本
```sql
SELECT
    department,
    COUNT(CASE WHEN status = 'active' THEN 1 END) AS active,
    COUNT(CASE WHEN status = 'inactive' THEN 1 END) AS inactive
FROM employees
GROUP BY department;
```

GROUP_CONCAT 用于非数值行转列
```sql
SELECT
    department,
    GROUP_CONCAT(CASE WHEN role = 'manager' THEN name END) AS managers,
    GROUP_CONCAT(CASE WHEN role = 'developer' THEN name END) AS developers
FROM employees
GROUP BY department;
```

## UNPIVOT: UNION ALL

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

过滤 NULL 值
```sql
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales WHERE Q1 IS NOT NULL
UNION ALL
SELECT product, 'Q2' AS quarter, Q2 AS amount FROM quarterly_sales WHERE Q2 IS NOT NULL
UNION ALL
SELECT product, 'Q3' AS quarter, Q3 AS amount FROM quarterly_sales WHERE Q3 IS NOT NULL
UNION ALL
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales WHERE Q4 IS NOT NULL
ORDER BY product, quarter;
```

## UNPIVOT: JSON 方法（3.38.0+）

使用 json_each 配合 json_object
```sql
SELECT
    s.product,
    j.key AS quarter,
    j.value AS amount
FROM quarterly_sales s,
    json_each(json_object('Q1', s.Q1, 'Q2', s.Q2, 'Q3', s.Q3, 'Q4', s.Q4)) j;
```

## 动态 PIVOT

SQLite 不支持动态 SQL
需要在应用层（Python/Java 等）动态生成 SQL 语句
示例（Python 伪代码）：
quarters = cursor.execute("SELECT DISTINCT quarter FROM sales").fetchall()
cols = ", ".join(f"SUM(CASE WHEN quarter='{q}' THEN amount ELSE 0 END) AS {q}" for q in quarters)
cursor.execute(f"SELECT product, {cols} FROM sales GROUP BY product")

## 注意事项

SQLite 没有原生 PIVOT/UNPIVOT 语法
CASE WHEN + GROUP BY 是唯一的 PIVOT 方法
UNION ALL 是标准的 UNPIVOT 方法
3.38.0+ 可用 json_each 做 UNPIVOT
动态 PIVOT 必须在应用层实现
SQLite 的类型系统灵活，CASE WHEN 中类型不严格
