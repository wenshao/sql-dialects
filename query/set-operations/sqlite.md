# SQLite: 集合运算

> 参考资料:
> - [SQLite Documentation - Compound Select Statements](https://www.sqlite.org/lang_select.html#compound_select_statements)
> - [SQLite Documentation - SELECT](https://www.sqlite.org/lang_select.html)

## UNION / UNION ALL

```sql
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;
```

## INTERSECT

```sql
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;
```

注意：SQLite 不支持 INTERSECT ALL
替代方案
```sql
SELECT e.id FROM employees e
INNER JOIN project_members p ON e.id = p.id;
```

## EXCEPT

```sql
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;
```

注意：SQLite 不支持 EXCEPT ALL
替代方案
```sql
SELECT id FROM employees
WHERE id NOT IN (SELECT id FROM terminated_employees);
```

## 嵌套与组合集合操作

优先级：INTERSECT > UNION = EXCEPT（按出现顺序）
SQLite 不支持括号包裹 SELECT 来控制优先级
可用子查询替代
```sql
SELECT * FROM (
    SELECT id FROM employees
    UNION
    SELECT id FROM contractors
)
INTERSECT
SELECT id FROM project_members;
```

## ORDER BY 与集合操作

ORDER BY 只能出现在最后，作用于整个结果集
```sql
SELECT name, salary FROM employees
UNION ALL
SELECT name, salary FROM contractors
ORDER BY salary DESC;
```

## LIMIT 与集合操作

```sql
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10;
```

LIMIT + OFFSET
```sql
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10 OFFSET 20;
```

## 与 CTE 结合（3.8.3+）

```sql
WITH active AS (
    SELECT id, name FROM employees WHERE active = 1
)
SELECT id, name FROM active
UNION
SELECT id, name FROM contractors;
```

## VALUES 作为集合操作的一部分（3.8.3+）

```sql
SELECT 'Alice' AS name
UNION ALL
SELECT 'Bob'
UNION ALL
SELECT 'Charlie';
```

## 注意事项

SQLite 的类型系统灵活，集合操作中类型转换很宽松
不支持 INTERSECT ALL 和 EXCEPT ALL
集合操作中不支持 FOR UPDATE（SQLite 不支持行级锁）
