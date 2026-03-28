# Vertica: 集合操作

> 参考资料:
> - [Vertica Documentation - UNION, INTERSECT, EXCEPT/MINUS](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Statements/SELECT/UNIONClause.htm)
> - [Vertica Documentation - SELECT](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Statements/SELECT/SELECT.htm)


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


注意：Vertica 不支持 INTERSECT ALL

## EXCEPT / MINUS

Vertica 同时支持 EXCEPT 和 MINUS
```sql
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

SELECT id FROM employees
MINUS
SELECT id FROM terminated_employees;
```


注意：Vertica 不支持 EXCEPT ALL

## 嵌套与组合集合操作

```sql
(SELECT id FROM employees
 UNION
 SELECT id FROM contractors)
INTERSECT
SELECT id FROM project_members;
```


## ORDER BY 与集合操作

```sql
SELECT name, salary FROM employees
UNION ALL
SELECT name, salary FROM contractors
ORDER BY salary DESC;
```


## LIMIT / OFFSET 与集合操作

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


## 注意事项

Vertica 不支持 INTERSECT ALL 和 EXCEPT ALL
MINUS 是 EXCEPT 的别名
作为列存储数据库，UNION ALL 性能优于 UNION
集合操作中的投影（projections）选择由优化器决定
