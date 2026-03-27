-- Google Cloud Spanner: CREATE TABLE (GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- Spanner uses its own SQL dialect (GoogleSQL)
-- Types: BOOL, INT64, FLOAT32, FLOAT64, NUMERIC, STRING(N), BYTES(N), DATE, TIMESTAMP, JSON, ARRAY

-- Basic table creation
CREATE TABLE Users (
    UserId     INT64 NOT NULL,
    Username   STRING(100) NOT NULL,
    Email      STRING(255) NOT NULL,
    Age        INT64,
    Balance    NUMERIC,                        -- Exact numeric, 29 digits before decimal, 9 after
    Bio        STRING(MAX),                    -- MAX = up to 2.5 MB
    CreatedAt  TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
    UpdatedAt  TIMESTAMP
) PRIMARY KEY (UserId);
-- Note: PRIMARY KEY is required and defined outside column list
-- Note: No auto-increment; generate keys in application

-- UUID-based primary key (recommended)
-- Use GENERATE_UUID() (returns STRING) or bit-reverse sequences
CREATE TABLE Products (
    ProductId  STRING(36) NOT NULL DEFAULT (GENERATE_UUID()),
    Name       STRING(255) NOT NULL,
    Price      NUMERIC,
    Category   STRING(50)
) PRIMARY KEY (ProductId);

-- Bit-reversed sequence (avoids hotspots, 2023+)
CREATE SEQUENCE OrderSeq OPTIONS (sequence_kind = 'bit_reversed_positive');
CREATE TABLE Orders (
    OrderId    INT64 NOT NULL DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE OrderSeq)),
    UserId     INT64 NOT NULL,
    Amount     NUMERIC,
    OrderDate  DATE NOT NULL
) PRIMARY KEY (OrderId);

-- INTERLEAVE IN PARENT (hierarchical storage, Spanner-specific)
-- Child rows are physically co-located with parent rows
CREATE TABLE OrderItems (
    OrderId    INT64 NOT NULL,
    ItemId     INT64 NOT NULL,
    ProductId  STRING(36) NOT NULL,
    Quantity   INT64,
    Price      NUMERIC
) PRIMARY KEY (OrderId, ItemId),
  INTERLEAVE IN PARENT Orders ON DELETE CASCADE;

-- Deeply nested interleaving
CREATE TABLE OrderItemNotes (
    OrderId    INT64 NOT NULL,
    ItemId     INT64 NOT NULL,
    NoteId     INT64 NOT NULL,
    Content    STRING(MAX)
) PRIMARY KEY (OrderId, ItemId, NoteId),
  INTERLEAVE IN PARENT OrderItems ON DELETE CASCADE;

-- ARRAY columns
CREATE TABLE Profiles (
    UserId     INT64 NOT NULL,
    Tags       ARRAY<STRING(50)>,
    Scores     ARRAY<FLOAT64>
) PRIMARY KEY (UserId);

-- Foreign key (not interleaved)
CREATE TABLE Reviews (
    ReviewId   INT64 NOT NULL,
    ProductId  STRING(36) NOT NULL,
    Rating     INT64,
    Content    STRING(MAX),
    CONSTRAINT fk_reviews_product FOREIGN KEY (ProductId) REFERENCES Products (ProductId)
) PRIMARY KEY (ReviewId);

-- Row deletion policy (TTL, auto-delete old rows)
CREATE TABLE Events (
    EventId    INT64 NOT NULL,
    EventTime  TIMESTAMP NOT NULL,
    Data       JSON
) PRIMARY KEY (EventId),
  ROW DELETION POLICY (OLDER_THAN(EventTime, INTERVAL 90 DAY));

-- CREATE TABLE with commit timestamps
CREATE TABLE AuditLog (
    LogId      INT64 NOT NULL,
    Action     STRING(50),
    CommitTs   TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true)
) PRIMARY KEY (LogId);

-- IF NOT EXISTS
CREATE TABLE IF NOT EXISTS Users (
    UserId INT64 NOT NULL,
    Username STRING(100)
) PRIMARY KEY (UserId);

-- Note: No CREATE TABLE AS SELECT (CTAS)
-- Note: No auto-increment (use GENERATE_UUID() or bit-reversed sequences)
-- Note: STRING and BYTES require length: STRING(N) or STRING(MAX)
-- Note: PRIMARY KEY must be specified at table level
-- Note: No SERIAL, no DEFAULT with sequences (use bit_reversed_positive)
-- Note: No ENUM, no user-defined types
-- Note: No TEMPORARY tables
-- Note: No table inheritance
