-- MariaDB: PIVOT / UNPIVOT
-- MariaDB 不原生支持 PIVOT/UNPIVOT, 需用 CASE WHEN 模拟
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - Pivoting
--       https://mariadb.com/kb/en/pivoting-in-mariadb/

-- ============================================================
-- 1. PIVOT 模拟 (CASE WHEN + GROUP BY)
-- ============================================================
SELECT
    dept_id,
    SUM(CASE WHEN YEAR(hire_date) = 2023 THEN 1 ELSE 0 END) AS y2023,
    SUM(CASE WHEN YEAR(hire_date) = 2024 THEN 1 ELSE 0 END) AS y2024,
    SUM(CASE WHEN YEAR(hire_date) = 2025 THEN 1 ELSE 0 END) AS y2025
FROM employees
GROUP BY dept_id;

-- ============================================================
-- 2. UNPIVOT 模拟 (UNION ALL)
-- ============================================================
SELECT id, 'q1' AS quarter, q1_sales AS sales FROM quarterly_sales
UNION ALL
SELECT id, 'q2', q2_sales FROM quarterly_sales
UNION ALL
SELECT id, 'q3', q3_sales FROM quarterly_sales
UNION ALL
SELECT id, 'q4', q4_sales FROM quarterly_sales;

-- ============================================================
-- 3. 动态 PIVOT (存储过程)
-- ============================================================
-- MariaDB 中需要通过动态 SQL 生成 CASE WHEN 列表
-- 适用于透视列数量不固定的场景
-- 对比: SQL Server/Oracle 原生 PIVOT 语法, 更简洁但列仍需静态指定

-- ============================================================
-- 4. 对引擎开发者的启示
-- ============================================================
-- PIVOT/UNPIVOT 可视为语法糖:
--   PIVOT = GROUP BY + CASE WHEN + 聚合 (优化器可合并执行)
--   UNPIVOT = CROSS JOIN LATERAL + VALUES (或 UNION ALL)
-- 原生支持的价值: 简化 SQL 编写, 优化器可能生成更好的计划
-- MySQL/MariaDB/PostgreSQL 均未原生支持 PIVOT (PostgreSQL 有 crosstab 扩展)
