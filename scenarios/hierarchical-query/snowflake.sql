-- Snowflake: 层次查询与树形结构
--
-- 参考资料:
--   [1] Snowflake Documentation - Recursive CTEs
--       https://docs.snowflake.com/en/sql-reference/constructs/with#recursive-cte
--   [2] Snowflake Documentation - CONNECT BY
--       https://docs.snowflake.com/en/sql-reference/constructs/connect-by

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE employees (
    id INT, name VARCHAR(100) NOT NULL, parent_id INT, dept VARCHAR(100));
INSERT INTO employees VALUES
    (1,'CEO',NULL,'总裁办'),(2,'CTO',1,'技术部'),(3,'CFO',1,'财务部'),
    (4,'VP工程',2,'技术部'),(5,'VP产品',2,'技术部'),
    (6,'开发经理',4,'技术部'),(7,'测试经理',4,'技术部'),
    (8,'工程师A',6,'技术部'),(9,'工程师B',6,'技术部'),
    (10,'测试员',7,'技术部'),(11,'会计主管',3,'财务部'),(12,'出纳',11,'财务部');

-- ============================================================
-- 1. 递归 CTE（标准方法）
-- ============================================================

-- 自顶向下遍历
WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, dept, 0 AS level,
           CAST(name AS VARCHAR(1000)) AS path
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, e.dept, t.level + 1,
           t.path || ' > ' || e.name
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SELECT id, REPEAT('  ', level) || name AS indented_name, level, path
FROM org_tree ORDER BY path;

-- 自底向上遍历
WITH RECURSIVE ancestors AS (
    SELECT id, name, parent_id, 0 AS level
    FROM employees WHERE name = '工程师A'
    UNION ALL
    SELECT e.id, e.name, e.parent_id, a.level + 1
    FROM employees e JOIN ancestors a ON e.id = a.parent_id
)
SELECT * FROM ancestors;

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 CONNECT BY: Snowflake 兼容 Oracle 语法
SELECT id, LPAD(' ', 2 * (LEVEL - 1)) || name AS indented_name,
       LEVEL AS depth,
       SYS_CONNECT_BY_PATH(name, ' > ') AS path
FROM employees
START WITH parent_id IS NULL
CONNECT BY PRIOR id = parent_id
ORDER SIBLINGS BY name;

-- CONNECT BY 是 Oracle 独有语法（非 SQL 标准）。
-- Snowflake 是少数同时支持递归 CTE 和 CONNECT BY 的数据库。
-- 对比:
--   Oracle:     CONNECT BY（原创，功能最强）
--   PostgreSQL: 只支持递归 CTE
--   MySQL:      只支持递归 CTE (8.0+)
--   BigQuery:   只支持递归 CTE
--
-- 对引擎开发者的启示:
--   递归 CTE 是 SQL 标准方案，CONNECT BY 是 Oracle 遗产。
--   如果目标是兼容 Oracle 迁移，CONNECT BY 是必要的。
--   否则递归 CTE 足够（PostgreSQL 的选择）。

-- ============================================================
-- 3. 子树聚合
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

-- ============================================================
-- 4. 深度限制（防止无限递归）
-- ============================================================

WITH RECURSIVE org_tree AS (
    SELECT id, name, parent_id, 0 AS level
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.level + 1
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
    WHERE t.level < 100
)
SELECT * FROM org_tree;

-- ============================================================
-- 5. 路径枚举模型（物化路径）
-- ============================================================

CREATE TABLE categories (id INT PRIMARY KEY, name VARCHAR(100), path VARCHAR(100));
SELECT * FROM categories WHERE path LIKE '1/2%';  -- 查询子孙
SELECT *, LENGTH(path) - LENGTH(REPLACE(path, '/', '')) AS depth FROM categories;

-- ============================================================
-- 横向对比: 层次查询能力
-- ============================================================
-- 能力            | Snowflake   | Oracle     | PostgreSQL | MySQL 8.0
-- 递归 CTE        | 支持        | 支持(11g+) | 支持       | 支持
-- CONNECT BY      | 支持        | 原创       | 不支持     | 不支持
-- 循环检测        | 深度限制    | NOCYCLE    | CYCLE 子句 | 深度限制
-- SYS_CONNECT_BY  | 支持        | 原创       | 不支持     | 不支持
