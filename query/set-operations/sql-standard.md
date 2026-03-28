# SQL 标准: 集合操作

> 参考资料:
> - [ISO/IEC 9075-2:2023 - SQL/Foundation](https://www.iso.org/standard/76584.html)
> - [SQL:2023 Standard - Set Operations](https://en.wikipedia.org/wiki/Set_operations_(SQL))

## UNION: 合并结果集并去重

```sql
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;
```

## UNION ALL: 合并结果集保留重复

```sql
SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;
```

## INTERSECT: 交集（SQL:1992+）

```sql
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;
```

INTERSECT ALL: 保留重复的交集（SQL:2003+）
```sql
SELECT id FROM employees
INTERSECT ALL
SELECT id FROM project_members;
```

## EXCEPT: 差集（SQL:1992+）

```sql
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;
```

EXCEPT ALL: 保留重复的差集（SQL:2003+）
```sql
SELECT id FROM employees
EXCEPT ALL
SELECT id FROM terminated_employees;
```

## 嵌套与组合集合操作

优先级：INTERSECT > UNION = EXCEPT
可使用括号明确优先级
```sql
(SELECT id FROM employees
 UNION
 SELECT id FROM contractors)
INTERSECT
SELECT id FROM project_members;
```

多重组合
```sql
SELECT id FROM table_a
UNION
SELECT id FROM table_b
EXCEPT
SELECT id FROM table_c;
```

## ORDER BY 与集合操作

ORDER BY 只能出现在最后一个查询之后，作用于整个结果集
```sql
SELECT name, 'employee' AS source FROM employees
UNION ALL
SELECT name, 'contractor' AS source FROM contractors
ORDER BY name;
```

## LIMIT / FETCH FIRST 与集合操作（SQL:2008+）

```sql
SELECT name FROM employees
UNION
SELECT name FROM contractors
ORDER BY name
FETCH FIRST 10 ROWS ONLY;
```

OFFSET + FETCH
```sql
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;
```

## 列数和类型匹配规则

所有集合操作要求：
1. 各查询的列数必须相同
2. 对应列的数据类型必须兼容
3. 结果列名取自第一个查询
