# Spanner: 行列转换

> 参考资料:
> - [Spanner Documentation - PIVOT](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax#pivot_operator)
> - [Spanner Documentation - UNPIVOT](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax#unpivot_operator)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## PIVOT: 原生语法

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

自定义列别名
```sql
SELECT * FROM (
    SELECT product, quarter, amount
    FROM sales
)
PIVOT (
    SUM(amount)
    FOR quarter IN ('Q1' AS first_q, 'Q2' AS second_q, 'Q3' AS third_q, 'Q4' AS fourth_q)
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
    COUNT(amount) AS cnt
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

## UNPIVOT: 原生语法

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

## UNPIVOT: UNNEST 替代方法

```sql
SELECT
    s.product,
    quarter,
    amount
FROM quarterly_sales s
CROSS JOIN UNNEST([
    STRUCT('Q1' AS quarter, s.Q1 AS amount),
    STRUCT('Q2' AS quarter, s.Q2 AS amount),
    STRUCT('Q3' AS quarter, s.Q3 AS amount),
    STRUCT('Q4' AS quarter, s.Q4 AS amount)
]);

```

## 注意事项

Spanner 使用 GoogleSQL 方言，原生支持 PIVOT/UNPIVOT
语法类似 BigQuery
PIVOT 支持多聚合函数
UNPIVOT 默认排除 NULL 行
UNNEST + STRUCT 是灵活的 UNPIVOT 替代方案
