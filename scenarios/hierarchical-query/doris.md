# Apache Doris: 层级查询

 Apache Doris: 层级查询

 参考资料:
   [1] Doris Documentation - Recursive CTE
       https://doris.apache.org/docs/sql-manual/sql-statements/

## 1. 递归 CTE (2.1+)

```sql
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, 0 AS level FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SELECT * FROM org_tree;

```

## 2. 路径枚举模型 (替代方案)

CREATE TABLE categories (id INT, name VARCHAR(100), path VARCHAR(500));

```sql
SELECT * FROM categories WHERE path LIKE '1/2%';
SELECT *, LENGTH(path) - LENGTH(REPLACE(path, '/', '')) AS depth FROM categories;

```

## 3. 闭包表模型

CREATE TABLE tree_closure (ancestor INT, descendant INT, depth INT);

```sql
SELECT e.* FROM tree_closure tc JOIN employees e ON e.id = tc.descendant
WHERE tc.ancestor = 2 AND tc.depth > 0;

```

对比:
StarRocks: 同样支持递归 CTE
ClickHouse: 不支持递归 CTE(用 arrayJoin 展开)
Oracle:    CONNECT BY(最早的层级查询语法)
MySQL 8.0: 递归 CTE(Doris 兼容)

