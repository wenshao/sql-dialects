-- PostgreSQL: 层次查询与树形结构 (Hierarchical Query)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - WITH RECURSIVE
--       https://www.postgresql.org/docs/current/queries-with.html
--   [2] PostgreSQL Documentation - ltree extension
--       https://www.postgresql.org/docs/current/ltree.html

-- ============================================================
-- 1. 递归 CTE: 标准方法 (8.4+)
-- ============================================================

-- 自顶向下遍历
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, 0 AS level, name::TEXT AS path
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1, t.path || ' > ' || e.name
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SELECT id, REPEAT('  ', level) || name AS indented, level, path
FROM org_tree ORDER BY path;

-- 自底向上（查找祖先链）
WITH RECURSIVE ancestors AS (
    SELECT id, name, parent_id, 0 AS level FROM employees WHERE name = 'Engineer_A'
    UNION ALL
    SELECT e.id, e.name, e.parent_id, a.level + 1
    FROM employees e JOIN ancestors a ON e.id = a.parent_id
)
SELECT * FROM ancestors;

-- ============================================================
-- 2. SEARCH / CYCLE 子句 (14+, SQL 标准)
-- ============================================================

-- 深度优先
WITH RECURSIVE org AS (
    SELECT id, name, parent_id, 0 AS level FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1
    FROM employees e JOIN org t ON e.parent_id = t.id
)
SEARCH DEPTH FIRST BY name SET ordercol
SELECT id, REPEAT('  ', level) || name, level FROM org ORDER BY ordercol;

-- 广度优先
-- SEARCH BREADTH FIRST BY name SET ordercol

-- 循环检测
WITH RECURSIVE org AS (
    SELECT id, name, parent_id FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id FROM employees e JOIN org t ON e.parent_id = t.id
)
CYCLE id SET is_cycle USING cycle_path
SELECT * FROM org WHERE NOT is_cycle;

-- 设计分析: 14 之前的循环检测需要手动维护 ARRAY 路径
-- WITH RECURSIVE tree AS (
--     SELECT id, ARRAY[id] AS visited, FALSE AS cycle ...
--     WHERE NOT e.id = ANY(t.visited)
-- )

-- ============================================================
-- 3. ltree 扩展: 物化路径的高效索引
-- ============================================================

CREATE EXTENSION IF NOT EXISTS ltree;

CREATE TABLE categories_ltree (
    id SERIAL PRIMARY KEY, name VARCHAR(100), path ltree
);
INSERT INTO categories_ltree (name, path) VALUES
    ('Electronics', 'root'),
    ('Phone', 'root.phone'),
    ('Apple', 'root.phone.apple'),
    ('Laptop', 'root.computer.laptop');

SELECT * FROM categories_ltree WHERE path <@ 'root.phone';     -- 子孙
SELECT * FROM categories_ltree WHERE path @> 'root.phone';     -- 祖先
SELECT *, nlevel(path) AS depth FROM categories_ltree;          -- 深度

-- ltree 支持 GiST 索引（高效祖先/子孙查询）
CREATE INDEX idx_path ON categories_ltree USING gist (path);

-- 设计对比:
--   递归 CTE: 通用方法，不需要冗余数据，但每次查询都递归
--   ltree:    物化路径+索引，查询 O(log n)，但写入需维护路径一致性
--   对比 Oracle: CONNECT BY PRIOR（专用语法，不需要 CTE）

-- ============================================================
-- 4. 子树聚合
-- ============================================================

WITH RECURSIVE tree AS (
    SELECT id, name, parent_id, id AS root_id FROM employees
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.root_id
    FROM employees e JOIN tree t ON e.parent_id = t.id
)
SELECT root_id, e.name, COUNT(*) - 1 AS subordinate_count
FROM tree t JOIN employees e ON t.root_id = e.id
GROUP BY root_id, e.name ORDER BY subordinate_count DESC;

-- ============================================================
-- 5. 横向对比与对引擎开发者的启示
-- ============================================================

-- 1. 层次查询语法:
--   PostgreSQL: WITH RECURSIVE (8.4+) + SEARCH/CYCLE (14+)
--   Oracle:     CONNECT BY PRIOR (最早，语法简洁但非标准)
--   MySQL:      WITH RECURSIVE (8.0+, 有 cte_max_recursion_depth 限制)
--   SQL Server: WITH RECURSIVE (2005+, MAXRECURSION 选项)
--
-- 2. 专用扩展:
--   PostgreSQL: ltree 扩展（物化路径+GiST索引）
--   SQL Server: HIERARCHYID 类型
--   Oracle:     CONNECT BY 是内置语法
--
-- 对引擎开发者:
--   递归 CTE 是 SQL 标准方案，所有现代引擎必须支持。
--   SEARCH/CYCLE 子句(14+)让循环检测变成声明式——
--   比手动 ARRAY 路径检测更安全更简洁。
--   ltree 类型展示了 PostgreSQL 可扩展类型的价值——
--   专用类型+专用索引可以将 O(n) 递归变为 O(log n) 索引查找。
