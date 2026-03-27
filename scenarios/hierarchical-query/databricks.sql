-- Databricks SQL: 层次查询与树形结构 (Hierarchical Query & Tree Traversal)
--
-- 参考资料:
--   [1] Databricks SQL Reference - Common Table Expressions
--       https://docs.databricks.com/en/sql/language-manual/sql-ref-syntax-qry-select-cte.html
--   [2] Databricks SQL Reference - SQL Reference
--       https://docs.databricks.com/en/sql/language-manual/index.html

-- ============================================================
-- 准备数据
-- ============================================================

CREATE TEMPORARY VIEW employees AS
SELECT * FROM VALUES
    (1,'CEO',CAST(NULL AS INT),'总裁办'),(2,'CTO',1,'技术部'),(3,'CFO',1,'财务部'),
    (4,'VP工程',2,'技术部'),(5,'VP产品',2,'技术部'),
    (6,'开发经理',4,'技术部'),(7,'测试经理',4,'技术部'),
    (8,'开发工程师A',6,'技术部'),(9,'开发工程师B',6,'技术部'),
    (10,'测试工程师',7,'技术部'),(11,'会计主管',3,'财务部'),
    (12,'出纳',11,'财务部')
AS t(id, name, parent_id, dept);

-- ============================================================
-- 1. 多层自连接
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

CREATE TEMPORARY VIEW categories AS
SELECT * FROM VALUES
    (1,'电子产品','1'),(2,'手机','1/2'),(3,'电脑','1/3'),
    (4,'苹果手机','1/2/4'),(5,'安卓手机','1/2/5'),(6,'笔记本','1/3/6')
AS t(id, name, path);

SELECT * FROM categories WHERE path LIKE '1/2%';
SELECT *, SIZE(SPLIT(path, '/')) - 1 AS depth FROM categories;

-- ============================================================
-- 3. 使用 explode 查询祖先
-- ============================================================

SELECT c2.*
FROM categories c1
LATERAL VIEW explode(split(c1.path, '/')) t AS ancestor_id
JOIN categories c2 ON c2.id = CAST(t.ancestor_id AS INT)
WHERE c1.id = 4;

-- ============================================================
-- 4-6. GraphFrames / Delta Lake
-- ============================================================

-- Databricks 推荐使用 GraphFrames 处理图遍历
-- Delta Lake 可以存储物化路径，支持 MERGE 更新

-- 注意：Databricks SQL 基于 Spark SQL，不支持递归 CTE
-- 注意：推荐使用路径枚举或 GraphFrames
-- 注意：Databricks Runtime ML 包含 GraphFrames
-- 注意：对于简单层次，多层 JOIN 足够使用
