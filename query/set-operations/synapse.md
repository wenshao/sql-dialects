# Azure Synapse Analytics: 集合操作

> 参考资料:
> - [Microsoft Docs - Synapse SQL Set Operators](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)
> - [Microsoft Docs - SELECT (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/queries/select-transact-sql)
> - [Microsoft Docs - EXCEPT and INTERSECT](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/set-operators-except-and-intersect-transact-sql)


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


注意：不支持 INTERSECT ALL

## EXCEPT

```sql
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;
```


注意：不支持 EXCEPT ALL

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


## TOP / OFFSET-FETCH 与集合操作

```sql
SELECT TOP 10 * FROM (
    SELECT name FROM employees
    UNION ALL
    SELECT name FROM contractors
) AS combined
ORDER BY name;
```


OFFSET-FETCH
```sql
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;
```


## 跨外部表集合操作（无服务器 SQL 池）

```sql
SELECT * FROM OPENROWSET(BULK 'path1/*.parquet', FORMAT='PARQUET') AS r1
UNION ALL
SELECT * FROM OPENROWSET(BULK 'path2/*.parquet', FORMAT='PARQUET') AS r2;
```


## 注意事项

兼容 SQL Server T-SQL 语法
不支持 INTERSECT ALL 和 EXCEPT ALL
专用 SQL 池中集合操作可能触发数据移动（Data Movement）
建议根据分布键优化以减少数据移动
