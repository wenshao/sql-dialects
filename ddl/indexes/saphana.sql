-- SAP HANA: Indexes
--
-- 参考资料:
--   [1] SAP HANA SQL Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/
--   [2] SAP HANA SQLScript Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/

-- Basic index (B-tree, default for row store)
CREATE INDEX idx_age ON users (age);

-- Unique index
CREATE UNIQUE INDEX uk_email ON users (email);

-- Composite index
CREATE INDEX idx_city_age ON users (city, age);

-- Descending index
CREATE INDEX idx_age_desc ON users (age DESC);

-- Inverted index (column store, default index type)
-- Column store tables automatically have inverted indexes on all columns
-- Explicit creation for additional index needs:
CREATE INVERTED INDEX idx_status ON users (status);

-- Inverted hash index (equality lookups, memory efficient)
CREATE INVERTED HASH INDEX idx_username ON users (username);

-- Inverted individual index (for high-cardinality columns)
CREATE INVERTED INDIVIDUAL INDEX idx_email_inv ON users (email);

-- CPBTREE index (column store, for range queries)
CREATE CPBTREE INDEX idx_created ON users (created_at);

-- Full-text index (for text search)
CREATE FULLTEXT INDEX ft_content ON documents (content)
    FUZZY SEARCH INDEX ON
    SYNC;

-- Full-text index with specific configuration
CREATE FULLTEXT INDEX ft_title ON documents (title)
    FUZZY SEARCH INDEX ON
    PHRASE INDEX RATIO 0.5
    LANGUAGE DETECTION ('EN', 'DE')
    SYNC;

-- Drop index
DROP INDEX idx_age;

-- Enable/disable index
ALTER INDEX idx_age DISABLE;
ALTER INDEX idx_age REBUILD;

-- Rebuild indexes on a table
ALTER TABLE users REBUILD INDEX;

-- View indexes
SELECT * FROM INDEXES WHERE TABLE_NAME = 'USERS';
SELECT * FROM INDEX_COLUMNS WHERE TABLE_NAME = 'USERS';

-- Column store: most queries do not require explicit indexes
-- The column store engine uses dictionary encoding, inverted indexes,
-- and min/max pruning automatically
-- Explicit indexes are mainly for:
--   1. Unique constraints
--   2. Full-text search
--   3. Specific performance optimization
