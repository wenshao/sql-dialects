-- SQL Server: 条件函数与 NULL 处理
--
-- 参考资料:
--   [1] SQL Server T-SQL - CASE, IIF, COALESCE
--       https://learn.microsoft.com/en-us/sql/t-sql/language-elements/case-transact-sql

-- ============================================================
-- 1. CASE WHEN（SQL 标准）
-- ============================================================

-- 搜索 CASE
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category
FROM users;

-- 简单 CASE
SELECT username,
    CASE status
        WHEN 0 THEN 'inactive'
        WHEN 1 THEN 'active'
        ELSE 'unknown'
    END AS status_name
FROM users;

-- ============================================================
-- 2. IIF: T-SQL 独有的三元条件函数（2012+）
-- ============================================================

SELECT username, IIF(age >= 18, 'adult', 'minor') AS category FROM users;

-- 设计分析（对引擎开发者）:
--   IIF 是 CASE WHEN 的语法糖——内部被转换为 CASE。
--   它来自 Visual Basic 传统（SQL Server 与微软生态的深度绑定）。
--   其他数据库不支持 IIF（MySQL 有 IF()，PostgreSQL 什么都没有）。
--
-- 横向对比:
--   MySQL:      IF(condition, true_val, false_val)
--   PostgreSQL: 无等价函数（必须用 CASE WHEN）
--   Oracle:     无 IIF/IF（DECODE 是类似但不同的函数）
--
-- 对引擎开发者的启示:
--   三元条件函数是高频需求，但 SQL 标准选择了 CASE WHEN 这种冗长语法。
--   提供简洁的三元函数（如 IIF 或 IF）是好的用户体验设计。

-- ============================================================
-- 3. ISNULL vs COALESCE: NULL 替换的微妙差异
-- ============================================================

-- ISNULL: SQL Server 特有，两参数
SELECT ISNULL(phone, 'N/A') FROM users;

-- COALESCE: SQL 标准，多参数
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- 关键差异（对引擎开发者重要）:
--   (1) 返回类型: ISNULL 使用第一个参数的类型；COALESCE 使用最高优先级的类型
--       ISNULL(NULL, 'long_string')  → 截断到第一个参数的类型长度
--       COALESCE(NULL, 'long_string') → 不截断
--   (2) NULL 性: ISNULL 的结果被优化器视为 NOT NULL；COALESCE 可能为 NULL
--   (3) 求值次数: COALESCE(expr, default) 如果 expr 非 NULL，expr 只求值一次
--       但 COALESCE 内部展开为 CASE WHEN expr IS NOT NULL THEN expr ELSE default END
--       所以 expr 可能被求值两次（如果是子查询，可能执行两次）
--
-- 最佳实践:
--   简单的两参数 NULL 替换: ISNULL（性能略好，不截断问题也罕见）
--   多参数或需要标准兼容: COALESCE

-- ============================================================
-- 4. NULLIF
-- ============================================================

SELECT NULLIF(age, 0) FROM users;  -- age 为 0 时返回 NULL
-- 常用于避免除零错误: SELECT total / NULLIF(count, 0) FROM stats;

-- ============================================================
-- 5. CHOOSE: 按位置选择值（2012+）
-- ============================================================

SELECT CHOOSE(2, 'a', 'b', 'c');  -- 'b'
SELECT CHOOSE(DATEPART(WEEKDAY, GETDATE()),
    'Sun','Mon','Tue','Wed','Thu','Fri','Sat') AS day_name;

-- CHOOSE 是 T-SQL 独有函数，其他数据库不支持。
-- 它是 CASE WHEN index = 1 THEN ... WHEN index = 2 THEN ... END 的语法糖。

-- ============================================================
-- 6. TRY_CAST / TRY_CONVERT: 安全类型转换（2012+）
-- ============================================================

SELECT TRY_CAST('abc' AS INT);              -- NULL（不报错）
SELECT TRY_CAST('42' AS INT);               -- 42
SELECT TRY_CONVERT(INT, 'abc');             -- NULL
SELECT TRY_CONVERT(DATE, '2024-02-30');     -- NULL（无效日期）

-- TRY_PARSE: 文化敏感的安全转换
SELECT TRY_PARSE('January 2024' AS DATE USING 'en-US');
SELECT TRY_PARSE('$1,234.56' AS MONEY USING 'en-US');

-- 设计分析（对引擎开发者）:
--   TRY_CAST/TRY_CONVERT 是 SQL Server 的重要创新——安全的类型转换。
--   在 ETL 场景中，输入数据质量无法保证，CAST 失败会终止整个查询。
--   TRY_CAST 返回 NULL 而非报错，允许查询继续执行。
--
-- 横向对比:
--   PostgreSQL: 无原生 TRY_CAST（需要自定义函数或 PL/pgSQL 异常处理）
--   MySQL:      CAST 失败时行为取决于 sql_mode（严格/宽松）
--   Oracle:     无 TRY_CAST（12c+ 有 VALIDATE_CONVERSION 函数）
--
-- 对引擎开发者的启示:
--   安全类型转换应该是内置功能，而非让用户写异常处理代码。
--   每个 CAST 变体都应该有对应的 TRY_ 版本。

-- ============================================================
-- 7. GREATEST / LEAST（2022+, SQL Server 最新添加）
-- ============================================================

SELECT GREATEST(1, 3, 2);  -- 3
SELECT LEAST(1, 3, 2);     -- 1

-- 2022 之前需要用 CASE 或 IIF 模拟:
SELECT IIF(5 > 3, 5, 3);   -- MAX of two values
-- 多值需要嵌套 IIF 或 VALUES + CROSS APPLY:
SELECT (SELECT MAX(v) FROM (VALUES (a),(b),(c)) AS t(v)) AS greatest_val;

-- 横向对比:
--   PostgreSQL: GREATEST/LEAST（从第一个版本就支持）
--   MySQL:      GREATEST/LEAST（很早就支持）
--   Oracle:     GREATEST/LEAST（很早就支持）
--   SQL Server: 2022 才添加（最晚的主流数据库）

-- ============================================================
-- 8. IS NULL 判断与 SQL Server 的 ANSI_NULLS 设置
-- ============================================================

SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;

-- SET ANSI_NULLS 控制 NULL 比较行为:
-- SET ANSI_NULLS ON（默认）: NULL = NULL → UNKNOWN（标准行为）
-- SET ANSI_NULLS OFF:        NULL = NULL → TRUE（非标准，已废弃）
-- 注意: SET ANSI_NULLS OFF 已计划在未来版本中移除。
--
-- 对引擎开发者的启示:
--   永远不要提供非标准的 NULL 比较选项——这只会造成混乱。
--   SQL Server 保留这个选项是为了向后兼容，但它是技术债务的典型例子。
