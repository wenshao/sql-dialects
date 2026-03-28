# Firebird: 集合操作

> 参考资料:
> - [Firebird Documentation - SELECT](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html#fblangref40-dml-select)
> - [Firebird Documentation - Set Operators](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html#fblangref40-dml-select-union)
> - ============================================================
> - UNION / UNION ALL（全版本支持）
> - ============================================================

```sql
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;
```

## UNION DISTINCT（3.0+）

```sql
SELECT id, name FROM employees
UNION DISTINCT
SELECT id, name FROM contractors;
```

## INTERSECT（2.0+）

```sql
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;
```

## INTERSECT DISTINCT（3.0+）

```sql
SELECT id FROM employees
INTERSECT DISTINCT
SELECT id FROM project_members;
```

## 注意：Firebird 不支持 INTERSECT ALL

## EXCEPT（2.0+）

```sql
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;
```

## 注意：Firebird 不支持 EXCEPT ALL

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

## FIRST / SKIP 与集合操作

## Firebird 使用 FIRST/SKIP 而非 LIMIT/OFFSET

```sql
SELECT FIRST 10 * FROM (
    SELECT name FROM employees
    UNION ALL
    SELECT name FROM contractors
    ORDER BY name
);
```

## ROWS 语法（2.0+）

```sql
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
ROWS 1 TO 10;
```

## FETCH FIRST（4.0+）

```sql
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
FETCH FIRST 10 ROWS ONLY;
```

## OFFSET + FETCH（4.0+）

```sql
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;
```

## 注意事项

INTERSECT 和 EXCEPT 从 2.0 版本开始支持
不支持 ALL 变体（INTERSECT ALL / EXCEPT ALL）
BLOB 列不能用于 UNION DISTINCT（需要 UNION ALL）
Firebird 4.0 引入了标准的 OFFSET-FETCH 语法
