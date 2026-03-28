-- Apache Doris: 条件函数
--
-- 参考资料:
--   [1] Doris Documentation - Conditional Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- ============================================================
-- 1. CASE WHEN (SQL 标准)
-- ============================================================
SELECT username,
    CASE WHEN age < 18 THEN 'minor'
         WHEN age < 65 THEN 'adult'
         ELSE 'senior' END AS category
FROM users;

SELECT username,
    CASE status WHEN 0 THEN 'inactive'
                WHEN 1 THEN 'active'
                ELSE 'unknown' END AS status_name
FROM users;

-- ============================================================
-- 2. IF (MySQL 兼容)
-- ============================================================
SELECT username, IF(age >= 18, 'adult', 'minor') AS category FROM users;

-- ============================================================
-- 3. NULL 处理函数
-- ============================================================
SELECT IFNULL(phone, 'N/A') FROM users;
SELECT COALESCE(phone, email, 'unknown') FROM users;
SELECT NULLIF(age, 0) FROM users;
SELECT NVL(phone, 'N/A') FROM users;       -- Oracle 兼容
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;  -- Oracle 兼容

-- ============================================================
-- 4. GREATEST / LEAST
-- ============================================================
SELECT GREATEST(1, 3, 2);   -- 3
SELECT LEAST(1, 3, 2);      -- 1

-- ============================================================
-- 5. NULL 判断
-- ============================================================
SELECT username FROM users WHERE age IS NULL;
SELECT username FROM users WHERE age IS NOT NULL;

-- ============================================================
-- 6. 对比其他引擎
-- ============================================================
-- IF():           MySQL/Doris/StarRocks(MySQL 兼容)
-- IIF():          SQL Server
-- NVL/NVL2:       Oracle/Doris(Oracle 兼容)
-- COALESCE:       SQL 标准(所有引擎)
-- DECODE:         Oracle 特有(Doris 不支持)
--
-- 对引擎开发者的启示:
--   条件函数的向量化实现需要"短路求值"优化:
--     CASE WHEN 的多分支按顺序求值，一旦命中即停止
--     COALESCE 的多参数同样短路
--     向量化时需要用 Selection Vector 标记已完成的行
