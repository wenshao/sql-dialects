-- Teradata: Date Functions
--
-- 参考资料:
--   [1] Teradata SQL Reference
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates
--   [2] Teradata Database Documentation
--       https://docs.teradata.com/

-- Current date/time
SELECT CURRENT_DATE;
SELECT CURRENT_TIME;
SELECT CURRENT_TIMESTAMP;
SELECT CURRENT_TIMESTAMP(0);          -- truncated to seconds

-- Date construction
SELECT DATE '2024-01-15';
SELECT CAST('2024-01-15' AS DATE);
SELECT CAST('2024-01-15 10:30:00' AS TIMESTAMP(0));

-- Date arithmetic (using INTERVAL)
SELECT CURRENT_DATE + INTERVAL '1' DAY;
SELECT CURRENT_DATE - INTERVAL '3' MONTH;
SELECT CURRENT_DATE + INTERVAL '1' YEAR;
SELECT CURRENT_TIMESTAMP + INTERVAL '2' HOUR;
SELECT CURRENT_TIMESTAMP - INTERVAL '30' MINUTE;

-- ADD_MONTHS
SELECT ADD_MONTHS(CURRENT_DATE, 3);
SELECT ADD_MONTHS(CURRENT_DATE, -6);

-- Date difference
SELECT (DATE '2024-12-31') - (DATE '2024-01-01');           -- returns INTERVAL
-- Days between
SELECT (DATE '2024-12-31' - DATE '2024-01-01') DAY(4);     -- integer days
-- Months between
SELECT MONTHS_BETWEEN(DATE '2024-12-31', DATE '2024-01-01');

-- Extract
SELECT EXTRACT(YEAR FROM CURRENT_DATE);
SELECT EXTRACT(MONTH FROM CURRENT_DATE);
SELECT EXTRACT(DAY FROM CURRENT_DATE);
SELECT EXTRACT(HOUR FROM CURRENT_TIMESTAMP);
SELECT EXTRACT(MINUTE FROM CURRENT_TIMESTAMP);
SELECT EXTRACT(SECOND FROM CURRENT_TIMESTAMP);

-- Teradata-specific date functions
SELECT CURRENT_DATE - EXTRACT(DAY FROM CURRENT_DATE) + 1;   -- first of month
SELECT LAST_DAY(CURRENT_DATE);                               -- last day of month (14+)

-- Day of week / year
-- Note: TD_DAY_OF_WEEK, TD_MONTH_OF_YEAR are available
SELECT (CURRENT_DATE - DATE '0001-01-07') MOD 7;            -- day of week calculation

-- Formatting
SELECT CURRENT_DATE (FORMAT 'YYYY-MM-DD');
SELECT CURRENT_DATE (FORMAT 'MM/DD/YYYY');
SELECT CURRENT_TIMESTAMP (FORMAT 'YYYY-MM-DDBHH:MI:SS');
-- Note: B = blank separator in FORMAT

-- TO_CHAR (14.10+)
SELECT TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD');
SELECT TO_CHAR(CURRENT_TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS');

-- Truncation
SELECT TRUNC(CURRENT_DATE, 'MM');     -- first of month (14.10+)
SELECT TRUNC(CURRENT_DATE, 'YY');     -- first of year
SELECT TRUNC(CURRENT_TIMESTAMP, 'HH'); -- truncate to hour

-- PERIOD operations (Teradata-specific)
SELECT BEGIN(PERIOD(DATE '2024-01-01', DATE '2024-12-31'));  -- 2024-01-01
SELECT END(PERIOD(DATE '2024-01-01', DATE '2024-12-31'));    -- 2024-12-31
-- OVERLAPS
SELECT PERIOD(DATE '2024-01-01', DATE '2024-06-30')
    OVERLAPS PERIOD(DATE '2024-06-01', DATE '2024-12-31');   -- TRUE

-- Calendar functions
SELECT CURRENT_DATE - (EXTRACT(DAY FROM CURRENT_DATE) - 1);  -- first of current month
SELECT ADD_MONTHS(CURRENT_DATE - (EXTRACT(DAY FROM CURRENT_DATE) - 1), 1) - 1;  -- last of month

-- Note: Teradata stores DATE as integer internally
-- Note: FORMAT clause is Teradata-specific for display formatting
-- Note: PERIOD types and operations are unique to Teradata
-- Note: INTERVAL syntax requires single quotes: INTERVAL '1' DAY
