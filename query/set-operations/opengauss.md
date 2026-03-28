# openGauss: 集合操作

> 参考资料:
> - [openGauss Documentation - UNION / INTERSECT / EXCEPT](https://docs.opengauss.org/en/docs/latest/docs/SQLReference/UNION-INTERSECT-EXCEPT-MINUS.html)
> - [openGauss Documentation - SELECT](https://docs.opengauss.org/en/docs/latest/docs/SQLReference/SELECT.html)


## UNION / UNION ALL

```sql
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;
```

## INTERSECT / INTERSECT ALL

```sql
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

SELECT id FROM employees
INTERSECT ALL
SELECT id FROM project_members;
```

## EXCEPT / EXCEPT ALL

```sql
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

SELECT id FROM employees
EXCEPT ALL
SELECT id FROM terminated_employees;
```

## MINUS 作为 EXCEPT 的别名

```sql
SELECT id FROM employees
MINUS
SELECT id FROM terminated_employees;
```

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

SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10 OFFSET 20;
```

## 注意事项

openGauss 兼容 PostgreSQL，完整支持所有集合操作
同时支持 EXCEPT 和 MINUS
支持所有 ALL 变体
分布式部署下集合操作可能需要数据重分布
