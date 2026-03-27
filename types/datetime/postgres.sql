-- PostgreSQL: 日期时间类型
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Date/Time Types
--       https://www.postgresql.org/docs/current/datatype-datetime.html
--   [2] PostgreSQL Source - timestamp.c, date.c
--       https://github.com/postgres/postgres/blob/master/src/backend/utils/adt/timestamp.c

-- ============================================================
-- 1. 类型概览
-- ============================================================

-- DATE:       日期，4 字节，4713 BC ~ 5874897 AD
-- TIME:       时间（无时区），8 字节
-- TIMETZ:     时间（带时区），12 字节（不推荐）
-- TIMESTAMP:  日期时间（无时区），8 字节，4713 BC ~ 294276 AD
-- TIMESTAMPTZ: 日期时间（带时区），8 字节（推荐!）
-- INTERVAL:   时间间隔，16 字节

CREATE TABLE events (
    id         BIGSERIAL PRIMARY KEY,
    event_date DATE,
    event_time TIME(3),            -- 毫秒精度
    created_at TIMESTAMP(6),       -- 微秒精度（默认6位）
    updated_at TIMESTAMPTZ         -- 推荐：带时区
);

-- ============================================================
-- 2. TIMESTAMP vs TIMESTAMPTZ: 设计选择的核心
-- ============================================================

-- TIMESTAMP: 存字面值，不做时区转换
--   适用: 不关心时区的时间（如"预约时间 14:00"不应因时区而变）
--
-- TIMESTAMPTZ: 存入时转为 UTC，读取时转为会话时区
--   适用: 所有需要跨时区正确显示的场景（官方推荐!）

SET timezone = 'Asia/Shanghai';
SELECT '2024-01-15 10:00:00'::TIMESTAMP;        -- 10:00:00 (不变)
SELECT '2024-01-15 10:00:00'::TIMESTAMPTZ;       -- 10:00:00+08
SET timezone = 'UTC';
SELECT '2024-01-15 10:00:00+08'::TIMESTAMPTZ;   -- 02:00:00+00 (转为UTC)

-- 内部存储:
--   TIMESTAMPTZ 和 TIMESTAMP 都是 8 字节 int64（微秒数）。
--   TIMESTAMPTZ 存储的是 UTC 时间，显示时按 session timezone 转换。
--   TIMESTAMP 存的就是字面值，完全不考虑时区。
--
-- 一个常见误解:
--   TIMESTAMPTZ 不存储时区信息！它只存 UTC 时间。
--   "WITH TIME ZONE" 的含义是"输入时考虑时区，输出时转换时区"。

-- ============================================================
-- 3. INTERVAL 类型: 三部分存储
-- ============================================================

SELECT INTERVAL '1 year 2 months 3 days 4 hours';

-- INTERVAL 内部存储:
--   months: 整数（年×12 + 月数）
--   days:   整数（天数）
--   microseconds: int64（时/分/秒的微秒数）
--
-- 为什么不统一为微秒?
--   1 month ≠ 30 days（2月只有28/29天，各月天数不同）
--   1 day ≠ 24 hours（夏令时切换日可能是23或25小时）
--   因此三部分必须独立存储，加法时分别计算。

-- 日期运算
SELECT NOW() + INTERVAL '1 day';
SELECT '2024-12-31'::DATE - '2024-01-01'::DATE;  -- 365 (INTEGER!)
SELECT AGE('2024-12-31', '2024-01-01');            -- INTERVAL

-- ============================================================
-- 4. NOW() vs CLOCK_TIMESTAMP()
-- ============================================================

SELECT NOW();                    -- 事务开始时间（同一事务内不变）
SELECT CLOCK_TIMESTAMP();       -- 真实当前时间（每次调用不同）
SELECT STATEMENT_TIMESTAMP();   -- 语句开始时间
SELECT TRANSACTION_TIMESTAMP(); -- 同 NOW()

-- 设计原因:
--   事务内时间一致性: 审计日志的多条记录应有相同时间戳。
--   对比 MySQL: NOW() 是语句级的（同一语句不变，不同语句变化）。

