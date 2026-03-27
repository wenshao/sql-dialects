-- PostgreSQL: 条件函数与表达式
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Conditional Expressions
--       https://www.postgresql.org/docs/current/functions-conditional.html
--   [2] PostgreSQL Source - Type Coercion
--       https://www.postgresql.org/docs/current/typeconv.html

-- ============================================================
-- 1. CASE WHEN 表达式
-- ============================================================

-- 搜索型 CASE
SELECT username,
    CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END AS category
FROM users;

-- 简单 CASE
SELECT username,
    CASE status WHEN 0 THEN 'inactive' WHEN 1 THEN 'active' ELSE 'unknown' END
FROM users;

-- ============================================================
-- 2. COALESCE / NULLIF / GREATEST / LEAST
-- ============================================================

SELECT COALESCE(phone, email, 'unknown') FROM users;   -- 第一个非 NULL 值
SELECT NULLIF(age, 0) FROM users;                       -- 相等返回 NULL
SELECT GREATEST(1, 3, 2);                               -- 3
SELECT LEAST(1, 3, 2);                                  -- 1

-- ============================================================
-- 3. :: 类型转换运算符: PostgreSQL 的解析器设计选择
-- ============================================================

SELECT CAST('123' AS INTEGER);        -- SQL 标准
SELECT '123'::INTEGER;                -- PostgreSQL 特有的 :: 语法
SELECT '2024-01-15'::DATE;
SELECT 'true'::BOOLEAN;
SELECT '192.168.1.1'::INET;           -- PostgreSQL 专有类型
SELECT '{"a":1}'::JSONB;

-- 设计分析: 为什么 PostgreSQL 有 :: 运算符
--   :: 是 PostgreSQL 解析器（gram.y）中的硬编码运算符。
--   在词法分析阶段，:: 被识别为 TYPECAST token。
--   它比 CAST(x AS type) 更简洁，尤其在嵌套表达式中:
--     CAST(CAST(data->>'age' AS INTEGER) AS TEXT)  -- 冗长
--     (data->>'age')::INT::TEXT                     -- 简洁
--
--   trade-off:
--     优点: 简洁、链式调用方便
--     缺点: 不可移植（MySQL/Oracle/SQL Server 不支持）
--
--   对引擎开发者:
--     如果目标是 PostgreSQL 兼容，:: 是必须实现的语法。
--     CockroachDB, YugabyteDB, Neon 都实现了 :: 运算符。

-- ============================================================
-- 4. PostgreSQL 的类型严格性
-- ============================================================

-- PostgreSQL 类型系统是严格的——不隐式转换不兼容类型
SELECT 'hello' || 42;           -- 错误！TEXT || INTEGER 不匹配
SELECT 'hello' || 42::TEXT;     -- 正确: 'hello42'

-- 数值间: 自动提升（INT → BIGINT → NUMERIC → FLOAT）
SELECT 1 + 1.5;                -- 2.5 (INT → NUMERIC)

-- 字符串到数值: 不隐式转换
-- SELECT 'abc' + 1;           -- 错误!（MySQL 会返回 1）

-- 对比:
--   PostgreSQL: 严格（需要显式 CAST/::）
--   MySQL:      宽松（'123' + 0 = 123，'abc' + 0 = 0，静默转换）
--   Oracle:     中等（TO_NUMBER/TO_CHAR 显式转换为主）
--   SQL Server: 中等（有隐式转换规则表）
--   SQLite:     极宽松（动态类型，任何列存任何类型）
--
-- PostgreSQL 的严格性是有意的设计:
--   防止类型混淆导致的隐蔽 bug（如 MySQL 的 WHERE col = 0 匹配所有非数字行）。

-- ============================================================
-- 5. IS DISTINCT FROM: NULL 安全的比较
-- ============================================================

-- 标准 SQL:  NULL = NULL → NULL (UNKNOWN)
-- IS DISTINCT FROM:  NULL IS NOT DISTINCT FROM NULL → TRUE

SELECT * FROM users WHERE phone IS DISTINCT FROM 'unknown';
-- NULL IS DISTINCT FROM 'unknown' → TRUE（会返回 phone=NULL 的行）

SELECT * FROM users WHERE phone IS NOT DISTINCT FROM NULL;
-- 等同于 WHERE phone IS NULL

-- 设计分析:
--   IS DISTINCT FROM 是 SQL:1999 标准，解决了三值逻辑的痛点。
--   对比 MySQL 的 <=> 运算符（NULL-safe equal，非标准）:
--     MySQL:      WHERE a <=> b
--     PostgreSQL: WHERE a IS NOT DISTINCT FROM b
--   PostgreSQL 选择了更冗长但符合标准的语法。

