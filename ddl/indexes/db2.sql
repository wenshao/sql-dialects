-- IBM Db2: Indexes
--
-- 参考资料:
--   [1] Db2 SQL Reference
--       https://www.ibm.com/docs/en/db2/11.5?topic=sql
--   [2] Db2 Built-in Functions
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in

-- Basic index
CREATE INDEX idx_age ON users (age);

-- Unique index
CREATE UNIQUE INDEX uk_email ON users (email);

-- Composite index
CREATE INDEX idx_city_age ON users (city, age);

-- Descending index
CREATE INDEX idx_age_desc ON users (age DESC);

-- Include columns (index-only access)
CREATE INDEX idx_username ON users (username) INCLUDE (email, age);

-- Clustered index (data physically ordered)
CREATE INDEX idx_created ON users (created_at) CLUSTER;
-- Note: only one clustered index per table

-- Expression-based index (Db2 11.1+)
CREATE INDEX idx_lower_email ON users (LOWER(email));

-- Partial index (filtered, Db2 11.1+)
-- Note: Db2 doesn't have partial indexes like PostgreSQL
-- Use MQTs or design indexes for specific query patterns

-- Unique where not null
CREATE UNIQUE INDEX uk_phone ON users (phone) EXCLUDE NULL KEYS;

-- XML index (for XML column)
CREATE INDEX idx_xml_name ON xml_docs (doc)
    GENERATE KEY USING XMLPATTERN '/customer/name' AS SQL VARCHAR(100);

-- Index on partitioned table (partitioned index)
CREATE INDEX idx_sale_date ON sales (sale_date) PARTITIONED;

-- Non-partitioned index on partitioned table
CREATE INDEX idx_sale_amount ON sales (amount) NOT PARTITIONED;

-- Spatial index (Db2 Spatial Extender)
CREATE INDEX idx_location ON places (location)
    EXTEND USING db2gse.spatial_index (0.5, 10, 20);

-- Drop index
DROP INDEX idx_age;

-- Rebuild / reorganize indexes
REORG INDEXES ALL FOR TABLE users;

-- Collect index statistics
RUNSTATS ON TABLE schema.users FOR INDEXES ALL;
RUNSTATS ON TABLE schema.users WITH DISTRIBUTION AND DETAILED INDEXES ALL;

-- View indexes
SELECT * FROM SYSCAT.INDEXES WHERE TABNAME = 'USERS';
SELECT * FROM SYSCAT.INDEXCOLUSE WHERE INDNAME = 'IDX_AGE';

-- Design advisor (suggest indexes)
-- db2advis -d mydb -s "SELECT * FROM users WHERE age > 25"
