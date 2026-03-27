-- Trino: 层次查询与树形结构 (Hierarchical Query & Tree Traversal)
--
-- 参考资料:
--   [1] Trino Documentation - WITH clause
--       https://trino.io/docs/current/sql/select.html#with-clause
--   [2] Trino Documentation - SQL Reference
--       https://trino.io/docs/current/sql.html

-- ============================================================
-- 准备数据
-- ============================================================

-- Trino 使用各种 connector 的表

-- ============================================================
-- 1. 多层自连接（Trino 不支持递归 CTE）
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

SELECT * FROM categories WHERE path LIKE '1/2%';

-- 使用 UNNEST + split 查询祖先
SELECT c2.*
FROM categories c1
CROSS JOIN UNNEST(split(c1.path, '/')) AS t(ancestor_id)
JOIN categories c2 ON c2.id = CAST(t.ancestor_id AS INT)
WHERE c1.id = 4;

-- ============================================================
-- 3. 深度计算
-- ============================================================

SELECT *, CARDINALITY(split(path, '/')) - 1 AS depth FROM categories;

-- ============================================================
-- 4-6. 替代方案
-- ============================================================

-- Trino 不支持递归 CTE，建议：
-- 1. 在数据源中使用支持递归 CTE 的引擎预处理
-- 2. 使用物化路径模型
-- 3. 使用闭包表
-- 4. 在应用层实现递归逻辑

-- 注意：Trino 不支持递归 CTE
-- 注意：Trino 不支持 CONNECT BY
-- 注意：推荐在数据源端进行层次查询预处理
-- 注意：UNNEST + split 可以解构物化路径
