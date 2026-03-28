# SQL Server: 层次查询

> 参考资料:
> - [SQL Server - Recursive CTEs](https://learn.microsoft.com/en-us/sql/t-sql/queries/with-common-table-expression-transact-sql)

## 准备数据

```sql
CREATE TABLE employees (
    id INT PRIMARY KEY, name NVARCHAR(100) NOT NULL,
    parent_id INT REFERENCES employees(id), dept NVARCHAR(100)
);
INSERT INTO employees VALUES
    (1,'CEO',NULL,'exec'),(2,'CTO',1,'tech'),(3,'CFO',1,'finance'),
    (4,'VP Eng',2,'tech'),(5,'VP Product',2,'tech'),
    (6,'Dev Manager',4,'tech'),(7,'QA Manager',4,'tech'),
    (8,'Dev A',6,'tech'),(9,'Dev B',6,'tech'),
    (10,'QA',7,'tech'),(11,'Accountant',3,'finance');
```

## 递归 CTE: 自顶向下遍历

```sql
;WITH org_tree AS (
    SELECT id, name, parent_id, 0 AS level,
           CAST(name AS NVARCHAR(MAX)) AS path
    FROM employees WHERE parent_id IS NULL      -- 锚成员
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1,
           t.path + N' > ' + e.name
    FROM employees e JOIN org_tree t ON e.parent_id = t.id  -- 递归成员
)
SELECT REPLICATE('  ', level) + name AS indented_name, level, path
FROM org_tree ORDER BY path;
```

设计分析（对引擎开发者）:
  SQL Server 使用标准递归 CTE（不需要 RECURSIVE 关键字）。
  Oracle 有独有的 CONNECT BY 语法，但 SQL Server 不支持它。
  深度优先遍历需要手动构造 path 列来排序。

  SQL:2011 引入了 SEARCH DEPTH FIRST 和 SEARCH BREADTH FIRST 子句:
  PostgreSQL 14+ 支持，SQL Server 至今不支持。

## 自底向上遍历（找上级链）

```sql
;WITH ancestors AS (
    SELECT id, name, parent_id, 0 AS level
    FROM employees WHERE name = N'Dev A'
    UNION ALL
    SELECT e.id, e.name, e.parent_id, a.level + 1
    FROM employees e JOIN ancestors a ON e.id = a.parent_id
)
SELECT * FROM ancestors;  -- Dev A → Dev Manager → VP Eng → CTO → CEO
```

## 深度优先 vs 广度优先

深度优先: ORDER BY 手动构造的 sort_path
```sql
;WITH org_tree AS (
    SELECT id, name, parent_id, 0 AS level,
           CAST(RIGHT('000' + CAST(id AS VARCHAR), 4) AS NVARCHAR(MAX)) AS sort_path
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1,
           t.sort_path + N'/' + RIGHT('000' + CAST(e.id AS VARCHAR), 4)
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SELECT REPLICATE('  ', level) + name AS tree, level FROM org_tree ORDER BY sort_path;
```

广度优先: ORDER BY level, name
```sql
;WITH org_tree AS (
    SELECT id, name, parent_id, 0 AS level FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SELECT * FROM org_tree ORDER BY level, name;
```

## 循环检测（SQL Server 不支持 CYCLE 子句）

PostgreSQL 14+ 有 CYCLE 子句自动检测循环。
SQL Server 必须手动实现:
```sql
;WITH org_tree AS (
    SELECT id, name, parent_id, 0 AS level,
           CAST(CONCAT('/', id, '/') AS NVARCHAR(MAX)) AS visited
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1,
           CAST(t.visited + CAST(e.id AS NVARCHAR) + '/' AS NVARCHAR(MAX))
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
    WHERE t.visited NOT LIKE '%/' + CAST(e.id AS NVARCHAR) + '/%'  -- 检测循环
      AND t.level < 100  -- 安全限制
)
SELECT * FROM org_tree;
```

## 子树聚合

```sql
;WITH tree AS (
    SELECT id, name, parent_id, id AS root_id FROM employees
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.root_id
    FROM employees e JOIN tree t ON e.parent_id = t.id
)
SELECT root_id, e.name, COUNT(*) - 1 AS subordinates
FROM tree t JOIN employees e ON t.root_id = e.id
GROUP BY root_id, e.name
HAVING COUNT(*) > 1 ORDER BY subordinates DESC;
```

## 路径枚举模型（物化路径）

```sql
CREATE TABLE categories (id INT PRIMARY KEY, name NVARCHAR(100), path NVARCHAR(500));
```

查询子孙: WHERE path LIKE '1/2/%'
查询深度: LEN(path) - LEN(REPLACE(path, '/', ''))
优势: 不需要递归，查询简单
劣势: 维护困难（移动节点需要更新所有后代的 path）

横向对比:
  Oracle:      CONNECT BY PRIOR（最简洁的层次查询语法）
  PostgreSQL:  WITH RECURSIVE + SEARCH DEPTH FIRST（14+, 最标准）
  SQL Server:  WITH（无 RECURSIVE 关键字，无 SEARCH/CYCLE 子句）
  MySQL:       WITH RECURSIVE（8.0+）
  ClickHouse:  不支持递归 CTE（必须用应用层递归）
