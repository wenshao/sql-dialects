# Azure Synapse Analytics: 层次查询与树形结构 (Hierarchical Query & Tree Traversal)

> 参考资料:
> - [Synapse SQL Documentation - T-SQL Reference](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)


## 准备数据


```sql
CREATE TABLE employees (id INT, name NVARCHAR(100), parent_id INT, dept NVARCHAR(100));
```


## 1. 多层自连接（Synapse 专用 SQL 池不支持递归 CTE）


```sql
SELECT e1.name AS level_0, e2.name AS level_1,
       e3.name AS level_2, e4.name AS level_3
FROM employees e1
LEFT JOIN employees e2 ON e2.parent_id = e1.id
LEFT JOIN employees e3 ON e3.parent_id = e2.id
LEFT JOIN employees e4 ON e4.parent_id = e3.id
WHERE e1.parent_id IS NULL;
```


## 2. 路径枚举模型


```sql
CREATE TABLE categories (id INT, name NVARCHAR(100), path NVARCHAR(500));
SELECT * FROM categories WHERE path LIKE '1/2%';
SELECT *, LEN(path) - LEN(REPLACE(path, '/', '')) AS depth FROM categories;
```


## 3. Serverless SQL Pool（支持递归 CTE）


Synapse Serverless SQL Pool 支持递归 CTE
WITH RECURSIVE org_tree AS (
SELECT id, name, parent_id, 0 AS level
FROM employees WHERE parent_id IS NULL
UNION ALL
SELECT e.id, e.name, e.parent_id, t.level + 1
FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SELECT * FROM org_tree;

## 4-6. 替代方案


使用 CTAS 迭代构建层次
第1次：INSERT INTO tree_result SELECT ... WHERE parent_id IS NULL;
第2次：INSERT INTO tree_result SELECT ... JOIN tree_result ...;

注意：Synapse 专用 SQL 池不支持递归 CTE
注意：Synapse Serverless SQL 池支持递归 CTE
注意：推荐使用路径枚举模型
注意：可以使用 Synapse Pipeline 进行迭代 ETL
