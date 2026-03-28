# Firebird: PIVOT / UNPIVOT

> 参考资料:
> - [Firebird Documentation - SELECT](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html#fblangref40-dml-select)
> - [Firebird Documentation - Aggregate Functions](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html#fblangref40-aggfuncs)


注意：Firebird 没有原生 PIVOT / UNPIVOT 语法
使用 CASE WHEN + GROUP BY 实现 PIVOT
使用 UNION ALL 实现 UNPIVOT


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

## DECODE 函数（Firebird 版本）

```sql
SELECT
    product,
    SUM(DECODE(quarter, 'Q1', amount, 0)) AS Q1,
    SUM(DECODE(quarter, 'Q2', amount, 0)) AS Q2,
    SUM(DECODE(quarter, 'Q3', amount, 0)) AS Q3,
    SUM(DECODE(quarter, 'Q4', amount, 0)) AS Q4
FROM sales
GROUP BY product;
```

## FILTER 子句（3.0+）

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

## UNPIVOT: UNION ALL

```sql
SELECT product, 'Q1' AS quarter, Q1 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q2' AS quarter, Q2 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q3' AS quarter, Q3 AS amount FROM quarterly_sales
UNION ALL
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales;
```

## 动态 PIVOT（EXECUTE STATEMENT）

## 使用 EXECUTE BLOCK + EXECUTE STATEMENT

```sql
EXECUTE BLOCK RETURNS (product VARCHAR(100), Q1 NUMERIC(18,2), Q2 NUMERIC(18,2))
AS
DECLARE sql_text VARCHAR(4000);
BEGIN
    sql_text = 'SELECT product, '
        || 'SUM(CASE WHEN quarter = ''Q1'' THEN amount ELSE 0 END),'
        || 'SUM(CASE WHEN quarter = ''Q2'' THEN amount ELSE 0 END) '
        || 'FROM sales GROUP BY product';
    FOR EXECUTE STATEMENT sql_text INTO product, Q1, Q2 DO
        SUSPEND;
END;
```

## 注意事项

Firebird 没有原生 PIVOT/UNPIVOT 语法
FILTER 子句从 3.0 开始支持
DECODE 函数可简化条件表达式
动态 PIVOT 可通过 EXECUTE BLOCK 实现
BLOB 列不能用于 GROUP BY
