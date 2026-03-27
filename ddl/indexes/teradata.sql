-- Teradata: Indexes
--
-- 参考资料:
--   [1] Teradata SQL Reference
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates
--   [2] Teradata Database Documentation
--       https://docs.teradata.com/

-- PRIMARY INDEX (defined at table creation, determines data distribution)
-- Unique Primary Index (UPI)
CREATE TABLE users (
    id       INTEGER NOT NULL,
    username VARCHAR(64),
    email    VARCHAR(255)
)
UNIQUE PRIMARY INDEX (id);

-- Non-Unique Primary Index (NUPI)
CREATE TABLE orders (
    order_id INTEGER NOT NULL,
    user_id  INTEGER NOT NULL,
    amount   DECIMAL(12,2)
)
PRIMARY INDEX (user_id);

-- Secondary Index (non-unique)
CREATE INDEX idx_email ON users (email);

-- Unique Secondary Index (USI)
CREATE UNIQUE INDEX usi_email ON users (email);

-- Non-Unique Secondary Index (NUSI)
CREATE INDEX nusi_city ON users (city);

-- Composite index
CREATE INDEX idx_city_age ON users (city, age);

-- Join Index (materialized join, pre-computed join results)
CREATE JOIN INDEX jidx_user_orders AS
    SELECT u.id, u.username, o.order_id, o.amount
    FROM users u
    INNER JOIN orders o ON u.id = o.user_id
PRIMARY INDEX (id);

-- Single-table aggregate join index
CREATE JOIN INDEX jidx_city_stats AS
    SELECT city, COUNT(*) AS cnt, SUM(age) AS total_age
    FROM users
    GROUP BY city
PRIMARY INDEX (city);

-- Hash index (for equality lookups on NUSI)
CREATE HASH INDEX hidx_email ON users (email)
BY (email)
ORDER BY (email);

-- Collect statistics (Teradata's equivalent of ANALYZE)
COLLECT STATISTICS ON users INDEX (idx_email);
COLLECT STATISTICS ON users COLUMN (username);
COLLECT STATISTICS ON users COLUMN (city, age);

-- Collect stats using SAMPLE
COLLECT STATISTICS USING SAMPLE ON users COLUMN (email);

-- Drop index
DROP INDEX idx_email ON users;

-- Show indexes / statistics
HELP INDEX users;
HELP STATISTICS users;
SHOW TABLE users;

-- Note: PRIMARY INDEX cannot be changed after table creation
-- Note: NUSI is an all-AMP operation (subtable on each AMP)
-- Note: USI involves 2-AMP operation (hash to subtable AMP, then to data AMP)
