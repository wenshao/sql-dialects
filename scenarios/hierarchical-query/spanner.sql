-- Google Cloud Spanner: 层次查询与树形结构 (Hierarchical Query & Tree Traversal)
--
-- 参考资料:
--   [1] Spanner Documentation - SQL Reference
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax

-- ============================================================
-- 准备数据（Spanner 使用 Interleaved Tables 表示父子关系）
-- ============================================================

CREATE TABLE departments (
    dept_id INT64 NOT NULL,
    name    STRING(100)
) PRIMARY KEY (dept_id);

-- Interleaved Table（Spanner 特有的物理层次关系）
CREATE TABLE employees (
    dept_id   INT64 NOT NULL,
    id        INT64 NOT NULL,
    name      STRING(100),
    parent_id INT64
) PRIMARY KEY (dept_id, id),
  INTERLEAVE IN PARENT departments ON DELETE CASCADE;

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

CREATE TABLE categories (
    id   INT64 NOT NULL,
    name STRING(100),
    path STRING(500)
) PRIMARY KEY (id);

SELECT * FROM categories WHERE STARTS_WITH(path, '1/2');

-- ============================================================
-- 3. Spanner 的 Interleaved Tables
-- ============================================================

-- Interleaved Tables 是 Spanner 特有的物理层次关系
-- 父子行数据在物理上共置，JOIN 性能极佳
-- 适合表示一对多的层次关系

-- 注意：Spanner 不支持递归 CTE
-- 注意：Spanner 不支持 CONNECT BY
-- 注意：Interleaved Tables 是 Spanner 原生的层次关系方案
-- 注意：使用 STARTS_WITH 替代 LIKE 'prefix%' 更高效
