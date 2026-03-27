-- Spark SQL: 层次查询与树形结构 (Hierarchical Query & Tree Traversal)
--
-- 参考资料:
--   [1] Spark SQL Documentation - Common Table Expressions
--       https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-cte.html
--   [2] Spark SQL Documentation - SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html

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
-- 1. 多层自连接（Spark SQL 通用方法）
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
-- 2. 路径枚举模型（推荐）
-- ============================================================

CREATE TEMPORARY VIEW categories AS
SELECT * FROM VALUES
    (1,'电子产品','1'),(2,'手机','1/2'),(3,'电脑','1/3'),
    (4,'苹果手机','1/2/4'),(5,'安卓手机','1/2/5'),
    (6,'笔记本','1/3/6')
AS t(id, name, path);

SELECT * FROM categories WHERE path LIKE '1/2%';
SELECT *, SIZE(SPLIT(path, '/')) - 1 AS depth FROM categories;

-- ============================================================
-- 3. 使用 Spark GraphFrames（推荐用于复杂图遍历）
-- ============================================================

-- GraphFrames 提供了 BFS、连通分量等图算法
-- 在 PySpark 中使用：
-- from graphframes import GraphFrame
-- vertices = spark.createDataFrame([(1,"CEO"), (2,"CTO"), ...], ["id", "name"])
-- edges = spark.createDataFrame([(2,1), (3,1), ...], ["src", "dst"])
-- g = GraphFrame(vertices, edges)
-- g.bfs(fromExpr="id = 1", toExpr="id = 8")

-- ============================================================
-- 4. 使用 explode + split 查询祖先
-- ============================================================

SELECT c2.*
FROM categories c1
LATERAL VIEW explode(split(c1.path, '/')) t AS ancestor_id
JOIN categories c2 ON c2.id = CAST(t.ancestor_id AS INT)
WHERE c1.id = 4;

-- ============================================================
-- 5. 迭代方法（DataFrame API）
-- ============================================================

-- 在 PySpark 中可以使用循环迭代实现：
-- result = spark.sql("SELECT * FROM employees WHERE parent_id IS NULL")
-- while True:
--     next_level = spark.sql(f"""
--         SELECT e.* FROM employees e
--         JOIN {result.createOrReplaceTempView('current')} c
--         ON e.parent_id = c.id
--     """)
--     if next_level.count() == 0: break
--     result = result.union(next_level)

-- ============================================================
-- 6. 闭包表方法
-- ============================================================

-- 与 Hive 相同的闭包表方案
CREATE TEMPORARY VIEW tree_closure AS
SELECT * FROM VALUES
    (1,1,0),(1,2,1),(1,3,1),(1,4,2),(1,5,2),
    (2,2,0),(2,4,1),(2,5,1),(2,6,2),(2,7,2),
    (3,3,0),(3,11,1),(3,12,2)
AS t(ancestor, descendant, depth);

SELECT e.* FROM tree_closure tc
JOIN employees e ON e.id = tc.descendant
WHERE tc.ancestor = 2 AND tc.depth > 0;

-- 注意：Spark SQL 3.4+ 实验性支持递归 CTE（需要配置）
-- 注意：spark.sql.legacy.ctePrecedencePolicy 设置可能影响 CTE 行为
-- 注意：推荐使用 GraphFrames 处理复杂图遍历
-- 注意：路径枚举和闭包表是无递归 CTE 时的最佳方案
