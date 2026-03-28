# Impala: 集合操作

> 参考资料:
> - [Impala Documentation - UNION](https://impala.apache.org/docs/build/html/topics/impala_union.html)
> - [Impala Documentation - SELECT](https://impala.apache.org/docs/build/html/topics/impala_select.html)


## UNION / UNION ALL

```sql
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;
```


UNION DISTINCT
```sql
SELECT id, name FROM employees
UNION DISTINCT
SELECT id, name FROM contractors;
```


## INTERSECT（4.4+）

注意：Impala 4.4 之前不支持 INTERSECT
```sql
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;
```


### 4.4 之前的替代方案

```sql
SELECT DISTINCT e.id FROM employees e
INNER JOIN project_members p ON e.id = p.id;
```


## EXCEPT / MINUS（4.4+）

注意：Impala 4.4 之前不支持 EXCEPT
```sql
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;
```


MINUS 作为别名
```sql
SELECT id FROM employees
MINUS
SELECT id FROM terminated_employees;
```


### 4.4 之前的替代方案

```sql
SELECT e.id FROM employees e
LEFT ANTI JOIN terminated_employees t ON e.id = t.id;
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

INTERSECT 和 EXCEPT/MINUS 从 4.4 开始支持
不支持 INTERSECT ALL 和 EXCEPT ALL
可使用 LEFT ANTI JOIN 替代 EXCEPT
Impala 的 UNION 去重使用哈希或排序
