-- IBM Db2: Date/Time Types
--
-- 参考资料:
--   [1] Db2 SQL Reference
--       https://www.ibm.com/docs/en/db2/11.5?topic=sql
--   [2] Db2 Built-in Functions
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in

-- DATE: date only, 4 bytes
-- TIME: time of day, 3 bytes (second precision)
-- TIMESTAMP: date + time, 10-12 bytes
-- TIMESTAMP(p): fractional seconds precision 0-12 (default 6)

CREATE TABLE events (
    id         BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY,
    event_date DATE,
    event_time TIME,                  -- always second precision (no fractional)
    created_at TIMESTAMP,             -- default 6 fractional digits
    precise_at TIMESTAMP(12)          -- up to picosecond precision
);

-- No TIME WITH TIME ZONE or TIMESTAMP WITH TIME ZONE in Db2 for LUW
-- Use TIMESTAMP and handle time zones in application logic
-- Db2 for z/OS: TIMESTAMP WITH TIME ZONE (Db2 12+)

-- Current date/time
SELECT CURRENT DATE FROM SYSIBM.SYSDUMMY1;         -- DATE
SELECT CURRENT TIME FROM SYSIBM.SYSDUMMY1;         -- TIME
SELECT CURRENT TIMESTAMP FROM SYSIBM.SYSDUMMY1;    -- TIMESTAMP
-- Note: no parentheses, no underscore (CURRENT DATE, not CURRENT_DATE)

-- Also supported:
SELECT CURRENT_DATE FROM SYSIBM.SYSDUMMY1;
SELECT CURRENT_TIMESTAMP FROM SYSIBM.SYSDUMMY1;

-- Date arithmetic (using labeled durations)
SELECT CURRENT DATE + 1 DAY FROM SYSIBM.SYSDUMMY1;
SELECT CURRENT DATE + 3 MONTHS FROM SYSIBM.SYSDUMMY1;
SELECT CURRENT DATE - 1 YEAR FROM SYSIBM.SYSDUMMY1;
SELECT CURRENT TIMESTAMP + 2 HOURS FROM SYSIBM.SYSDUMMY1;

-- TIMESTAMPDIFF (returns estimated difference)
SELECT TIMESTAMPDIFF(2, CHAR(TIMESTAMP('2024-12-31-00.00.00') - TIMESTAMP('2024-01-01-00.00.00')))
FROM SYSIBM.SYSDUMMY1;
-- Unit codes: 1=fractions, 2=seconds, 4=minutes, 8=hours, 16=days, 32=weeks, 64=months, 128=quarters, 256=years

-- DAYS function (Julian day number)
SELECT DAYS('2024-12-31') - DAYS('2024-01-01') FROM SYSIBM.SYSDUMMY1;  -- 365

-- EXTRACT (Db2 11.1+)
SELECT EXTRACT(YEAR FROM CURRENT TIMESTAMP) FROM SYSIBM.SYSDUMMY1;
SELECT EXTRACT(MONTH FROM CURRENT DATE) FROM SYSIBM.SYSDUMMY1;

-- Legacy extraction functions
SELECT YEAR(CURRENT DATE) FROM SYSIBM.SYSDUMMY1;
SELECT MONTH(CURRENT DATE) FROM SYSIBM.SYSDUMMY1;
SELECT DAY(CURRENT DATE) FROM SYSIBM.SYSDUMMY1;
SELECT HOUR(CURRENT TIMESTAMP) FROM SYSIBM.SYSDUMMY1;
SELECT MINUTE(CURRENT TIMESTAMP) FROM SYSIBM.SYSDUMMY1;
SELECT SECOND(CURRENT TIMESTAMP) FROM SYSIBM.SYSDUMMY1;
SELECT DAYOFWEEK(CURRENT DATE) FROM SYSIBM.SYSDUMMY1;    -- 1=Sunday
SELECT DAYOFYEAR(CURRENT DATE) FROM SYSIBM.SYSDUMMY1;

-- Formatting
SELECT VARCHAR_FORMAT(CURRENT TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS') FROM SYSIBM.SYSDUMMY1;
SELECT TO_CHAR(CURRENT TIMESTAMP, 'YYYY-MM-DD') FROM SYSIBM.SYSDUMMY1;  -- Db2 11.1+

-- Parsing
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM SYSIBM.SYSDUMMY1;
SELECT TIMESTAMP_FORMAT('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS') FROM SYSIBM.SYSDUMMY1;

-- Truncation
SELECT TRUNC(CURRENT TIMESTAMP, 'DD') FROM SYSIBM.SYSDUMMY1;   -- truncate to day
SELECT TRUNC(CURRENT TIMESTAMP, 'MM') FROM SYSIBM.SYSDUMMY1;   -- truncate to month

-- Note: Db2 timestamp format uses dashes and dots: 'YYYY-MM-DD-HH.MI.SS.FFFFFF'
-- Note: TIMESTAMP precision up to 12 (picoseconds), more than most databases
-- Note: labeled durations (+ 1 DAY, - 3 MONTHS) are Db2-specific syntax
