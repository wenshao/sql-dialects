-- MaxCompute (ODPS): 类型转换
--
-- 参考资料:
--   [1] MaxCompute SQL Reference - Type Conversion
--       https://help.aliyun.com/zh/maxcompute/user-guide/type-conversions

-- ============================================================
-- 1. CAST —— 显式类型转换
-- ============================================================

-- 数值转换
SELECT CAST('42' AS BIGINT);                -- STRING → BIGINT
SELECT CAST(42 AS STRING);                  -- BIGINT → STRING
SELECT CAST('3.14' AS DOUBLE);              -- STRING → DOUBLE
SELECT CAST('3.14' AS DECIMAL(10,2));       -- STRING → DECIMAL
SELECT CAST(3.14 AS BIGINT);               -- DOUBLE → BIGINT（截断，非四舍五入）
SELECT CAST(42 AS FLOAT);                   -- BIGINT → FLOAT
SELECT CAST(TRUE AS BIGINT);               -- BOOLEAN → BIGINT（TRUE=1, FALSE=0）
SELECT CAST(0 AS BOOLEAN);                 -- BIGINT → BOOLEAN（0=FALSE, 非0=TRUE）
SELECT CAST(100 AS INT);                    -- BIGINT → INT（2.0+）

-- 日期转换
SELECT TO_DATE('2024-01-15', 'yyyy-MM-dd');             -- STRING → DATETIME
SELECT TO_CHAR(GETDATE(), 'yyyy-MM-dd HH:mm:ss');       -- DATETIME → STRING
SELECT CAST('2024-01-15' AS DATE);                       -- STRING → DATE（2.0+）
SELECT CAST('2024-01-15 10:30:00' AS DATETIME);          -- STRING → DATETIME

-- Unix 时间戳转换
SELECT FROM_UNIXTIME(1705276800);                        -- BIGINT → DATETIME
SELECT FROM_UNIXTIME(1705276800, 'yyyy-MM-dd HH:mm:ss');-- BIGINT → STRING
SELECT UNIX_TIMESTAMP(GETDATE());                        -- DATETIME → BIGINT

-- ============================================================
-- 2. CAST 失败行为 —— MaxCompute 的重大限制
-- ============================================================

-- CAST 转换失败: 直接报错并终止整个作业
-- 这是 MaxCompute 最常被抱怨的行为之一

-- 对比:
--   MaxCompute: CAST('abc' AS BIGINT) → 作业失败
--   BigQuery:   SAFE_CAST('abc' AS INT64) → NULL
--   Snowflake:  TRY_CAST('abc' AS INTEGER) → NULL
--   SQL Server: TRY_CAST('abc' AS INT) → NULL
--   PostgreSQL: CAST('abc' AS INTEGER) → 报错（但支持事务回滚）
--   MySQL:      CAST('abc' AS SIGNED) → 0（宽松模式）

-- 安全转换的替代方案（手动验证）:
SELECT
    CASE WHEN col RLIKE '^-?[0-9]+$'
         THEN CAST(col AS BIGINT)
         ELSE NULL
    END AS safe_int
FROM dirty_data;

SELECT
    CASE WHEN col RLIKE '^-?[0-9]+(\\.[0-9]+)?$'
         THEN CAST(col AS DOUBLE)
         ELSE NULL
    END AS safe_double
FROM dirty_data;

SELECT
    CASE WHEN ISDATE(col, 'yyyy-MM-dd')
         THEN TO_DATE(col, 'yyyy-MM-dd')
         ELSE NULL
    END AS safe_date
FROM dirty_data;

-- 对引擎开发者: TRY_CAST/SAFE_CAST 是数据工程的刚需
--   批处理作业中一条脏数据不应杀死整个作业（数小时的工作白费）
--   应优先实现 TRY_CAST 而非让用户写复杂的 CASE + REGEXP

-- ============================================================
-- 3. 隐式转换规则
-- ============================================================

-- 数值提升链: TINYINT → SMALLINT → INT → BIGINT → FLOAT → DOUBLE
SELECT 1 + 1.5;                             -- INT + DOUBLE → DOUBLE
SELECT '42' + 0;                            -- STRING + BIGINT → DOUBLE（隐式转换）
SELECT CONCAT('val: ', 42);                 -- 42 隐式转为 STRING

