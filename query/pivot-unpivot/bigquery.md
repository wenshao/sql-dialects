# BigQuery: PIVOT / UNPIVOT（原生支持）

> 参考资料:
> - [1] Google BigQuery Documentation - PIVOT
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#pivot_operator
> - [2] Google BigQuery Documentation - UNPIVOT
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#unpivot_operator
> - [3] Google BigQuery Documentation - Aggregate Functions
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/aggregate_functions


## PIVOT: 原生语法

基本 PIVOT

```sql
SELECT * FROM (
    SELECT product, quarter, amount
    FROM `project.dataset.sales`
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
    FROM `project.dataset.sales`
)
PIVOT (
    SUM(amount) AS total,
    COUNT(amount) AS cnt
    FOR quarter IN ('Q1', 'Q2', 'Q3', 'Q4')
);

```

自定义列别名

```sql
SELECT * FROM (
    SELECT product, quarter, amount
    FROM `project.dataset.sales`
)
PIVOT (
    SUM(amount)
    FOR quarter IN ('Q1' AS first_quarter, 'Q2' AS second_quarter,
                    'Q3' AS third_quarter, 'Q4' AS fourth_quarter)
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
FROM `project.dataset.sales`
GROUP BY product;

```

使用 IF 函数

```sql
SELECT
    product,
    SUM(IF(quarter = 'Q1', amount, 0)) AS Q1,
    SUM(IF(quarter = 'Q2', amount, 0)) AS Q2,
    SUM(IF(quarter = 'Q3', amount, 0)) AS Q3,
    SUM(IF(quarter = 'Q4', amount, 0)) AS Q4
FROM `project.dataset.sales`
GROUP BY product;

```

COUNTIF

```sql
SELECT
    department,
    COUNTIF(status = 'active') AS active_count,
    COUNTIF(status = 'inactive') AS inactive_count
FROM `project.dataset.employees`
GROUP BY department;

```

## UNPIVOT: 原生语法

基本 UNPIVOT

```sql
SELECT * FROM `project.dataset.quarterly_sales`
UNPIVOT (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);

```

INCLUDE NULLS

```sql
SELECT * FROM `project.dataset.quarterly_sales`
UNPIVOT INCLUDE NULLS (
    amount FOR quarter IN (Q1, Q2, Q3, Q4)
);

```

多列 UNPIVOT

```sql
SELECT * FROM `project.dataset.employee_contacts`
UNPIVOT (
    (phone, email) FOR contact_type IN (
        (home_phone, home_email) AS 'home',
        (work_phone, work_email) AS 'work'
    )
);

```

## UNPIVOT: CROSS JOIN + UNNEST 替代方法

```sql
SELECT
    s.product,
    quarter,
    amount
FROM `project.dataset.quarterly_sales` s
CROSS JOIN UNNEST([
    STRUCT('Q1' AS quarter, s.Q1 AS amount),
    STRUCT('Q2' AS quarter, s.Q2 AS amount),
    STRUCT('Q3' AS quarter, s.Q3 AS amount),
    STRUCT('Q4' AS quarter, s.Q4 AS amount)
]);

```

## 动态 PIVOT

BigQuery 不支持动态 SQL
需要在客户端生成 SQL 或使用 EXECUTE IMMEDIATE（脚本模式）

```sql
EXECUTE IMMEDIATE (
    SELECT CONCAT(
        'SELECT product, ',
        STRING_AGG(
            CONCAT('SUM(IF(quarter = ''', quarter, ''', amount, 0)) AS ', quarter),
            ', '
        ),
        ' FROM `project.dataset.sales` GROUP BY product'
    )
    FROM (SELECT DISTINCT quarter FROM `project.dataset.sales` ORDER BY quarter)
);

```

## 注意事项

BigQuery 原生支持 PIVOT 和 UNPIVOT
PIVOT 支持多聚合函数
UNPIVOT 默认排除 NULL 行（使用 INCLUDE NULLS 保留）
CROSS JOIN UNNEST 是 UNPIVOT 的灵活替代方案
动态 PIVOT 可通过 EXECUTE IMMEDIATE 实现（脚本模式）

