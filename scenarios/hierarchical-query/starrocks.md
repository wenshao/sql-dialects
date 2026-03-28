# StarRocks: 层级查询

> 参考资料:
> - [1] StarRocks Documentation - Recursive CTE
>   https://docs.starrocks.io/docs/sql-reference/sql-statements/


递归 CTE (与 Doris 相同)

```sql
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, 0 AS level FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SELECT * FROM org_tree;

```

路径枚举和闭包表模型同样适用(与 Doris 相同)。