-- 1.0 vs 2.0 隐式转换差异:
--   1.0: 更宽松（STRING 与 数值 混合运算自动转换）
--   2.0: 更严格（部分隐式转换被禁止）
--
--   例子: SELECT '10' > 9;
--     1.0: '10' 转为 DOUBLE 10.0，比较 10.0 > 9 → TRUE
--     2.0: 可能报类型不匹配错误
--
--   对引擎开发者: 隐式转换规则应严格且一致
--     过于宽松的隐式转换（如 MySQL 的 '123abc' → 123）是安全隐患
--     完全禁止隐式转换（如 PostgreSQL）增加用户负担

-- ============================================================
-- 4. 日期/时间格式化
-- ============================================================

-- 格式码体系（Java SimpleDateFormat）:
--   yyyy: 4 位年
--   MM:   2 位月（大写!）
--   dd:   2 位日
--   HH:   24 小时制（大写!）
--   mm:   2 位分钟（小写!）
--   ss:   2 位秒

-- 常用格式:
SELECT TO_CHAR(GETDATE(), 'yyyy-MM-dd HH:mm:ss');   -- 标准格式
SELECT TO_CHAR(GETDATE(), 'yyyyMMdd');               -- 分区键格式
SELECT TO_CHAR(GETDATE(), 'yyyy年MM月dd日');          -- 中文格式

-- 解析:
SELECT TO_DATE('20240115', 'yyyyMMdd');               -- 分区键→DATETIME
SELECT TO_DATE('2024/01/15', 'yyyy/MM/dd');           -- 斜杠分隔
SELECT TO_DATE('Jan 15 2024', 'MMM dd yyyy');         -- 英文月名

-- ============================================================
-- 5. 复合类型转换
-- ============================================================

SELECT CAST(ARRAY(1, 2, 3) AS ARRAY<STRING>);         -- ARRAY<INT> → ARRAY<STRING>
-- MAP 和 STRUCT 的类型转换支持有限

-- JSON 转换（STRING ↔ JSON）
SELECT GET_JSON_OBJECT('{"a":1}', '$.a');              -- JSON STRING → STRING

-- ============================================================
-- 6. 类型转换矩阵（简化版）
-- ============================================================

-- 从\到    | BIGINT | DOUBLE | STRING | DATETIME | BOOLEAN | DECIMAL
-- ---------|--------|--------|--------|----------|---------|--------
-- BIGINT   | -      | 隐式   | CAST   | 不可     | CAST    | CAST
-- DOUBLE   | CAST   | -      | CAST   | 不可     | 不可    | CAST
-- STRING   | CAST   | CAST   | -      | TO_DATE  | CAST    | CAST
-- DATETIME | 不可   | 不可   | TO_CHAR| -        | 不可    | 不可
-- BOOLEAN  | CAST   | 不可   | CAST   | 不可     | -       | 不可
-- DECIMAL  | CAST   | CAST   | CAST   | 不可     | 不可    | -

-- ============================================================
-- 7. 横向对比: 类型转换
-- ============================================================

-- CAST 语法:
--   MaxCompute: CAST(expr AS type)      | 所有引擎均支持
--   PostgreSQL: expr::type（简写）      | MaxCompute: 不支持 ::
--   SQL Server: CONVERT(type, expr)     | MaxCompute: 不支持 CONVERT

-- 安全转换:
--   MaxCompute: 不支持                  | BigQuery: SAFE_CAST
--   Snowflake:  TRY_CAST               | SQL Server: TRY_CAST
--   PostgreSQL: 不支持（需自定义）

-- 隐式转换严格度:
--   MaxCompute: 中等（Hive 兼容）       | PostgreSQL: 严格
--   MySQL:      宽松                    | SQLite: 极宽松（动态类型）

-- ============================================================
-- 8. 对引擎开发者的启示
-- ============================================================

-- 1. TRY_CAST/SAFE_CAST 是最高优先级的类型转换功能 — 数据工程刚需
-- 2. :: 简写语法（PostgreSQL 风格）极大提升 SQL 可读性 — 值得支持
-- 3. 隐式转换规则必须完整文档化 — 1.0/2.0 行为差异是用户的主要困惑源
-- 4. 日期格式码应统一为一套体系 — 避免 TO_CHAR/DATE_FORMAT 两套格式码
-- 5. BOOLEAN ↔ INTEGER 的转换应该支持（TRUE=1/FALSE=0 是通用约定）
-- 6. 类型转换矩阵应在文档中完整列出（每对类型的转换规则和精度影响）
