# StarRocks: 集合操作

> 参考资料:
> - [1] StarRocks Documentation - Set Operations
>   https://docs.starrocks.io/docs/sql-reference/sql-statements/


```sql
SELECT id, name FROM employees UNION SELECT id, name FROM contractors;
SELECT id, name FROM employees UNION ALL SELECT id, name FROM contractors;
SELECT id FROM employees INTERSECT SELECT id FROM project_members;
SELECT id FROM employees EXCEPT SELECT id FROM terminated;
SELECT id FROM employees MINUS SELECT id FROM terminated;

(SELECT id FROM employees UNION SELECT id FROM contractors)
INTERSECT SELECT id FROM project_members;

SELECT name FROM employees UNION ALL SELECT name FROM contractors ORDER BY name LIMIT 10;

```

与 Doris 完全相同(同源)。不支持 ALL 变体。