-- ============================================================
-- 5. AT TIME ZONE 的语义双重性
-- ============================================================

-- 规则（常让人困惑）:
--   TIMESTAMPTZ AT TIME ZONE 'X' → TIMESTAMP（去掉时区，转为X时区的本地时间）
--   TIMESTAMP   AT TIME ZONE 'X' → TIMESTAMPTZ（假设输入是X时区，转为UTC）

SELECT TIMESTAMPTZ '2024-01-15 10:00+08' AT TIME ZONE 'UTC';
-- 结果: TIMESTAMP '2024-01-15 02:00:00' (UTC本地时间)

SELECT TIMESTAMP '2024-01-15 10:00:00' AT TIME ZONE 'Asia/Shanghai';
-- 结果: TIMESTAMPTZ '2024-01-15 10:00:00+08' (假设输入是上海时间)

-- ============================================================
-- 6. 横向对比: 日期时间类型差异
-- ============================================================

-- 1. 时间精度:
--   PostgreSQL: 微秒（6位小数，TIMESTAMP(6)）
--   MySQL:      微秒（5.6.4+，DATETIME(6)）
--   Oracle:     纳秒（TIMESTAMP(9)）
--   SQL Server: 100纳秒（DATETIME2(7)）
--   ClickHouse: 纳秒（DateTime64(9)）
--
-- 2. 时区处理:
--   PostgreSQL: TIMESTAMP vs TIMESTAMPTZ（存UTC，显示转换）
--   MySQL:      DATETIME（无时区）vs TIMESTAMP（存UTC，有2038问题!）
--   Oracle:     TIMESTAMP vs TIMESTAMP WITH TIME ZONE vs WITH LOCAL TZ（三种）
--   SQL Server: DATETIME2 vs DATETIMEOFFSET（存储时区偏移量）
--
-- 3. 2038 年问题:
--   PostgreSQL: 无（int64 存储，范围到 294276 AD）
--   MySQL:      TIMESTAMP 类型有 2038 问题（32位 Unix 时间戳）
--               DATETIME 无此问题（范围到 9999-12-31）
--
-- 4. INTERVAL 类型:
--   PostgreSQL: 功能最丰富（三部分独立存储）
--   MySQL:      无独立 INTERVAL 类型（只能在 DATE_ADD 中使用）
--   Oracle:     INTERVAL YEAR TO MONTH / INTERVAL DAY TO SECOND（两种）
--   SQL Server: 无 INTERVAL 类型

-- ============================================================
-- 7. 对引擎开发者的启示
-- ============================================================

-- (1) "TIMESTAMPTZ 不存储时区" 是反直觉但正确的设计:
--     存 UTC + 显示时转换 = 最简单最正确的实现。
--     SQL Server 的 DATETIMEOFFSET 存储偏移量，但同一时刻可能有
--     多种表示（+08:00 vs Asia/Shanghai vs CST），语义更复杂。
--
-- (2) INTERVAL 三部分存储是日历正确性的保证:
--     "1 month + 15 days" 不能简化为"45 days"（月份天数不固定）。
--     新引擎如果只存微秒数，在月/年运算时会产生精度问题。
--
-- (3) 事务时间 vs 语句时间 vs 实际时间 的区分:
--     对审计和事务一致性至关重要。
--     NOW() = 事务时间是正确的默认行为。

-- ============================================================
-- 8. 版本演进
-- ============================================================
-- PostgreSQL 全版本: DATE, TIME, TIMESTAMP, TIMESTAMPTZ, INTERVAL
-- PostgreSQL 8.4:   MAKE_TIMESTAMP 系列函数
-- PostgreSQL 12:    DATE_TRUNC 支持 AT TIME ZONE 参数
-- PostgreSQL 14:    EXTRACT 返回 NUMERIC（之前返回 FLOAT8 有精度问题）
-- PostgreSQL 16:    改进 INTERVAL 的比较语义
