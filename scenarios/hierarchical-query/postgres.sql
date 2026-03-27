-- PostgreSQL: 层次查询与树形结构 (Hierarchical Query & Tree Traversal)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - WITH Queries (Common Table Expressions)
--       https://www.postgresql.org/docs/current/queries-with.html
--   [2] PostgreSQL Documentation - ltree extension
--       https://www.postgresql.org/docs/current/ltree.html

-- ============================================================
-- 准备数据：组织架构表（邻接表模型）
-- ============================================================

CREATE TABLE employees (
    id        SERIAL PRIMARY KEY,
    name      VARCHAR(100) NOT NULL,
    parent_id INTEGER REFERENCES employees(id),
    dept      VARCHAR(100)
);
INSERT INTO employees (id, name, parent_id, dept) VALUES
    (1, 'CEO',        NULL, '总裁办'),
    (2, 'CTO',        1,    '技术部'),
    (3, 'CFO',        1,    '财务部'),
    (4, 'VP工程',     2,    '技术部'),
    (5, 'VP产品',     2,    '技术部'),
    (6, '开发经理',   4,    '技术部'),
    (7, '测试经理',   4,    '技术部'),
    (8, '开发工程师A', 6,   '技术部'),
    (9, '开发工程师B', 6,   '技术部'),
    (10,'测试工程师',  7,   '技术部'),
    (11,'会计主管',    3,   '财务部'),
    (12,'出纳',        11,  '财务部');

-- ============================================================
-- 1. 递归 CTE —— 标准方法（PostgreSQL 8.4+）
-- ============================================================

-- 从根节点向下遍历（自顶向下）
WITH RECURSIVE org_tree AS (
    -- 锚定成员：根节点
    SELECT id, name, parent_id, dept,
           0 AS level,
           name::TEXT AS path
    FROM employees
    WHERE parent_id IS NULL

    UNION ALL

    -- 递归成员：子节点
    SELECT e.id, e.name, e.parent_id, e.dept,
           t.level + 1,
           t.path || ' > ' || e.name
    FROM employees e
    JOIN org_tree t ON e.parent_id = t.id
)
SELECT id, REPEAT('  ', level) || name AS indented_name,
       level, path
FROM org_tree
ORDER BY path;

-- 从指定节点向上遍历（找到某人的所有上级）
WITH RECURSIVE ancestors AS (
    SELECT id, name, parent_id, 0 AS level
    FROM employees
    WHERE name = '开发工程师A'

    UNION ALL

    SELECT e.id, e.name, e.parent_id, a.level + 1
    FROM employees e
    JOIN ancestors a ON e.id = a.parent_id
)
SELECT * FROM ancestors;

-- ============================================================
-- 2. 深度优先 vs 广度优先遍历（PostgreSQL 14+）
-- ============================================================

-- 深度优先遍历（PostgreSQL 14+ SEARCH 子句）
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, 0 AS level
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SEARCH DEPTH FIRST BY name SET ordercol
SELECT id, REPEAT('  ', level) || name AS indented_name, level
FROM org_tree
ORDER BY ordercol;

-- 广度优先遍历
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, 0 AS level
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SEARCH BREADTH FIRST BY name SET ordercol
SELECT id, name, level
FROM org_tree
ORDER BY ordercol;

-- 兼容旧版本的深度优先（手动构造排序路径）
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, 0 AS level,
           ARRAY[id] AS sort_path
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1,
           t.sort_path || e.id
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SELECT id, REPEAT('  ', level) || name AS indented_name, level
FROM org_tree
ORDER BY sort_path;

-- ============================================================
-- 3. 循环检测（PostgreSQL 14+）
-- ============================================================

-- PostgreSQL 14+ 内置 CYCLE 子句
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, 0 AS level
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
CYCLE id SET is_cycle USING cycle_path
SELECT * FROM org_tree WHERE NOT is_cycle;

-- 兼容旧版本的循环检测
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, 0 AS level,
           ARRAY[id] AS visited,
           FALSE AS is_cycle
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1,
           t.visited || e.id,
           e.id = ANY(t.visited)
    FROM employees e
    JOIN org_tree t ON e.parent_id = t.id
    WHERE NOT t.is_cycle
)
SELECT id, name, level FROM org_tree WHERE NOT is_cycle;

-- ============================================================
-- 4. 路径枚举模型（物化路径）
-- ============================================================

CREATE TABLE categories (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(100),
    path TEXT  -- 例如 '1/2/4/6'
);
INSERT INTO categories (id, name, path) VALUES
    (1, '电子产品', '1'),
    (2, '手机',     '1/2'),
    (3, '电脑',     '1/3'),
    (4, '苹果手机', '1/2/4'),
    (5, '安卓手机', '1/2/5'),
    (6, '笔记本',   '1/3/6');

-- 查询某个节点的所有子孙
SELECT * FROM categories WHERE path LIKE '1/2%';

-- 查询某个节点的所有祖先
SELECT * FROM categories
WHERE '1/2/4' LIKE path || '%'
ORDER BY LENGTH(path);

-- 查询深度
SELECT *, LENGTH(path) - LENGTH(REPLACE(path, '/', '')) AS depth
FROM categories;

-- ============================================================
-- 5. ltree 扩展（PostgreSQL 特有）
-- ============================================================

CREATE EXTENSION IF NOT EXISTS ltree;

CREATE TABLE categories_ltree (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(100),
    path ltree
);
INSERT INTO categories_ltree (id, name, path) VALUES
    (1, '电子产品', 'root'),
    (2, '手机',     'root.phone'),
    (3, '电脑',     'root.computer'),
    (4, '苹果手机', 'root.phone.apple'),
    (5, '安卓手机', 'root.phone.android'),
    (6, '笔记本',   'root.computer.laptop');

-- ltree 操作
SELECT * FROM categories_ltree WHERE path <@ 'root.phone';     -- 子孙
SELECT * FROM categories_ltree WHERE path @> 'root.phone';     -- 祖先
SELECT *, nlevel(path) AS depth FROM categories_ltree;          -- 深度

-- ============================================================
-- 6. 子树聚合
-- ============================================================

-- 统计每个经理下属人数（递归）
WITH RECURSIVE subordinates AS (
    SELECT id, name, parent_id FROM employees
    UNION ALL
    SELECT e.id, e.name, e.parent_id
    FROM employees e JOIN subordinates s ON e.parent_id = s.id
)
SELECT e.id, e.name,
       (SELECT COUNT(*) - 1 FROM subordinates WHERE id IN (
           WITH RECURSIVE sub AS (
               SELECT id FROM employees WHERE id = e.id
               UNION ALL
               SELECT emp.id FROM employees emp JOIN sub ON emp.parent_id = sub.id
           ) SELECT id FROM sub
       )) AS subordinate_count
FROM employees e WHERE e.parent_id IS NULL OR e.id IN (
    SELECT DISTINCT parent_id FROM employees WHERE parent_id IS NOT NULL
);

-- 简化版：统计子树大小
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

-- 注意：递归 CTE 需要 PostgreSQL 8.4+
-- 注意：SEARCH DEPTH/BREADTH FIRST 和 CYCLE 子句需要 PostgreSQL 14+
-- 注意：ltree 扩展需要单独安装（CREATE EXTENSION ltree）
-- 注意：递归 CTE 的性能取决于树的深度和宽度
-- 注意：物化路径模型适合读多写少的场景
