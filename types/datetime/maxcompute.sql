-- MaxCompute (ODPS): 日期时间类型
--
-- 参考资料:
--   [1] MaxCompute SQL - Data Types
--       https://help.aliyun.com/zh/maxcompute/user-guide/data-types-1
--   [2] MaxCompute - Date Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/date-functions

-- ============================================================
-- 1. 日期时间类型总览
-- ============================================================

-- DATETIME:   日期+时间，精度到毫秒，0000-01-01 ~ 9999-12-31（1.0+）
-- DATE:       仅日期，0001-01-01 ~ 9999-12-31（2.0+）
-- TIMESTAMP:  日期+时间，精度到纳秒（2.0+）

SET odps.sql.type.system.odps2 = true;

CREATE TABLE events (
    id           BIGINT,
    event_date   DATE,                      -- 2.0+ 仅日期
    created_at   DATETIME,                  -- 1.0+ 精度毫秒
    precise_at   TIMESTAMP                  -- 2.0+ 精度纳秒
);

-- ============================================================
-- 2. 设计决策: DATETIME vs TIMESTAMP
-- ============================================================

-- DATETIME（1.0 唯一的时间类型）:
--   精度: 毫秒（3 位小数）
--   范围: 0000-01-01 00:00:00.000 ~ 9999-12-31 23:59:59.999
--   语义: 绝对时间点（无时区信息）
--   存储: 内部为毫秒级 Unix 时间戳

-- TIMESTAMP（2.0 引入，Hive 兼容）:
--   精度: 纳秒（9 位小数）
--   范围: 0001-01-01 00:00:00.000000000 ~ 9999-12-31 23:59:59.999999999
--   语义: 绝对时间点（无时区信息，与 MySQL TIMESTAMP 不同!）
--   存储: 内部为纳秒级表示

-- 关键差异: MaxCompute 的 TIMESTAMP 不做时区转换
--   MySQL TIMESTAMP: 存储 UTC，读取时按 session time_zone 转换
--   MaxCompute TIMESTAMP: 存储字面值，不做任何时区转换
--   PostgreSQL TIMESTAMPTZ: 存储 UTC，显示时按 session 时区转换
--   MaxCompute 没有时区支持（所有时间视为本地时间）
--
--   对引擎开发者: 时间类型至少需要两种:
--     无时区: 业务时间（订单时间、生日）
--     有时区: 系统时间（日志时间、审计时间）
--     MaxCompute 缺少有时区类型 — 跨时区分析是个问题

-- ============================================================
-- 3. 获取当前时间
-- ============================================================

SELECT GETDATE();                           -- 返回 DATETIME
SELECT CURRENT_TIMESTAMP();                 -- 返回 TIMESTAMP

-- GETDATE() 的特殊行为:
--   在同一个 SQL 作业中，GETDATE() 返回作业启动时间（不是执行到该行的时间）
--   对比: MySQL NOW() 返回语句开始时间，SYSDATE() 返回实际执行时间
--   批处理引擎: 作业可能运行数小时，GETDATE() 始终返回启动时间

-- ============================================================
-- 4. 日期加减 —— DATEADD 参数顺序
-- ============================================================

-- DATEADD(date, delta, unit)
SELECT DATEADD(DATETIME '2024-01-15 10:00:00', 7, 'dd');    -- 加 7 天
SELECT DATEADD(DATETIME '2024-01-15 10:00:00', 3, 'mm');    -- 加 3 月
SELECT DATEADD(DATETIME '2024-01-15 10:00:00', 2, 'hh');    -- 加 2 小时
SELECT DATEADD(DATETIME '2024-01-15 10:00:00', -1, 'yyyy'); -- 减 1 年

-- 注意: DATEADD 参数顺序与其他引擎不同!
--   MaxCompute: DATEADD(date, delta, unit)
--   SQL Server: DATEADD(unit, delta, date)
--   BigQuery:   DATE_ADD(date, INTERVAL delta unit)
--   PostgreSQL: date + INTERVAL 'delta unit'
--   MySQL:      DATE_ADD(date, INTERVAL delta unit)
--   迁移陷阱: 参数顺序错误不会报编译错误，但结果不正确

-- 日期差
SELECT DATEDIFF(DATE '2024-12-31', DATE '2024-01-01', 'dd');  -- 365
SELECT DATEDIFF(DATE '2024-12-31', DATE '2024-01-01', 'mm');  -- 11
SELECT DATEDIFF(DATE '2025-01-01', DATE '2024-01-01', 'yyyy');-- 1

-- ADD_MONTHS: 加月（自动处理月末）
SELECT ADD_MONTHS(DATE '2024-01-31', 1);    -- 2024-02-29（闰年月末调整）

-- ============================================================
-- 5. 提取日期部分
-- ============================================================

