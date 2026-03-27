-- Hive: 层次查询与树形结构 (Hierarchical Query & Tree Traversal)
--
-- 参考资料:
--   [1] Apache Hive Documentation - LanguageManual Select
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select
--   [2] Apache Hive Documentation - Lateral View
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+LateralView

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TABLE employees (id INT, name STRING, parent_id INT, dept STRING);
INSERT INTO employees VALUES
    (1,'CEO',NULL,'总裁办'),(2,'CTO',1,'技术部'),(3,'CFO',1,'财务部'),
    (4,'VP工程',2,'技术部'),(5,'VP产品',2,'技术部'),
    (6,'开发经理',4,'技术部'),(7,'测试经理',4,'技术部'),
    (8,'开发工程师A',6,'技术部'),(9,'开发工程师B',6,'技术部'),
    (10,'测试工程师',7,'技术部'),(11,'会计主管',3,'财务部'),
    (12,'出纳',11,'财务部');

-- ============================================================
-- Hive 不支持递归 CTE，层次查询需要替代方案
-- ============================================================

-- ============================================================
-- 1. 多层自连接方法（固定深度）
-- ============================================================

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
-- 2. 路径枚举模型（推荐方案）
-- ============================================================

CREATE TABLE categories (id INT, name STRING, path STRING);
INSERT INTO categories VALUES
    (1,'电子产品','1'),(2,'手机','1/2'),(3,'电脑','1/3'),
    (4,'苹果手机','1/2/4'),(5,'安卓手机','1/2/5'),
    (6,'笔记本','1/3/6');

-- 查询子孙
SELECT * FROM categories WHERE path LIKE '1/2%';

-- 查询深度
SELECT *, SIZE(SPLIT(path, '/')) - 1 AS depth FROM categories;

-- 查询祖先路径中的所有节点
SELECT c2.*
FROM categories c1
LATERAL VIEW explode(split(c1.path, '/')) t AS ancestor_id
JOIN categories c2 ON c2.id = CAST(t.ancestor_id AS INT)
WHERE c1.id = 4;

-- ============================================================
-- 3. 使用 Hive UDF 实现层次查询
-- ============================================================

-- 可以通过自定义 UDF/UDTF 实现递归遍历
-- 或使用多次迭代的 INSERT OVERWRITE 模拟递归

-- 迭代方法（需要多次执行）
CREATE TABLE tree_result (id INT, name STRING, level INT, path STRING);

-- 第一次迭代：插入根节点
INSERT INTO tree_result
SELECT id, name, 0, CAST(id AS STRING) FROM employees WHERE parent_id IS NULL;

-- 第二次迭代：插入第一层子节点
INSERT INTO tree_result
SELECT e.id, e.name, 1, CONCAT(t.path, '/', CAST(e.id AS STRING))
FROM employees e JOIN tree_result t ON e.parent_id = t.id WHERE t.level = 0;

-- 继续迭代直到没有新行...

-- ============================================================
-- 4. 使用 GraphX（Spark on Hive）
-- ============================================================

-- 对于复杂的图遍历，推荐使用 Spark GraphX
-- 或将数据导出到支持递归 CTE 的引擎中处理

-- ============================================================
-- 5. 闭包表模型（Closure Table）
-- ============================================================

CREATE TABLE tree_closure (
    ancestor   INT,
    descendant INT,
    depth      INT
);
-- 预计算所有祖先-后代关系
INSERT INTO tree_closure VALUES
    (1,1,0),(1,2,1),(1,3,1),(1,4,2),(1,5,2),
    (1,6,3),(1,7,3),(1,8,4),(1,9,4),(1,10,4),
    (1,11,2),(1,12,3),
    (2,2,0),(2,4,1),(2,5,1),(2,6,2),(2,7,2),
    (2,8,3),(2,9,3),(2,10,3),
    (3,3,0),(3,11,1),(3,12,2),
    (4,4,0),(4,6,1),(4,7,1),(4,8,2),(4,9,2),(4,10,2),
    (5,5,0),(6,6,0),(6,8,1),(6,9,1),
    (7,7,0),(7,10,1),(8,8,0),(9,9,0),(10,10,0),
    (11,11,0),(11,12,1),(12,12,0);

-- 查询某节点的所有子孙
SELECT e.* FROM tree_closure tc
JOIN employees e ON e.id = tc.descendant
WHERE tc.ancestor = 2 AND tc.depth > 0;

-- 查询某节点的所有祖先
SELECT e.* FROM tree_closure tc
JOIN employees e ON e.id = tc.ancestor
WHERE tc.descendant = 8 AND tc.depth > 0;

-- ============================================================
-- 6. 子树聚合
-- ============================================================

SELECT tc.ancestor, e.name, COUNT(*) - 1 AS subordinate_count
FROM tree_closure tc
JOIN employees e ON e.id = tc.ancestor
GROUP BY tc.ancestor, e.name
HAVING COUNT(*) > 1
ORDER BY subordinate_count DESC;

-- 注意：Hive 不支持递归 CTE
-- 注意：Hive 不支持 CONNECT BY
-- 注意：推荐使用路径枚举或闭包表模型
-- 注意：复杂层次查询建议使用 Spark SQL 或其他支持递归 CTE 的引擎
-- 注意：多层自连接方法受限于固定深度
