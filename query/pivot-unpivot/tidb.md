# TiDB: 行列转换

> 参考资料:
> - [TiDB Documentation - SELECT](https://docs.pingcap.com/tidb/stable/sql-statement-select)
> - [TiDB Documentation - Control Flow Functions](https://docs.pingcap.com/tidb/stable/control-flow-functions)
> - [TiDB Documentation - Aggregate Functions](https://docs.pingcap.com/tidb/stable/aggregate-group-by-functions)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

## 注意：TiDB 没有原生 PIVOT / UNPIVOT 语法

兼容 MySQL，使用 CASE WHEN + GROUP BY / IF 实现
PIVOT: CASE WHEN + GROUP BY
```sql
    product,
    SUM(CASE WHEN quarter = 'Q1' THEN amount ELSE 0 END) AS Q1,
    SUM(CASE WHEN quarter = 'Q2' THEN amount ELSE 0 END) AS Q2,
    SUM(CASE WHEN quarter = 'Q3' THEN amount ELSE 0 END) AS Q3,
    SUM(CASE WHEN quarter = 'Q4' THEN amount ELSE 0 END) AS Q4
FROM sales
GROUP BY product;

```

IF 函数
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

GROUP_CONCAT
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
SELECT product, 'Q4' AS quarter, Q4 AS amount FROM quarterly_sales;

```

## UNPIVOT: CTE + CROSS JOIN

```sql
WITH quarters AS (
    SELECT 'Q1' AS quarter UNION ALL
    SELECT 'Q2' UNION ALL
    SELECT 'Q3' UNION ALL
    SELECT 'Q4'
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
CROSS JOIN quarters q;

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

TiDB 兼容 MySQL，没有原生 PIVOT/UNPIVOT
CASE WHEN 和 IF() 是标准行转列方法
分布式架构下聚合可能触发跨节点计算
动态 PIVOT 需要 Prepared Statement
TiFlash 列存引擎可加速 PIVOT 聚合查询
