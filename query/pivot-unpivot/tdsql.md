# TDSQL: PIVOT / UNPIVOT

> 参考资料:
> - [TDSQL Documentation](https://cloud.tencent.com/document/product/557)
> - [TDSQL for MySQL Documentation](https://cloud.tencent.com/document/product/557/7700)


注意：TDSQL 兼容 MySQL，没有原生 PIVOT / UNPIVOT 语法
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

## IF 函数

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

## 动态 PIVOT（Prepared Statement）

```sql
SET @sql = NULL;
SELECT GROUP_CONCAT(DISTINCT
    CONCAT('SUM(IF(quarter = ''', quarter, ''', amount, 0)) AS `', quarter, '`')
) INTO @sql
FROM sales;

SET @sql = CONCAT('SELECT product, ', @sql, ' FROM sales GROUP BY product');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
```

## 注意事项

TDSQL 兼容 MySQL，没有原生 PIVOT/UNPIVOT
CASE WHEN 和 IF() 是行转列的标准方法
动态 PIVOT 需要 Prepared Statement
分布式模式下聚合可能触发跨分片操作
