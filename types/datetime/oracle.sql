-- Oracle: 日期时间类型
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Datetime Data Types
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Data-Types.html
--   [2] Oracle SQL Language Reference - Datetime Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Single-Row-Functions.html

-- DATE: 日期+时间（精确到秒），7 字节，4712 BC ~ 9999 AD
-- TIMESTAMP: 日期+时间（可达纳秒），7-11 字节
-- TIMESTAMP WITH TIME ZONE: 带时区
-- TIMESTAMP WITH LOCAL TIME ZONE: 存储转为数据库时区，读取转为会话时区
-- INTERVAL YEAR TO MONTH: 年月间隔
-- INTERVAL DAY TO SECOND: 日秒间隔

CREATE TABLE events (
    id         NUMBER(19) GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_date DATE,                                   -- 精确到秒
    created_at TIMESTAMP(6),                           -- 微秒精度
    updated_at TIMESTAMP WITH TIME ZONE,
    local_time TIMESTAMP WITH LOCAL TIME ZONE
);

-- 注意：Oracle 的 DATE 包含时间部分，这和其他数据库不同！

-- 获取当前时间
SELECT SYSDATE FROM dual;               -- DATE 类型
SELECT SYSTIMESTAMP FROM dual;           -- TIMESTAMP WITH TIME ZONE
SELECT CURRENT_TIMESTAMP FROM dual;      -- 会话时区的 TIMESTAMP
SELECT CURRENT_DATE FROM dual;           -- 会话时区的 DATE

-- 日期运算
SELECT SYSDATE + 1 FROM dual;                         -- + 1 天
SELECT SYSDATE + 1/24 FROM dual;                      -- + 1 小时
SELECT SYSDATE + INTERVAL '1' DAY FROM dual;
SELECT SYSDATE + INTERVAL '2' HOUR FROM dual;
SELECT SYSDATE - TO_DATE('2024-01-01', 'YYYY-MM-DD') FROM dual;  -- 天数差

-- 格式化
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM dual;
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM dual;
SELECT TO_TIMESTAMP('2024-01-15 10:30:00.123', 'YYYY-MM-DD HH24:MI:SS.FF3') FROM dual;

-- 提取部分
SELECT EXTRACT(YEAR FROM SYSDATE) FROM dual;
SELECT EXTRACT(MONTH FROM SYSDATE) FROM dual;

-- 月份运算
SELECT ADD_MONTHS(SYSDATE, 3) FROM dual;              -- + 3 个月
SELECT MONTHS_BETWEEN(SYSDATE, TO_DATE('2024-01-01', 'YYYY-MM-DD')) FROM dual;

-- 截断
SELECT TRUNC(SYSDATE) FROM dual;                      -- 截断到天（去掉时间部分）
SELECT TRUNC(SYSDATE, 'MM') FROM dual;                -- 截断到月初
SELECT TRUNC(SYSDATE, 'YYYY') FROM dual;              -- 截断到年初
