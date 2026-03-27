-- Hive: 日期函数
--
-- 参考资料:
--   [1] Apache Hive - Date Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF#LanguageManualUDF-DateFunctions
--   [2] Apache Hive - Data Types
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types

-- 当前日期时间
SELECT CURRENT_DATE;                                     -- DATE（2.0+）
SELECT CURRENT_TIMESTAMP;                               -- TIMESTAMP（2.0+）
SELECT UNIX_TIMESTAMP();                                -- 当前 Unix 时间戳（秒）
SELECT FROM_UNIXTIME(UNIX_TIMESTAMP());                 -- 当前时间字符串

-- 构造
SELECT TO_DATE('2024-01-15 10:30:00');                    -- DATE（提取日期部分）
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP);

-- 日期加减
SELECT DATE_ADD('2024-01-15', 7);                         -- 加 7 天
SELECT DATE_SUB('2024-01-15', 7);                         -- 减 7 天
SELECT ADD_MONTHS('2024-01-15', 3);                       -- 加 3 月
SELECT ADD_MONTHS('2024-01-31', 1);                       -- 2024-02-29（自动处理月末）

-- INTERVAL 表达式（1.2+）
SELECT CURRENT_TIMESTAMP + INTERVAL '1' DAY;
SELECT CURRENT_TIMESTAMP - INTERVAL '2' HOUR;
SELECT CURRENT_TIMESTAMP + INTERVAL '3' MONTH;

-- 日期差
SELECT DATEDIFF('2024-12-31', '2024-01-01');              -- 365（天数差）
SELECT MONTHS_BETWEEN('2024-12-31', '2024-01-01');        -- 月数差

-- 提取
SELECT YEAR('2024-01-15');                                -- 2024
SELECT MONTH('2024-01-15');                               -- 1
SELECT DAY('2024-01-15');                                 -- 15
SELECT HOUR('2024-01-15 10:30:00');                       -- 10
SELECT MINUTE('2024-01-15 10:30:00');                     -- 30
SELECT SECOND('2024-01-15 10:30:00');                     -- 0
SELECT WEEKOFYEAR('2024-01-15');                          -- 第几周
SELECT DAYOFWEEK('2024-01-15');                           -- 周几（2.2+）
SELECT DAYOFYEAR('2024-01-15');                           -- 一年中第几天（未内置，可用 DATEDIFF 计算）
SELECT EXTRACT(YEAR FROM TIMESTAMP '2024-01-15 10:30:00'); -- 2.2+
SELECT EXTRACT(MONTH FROM TIMESTAMP '2024-01-15 10:30:00');

-- 格式化
SELECT DATE_FORMAT('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
SELECT DATE_FORMAT('2024-01-15', 'yyyy/MM/dd');
SELECT FROM_UNIXTIME(UNIX_TIMESTAMP(), 'yyyy-MM-dd');

-- Unix 时间戳
SELECT UNIX_TIMESTAMP('2024-01-15 10:00:00', 'yyyy-MM-dd HH:mm:ss');
SELECT FROM_UNIXTIME(1705312800);
SELECT FROM_UNIXTIME(1705312800, 'yyyy-MM-dd');

-- 截断
SELECT TRUNC('2024-01-15', 'MM');                         -- 月初
SELECT TRUNC('2024-01-15', 'YY');                         -- 年初
SELECT TRUNC('2024-01-15', 'Q');                          -- 季初

-- 最后一天 / 下一天
SELECT LAST_DAY('2024-01-15');                            -- 2024-01-31
SELECT NEXT_DAY('2024-01-15', 'MO');                     -- 下一个周一

-- 其他
SELECT DATE_FORMAT(CURRENT_TIMESTAMP, 'u');              -- 星期几（1=周一）
SELECT FROM_UTC_TIMESTAMP('2024-01-15 10:00:00', 'Asia/Shanghai');  -- UTC 转本地
SELECT TO_UTC_TIMESTAMP('2024-01-15 18:00:00', 'Asia/Shanghai');    -- 本地转 UTC

-- 注意：日期函数大多接受 STRING 参数（隐式转换）
-- 注意：DATEDIFF 只返回天数差，不支持其他单位
-- 注意：格式化字符串使用 Java SimpleDateFormat 风格
-- 注意：FROM_UTC_TIMESTAMP / TO_UTC_TIMESTAMP 是唯一的时区函数
