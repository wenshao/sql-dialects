-- ClickHouse: 错误处理（Error Handling）
--
-- 参考资料:
--   [1] ClickHouse Documentation - Error Codes
--       https://clickhouse.com/docs/en/interfaces/formats
--   [2] ClickHouse - Safe Functions
--       https://clickhouse.com/docs/en/sql-reference/functions/type-conversion-functions

-- ============================================================
-- 1. ClickHouse 没有服务端错误处理（为什么）
-- ============================================================

-- ClickHouse 不支持 TRY/CATCH、EXCEPTION、DECLARE HANDLER。
-- 原因: ClickHouse 没有存储过程或过程式语言。
-- SQL 是声明式的，每个查询独立执行，失败则返回错误码给客户端。
--
-- 但 ClickHouse 有一个独特的设计: "安全函数族"
-- 通过函数变体在 SQL 层面避免运行时错误，而非捕获错误。
-- 这比 TRY/CATCH 更适合 OLAP 场景:
--   OLAP 查询处理百万行，一行的类型转换失败不应终止整个查询。

-- ============================================================
-- 2. 安全函数族: *OrZero / *OrNull / *OrDefault / try*
-- ============================================================

-- 2.1 类型转换安全函数
SELECT toUInt64('42');               -- 42
SELECT toUInt64('not_a_number');     -- 报错!
SELECT toUInt64OrZero('not_a_number');  -- 0（失败返回零值）
SELECT toUInt64OrNull('not_a_number');  -- NULL（失败返回 NULL）
SELECT toFloat64OrZero('abc');       -- 0.0
SELECT toDateOrNull('invalid');      -- NULL

-- 2.2 聚合函数安全变体
SELECT sumOrDefault(amount) FROM empty_table;    -- 0（空表返回默认值）
SELECT avgOrNull(amount) FROM empty_table;       -- NULL
SELECT countOrDefault(id) FROM empty_table;      -- 0

-- 2.3 try* 函数
SELECT tryBase64Decode('invalid-base64');     -- 空字符串（失败不报错）

-- 设计分析:
--   这种"安全函数族"设计是 ClickHouse 独有的:
--   每个可能失败的函数都有 OrZero/OrNull/OrDefault 变体。
--   这比 PostgreSQL 的 EXCEPTION WHEN 更轻量（无异常处理开销）。
--   适合 OLAP: 批量数据中个别脏数据不应中断整个分析查询。
--
-- 对比:
--   PostgreSQL: TRY_CAST 不存在，需要 EXCEPTION WHEN 或 PL/pgSQL
--   MySQL:      CAST 失败返回 0/NULL（取决于 sql_mode）
--   BigQuery:   SAFE_CAST 返回 NULL
--   SQL Server: TRY_CAST / TRY_CONVERT

-- ============================================================
-- 3. SQL 层面的错误避免
-- ============================================================

-- IF EXISTS / IF NOT EXISTS
CREATE TABLE IF NOT EXISTS users (id UInt64, name String) ENGINE = MergeTree() ORDER BY id;
DROP TABLE IF EXISTS temp_table;

-- 条件表达式避免除零等错误
SELECT if(denominator != 0, numerator / denominator, 0) FROM data;
SELECT intDivOrZero(numerator, denominator) FROM data;

-- isNull / isNotNull 保护
SELECT if(isNotNull(value), toFloat64(value), 0.0) FROM data;

-- multiIf 替代多层嵌套（减少出错概率）
SELECT multiIf(
    status = 0, 'inactive',
    status = 1, 'active',
    status = 2, 'suspended',
    'unknown'
) FROM users;

-- ============================================================
-- 4. Mutation 错误处理
-- ============================================================

-- Mutation 失败不会自动重试:
SELECT mutation_id, command, latest_fail_reason, latest_fail_time
FROM system.mutations
WHERE table = 'users' AND is_done = 0;

-- 取消失败的 mutation:
KILL MUTATION WHERE mutation_id = 'xxx';

-- ============================================================
-- 5. 对比与引擎开发者启示
-- ============================================================
-- ClickHouse 的错误处理设计:
--   (1) 无 TRY/CATCH → 安全函数族替代
--   (2) *OrZero/*OrNull → 每个危险函数都有安全变体
--   (3) 适合 OLAP → 脏数据不中断批量查询
--
-- 对引擎开发者的启示:
--   OLAP 引擎应该为所有类型转换函数提供安全变体。
--   这比 TRY/CATCH 更高效（无异常栈展开开销），
--   也更符合 OLAP 的批量处理模式:
--   一行的错误不应该终止整个查询的执行。
