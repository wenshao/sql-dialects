# PolarDB: 集合操作

> 参考资料:
> - [PolarDB Documentation](https://www.alibabacloud.com/help/en/polardb/)
> - [PolarDB-X Documentation - SQL Reference](https://www.alibabacloud.com/help/en/polardb/polardb-for-xscale/)


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

## INTERSECT（PolarDB for PostgreSQL 全版本，PolarDB-X 2.0+）

```sql
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;
```

## INTERSECT ALL（PolarDB for PostgreSQL）

```sql
SELECT id FROM employees
INTERSECT ALL
SELECT id FROM project_members;
```

## EXCEPT

```sql
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;
```

## EXCEPT ALL（PolarDB for PostgreSQL）

```sql
SELECT id FROM employees
EXCEPT ALL
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

PolarDB for PostgreSQL 兼容 PostgreSQL，完整支持所有集合操作
PolarDB for MySQL 兼容 MySQL，INTERSECT/EXCEPT 支持取决于版本
PolarDB-X 分布式版本支持基本的集合操作
分布式模式下 UNION 去重可能触发全局排序
