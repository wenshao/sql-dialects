# CockroachDB: 集合操作

> 参考资料:
> - [CockroachDB Documentation - Selection Queries](https://www.cockroachlabs.com/docs/stable/selection-queries)
> - [CockroachDB Documentation - Set Operations](https://www.cockroachlabs.com/docs/stable/selection-queries#set-operations)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

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

CockroachDB 兼容 PostgreSQL 语法，完整支持所有集合操作
支持 ALL 变体
在分布式环境中，集合操作可能需要跨节点数据传输
类型转换规则与 PostgreSQL 一致
