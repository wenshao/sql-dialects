-- SAP HANA: 集合操作
--
-- 参考资料:
--   [1] SAP HANA SQL Reference - Set Operators
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20fcf24075191014a89e9dc7b8408b26.html
--   [2] SAP HANA SQL Reference - SELECT
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20fcf24075191014a89e9dc7b8408b26.html

-- ============================================================
-- UNION / UNION ALL
-- ============================================================
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;

-- ============================================================
-- INTERSECT
-- ============================================================
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

-- 注意：SAP HANA 不支持 INTERSECT ALL

-- ============================================================
-- EXCEPT
-- ============================================================
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

-- 注意：SAP HANA 不支持 EXCEPT ALL

-- ============================================================
-- 嵌套与组合集合操作
-- ============================================================
(SELECT id FROM employees
 UNION
 SELECT id FROM contractors)
INTERSECT
SELECT id FROM project_members;

-- ============================================================
-- ORDER BY 与集合操作
-- ============================================================
SELECT name, salary FROM employees
UNION ALL
SELECT name, salary FROM contractors
ORDER BY salary DESC;

-- ============================================================
-- LIMIT / OFFSET 与集合操作
-- ============================================================
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10;

-- LIMIT + OFFSET
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10 OFFSET 20;

-- ============================================================
-- 注意事项
-- ============================================================
-- SAP HANA 不支持 INTERSECT ALL 和 EXCEPT ALL
-- 不支持 MINUS（使用 EXCEPT）
-- LOB 类型列不能直接用于集合操作
-- 集合操作利用 HANA 的列存储和并行处理能力