-- ============================================================
-- 6. 布尔表达式: PostgreSQL 的真正布尔类型
-- ============================================================

-- PostgreSQL 的 BOOLEAN 是真正的类型（不是 TINYINT(1) 的别名）
SELECT username, (age >= 18) AS is_adult FROM users;
-- 直接在 SELECT 中使用布尔表达式（MySQL 也支持但行为可能不同）

-- WHERE 子句中直接使用布尔列
SELECT * FROM users WHERE active;         -- 等同于 WHERE active = TRUE
SELECT * FROM users WHERE NOT active;     -- 等同于 WHERE active = FALSE

-- ============================================================
-- 7. num_nulls / num_nonnulls (9.6+)
-- ============================================================

SELECT num_nulls(phone, email, city) FROM users;      -- NULL 参数个数
SELECT num_nonnulls(phone, email, city) FROM users;   -- 非 NULL 参数个数

-- 实用场景: 数据完整性检查
SELECT * FROM users WHERE num_nulls(phone, email, address) > 1;

-- ============================================================
-- 8. 安全类型转换（PostgreSQL 没有 TRY_CAST）
-- ============================================================

-- PostgreSQL 没有内置 TRY_CAST（SQL Server 有）
-- 解决方案 1: 正则判断
SELECT CASE WHEN '123a' ~ '^\d+$' THEN '123a'::INTEGER ELSE NULL END;

-- 解决方案 2: 自定义函数
CREATE OR REPLACE FUNCTION try_cast_int(text) RETURNS INTEGER AS $$
BEGIN RETURN $1::INTEGER;
EXCEPTION WHEN OTHERS THEN RETURN NULL;
END; $$ LANGUAGE plpgsql IMMUTABLE;

SELECT try_cast_int('123');     -- 123
SELECT try_cast_int('abc');     -- NULL（不报错）

-- 对比:
--   SQL Server: TRY_CAST('abc' AS INT) → NULL
--   BigQuery:   SAFE_CAST('abc' AS INT64) → NULL
--   PostgreSQL: 需要自定义函数（社区长期讨论但未纳入核心）

-- ============================================================
-- 9. 横向对比: 条件函数差异
-- ============================================================

-- 1. NULL 处理:
--   PostgreSQL: COALESCE (标准), NULLIF (标准)
--   MySQL:      COALESCE, IFNULL(a,b), IF(cond,t,f)
--   Oracle:     COALESCE, NVL(a,b), NVL2(a,b,c), DECODE
--   SQL Server: COALESCE, ISNULL(a,b), IIF(cond,t,f)
--
-- 2. :: 类型转换:
--   PostgreSQL: :: 运算符 + CAST（两种语法）
--   MySQL:      CAST + CONVERT
--   Oracle:     CAST + TO_NUMBER/TO_CHAR/TO_DATE
--   SQL Server: CAST + CONVERT + TRY_CAST + TRY_CONVERT
--
-- 3. 布尔类型:
--   PostgreSQL: 真正的 BOOLEAN (TRUE/FALSE/NULL)
--   MySQL:      TINYINT(1) 的别名，0/1
--   Oracle:     无布尔类型（PL/SQL 有，SQL 没有）
--   SQL Server: BIT (0/1/NULL)

-- ============================================================
-- 10. 对引擎开发者的启示
-- ============================================================

-- (1) :: 运算符的实现:
--     :: 在解析器中作为一元后缀运算符处理，优先级高于大多数运算符。
--     语法: expression::typename，展开为 CAST(expression AS typename)。
--     解析器需要特殊处理: typename 不是普通标识符，可能是数组类型（INT[]）。
--
-- (2) 类型严格性是安全性的基础:
--     MySQL 的隐式转换导致了无数 SQL 注入和逻辑 bug。
--     新引擎应该默认严格，必要时提供显式宽松模式。
--
-- (3) IS DISTINCT FROM 应该成为标准配置:
--     三值逻辑是 SQL 最大的复杂性来源之一。
--     IS DISTINCT FROM 提供了直觉性的 NULL 比较，应该优先推荐。

-- ============================================================
-- 11. 版本演进
-- ============================================================
-- PostgreSQL 8.2:  IS DISTINCT FROM（SQL:1999 标准）
-- PostgreSQL 9.4:  FILTER 子句（条件聚合）
-- PostgreSQL 9.6:  num_nulls / num_nonnulls
-- PostgreSQL 14:   IS JSON 谓词（检查字符串是否为有效 JSON）
