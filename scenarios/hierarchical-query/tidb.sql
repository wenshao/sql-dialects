-- TiDB: 层次查询与树形结构 (Hierarchical Query & Tree Traversal)
--
-- 参考资料:
--   [1] TiDB Documentation - CTE
--       https://docs.pingcap.com/tidb/stable/sql-statement-with
--   [2] TiDB Documentation - Recursive CTE
--       https://docs.pingcap.com/tidb/stable/sql-statement-with#recursive-cte

-- ============================================================
-- 准备数据：组织架构表（邻接表模型）
-- ============================================================

CREATE TABLE employees (
    id        INT PRIMARY KEY,
    name      VARCHAR(100) NOT NULL,
    parent_id INT, FOREIGN KEY (parent_id) REFERENCES employees(id),
    dept      VARCHAR(100)
);
INSERT INTO employees (id, name, parent_id, dept) VALUES
    (1,'CEO',NULL,'总裁办'),(2,'CTO',1,'技术部'),(3,'CFO',1,'财务部'),
    (4,'VP工程',2,'技术部'),(5,'VP产品',2,'技术部'),
    (6,'开发经理',4,'技术部'),(7,'测试经理',4,'技术部'),
    (8,'开发工程师A',6,'技术部'),(9,'开发工程师B',6,'技术部'),
    (10,'测试工程师',7,'技术部'),(11,'会计主管',3,'财务部'),
    (12,'出纳',11,'财务部');

-- ============================================================
-- 1. 递归 CTE —— 标准方法
-- ============================================================

-- 自顶向下遍历
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, dept,
           0 AS level,
           CAST(name AS CHAR(1000)) AS path
    FROM employees
    WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, e.dept,
           t.level + 1,
           t.path || ' > ' || e.name
    FROM employees e
    JOIN org_tree t ON e.parent_id = t.id
)
SELECT id, REPEAT('  ', level) || name AS indented_name, level, path
FROM org_tree
ORDER BY path;

-- 自底向上遍历（找上级链）
WITH RECURSIVE ancestors AS (
    SELECT id, name, parent_id, 0 AS level
    FROM employees WHERE name = '开发工程师A'
    UNION ALL
    SELECT e.id, e.name, e.parent_id, a.level + 1
    FROM employees e JOIN ancestors a ON e.id = a.parent_id
)
SELECT * FROM ancestors;

-- ============================================================
-- 2. 深度优先 vs 广度优先遍历
-- ============================================================

-- 深度优先（手动构造排序路径）
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, 0 AS level,
           CAST(name AS CHAR(1000)) AS sort_path
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1,
           t.sort_path || ' > ' || e.name
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SELECT id, REPEAT('  ', level) || name AS indented_name, level
FROM org_tree ORDER BY sort_path;

-- 广度优先（按 level 排序）
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, 0 AS level
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SELECT * FROM org_tree ORDER BY level, name;

-- ============================================================
-- 3. 循环检测
-- ============================================================

-- 使用深度限制防止无限递归
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, 0 AS level
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
    WHERE t.level < 100  -- 深度限制
)
SELECT * FROM org_tree;

-- ============================================================
-- 4. 路径枚举模型（物化路径）
-- ============================================================

CREATE TABLE categories (
    id   INT PRIMARY KEY,
    name VARCHAR(100),
    path VARCHAR(100)
);

-- 查询子孙节点
SELECT * FROM categories WHERE path LIKE '1/2%';

-- 查询深度
SELECT *, LENGTH(path) - LENGTH(REPLACE(path, '/', '')) AS depth
FROM categories;

-- ============================================================
-- 5. 多层自连接方法（适用于不支持递归 CTE 的引擎）
-- ============================================================

-- 固定深度查询（最多4层）
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

-- ============================================================
-- 6. 子树聚合
-- ============================================================

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

-- 注意：TiDB 5.1+ 支持递归 CTE
-- 注意：TiDB 兼容 MySQL 语法
-- 注意：TiDB 不支持 CONNECT BY
-- 注意：分布式环境下递归 CTE 在 TiDB Server 上执行
