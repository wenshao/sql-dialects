-- Flink SQL: 层次查询与树形结构 (Hierarchical Query & Tree Traversal)
--
-- 参考资料:
--   [1] Flink Documentation - SQL Queries
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/overview/
--   [2] Flink Documentation - Joins
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/joins/

-- ============================================================
-- Flink SQL 不支持递归 CTE，使用替代方案
-- ============================================================

CREATE TABLE employees (
    id        INT,
    name      STRING,
    parent_id INT,
    dept      STRING,
    PRIMARY KEY (id) NOT ENFORCED
) WITH ('connector' = 'filesystem', 'path' = '/data/employees', 'format' = 'csv');

-- ============================================================
-- 1. 多层自连接（固定深度）
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

CREATE TABLE categories (
    id   INT,
    name STRING,
    path STRING,
    PRIMARY KEY (id) NOT ENFORCED
) WITH ('connector' = 'filesystem', 'path' = '/data/categories', 'format' = 'csv');

SELECT * FROM categories WHERE path LIKE '1/2%';

-- ============================================================
-- 3. 在流处理中维护层次关系
-- ============================================================

-- 使用 Temporal Join 维护实时层次关系
-- CREATE TABLE employee_hierarchy (
--     employee_id INT,
--     manager_chain STRING,  -- 物化路径
--     update_time TIMESTAMP(3),
--     PRIMARY KEY (employee_id) NOT ENFORCED
-- ) WITH (...);

-- 注意：Flink SQL 不支持递归 CTE
-- 注意：Flink SQL 不支持 CONNECT BY
-- 注意：流处理场景下，推荐使用 Temporal Join 维护层次关系
-- 注意：复杂层次查询建议在批处理引擎中完成
