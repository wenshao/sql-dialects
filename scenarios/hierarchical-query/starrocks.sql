-- StarRocks: 层次查询与树形结构 (Hierarchical Query & Tree Traversal)
--
-- 参考资料:
--   [1] StarRocks Documentation - SQL Reference
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/
--   [2] StarRocks Documentation - Window Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/Window_function/

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
-- 2. 路径枚举模型（推荐）
-- ============================================================

CREATE TABLE categories (id INT, name VARCHAR(100), path VARCHAR(500))
DISTRIBUTED BY HASH(id) BUCKETS 1 PROPERTIES ("replication_num" = "1");

SELECT * FROM categories WHERE path LIKE '1/2%';
SELECT *, LENGTH(path) - LENGTH(REPLACE(path, '/', '')) AS depth FROM categories;

-- ============================================================
-- 3-6. 闭包表 / 子树聚合
-- ============================================================

-- 与 Doris 类似，StarRocks 不支持递归 CTE
-- 推荐使用路径枚举或闭包表模型

-- 注意：StarRocks 不支持递归 CTE
-- 注意：StarRocks 不支持 CONNECT BY
-- 注意：StarRocks 与 Doris 语法高度兼容
-- 注意：推荐在 ETL 阶段将层次数据扁平化
