# Flink SQL: 行列转换

> 参考资料:
> - [Apache Flink Documentation - Queries](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/overview/)
> - [Apache Flink Documentation - Aggregate Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/#aggregate-functions)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

## 注意：Flink SQL 没有原生 PIVOT / UNPIVOT 语法

使用 CASE WHEN + GROUP BY 实现 PIVOT
使用 UNION ALL 实现 UNPIVOT
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

## UNPIVOT: CROSS JOIN + VALUES（Flink 1.15+）

```sql
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
CROSS JOIN (VALUES ('Q1'), ('Q2'), ('Q3'), ('Q4')) AS q(quarter);

```

## 流处理中的 PIVOT

实时按事件类型聚合（窗口 PIVOT）
```sql
SELECT
    TUMBLE_START(event_time, INTERVAL '1' HOUR) AS window_start,
    SUM(CASE WHEN event_type = 'click' THEN 1 ELSE 0 END) AS clicks,
    SUM(CASE WHEN event_type = 'view' THEN 1 ELSE 0 END) AS views,
    SUM(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS purchases
FROM events
GROUP BY TUMBLE(event_time, INTERVAL '1' HOUR);

```

## 注意事项

Flink SQL 没有原生 PIVOT/UNPIVOT 语法
CASE WHEN + GROUP BY 是标准方法
流处理中 PIVOT 需要与窗口操作结合
UNION ALL 在流模式下需要合并多个流
动态 PIVOT 不可行（流 schema 必须固定）
