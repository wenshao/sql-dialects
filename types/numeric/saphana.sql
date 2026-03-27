-- SAP HANA: Numeric Types
--
-- 参考资料:
--   [1] SAP HANA SQL Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/
--   [2] SAP HANA SQLScript Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/

-- Integer types
-- TINYINT:   1 byte, 0 ~ 255 (unsigned)
-- SMALLINT:  2 bytes, -32768 ~ 32767
-- INTEGER:   4 bytes, -2^31 ~ 2^31-1
-- BIGINT:    8 bytes, -2^63 ~ 2^63-1

CREATE COLUMN TABLE examples (
    tiny_val   TINYINT,               -- 0-255 only (unsigned)
    small_val  SMALLINT,
    int_val    INTEGER,
    big_val    BIGINT
);

-- Decimal / Numeric (exact)
-- DECIMAL(p,s): precision up to 38
-- SMALLDECIMAL: floating-point decimal, 1-16 digits
CREATE TABLE prices (
    price       DECIMAL(10,2),
    rate        DECIMAL(34,6),
    small_price SMALLDECIMAL,         -- auto-precision, efficient storage
    max_num     DECIMAL(38,0)
);

-- Floating point
-- REAL:   4 bytes, ~7 digits precision
-- DOUBLE: 8 bytes, ~15 digits precision
-- FLOAT(n): n <= 24 maps to REAL, n > 24 maps to DOUBLE
CREATE TABLE measurements (
    real_val   REAL,
    double_val DOUBLE,
    float_val  FLOAT(53)
);

-- Boolean (native type)
CREATE TABLE flags (
    active BOOLEAN DEFAULT TRUE
);
-- Values: TRUE / FALSE / NULL / UNKNOWN

-- Auto-generated identity
CREATE TABLE auto_id (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    name NVARCHAR(100)
);

-- Sequence
CREATE SEQUENCE seq_orders START WITH 1 INCREMENT BY 1 NO MAXVALUE;
-- SELECT seq_orders.NEXTVAL FROM DUMMY;

-- SMALLDECIMAL (SAP HANA-specific, efficient variable-precision decimal)
-- Precision determined automatically, up to 16 digits
-- More memory-efficient than DECIMAL in column store
CREATE TABLE efficient_nums (
    amount SMALLDECIMAL
);

-- Note: TINYINT is unsigned (0-255) unlike most databases
-- Note: SMALLDECIMAL is unique to SAP HANA, optimal for column store
-- Note: DECIMAL max precision is 38
-- Note: column store compresses numeric types very effectively
-- Note: no UNSIGNED keyword for other integer types
