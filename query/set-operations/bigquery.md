# BigQuery: 集合操作

> 参考资料:
> - [1] Google BigQuery Documentation - Set Operators
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#set_operators
> - [2] Google BigQuery Documentation - Query Syntax
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax


## UNION / UNION ALL

```sql
SELECT id, name FROM `project.dataset.employees`
UNION DISTINCT
SELECT id, name FROM `project.dataset.contractors`;

SELECT id, name FROM `project.dataset.employees`
UNION ALL
SELECT id, name FROM `project.dataset.contractors`;

```

 注意：BigQuery 推荐使用 UNION DISTINCT 而非 UNION

## INTERSECT

```sql
SELECT id FROM `project.dataset.employees`
INTERSECT DISTINCT
SELECT id FROM `project.dataset.project_members`;

```

 注意：BigQuery 不支持 INTERSECT ALL

## EXCEPT

```sql
SELECT id FROM `project.dataset.employees`
EXCEPT DISTINCT
SELECT id FROM `project.dataset.terminated_employees`;

```

 注意：BigQuery 不支持 EXCEPT ALL

## 嵌套与组合集合操作

支持括号控制优先级

```sql
(SELECT id FROM `project.dataset.employees`
 UNION ALL
 SELECT id FROM `project.dataset.contractors`)
INTERSECT DISTINCT
SELECT id FROM `project.dataset.project_members`;

```

## ORDER BY 与集合操作

```sql
SELECT name, salary FROM `project.dataset.employees`
UNION ALL
SELECT name, salary FROM `project.dataset.contractors`
ORDER BY salary DESC;

```

## LIMIT 与集合操作

```sql
SELECT name FROM `project.dataset.employees`
UNION ALL
SELECT name FROM `project.dataset.contractors`
ORDER BY name
LIMIT 10;

```

LIMIT + OFFSET

```sql
SELECT name FROM `project.dataset.employees`
UNION ALL
SELECT name FROM `project.dataset.contractors`
ORDER BY name
LIMIT 10 OFFSET 20;

```

## 与 CTE 结合

```sql
WITH active_emp AS (
    SELECT id, name FROM `project.dataset.employees` WHERE active = TRUE
)
SELECT id, name FROM active_emp
UNION ALL
SELECT id, name FROM `project.dataset.contractors`;

```

## CORRESPONDING（BigQuery 不支持）

 BigQuery 要求所有 SELECT 列数和类型严格匹配

## 注意事项

BigQuery 要求使用 UNION DISTINCT / EXCEPT DISTINCT / INTERSECT DISTINCT
不支持 ALL 变体的 INTERSECT ALL 和 EXCEPT ALL
STRUCT / ARRAY 类型可用于集合操作（会按值比较）

