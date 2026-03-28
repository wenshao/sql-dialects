-- Hive: 集合操作 (UNION / INTERSECT / EXCEPT)
--
-- 参考资料:
--   [1] Apache Hive Language Manual - Union
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Union
--   [2] Apache Hive Documentation - SELECT
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select

-- ============================================================
-- 1. UNION ALL (全版本支持)
-- ============================================================
SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;

-- UNION ALL 在 Hive 中的性能:
-- 不需要去重 → 不需要额外的排序/哈希操作 → 最高效的集合操作
-- 在 MapReduce 模型中: 两个表的 Mapper 输出直接合并

-- ============================================================
-- 2. UNION DISTINCT (1.2.0+)
-- ============================================================
SELECT id, name FROM employees
UNION DISTINCT
SELECT id, name FROM contractors;

-- UNION（不带 ALL/DISTINCT）默认是 DISTINCT
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

-- 1.2.0 之前的替代方案
SELECT DISTINCT * FROM (
    SELECT id, name FROM employees
    UNION ALL
    SELECT id, name FROM contractors
) combined;

-- ============================================================
-- 3. INTERSECT (2.1.0+)
-- ============================================================
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

-- INTERSECT DISTINCT (默认)
SELECT id FROM employees
INTERSECT DISTINCT
SELECT id FROM project_members;

-- 2.1.0 之前的替代方案: JOIN
SELECT DISTINCT e.id FROM employees e
INNER JOIN project_members p ON e.id = p.id;

-- ============================================================
-- 4. EXCEPT / MINUS (2.1.0+)
-- ============================================================
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

-- MINUS 是 EXCEPT 的别名（Oracle 兼容）
SELECT id FROM employees
MINUS
SELECT id FROM terminated_employees;

-- 2.1.0 之前的替代方案: LEFT JOIN + IS NULL
SELECT e.id FROM employees e
LEFT JOIN terminated_employees t ON e.id = t.id
WHERE t.id IS NULL;

-- ============================================================
-- 5. 组合使用
-- ============================================================
SELECT * FROM (
    SELECT id FROM employees
    UNION ALL
    SELECT id FROM contractors
) combined
INTERSECT
SELECT id FROM project_members;

-- ORDER BY / LIMIT 应用于最终结果
SELECT name, salary FROM employees
UNION ALL
SELECT name, salary FROM contractors
ORDER BY salary DESC
LIMIT 10;

-- ============================================================
-- 6. 设计分析: 集合操作的演进
-- ============================================================
-- Hive 的集合操作支持非常晚:
-- 0.x: 只有 UNION ALL
-- 1.2: UNION DISTINCT
-- 2.1: INTERSECT / EXCEPT / MINUS
--
-- 为什么这么晚?
-- 1. UNION ALL 在 MapReduce 中简单: 直接合并两个 Mapper 的输出
-- 2. UNION DISTINCT 需要去重: 额外的 Reduce 阶段做全局去重
-- 3. INTERSECT/EXCEPT 需要集合比较: 更复杂的 Shuffle + Reduce 逻辑
-- 早期 Hive 优先实现了最简单最实用的 UNION ALL

-- ============================================================
-- 7. 已知限制
-- ============================================================
-- 1. 不支持 INTERSECT ALL / EXCEPT ALL: 只有 DISTINCT 版本
-- 2. 列数和类型必须匹配: 两个查询的列数必须相同，类型需要兼容
-- 3. 列名取第一个查询的: 最终结果的列名来自第一个 SELECT
-- 4. 1.2.0 之前只有 UNION ALL: 需要手动去重

-- ============================================================
-- 8. 跨引擎对比
-- ============================================================
-- 引擎          UNION ALL  UNION   INTERSECT  EXCEPT   INTERSECT ALL
-- MySQL(8.0+)   支持       支持    支持       支持     支持
-- PostgreSQL    支持       支持    支持       支持     支持
-- Oracle        支持       支持    支持       MINUS    不支持
-- Hive          支持       1.2+    2.1+       2.1+     不支持
-- Spark SQL     支持       支持    支持       支持     不支持
-- BigQuery      支持       支持    支持       支持     不支持

-- ============================================================
-- 9. 对引擎开发者的启示
-- ============================================================
-- 1. UNION ALL 是最基础的集合操作: 不需要去重，实现简单，优先支持
-- 2. INTERSECT/EXCEPT 可以用 JOIN 替代: 但原生语法更简洁
-- 3. ALL 变体（INTERSECT ALL/EXCEPT ALL）很少使用: 大多数引擎不支持
-- 4. MINUS 是 Oracle 兼容性的需要: Hive 同时支持 EXCEPT 和 MINUS
