-- Apache Impala: 层次查询与树形结构 (Hierarchical Query & Tree Traversal)
--
-- 参考资料:
--   [1] Apache Impala Documentation - SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html

-- ============================================================
-- Apache Impala 不支持递归 CTE，使用替代方案
-- ============================================================

-- 1. 多层自连接（固定深度）
SELECT e1.name AS level_0, e2.name AS level_1,
       e3.name AS level_2, e4.name AS level_3
FROM employees e1
LEFT JOIN employees e2 ON e2.parent_id = e1.id
LEFT JOIN employees e3 ON e3.parent_id = e2.id
LEFT JOIN employees e4 ON e4.parent_id = e3.id
WHERE e1.parent_id IS NULL;

-- 2. 路径枚举模型
SELECT * FROM categories WHERE path LIKE '1/2%';

-- 3. 闭包表模型
-- CREATE TABLE tree_closure (ancestor INT, descendant INT, depth INT);
-- SELECT e.* FROM tree_closure tc JOIN employees e ON e.id = tc.descendant
-- WHERE tc.ancestor = 2 AND tc.depth > 0;

-- 注意：Apache Impala 不支持递归 CTE
-- 注意：不支持 CONNECT BY
-- 注意：推荐使用路径枚举或闭包表模型
-- 注意：复杂层次查询建议在其他引擎中预处理