SELECT YEAR(DATE '2024-01-15');             -- 2024
SELECT MONTH(DATE '2024-01-15');            -- 1
SELECT DAY(DATE '2024-01-15');              -- 15
SELECT HOUR(DATETIME '2024-01-15 10:30:00');-- 10
SELECT MINUTE(DATETIME '2024-01-15 10:30:00');-- 30
SELECT SECOND(DATETIME '2024-01-15 10:30:00');-- 0
SELECT WEEKDAY(DATE '2024-01-15');          -- 周几
SELECT DAYOFYEAR(DATE '2024-01-15');        -- 15（一年中第几天）
SELECT WEEKOFYEAR(DATE '2024-01-15');       -- 第几周
SELECT LAST_DAY(DATE '2024-01-15');         -- 2024-01-31

-- 对比: 标准 SQL EXTRACT
--   标准: EXTRACT(YEAR FROM date)
--   MaxCompute: YEAR(date)（函数式，Hive 兼容）
--   BigQuery:   EXTRACT(YEAR FROM date)（遵循标准）

-- ============================================================
-- 6. 格式化与解析
-- ============================================================

-- TO_CHAR: 日期→字符串
SELECT TO_CHAR(DATETIME '2024-01-15 10:30:00', 'yyyy-mm-dd hh:mi:ss');
SELECT TO_CHAR(GETDATE(), 'yyyyMMdd');      -- 20240115 格式

-- DATE_FORMAT: Java SimpleDateFormat 风格
SELECT DATE_FORMAT(DATETIME '2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');

-- 格式化陷阱: 两套格式码!
--   TO_CHAR:     yyyy-mm-dd hh:mi:ss（Oracle 风格，小写 mm=月, mi=分钟）
--   DATE_FORMAT: yyyy-MM-dd HH:mm:ss（Java 风格，MM=月, mm=分钟）
--   迁移陷阱: mm 在两个函数中含义不同!

-- TO_DATE: 字符串→DATETIME
SELECT TO_DATE('2024-01-15 10:30:00', 'yyyy-mm-dd hh:mi:ss');

-- CAST
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('2024-01-15 10:30:00' AS DATETIME);

-- ============================================================
-- 7. 截断
-- ============================================================

SELECT TRUNC(DATETIME '2024-01-15 10:30:00', 'yyyy'); -- 2024-01-01 00:00:00
SELECT TRUNC(DATETIME '2024-01-15 10:30:00', 'mm');   -- 2024-01-01 00:00:00
SELECT TRUNC(DATETIME '2024-01-15 10:30:00', 'dd');   -- 2024-01-15 00:00:00
SELECT TRUNC(DATETIME '2024-01-15 10:30:00', 'hh');   -- 2024-01-15 10:00:00

-- ============================================================
-- 8. Unix 时间戳互转
-- ============================================================

SELECT UNIX_TIMESTAMP();                    -- 当前 Unix 秒数
SELECT UNIX_TIMESTAMP(DATETIME '2024-01-15 10:00:00');
SELECT FROM_UNIXTIME(1705312800);           -- 返回 DATETIME
SELECT FROM_UNIXTIME(1705312800, 'yyyy-MM-dd HH:mm:ss');

-- 日期验证
SELECT ISDATE('2024-01-15', 'yyyy-mm-dd'); -- TRUE/FALSE

-- ============================================================
-- 9. 横向对比: 日期时间类型
-- ============================================================

-- 时间类型:
--   MaxCompute: DATETIME(ms)/DATE/TIMESTAMP(ns)，无时区
--   Hive:       TIMESTAMP(ns)/DATE，无时区（MaxCompute 继承）
--   BigQuery:   DATE/DATETIME(无时区)/TIMESTAMP(有时区)/TIME
--   PostgreSQL: DATE/TIMESTAMP/TIMESTAMPTZ/TIME/TIMETZ/INTERVAL
--   MySQL:      DATE/DATETIME(μs)/TIMESTAMP(μs，有时区转换)/TIME/YEAR
--   Snowflake:  DATE/TIMESTAMP_NTZ/TIMESTAMP_LTZ/TIMESTAMP_TZ
--   ClickHouse: Date/Date32/DateTime(s)/DateTime64(ns)

-- 时区支持:
--   MaxCompute: 无时区       | Hive: 无时区
--   BigQuery:   TIMESTAMP 有 | PostgreSQL: TIMESTAMPTZ
--   MySQL:      TIMESTAMP 有 | Snowflake: 三种 TIMESTAMP 变体

-- 精度:
--   MaxCompute DATETIME: 毫秒(3位)  | TIMESTAMP: 纳秒(9位)
--   PostgreSQL: 微秒(6位)           | MySQL 8.0: 微秒(6位)
--   ClickHouse DateTime64: 纳秒(9位)| BigQuery DATETIME: 微秒(6位)

-- ============================================================
-- 10. 对引擎开发者的启示
-- ============================================================

-- 1. 时区支持是不可回避的: 缺少时区类型导致跨时区分析困难
-- 2. 格式化函数应统一格式码: 两套格式码是维护负担和用户陷阱
-- 3. DATEADD 参数顺序应与生态中的主流引擎一致（减少迁移成本）
-- 4. 批处理引擎的"当前时间"语义需要明确: 作业启动时间 vs 执行时间
-- 5. 纳秒精度（TIMESTAMP）对日志和事件分析很重要 — 应优先支持
-- 6. INTERVAL 类型（PostgreSQL 风格）比函数式 DATEADD 更灵活
