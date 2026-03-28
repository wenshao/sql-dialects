# Amazon Redshift: 集合操作

> 参考资料:
> - [Amazon Redshift Documentation - UNION, INTERSECT, EXCEPT](https://docs.aws.amazon.com/redshift/latest/dg/r_UNION.html)
> - [Amazon Redshift Documentation - INTERSECT](https://docs.aws.amazon.com/redshift/latest/dg/r_INTERSECT.html)
> - [Amazon Redshift Documentation - EXCEPT](https://docs.aws.amazon.com/redshift/latest/dg/r_EXCEPT.html)


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


注意：Redshift 不支持 INTERSECT ALL

## EXCEPT / MINUS

Redshift 同时支持 EXCEPT 和 MINUS
```sql
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

SELECT id FROM employees
MINUS
SELECT id FROM terminated_employees;
```


注意：Redshift 不支持 EXCEPT ALL / MINUS ALL

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


## 注意事项

Redshift 不支持 INTERSECT ALL 和 EXCEPT ALL
MINUS 是 EXCEPT 的别名
集合操作结果受 Redshift 分布键影响，可能需要数据重分布
SUPER 类型列不能用于 UNION
