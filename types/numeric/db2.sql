-- IBM Db2: Numeric Types
--
-- 参考资料:
--   [1] Db2 SQL Reference
--       https://www.ibm.com/docs/en/db2/11.5?topic=sql
--   [2] Db2 Built-in Functions
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in

-- Integer types
-- SMALLINT:  2 bytes, -32768 ~ 32767
-- INTEGER:   4 bytes, -2^31 ~ 2^31-1
-- BIGINT:    8 bytes, -2^63 ~ 2^63-1

CREATE TABLE examples (
    small_val  SMALLINT,
    int_val    INTEGER,
    big_val    BIGINT
);

-- No TINYINT or UNSIGNED types

-- Decimal / Numeric (exact)
-- DECIMAL(p,s) / NUMERIC(p,s): precision up to 31
CREATE TABLE prices (
    price     DECIMAL(10,2),          -- up to 99999999.99
    rate      DECIMAL(18,6),          -- high precision
    max_num   DECIMAL(31,0)           -- max precision
);

-- DECFLOAT (decimal floating-point, IEEE 754R)
-- DECFLOAT(16): 16-digit precision
-- DECFLOAT(34): 34-digit precision (default)
CREATE TABLE financial (
    amount DECFLOAT(34),              -- exact decimal arithmetic, no rounding
    rate   DECFLOAT(16)
);
-- DECFLOAT avoids binary floating-point rounding issues

-- Floating point
-- REAL:             4 bytes, ~7 digits precision
-- DOUBLE / DOUBLE PRECISION / FLOAT: 8 bytes, ~15 digits precision
-- FLOAT(n): n <= 24 maps to REAL, n > 24 maps to DOUBLE
CREATE TABLE measurements (
    real_val   REAL,
    double_val DOUBLE,
    float_val  FLOAT(53)              -- maps to DOUBLE
);

-- Boolean (Db2 11.1+)
CREATE TABLE flags (
    active BOOLEAN DEFAULT TRUE
);
-- Values: TRUE / FALSE / NULL

-- Auto-generated identity
CREATE TABLE auto_id (
    id INTEGER GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1),
    name VARCHAR(100)
);

-- Sequence (alternative to identity)
CREATE SEQUENCE seq_orders START WITH 1 INCREMENT BY 1 NO MAXVALUE CACHE 20;
-- SELECT NEXT VALUE FOR seq_orders FROM SYSIBM.SYSDUMMY1;

-- Special values
SELECT INFINITY FROM SYSIBM.SYSDUMMY1;      -- DECFLOAT infinity
SELECT NAN FROM SYSIBM.SYSDUMMY1;            -- DECFLOAT NaN
SELECT -INFINITY FROM SYSIBM.SYSDUMMY1;

-- Note: DECIMAL max precision is 31 (not 38 like some databases)
-- Note: DECFLOAT is unique to Db2 (ideal for financial calculations)
-- Note: no UNSIGNED types
-- Note: no SERIAL type; use IDENTITY or SEQUENCE
