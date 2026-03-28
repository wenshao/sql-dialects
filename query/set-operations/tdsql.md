# TDSQL: 集合操作

> 参考资料:
> - [TDSQL Documentation](https://cloud.tencent.com/document/product/557)
> - [TDSQL for MySQL Documentation](https://cloud.tencent.com/document/product/557/7700)


## UNION / UNION ALL

```sql
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;
```

## UNION DISTINCT

```sql
SELECT id, name FROM employees
UNION DISTINCT
SELECT id, name FROM contractors;
```

## INTERSECT（兼容版本依赖底层引擎）

## TDSQL for MySQL 兼容 MySQL 8.0.31+ 语法

```sql
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;
```

## 替代方案（适用于旧版本）

```sql
SELECT DISTINCT e.id FROM employees e
INNER JOIN project_members p ON e.id = p.id;
```

## EXCEPT（兼容版本依赖底层引擎）

```sql
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;
```

## 替代方案

```sql
SELECT e.id FROM employees e
LEFT JOIN terminated_employees t ON e.id = t.id
WHERE t.id IS NULL;
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

SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10 OFFSET 20;
```

## 注意事项

TDSQL 兼容 MySQL 语法
INTERSECT/EXCEPT 支持取决于底层 MySQL 版本
分布式模式下 UNION 可能触发跨分片操作
建议优先使用 UNION ALL 以获得更好性能
