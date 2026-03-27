-- ksqlDB: 日期函数

-- 字符串转时间戳
SELECT STRINGTOTIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss')
FROM events EMIT CHANGES;

-- 时间戳转字符串
SELECT TIMESTAMPTOSTRING(ROWTIME, 'yyyy-MM-dd HH:mm:ss')
FROM events EMIT CHANGES;

SELECT TIMESTAMPTOSTRING(ROWTIME, 'yyyy-MM-dd HH:mm:ss', 'Asia/Shanghai')
FROM events EMIT CHANGES;

-- FROM_UNIXTIME（Unix 毫秒转 TIMESTAMP）
SELECT FROM_UNIXTIME(epoch_ms) FROM events EMIT CHANGES;

-- UNIX_TIMESTAMP（当前 Unix 毫秒）
SELECT UNIX_TIMESTAMP() FROM events EMIT CHANGES;

-- UNIX_DATE（当前日期的天数，从 epoch 开始）
SELECT UNIX_DATE() FROM events EMIT CHANGES;

-- FROM_DAYS（天数转 DATE）
SELECT FROM_DAYS(UNIX_DATE()) FROM events EMIT CHANGES;

-- DATETOSTRING / STRINGTODATE
SELECT DATETOSTRING(event_date, 'yyyy-MM-dd') FROM events EMIT CHANGES;
SELECT STRINGTODATE('2024-01-15', 'yyyy-MM-dd') FROM events EMIT CHANGES;

-- TIMETOSTRING / STRINGTOTIME
SELECT TIMETOSTRING(event_time, 'HH:mm:ss') FROM events EMIT CHANGES;
SELECT STRINGTOTIME('10:30:00', 'HH:mm:ss') FROM events EMIT CHANGES;

-- CONVERT_TZ（时区转换）
SELECT CONVERT_TZ(FROM_UNIXTIME(epoch_ms), 'UTC', 'Asia/Shanghai')
FROM events EMIT CHANGES;

-- ============================================================
-- 窗口时间函数
-- ============================================================

SELECT WINDOWSTART, WINDOWEND,
    TIMESTAMPTOSTRING(WINDOWSTART, 'HH:mm') AS start_time,
    TIMESTAMPTOSTRING(WINDOWEND, 'HH:mm') AS end_time
FROM events
WINDOW TUMBLING (SIZE 1 HOUR)
GROUP BY event_type
EMIT CHANGES;

-- 注意：ksqlDB 使用 Java 日期格式模式
-- 注意：时间戳以毫秒为单位
-- 注意：不支持 INTERVAL 类型
-- 注意：不支持 EXTRACT / DATE_PART
-- 注意：不支持 DATE_ADD / DATE_SUB
