-- StarRocks: 条件函数
--
-- 参考资料:
--   [1] StarRocks Documentation - Conditional Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/

-- ============================================================
-- 1. CASE WHEN
-- ============================================================
SELECT username,
    CASE WHEN age < 18 THEN 'minor'
         WHEN age < 65 THEN 'adult'
         ELSE 'senior' END AS category
FROM users;

-- ============================================================
-- 2. IF
-- ============================================================
SELECT username, IF(age >= 18, 'adult', 'minor') FROM users;

-- ============================================================
-- 3. NULL 处理
-- ============================================================
SELECT IFNULL(phone, 'N/A') FROM users;
SELECT COALESCE(phone, email, 'unknown') FROM users;
SELECT NULLIF(age, 0) FROM users;

-- ============================================================
-- 4. GREATEST / LEAST
-- ============================================================
SELECT GREATEST(1, 3, 2);
SELECT LEAST(1, 3, 2);

-- ============================================================
-- 5. StarRocks vs Doris 差异
-- ============================================================
-- 核心函数完全相同。
-- Doris 额外支持 NVL/NVL2(Oracle 兼容)。
-- StarRocks 也支持 NVL/NVL2(但文档中较少提及)。
