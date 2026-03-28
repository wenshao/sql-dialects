# MySQL: PIVOT/UNPIVOT

> 参考资料:
> - [MySQL 8.0 Reference Manual - GROUP BY](https://dev.mysql.com/doc/refman/8.0/en/group-by-modifiers.html)
> - [MySQL 8.0 Reference Manual - Flow Control Functions](https://dev.mysql.com/doc/refman/8.0/en/flow-control-functions.html)
> - [MySQL 8.0 Reference Manual - Prepared Statements](https://dev.mysql.com/doc/refman/8.0/en/sql-prepared-statements.html)

## 注意：MySQL 没有原生 PIVOT / UNPIVOT 语法

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

使用 IF 函数（MySQL 特有）
```sql
SELECT
    product,
    SUM(IF(quarter = 'Q1', amount, 0)) AS Q1,
    SUM(IF(quarter = 'Q2', amount, 0)) AS Q2,
    SUM(IF(quarter = 'Q3', amount, 0)) AS Q3,
    SUM(IF(quarter = 'Q4', amount, 0)) AS Q4
FROM sales
GROUP BY product;
```

COUNT + CASE
```sql
SELECT
    department,
    COUNT(CASE WHEN gender = 'M' THEN 1 END) AS male_count,
    COUNT(CASE WHEN gender = 'F' THEN 1 END) AS female_count
FROM employees
GROUP BY department;
```

## PIVOT: GROUP_CONCAT 生成逗号分隔值

```sql
SELECT
    product,
    GROUP_CONCAT(CASE WHEN quarter = 'Q1' THEN amount END) AS Q1_values
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
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales
ORDER BY product, quarter;
```

## UNPIVOT: CROSS JOIN + 生成行号（8.0+ CTE）

```sql
WITH quarters AS (
    SELECT 'Q1' AS quarter, 1 AS qn
    UNION ALL SELECT 'Q2', 2
    UNION ALL SELECT 'Q3', 3
    UNION ALL SELECT 'Q4', 4
)
SELECT
    s.product,
    q.quarter,
    CASE q.quarter
        WHEN 'Q1' THEN s.Q1
        WHEN 'Q2' THEN s.Q2
        WHEN 'Q3' THEN s.Q3
        WHEN 'Q4' THEN s.Q4
    END AS amount
FROM quarterly_sales s
CROSS JOIN quarters q
ORDER BY s.product, q.qn;
```

## 动态 PIVOT（Prepared Statement）

动态构建列
```sql
SET @sql = NULL;
SELECT GROUP_CONCAT(DISTINCT
    CONCAT('SUM(CASE WHEN quarter = ''', quarter, ''' THEN amount ELSE 0 END) AS `', quarter, '`')
) INTO @sql
FROM sales;

SET @sql = CONCAT('SELECT product, ', @sql, ' FROM sales GROUP BY product');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
```

## 动态 UNPIVOT（Prepared Statement）

假设列名在 INFORMATION_SCHEMA 中查询
```sql
SET @sql = NULL;
SELECT GROUP_CONCAT(
    CONCAT('SELECT product, ''', COLUMN_NAME, ''' AS quarter, `', COLUMN_NAME, '` AS amount FROM quarterly_sales')
    SEPARATOR ' UNION ALL '
) INTO @sql
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'quarterly_sales'
  AND COLUMN_NAME IN ('Q1', 'Q2', 'Q3', 'Q4');

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
```

## 注意事项

MySQL 没有原生 PIVOT/UNPIVOT 语法
CASE WHEN + GROUP BY 是标准行转列方法
IF() 函数比 CASE WHEN 更简洁但可读性稍差
动态 PIVOT 需要 Prepared Statement
GROUP_CONCAT 默认最大长度 1024，可通过 group_concat_max_len 调整
