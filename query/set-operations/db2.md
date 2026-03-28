# DB2: 集合操作

> 参考资料:
> - [IBM DB2 Documentation - Fullselect](https://www.ibm.com/docs/en/db2/11.5?topic=queries-fullselect)
> - [IBM DB2 Documentation - UNION, EXCEPT, INTERSECT](https://www.ibm.com/docs/en/db2/11.5?topic=statements-select)


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

## 嵌套与组合集合操作

## INTERSECT 优先级高于 UNION 和 EXCEPT

使用括号控制优先级

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

## FETCH FIRST 与集合操作

```sql
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
FETCH FIRST 10 ROWS ONLY;
```

## OFFSET + FETCH（DB2 11.1+）

```sql
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;
```

## VALUES 与集合操作

```sql
VALUES ('Alice'), ('Bob')
UNION ALL
SELECT name FROM employees;
```

## 注意事项

DB2 完整支持 SQL 标准的 ALL 变体
LONG VARCHAR / BLOB / CLOB 有使用限制
隐式类型转换规则严格，建议显式 CAST
集合操作中的列名取自第一个查询
