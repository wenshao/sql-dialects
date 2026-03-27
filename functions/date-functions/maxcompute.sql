-- MaxCompute (ODPS): 日期函数
--
-- 参考资料:
--   [1] MaxCompute SQL - Date Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/date-functions
--   [2] MaxCompute Built-in Functions
--       https://help.aliyun.com/zh/maxcompute/user-guide/built-in-functions-overview

-- 当前日期时间
SELECT GETDATE();                                        -- DATETIME 当前时间
SELECT CURRENT_TIMESTAMP();                             -- TIMESTAMP 当前时间

-- 构造
SELECT TO_DATE('2024-01-15 10:30:00', 'yyyy-mm-dd hh:mi:ss');  -- DATETIME
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('2024-01-15 10:30:00' AS DATETIME);

-- 日期加减
SELECT DATEADD(DATETIME '2024-01-15 10:00:00', 7, 'dd');        -- 加 7 天
SELECT DATEADD(DATETIME '2024-01-15 10:00:00', 3, 'mm');        -- 加 3 月
SELECT DATEADD(DATETIME '2024-01-15 10:00:00', 2, 'hh');        -- 加 2 小时
SELECT DATEADD(DATETIME '2024-01-15 10:00:00', -1, 'yyyy');     -- 减 1 年

-- 日期差
SELECT DATEDIFF(DATE '2024-12-31', DATE '2024-01-01', 'dd');     -- 365
SELECT DATEDIFF(DATE '2024-12-31', DATE '2024-01-01', 'mm');     -- 11
SELECT DATEDIFF(DATE '2025-01-01', DATE '2024-01-01', 'yyyy');   -- 1

-- 提取
SELECT YEAR(DATE '2024-01-15');                          -- 2024
SELECT MONTH(DATE '2024-01-15');                         -- 1
SELECT DAY(DATE '2024-01-15');                           -- 15
SELECT HOUR(DATETIME '2024-01-15 10:30:00');             -- 10
SELECT MINUTE(DATETIME '2024-01-15 10:30:00');           -- 30
SELECT SECOND(DATETIME '2024-01-15 10:30:00');           -- 0
SELECT WEEKDAY(DATE '2024-01-15');                       -- 周几
SELECT DAYOFYEAR(DATE '2024-01-15');                     -- 15（一年中第几天）
SELECT WEEKOFYEAR(DATE '2024-01-15');                    -- 第几周

-- 格式化
SELECT TO_CHAR(DATETIME '2024-01-15 10:30:00', 'yyyy-mm-dd hh:mi:ss');
SELECT DATE_FORMAT(DATETIME '2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');

-- 截断
SELECT TRUNC(DATETIME '2024-01-15 10:30:00', 'mm');      -- 月初
SELECT TRUNC(DATETIME '2024-01-15 10:30:00', 'dd');      -- 当天零点
SELECT TRUNC(DATETIME '2024-01-15 10:30:00', 'yyyy');    -- 年初
SELECT TRUNC(DATETIME '2024-01-15 10:30:00', 'hh');      -- 整点

-- 最后一天
SELECT LAST_DAY(DATE '2024-01-15');                       -- 2024-01-31

-- Unix 时间戳
SELECT UNIX_TIMESTAMP();                                 -- 当前 Unix 秒
SELECT UNIX_TIMESTAMP(DATETIME '2024-01-15 10:00:00');
SELECT FROM_UNIXTIME(1705312800);                        -- 返回 DATETIME

-- 其他
SELECT ISDATE('2024-01-15', 'yyyy-mm-dd');               -- 判断是否为有效日期
SELECT ADD_MONTHS(DATE '2024-01-31', 1);                 -- 加月（自动处理月末）

-- 注意：DATEADD/DATEDIFF 参数顺序与其他数据库不同
-- 注意：格式化字符串使用小写（yyyy-mm-dd hh:mi:ss）
-- 注意：没有时区支持
-- 注意：DATE_FORMAT 使用 Java SimpleDateFormat 风格
