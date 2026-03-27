-- Apache Doris: 层次查询与树形结构 (Hierarchical Query & Tree Traversal)
--
-- 参考资料:
--   [1] Doris Documentation - SQL Reference
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Documentation - Window Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/window-functions/

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE employees (id INT, name VARCHAR(100), parent_id INT, dept VARCHAR(100))
DISTRIBUTED BY HASH(id) BUCKETS 1 PROPERTIES ("replication_num" = "1");
INSERT INTO employees VALUES
    (1,'CEO',NULL,'总裁办'),(2,'CTO',1,'技术部'),(3,'CFO',1,'财务部'),
    (4,'VP工程',2,'技术部'),(5,'VP产品',2,'技术部'),
    (6,'开发经理',4,'技术部'),(7,'测试经理',4,'技术部'),
    (8,'开发工程师A',6,'技术部'),(9,'开发工程师B',6,'技术部'),
    (10,'测试工程师',7,'技术部'),(11,'会计主管',3,'财务部'),
    (12,'出纳',11,'财务部');

-- ============================================================
-- 1. 多层自连接（Doris 不支持递归 CTE）
-- ============================================================

SELECT e1.name AS level_0, e2.name AS level_1,
       e3.name AS level_2, e4.name AS level_3
FROM employees e1
LEFT JOIN employees e2 ON e2.parent_id = e1.id
LEFT JOIN employees e3 ON e3.parent_id = e2.id
LEFT JOIN employees e4 ON e4.parent_id = e3.id
WHERE e1.parent_id IS NULL;

-- ============================================================
-- 2. 路径枚举模型
-- ============================================================

CREATE TABLE categories (id INT, name VARCHAR(100), path VARCHAR(500))
DISTRIBUTED BY HASH(id) BUCKETS 1 PROPERTIES ("replication_num" = "1");

SELECT * FROM categories WHERE path LIKE '1/2%';
SELECT *, LENGTH(path) - LENGTH(REPLACE(path, '/', '')) AS depth FROM categories;

-- ============================================================
-- 3. 闭包表模型
-- ============================================================

CREATE TABLE tree_closure (ancestor INT, descendant INT, depth INT)
DISTRIBUTED BY HASH(ancestor) BUCKETS 1 PROPERTIES ("replication_num" = "1");

SELECT e.* FROM tree_closure tc
JOIN employees e ON e.id = tc.descendant
WHERE tc.ancestor = 2 AND tc.depth > 0;

-- ============================================================
-- 4-6. 子树聚合
-- ============================================================

SELECT tc.ancestor, e.name, COUNT(*) - 1 AS subordinate_count
FROM tree_closure tc JOIN employees e ON e.id = tc.ancestor
GROUP BY tc.ancestor, e.name HAVING COUNT(*) > 1
ORDER BY subordinate_count DESC;

-- 注意：Doris 不支持递归 CTE
-- 注意：Doris 不支持 CONNECT BY
-- 注意：推荐使用路径枚举或闭包表
-- 注意：Doris 的 MPP 架构适合大规模扁平化层次数据查询
