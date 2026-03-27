-- Oracle: 日期函数
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Datetime Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Single-Row-Functions.html
--   [2] Oracle SQL Language Reference - Data Types
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Data-Types.html

-- 当前日期时间
SELECT SYSDATE FROM dual;                        -- DATE（数据库服务器时间）
SELECT SYSTIMESTAMP FROM dual;                   -- TIMESTAMP WITH TIME ZONE
SELECT CURRENT_DATE FROM dual;                   -- DATE（会话时区）
SELECT CURRENT_TIMESTAMP FROM dual;              -- TIMESTAMP WITH TIME ZONE（会话时区）

-- 构造日期
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM dual;
SELECT TO_DATE('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS') FROM dual;
SELECT TO_TIMESTAMP('2024-01-15 10:30:00.123', 'YYYY-MM-DD HH24:MI:SS.FF3') FROM dual;

-- 日期加减
SELECT SYSDATE + 1 FROM dual;                    -- + 1 天
SELECT SYSDATE + 1/24 FROM dual;                 -- + 1 小时
SELECT SYSDATE + 1/1440 FROM dual;               -- + 1 分钟
SELECT SYSDATE + INTERVAL '3' MONTH FROM dual;
SELECT SYSDATE + INTERVAL '2' HOUR FROM dual;
SELECT ADD_MONTHS(SYSDATE, 6) FROM dual;         -- + 6 个月

-- 日期差
SELECT SYSDATE - TO_DATE('2024-01-01', 'YYYY-MM-DD') FROM dual;  -- 天数（小数）
SELECT MONTHS_BETWEEN(SYSDATE, TO_DATE('2024-01-01', 'YYYY-MM-DD')) FROM dual; -- 月数

-- 提取
SELECT EXTRACT(YEAR FROM SYSDATE) FROM dual;
SELECT EXTRACT(MONTH FROM SYSDATE) FROM dual;
SELECT EXTRACT(DAY FROM SYSDATE) FROM dual;
SELECT EXTRACT(HOUR FROM SYSTIMESTAMP) FROM dual;
SELECT EXTRACT(MINUTE FROM SYSTIMESTAMP) FROM dual;
SELECT EXTRACT(SECOND FROM SYSTIMESTAMP) FROM dual;
SELECT TO_CHAR(SYSDATE, 'D') FROM dual;          -- 星期几（取决于 NLS_TERRITORY，美国为 1=周日）
SELECT TO_CHAR(SYSDATE, 'DDD') FROM dual;        -- 一年中的第几天
SELECT TO_CHAR(SYSDATE, 'WW') FROM dual;         -- 一年中的第几周

-- 格式化
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM dual;
SELECT TO_CHAR(SYSDATE, 'Day, Month DD, YYYY') FROM dual;
SELECT TO_CHAR(SYSDATE, 'HH:MI AM') FROM dual;

-- 截断
SELECT TRUNC(SYSDATE) FROM dual;                  -- 去掉时间
SELECT TRUNC(SYSDATE, 'MM') FROM dual;            -- 月初
SELECT TRUNC(SYSDATE, 'YYYY') FROM dual;          -- 年初
SELECT TRUNC(SYSDATE, 'Q') FROM dual;             -- 季初
SELECT TRUNC(SYSDATE, 'DAY') FROM dual;           -- 本周周日

-- 四舍五入
SELECT ROUND(SYSDATE) FROM dual;                  -- 四舍五入到天
SELECT ROUND(SYSDATE, 'MM') FROM dual;            -- 四舍五入到月

-- 月末 / 下一个星期几
SELECT LAST_DAY(SYSDATE) FROM dual;               -- 本月最后一天
SELECT NEXT_DAY(SYSDATE, 'MONDAY') FROM dual;     -- 下一个周一

-- 时区转换
SELECT FROM_TZ(CAST(SYSDATE AS TIMESTAMP), 'UTC') AT TIME ZONE 'Asia/Shanghai' FROM dual;

-- 计算两个日期之间的工作日数（需要自己实现）
