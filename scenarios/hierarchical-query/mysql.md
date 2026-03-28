# MySQL: 层次查询

> 参考资料:
> - [MySQL Reference Manual - WITH (CTE)](https://dev.mysql.com/doc/refman/8.0/en/with.html)
> - [MySQL Reference Manual - Recursive CTEs](https://dev.mysql.com/doc/refman/8.0/en/with.html#common-table-expressions-recursive)

## 准备数据

```sql
CREATE TABLE employees (
    id        INT PRIMARY KEY AUTO_INCREMENT,
    name      VARCHAR(100) NOT NULL,
    parent_id INT,
    dept      VARCHAR(100),
    FOREIGN KEY (parent_id) REFERENCES employees(id)
);
INSERT INTO employees (id, name, parent_id, dept) VALUES
    (1,'CEO',NULL,'总裁办'),(2,'CTO',1,'技术部'),(3,'CFO',1,'财务部'),
    (4,'VP工程',2,'技术部'),(5,'VP产品',2,'技术部'),
    (6,'开发经理',4,'技术部'),(7,'测试经理',4,'技术部'),
    (8,'开发工程师A',6,'技术部'),(9,'开发工程师B',6,'技术部'),
    (10,'测试工程师',7,'技术部'),(11,'会计主管',3,'财务部'),
    (12,'出纳',11,'财务部');
```

## 递归 CTE（MySQL 8.0+）

自顶向下遍历
```sql
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, dept,
           0 AS level,
           CAST(name AS CHAR(1000)) AS path
    FROM employees
    WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, e.dept,
           t.level + 1,
           CONCAT(t.path, ' > ', e.name)
    FROM employees e
    JOIN org_tree t ON e.parent_id = t.id
)
SELECT id, CONCAT(REPEAT('  ', level), name) AS indented_name,
       level, path
FROM org_tree
ORDER BY path;
```

自底向上遍历
```sql
WITH RECURSIVE ancestors AS (
    SELECT id, name, parent_id, 0 AS level
    FROM employees WHERE name = '开发工程师A'
    UNION ALL
    SELECT e.id, e.name, e.parent_id, a.level + 1
    FROM employees e JOIN ancestors a ON e.id = a.parent_id
)
SELECT * FROM ancestors;
```

## 深度优先遍历（手动构造排序路径）

```sql
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, 0 AS level,
           CAST(LPAD(id, 5, '0') AS CHAR(1000)) AS sort_path
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1,
           CONCAT(t.sort_path, '/', LPAD(e.id, 5, '0'))
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SELECT id, CONCAT(REPEAT('  ', level), name) AS indented_name, level
FROM org_tree ORDER BY sort_path;
```

广度优先遍历
```sql
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, 0 AS level
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SELECT * FROM org_tree ORDER BY level, name;
```

## 循环检测

```sql
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, 0 AS level,
           CAST(id AS CHAR(1000)) AS visited_ids
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1,
           CONCAT(t.visited_ids, ',', e.id)
    FROM employees e
    JOIN org_tree t ON e.parent_id = t.id
    WHERE FIND_IN_SET(e.id, t.visited_ids) = 0
)
SELECT * FROM org_tree;
```

## 路径枚举模型

```sql
CREATE TABLE categories (
    id   INT PRIMARY KEY,
    name VARCHAR(100),
    path VARCHAR(500)
);
INSERT INTO categories VALUES
    (1,'电子产品','1'),(2,'手机','1/2'),(3,'电脑','1/3'),
    (4,'苹果手机','1/2/4'),(5,'安卓手机','1/2/5'),
    (6,'笔记本','1/3/6');

SELECT * FROM categories WHERE path LIKE '1/2%';
SELECT *, LENGTH(path) - LENGTH(REPLACE(path, '/', '')) AS depth FROM categories;
```

## MySQL 5.x 替代方案（无递归 CTE）

使用多次自连接（固定深度）
```sql
SELECT
    e1.name AS level_0,
    e2.name AS level_1,
    e3.name AS level_2,
    e4.name AS level_3
FROM employees e1
LEFT JOIN employees e2 ON e2.parent_id = e1.id
LEFT JOIN employees e3 ON e3.parent_id = e2.id
LEFT JOIN employees e4 ON e4.parent_id = e3.id
WHERE e1.parent_id IS NULL;
```

## 子树聚合

```sql
WITH RECURSIVE tree AS (
    SELECT id, name, parent_id, id AS root_id
    FROM employees
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.root_id
    FROM employees e JOIN tree t ON e.parent_id = t.id
)
SELECT root_id, e.name, COUNT(*) - 1 AS subordinate_count
FROM tree t JOIN employees e ON t.root_id = e.id
GROUP BY root_id, e.name
ORDER BY subordinate_count DESC;
```

注意：递归 CTE 需要 MySQL 8.0+
注意：MySQL 默认递归深度 1000（cte_max_recursion_depth）
注意：MySQL 5.x 只能用多层 JOIN 或应用层实现层次查询
注意：MySQL 不支持 CONNECT BY
注意：路径字符串拼接使用 CONCAT 函数
