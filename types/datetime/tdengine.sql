-- TDengine: 日期时间类型
--
-- 参考资料:
--   [1] TDengine SQL Reference
--       https://docs.taosdata.com/taos-sql/
--   [2] TDengine Function Reference
--       https://docs.taosdata.com/taos-sql/function/

-- TIMESTAMP: 唯一的时间类型
-- 支持毫秒（ms）、微秒（us）、纳秒（ns）精度

-- 精度在创建数据库时指定
CREATE DATABASE power PRECISION 'ms';     -- 毫秒（默认）
CREATE DATABASE power_us PRECISION 'us';  -- 微秒
CREATE DATABASE power_ns PRECISION 'ns';  -- 纳秒

CREATE STABLE sensors (
    ts     TIMESTAMP,                     -- 必须是第一列
    value  FLOAT
) TAGS (id INT);

-- ============================================================
-- 时间戳格式
-- ============================================================

-- 字符串格式
INSERT INTO d1001 VALUES ('2024-01-15 10:30:00.000', 10.3);
INSERT INTO d1001 VALUES ('2024-01-15T10:30:00.000+08:00', 10.3);

-- Unix 时间戳（毫秒）
INSERT INTO d1001 VALUES (1705286400000, 10.3);

-- NOW 函数
INSERT INTO d1001 VALUES (NOW, 10.3);

-- NOW + 偏移
INSERT INTO d1001 VALUES (NOW + 1s, 10.3);     -- 1 秒后
INSERT INTO d1001 VALUES (NOW - 1m, 10.3);     -- 1 分钟前
INSERT INTO d1001 VALUES (NOW + 1h, 10.3);     -- 1 小时后
INSERT INTO d1001 VALUES (NOW - 1d, 10.3);     -- 1 天前

-- 时间单位：a(毫秒), s(秒), m(分), h(时), d(天), w(周), n(月), y(年)

-- ============================================================
-- 时间函数
-- ============================================================

-- 当前时间
SELECT NOW();

-- 时间加减
SELECT ts + 1h FROM d1001;
SELECT ts - 1d FROM d1001;

-- TIMETRUNCATE（截断到指定精度）
SELECT TIMETRUNCATE(ts, 1h) FROM d1001;       -- 截断到小时
SELECT TIMETRUNCATE(ts, 1d) FROM d1001;       -- 截断到天

-- TIMEDIFF（时间差，返回时间单位）
SELECT TIMEDIFF(ts1, ts2) FROM ...;

-- TO_ISO8601（转 ISO 格式）
SELECT TO_ISO8601(ts) FROM d1001;

-- TO_UNIXTIMESTAMP（转 Unix 时间戳）
SELECT TO_UNIXTIMESTAMP('2024-01-15 10:30:00');

-- TIMEZONE（时区转换）
SELECT TIMEZONE(ts, 'Asia/Shanghai') FROM d1001;

-- TODAY（今天 0 点的时间戳）
SELECT TODAY();

-- ============================================================
-- 时间过滤（最重要的查询条件）
-- ============================================================

SELECT * FROM d1001 WHERE ts >= '2024-01-01' AND ts < '2024-02-01';
SELECT * FROM d1001 WHERE ts >= NOW - 1h;
SELECT * FROM d1001 WHERE ts BETWEEN '2024-01-01' AND '2024-01-31';

-- 注意：TIMESTAMP 是唯一的时间类型
-- 注意：没有 DATE、TIME、INTERVAL 类型
-- 注意：精度在数据库级别设置（ms/us/ns）
-- 注意：时间是 TDengine 查询优化的核心
