-- SAP HANA: Aggregate Functions
--
-- 参考资料:
--   [1] SAP HANA SQL Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/
--   [2] SAP HANA SQLScript Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/

-- Basic aggregates
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;

-- GROUP BY
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city;

-- HAVING
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > 10;

-- GROUPING SETS
SELECT city, status, COUNT(*)
FROM users
GROUP BY GROUPING SETS ((city), (status), ());

-- ROLLUP
SELECT city, status, COUNT(*)
FROM users
GROUP BY ROLLUP (city, status);

-- CUBE
SELECT city, status, COUNT(*)
FROM users
GROUP BY CUBE (city, status);

-- GROUPING() function
SELECT city, GROUPING(city) AS is_total, COUNT(*)
FROM users
GROUP BY ROLLUP (city);

-- String aggregation
SELECT STRING_AGG(username, ', ' ORDER BY username) FROM users;
SELECT city, STRING_AGG(username, ', ' ORDER BY username)
FROM users GROUP BY city;

-- Statistical functions
SELECT STDDEV(amount) FROM orders;
SELECT STDDEV_POP(amount) FROM orders;
SELECT VAR(amount) FROM orders;
SELECT VAR_POP(amount) FROM orders;
SELECT CORR(x, y) FROM data;
SELECT CORR_SPEARMAN(x, y) FROM data;           -- Spearman rank correlation (HANA-specific)
SELECT COVAR_SAMP(x, y) FROM data;
SELECT COVAR_POP(x, y) FROM data;
SELECT REGR_SLOPE(y, x) FROM data;
SELECT REGR_INTERCEPT(y, x) FROM data;
SELECT REGR_R2(y, x) FROM data;

-- Percentile
SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY age) FROM users;
SELECT PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY age) FROM users;
SELECT MEDIAN(age) FROM users;                    -- shorthand

-- SAP HANA-specific aggregates
-- AUTO_CORR (auto-correlation)
SELECT AUTO_CORR(value, 3 ORDER BY ts) FROM sensor_data;

-- CROSS_CORR (cross-correlation)
SELECT CROSS_CORR(x, y, 5 ORDER BY ts) FROM data;

-- DFT (Discrete Fourier Transform)
SELECT DFT(value ORDER BY ts) FROM sensor_data;

-- SERIES_DISAGGREGATE (distribute aggregate values)
-- For time series disaggregation

-- Conditional aggregation (no FILTER clause)
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN age < 30 THEN 1 ELSE 0 END) AS young,
    SUM(CASE WHEN age >= 30 THEN 1 ELSE 0 END) AS senior
FROM users;

-- FIRST_VALUE / LAST_VALUE as aggregates
SELECT city,
    FIRST_VALUE(username ORDER BY age) AS youngest_user,
    LAST_VALUE(username ORDER BY age) AS oldest_user
FROM users
GROUP BY city;

-- Note: SAP HANA adds statistical functions like CORR_SPEARMAN, AUTO_CORR
-- Note: time series aggregates (AUTO_CORR, CROSS_CORR, DFT) are unique
-- Note: column store engine optimizes aggregates with dictionary encoding
-- Note: no FILTER clause; use CASE WHEN inside aggregates
