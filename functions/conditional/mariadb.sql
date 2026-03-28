-- MariaDB: 条件函数
-- 与 MySQL 完全一致
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - Control Flow Functions
--       https://mariadb.com/kb/en/control-flow-functions/

-- ============================================================
-- 1. CASE 表达式
-- ============================================================
SELECT username,
    CASE
        WHEN age < 18 THEN '未成年'
        WHEN age < 60 THEN '成年'
        ELSE '老年'
    END AS age_group
FROM users;

SELECT username,
    CASE age
        WHEN 18 THEN '刚成年'
        WHEN 65 THEN '退休'
        ELSE '其他'
    END AS milestone
FROM users;

-- ============================================================
-- 2. IF / IFNULL / NULLIF / COALESCE
-- ============================================================
SELECT IF(age >= 18, '成年', '未成年') FROM users;
SELECT IFNULL(bio, '未填写') FROM users;
SELECT NULLIF(age, 0) FROM users;             -- age=0 返回 NULL
SELECT COALESCE(bio, email, username) FROM users;  -- 第一个非 NULL

-- ============================================================
-- 3. GREATEST / LEAST
-- ============================================================
SELECT GREATEST(10, 20, 30), LEAST(10, 20, 30);

-- ============================================================
-- 4. 对引擎开发者的启示
-- ============================================================
-- CASE 表达式在 SQL 标准中定义, 所有引擎必须支持
-- 实现: 编译为条件分支指令 (类似 if-else 链)
-- 短路求值: 匹配第一个 WHEN 后跳过后续条件 (标准要求)
-- COALESCE 可编译为嵌套 CASE WHEN x IS NOT NULL THEN x ELSE ...
-- IF() 是 MySQL/MariaDB 独有的函数式写法, 标准 SQL 用 CASE
