-- Oracle: 层次查询与树形结构 (Hierarchical Query & Tree Traversal)
--
-- 参考资料:
--   [1] Oracle Documentation - Hierarchical Queries (CONNECT BY)
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Hierarchical-Queries.html
--   [2] Oracle Documentation - Recursive Subquery Factoring
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE employees (
    id        NUMBER(10) PRIMARY KEY,
    name      VARCHAR2(100) NOT NULL,
    parent_id NUMBER(10) REFERENCES employees(id),
    dept      VARCHAR2(100)
);
INSERT ALL
    INTO employees VALUES (1,'CEO',NULL,'总裁办')
    INTO employees VALUES (2,'CTO',1,'技术部')
    INTO employees VALUES (3,'CFO',1,'财务部')
    INTO employees VALUES (4,'VP工程',2,'技术部')
    INTO employees VALUES (5,'VP产品',2,'技术部')
    INTO employees VALUES (6,'开发经理',4,'技术部')
    INTO employees VALUES (7,'测试经理',4,'技术部')
    INTO employees VALUES (8,'开发工程师A',6,'技术部')
    INTO employees VALUES (9,'开发工程师B',6,'技术部')
    INTO employees VALUES (10,'测试工程师',7,'技术部')
    INTO employees VALUES (11,'会计主管',3,'财务部')
    INTO employees VALUES (12,'出纳',11,'财务部')
SELECT 1 FROM DUAL;

-- ============================================================
-- 1. CONNECT BY（Oracle 特有，经典方法）
-- ============================================================

-- 自顶向下遍历
SELECT id,
       LPAD(' ', 2 * (LEVEL - 1)) || name AS indented_name,
       LEVEL AS depth,
       SYS_CONNECT_BY_PATH(name, ' > ') AS path,
       CONNECT_BY_ISLEAF AS is_leaf,
       CONNECT_BY_ROOT name AS root_name
FROM employees
START WITH parent_id IS NULL
CONNECT BY PRIOR id = parent_id
ORDER SIBLINGS BY name;

-- 自底向上遍历
SELECT id, name, LEVEL AS depth,
       SYS_CONNECT_BY_PATH(name, ' > ') AS path
FROM employees
START WITH name = '开发工程师A'
CONNECT BY PRIOR parent_id = id;

-- ============================================================
-- 2. 递归 CTE（Oracle 11gR2+）
-- ============================================================

WITH org_tree (id, name, parent_id, dept, lvl, path) AS (
    SELECT id, name, parent_id, dept,
           0, CAST(name AS VARCHAR2(4000))
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, e.dept,
           t.lvl + 1, t.path || ' > ' || e.name
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SELECT id, LPAD(' ', 2 * lvl) || name AS indented_name, lvl, path
FROM org_tree ORDER BY path;

-- ============================================================
-- 3. 深度优先 vs 广度优先
-- ============================================================

-- CONNECT BY 的 ORDER SIBLINGS BY 实现深度优先
SELECT LEVEL, LPAD(' ', 2 * (LEVEL - 1)) || name AS indented_name
FROM employees
START WITH parent_id IS NULL
CONNECT BY PRIOR id = parent_id
ORDER SIBLINGS BY name;

-- 广度优先（按 LEVEL 排序）
SELECT LEVEL, name
FROM employees
START WITH parent_id IS NULL
CONNECT BY PRIOR id = parent_id
ORDER BY LEVEL, name;

-- 递归 CTE 的 SEARCH 子句（Oracle 11gR2+）
WITH org_tree (id, name, parent_id, lvl) AS (
    SELECT id, name, parent_id, 0
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.lvl + 1
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
SEARCH DEPTH FIRST BY name SET order_col
SELECT LPAD(' ', 2 * lvl) || name AS indented_name, lvl
FROM org_tree ORDER BY order_col;

-- ============================================================
-- 4. 循环检测
-- ============================================================

-- CONNECT BY 自动检测循环（CONNECT BY NOCYCLE）
SELECT LEVEL, name, CONNECT_BY_ISCYCLE AS is_cycle
FROM employees
START WITH parent_id IS NULL
CONNECT BY NOCYCLE PRIOR id = parent_id;

-- 递归 CTE 的 CYCLE 子句
WITH org_tree (id, name, parent_id, lvl) AS (
    SELECT id, name, parent_id, 0
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, t.lvl + 1
    FROM employees e JOIN org_tree t ON e.parent_id = t.id
)
CYCLE id SET is_cycle TO 'Y' DEFAULT 'N'
SELECT * FROM org_tree WHERE is_cycle = 'N';

-- ============================================================
-- 5. 路径枚举模型
-- ============================================================

CREATE TABLE categories (
    id   NUMBER(10) PRIMARY KEY,
    name VARCHAR2(100),
    path VARCHAR2(500)
);
INSERT ALL
    INTO categories VALUES (1,'电子产品','1')
    INTO categories VALUES (2,'手机','1/2')
    INTO categories VALUES (3,'电脑','1/3')
    INTO categories VALUES (4,'苹果手机','1/2/4')
    INTO categories VALUES (5,'安卓手机','1/2/5')
    INTO categories VALUES (6,'笔记本','1/3/6')
SELECT 1 FROM DUAL;

SELECT * FROM categories WHERE path LIKE '1/2%';

-- ============================================================
-- 6. 子树聚合
-- ============================================================

-- 使用 CONNECT BY 统计子树大小
SELECT id, name,
       (SELECT COUNT(*) - 1
        FROM employees
        START WITH id = e.id
        CONNECT BY PRIOR id = parent_id) AS subordinate_count
FROM employees e
ORDER BY subordinate_count DESC;

-- 注意：CONNECT BY 是 Oracle 的经典层次查询语法
-- 注意：SYS_CONNECT_BY_PATH 构建从根到当前节点的路径
-- 注意：CONNECT_BY_ROOT 返回根节点的列值
-- 注意：CONNECT_BY_ISLEAF 标识叶子节点
-- 注意：ORDER SIBLINGS BY 在同级节点间排序
-- 注意：递归 CTE 从 Oracle 11gR2 开始支持
