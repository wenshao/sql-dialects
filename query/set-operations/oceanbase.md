# OceanBase: 集合操作

> 参考资料:
> - [OceanBase Documentation - UNION / INTERSECT / EXCEPT](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase Documentation - SELECT](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

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

## INTERSECT（MySQL 模式 4.0+，Oracle 模式全版本）

```sql
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

```

**注意:** INTERSECT ALL 仅 Oracle 模式支持

## EXCEPT / MINUS

MySQL 模式使用 EXCEPT
```sql
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

```

Oracle 模式使用 MINUS
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

## LIMIT 与集合操作

MySQL 模式
```sql
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10;

```

Oracle 模式
```sql
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
FETCH FIRST 10 ROWS ONLY;

```

## 注意事项

OceanBase 支持 MySQL 和 Oracle 两种兼容模式
MySQL 模式使用 EXCEPT，Oracle 模式使用 MINUS
两种模式下 UNION / UNION ALL 语法一致
Oracle 模式支持更完整的集合操作特性
