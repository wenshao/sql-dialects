-- MaxCompute (ODPS): 条件函数
--
-- 参考资料:
--   [1] MaxCompute SQL - Other Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/other-functions
--   [2] MaxCompute Built-in Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/built-in-functions-overview

-- ============================================================
-- 1. CASE WHEN —— SQL 标准条件表达式
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
        WHEN 2 THEN 'deleted'
        ELSE 'unknown'
    END AS status_name
FROM users;

-- ============================================================
-- 2. IF —— 三元条件函数（Hive 兼容）
-- ============================================================

SELECT IF(age >= 18, 'adult', 'minor') FROM users;
SELECT IF(amount > 0, amount, 0) FROM orders;

-- 设计分析: IF 函数 vs CASE WHEN
--   IF(cond, then, else) 是 CASE WHEN cond THEN then ELSE else END 的简写
--   Hive/MaxCompute: IF 是内置函数
--   MySQL: IF 是内置函数（相同语义）
--   PostgreSQL: 无 IF 函数（只有 CASE WHEN）
--   BigQuery: IF 是内置函数
--   标准 SQL: 只有 CASE WHEN（IF 是各方言的扩展）

-- ============================================================
-- 3. NULL 处理函数
-- ============================================================

-- COALESCE: 返回第一个非 NULL 值（SQL 标准）
SELECT COALESCE(phone, email, 'unknown') FROM users;

-- NVL: 两参数版本的 COALESCE（Oracle 兼容）
SELECT NVL(phone, 'no phone') FROM users;

-- NVL2: 三元 NULL 判断（Oracle 兼容，非常实用）
SELECT NVL2(phone, 'has phone', 'no phone') FROM users;
-- NVL2(expr, not_null_value, null_value):
--   expr 非 NULL → 返回 not_null_value
--   expr 为 NULL → 返回 null_value

-- NULLIF: 相等则返回 NULL
SELECT NULLIF(age, 0) FROM users;           -- age=0 时返回 NULL

-- 设计分析: NVL vs COALESCE
--   NVL(a, b): Oracle 遗产，只接受两个参数
--   COALESCE(a, b, c, ...): SQL 标准，接受任意多个参数
--   MaxCompute 同时支持两者 — Oracle 迁移友好
--   最佳实践: 新代码用 COALESCE（标准兼容），旧 Oracle 代码用 NVL

-- ============================================================
-- 4. DECODE —— Oracle 兼容的简单 CASE 替代
-- ============================================================

SELECT DECODE(status, 0, 'inactive', 1, 'active', 2, 'deleted', 'unknown')
FROM users;

-- DECODE(expr, val1, result1, val2, result2, ..., default):
--   等价于 CASE expr WHEN val1 THEN result1 WHEN val2 THEN result2 ELSE default END
--   Oracle 的经典函数，MaxCompute 完整支持
--   PostgreSQL: 不支持 DECODE（用 CASE WHEN）
--   BigQuery:   不支持 DECODE

-- ============================================================
-- 5. GREATEST / LEAST
-- ============================================================

SELECT GREATEST(1, 3, 2);                   -- 3（最大值）
SELECT LEAST(1, 3, 2);                      -- 1（最小值）

-- 对比: GREATEST/LEAST 是跨列的 MAX/MIN
--   MAX(col): 聚合函数，跨行取最大值
--   GREATEST(col1, col2, col3): 标量函数，同一行多列取最大值
--   这个区别很多初学者混淆

-- NULL 处理:
--   MaxCompute: 如果任一参数为 NULL，结果为 NULL
--   对比 PostgreSQL: GREATEST(1, NULL, 3) = 3（忽略 NULL）

-- ============================================================
-- 6. 类型判断与转换
-- ============================================================

-- 类型判断
SELECT TYPEOF(123);                         -- 返回类型名
SELECT GETTYPE(123);                        -- 返回类型名（别名）

-- CAST: 显式类型转换
SELECT CAST('123' AS BIGINT);
SELECT CAST(123 AS STRING);
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('true' AS BOOLEAN);

-- 注意: 没有 TRY_CAST / SAFE_CAST
--   转换失败直接报错并中止整个作业
--   对比:
--     BigQuery:   SAFE_CAST('abc' AS INT64) → NULL（不报错）
--     Snowflake:  TRY_CAST('abc' AS INTEGER) → NULL
--     SQL Server: TRY_CAST('abc' AS INT) → NULL
--     PostgreSQL: 无 TRY_CAST（需要自定义函数或用 CASE + 正则验证）
--     MySQL:      CAST 对无效值返回 0 或 NULL（取决于 sql_mode）
--
--   这是 MaxCompute 的重大限制:
--     ETL 管道中遇到一条脏数据就整个作业失败
--     替代方案: 在 CAST 前用 REGEXP 验证数据格式
SELECT
    CASE WHEN col RLIKE '^[0-9]+$' THEN CAST(col AS BIGINT) ELSE NULL END AS safe_val
FROM dirty_data;

-- 不支持 :: 转换语法（PostgreSQL 风格）
-- 不支持 CONVERT 函数（SQL Server 风格）

-- ============================================================
-- 7. IS 判断
-- ============================================================

SELECT * FROM users WHERE phone IS NULL;
SELECT * FROM users WHERE phone IS NOT NULL;

-- IN 判断
SELECT * FROM users WHERE city IN ('Beijing', 'Shanghai', 'Guangzhou');

-- BETWEEN
SELECT * FROM orders WHERE amount BETWEEN 100 AND 1000;

-- ============================================================
-- 8. 横向对比: 条件函数
-- ============================================================

-- IF 函数:
--   MaxCompute: IF(cond, a, b)   | MySQL: IF(cond, a, b) | Hive: IF(cond, a, b)
--   PostgreSQL: 不支持           | BigQuery: IF(cond, a, b)
--   SQL Server: IIF(cond, a, b)

-- NVL:
--   MaxCompute: NVL(a, b)        | Oracle: NVL(a, b)
--   PostgreSQL: 不支持           | MySQL: IFNULL(a, b)
--   SQL Server: ISNULL(a, b)     | BigQuery: IFNULL(a, b)

-- DECODE:
--   MaxCompute: 支持             | Oracle: 支持
--   PostgreSQL: 不支持           | BigQuery: 不支持

-- TRY_CAST:
--   MaxCompute: 不支持           | BigQuery: SAFE_CAST | Snowflake: TRY_CAST
--   SQL Server: TRY_CAST         | PostgreSQL: 不支持

-- ============================================================
-- 9. 对引擎开发者的启示
-- ============================================================

-- 1. TRY_CAST/SAFE_CAST 是数据工程的刚需 — 一条脏数据不应杀死整个作业
-- 2. IF 函数虽非标准但使用率极高 — 值得作为 CASE WHEN 的语法糖支持
-- 3. NVL/DECODE 等 Oracle 兼容函数降低了迁移成本 — 值得投资
-- 4. GREATEST/LEAST 的 NULL 处理语义应该与生态主流保持一致
-- 5. 条件函数是 SQL 中使用频率最高的函数族 — 性能优化优先级高
-- 6. CASE WHEN 的短路求值（短路评估）行为应明确文档化
