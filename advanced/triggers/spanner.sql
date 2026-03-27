-- Google Cloud Spanner: Triggers (GoogleSQL)
--
-- 参考资料:
--   [1] Spanner SQL Reference (GoogleSQL)
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax
--   [2] Spanner - Functions
--       https://cloud.google.com/spanner/docs/reference/standard-sql/functions-and-operators
--   [3] Spanner - Data Types
--       https://cloud.google.com/spanner/docs/reference/standard-sql/data-types

-- Spanner does NOT support triggers
-- Use alternative approaches instead

-- ============================================================
-- No trigger support
-- ============================================================

-- The following syntax is NOT supported:
-- CREATE TRIGGER ...
-- DROP TRIGGER ...
-- No BEFORE/AFTER row-level triggers
-- No statement-level triggers

-- ============================================================
-- Alternative 1: Computed / generated columns
-- ============================================================

-- Use generated columns for derived values
CREATE TABLE Products (
    ProductId  INT64 NOT NULL,
    Price      NUMERIC,
    TaxRate    NUMERIC,
    TotalPrice NUMERIC AS (Price * (1 + TaxRate)) STORED
) PRIMARY KEY (ProductId);

-- Commit timestamp for auto-recording modification time
CREATE TABLE AuditableUsers (
    UserId    INT64 NOT NULL,
    Username  STRING(100),
    UpdatedAt TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true)
) PRIMARY KEY (UserId);

-- On update, set commit timestamp:
UPDATE AuditableUsers SET Username = 'alice', UpdatedAt = PENDING_COMMIT_TIMESTAMP()
WHERE UserId = 1;

-- ============================================================
-- Alternative 2: Change streams (Spanner-specific, 2022+)
-- ============================================================

-- Change streams capture data changes and emit them to consumers
-- This is the closest alternative to triggers

-- Watch all changes to a table
CREATE CHANGE STREAM UserChanges FOR Users;

-- Watch specific columns
CREATE CHANGE STREAM OrderAmountChanges FOR Orders (Amount, Status);

-- Watch all tables
CREATE CHANGE STREAM AllChanges FOR ALL;

-- Change streams with retention
CREATE CHANGE STREAM UserChanges FOR Users
    OPTIONS (retention_period = '7d', value_capture_type = 'NEW_AND_OLD_VALUES');

-- Drop change stream
DROP CHANGE STREAM UserChanges;

-- Change stream data is consumed via:
-- - Dataflow (Apache Beam) connectors
-- - SpannerIO in Dataflow
-- - Custom gRPC API consumers

-- ============================================================
-- Alternative 3: Row deletion policies (TTL)
-- ============================================================

-- Automatic cleanup (like a scheduled delete trigger)
CREATE TABLE TempEvents (
    EventId   INT64 NOT NULL,
    CreatedAt TIMESTAMP NOT NULL
) PRIMARY KEY (EventId),
  ROW DELETION POLICY (OLDER_THAN(CreatedAt, INTERVAL 30 DAY));

-- ============================================================
-- Alternative 4: Application-level logic
-- ============================================================

-- Implement trigger-like behavior in application code:
-- 1. Use transactions to group related operations
-- 2. Wrap complex logic in application service methods
-- 3. Use Cloud Functions triggered by change streams

-- Example application-level audit pattern (in transaction):
-- BEGIN TRANSACTION;
-- UPDATE Users SET Email = @newEmail WHERE UserId = @id;
-- INSERT INTO AuditLog (LogId, TableName, Action, UserId, CommitTs)
--     VALUES (@logId, 'Users', 'UPDATE', @id, PENDING_COMMIT_TIMESTAMP());
-- COMMIT;

-- Note: Triggers are NOT supported in Spanner
-- Note: Change streams are the primary alternative (async, external)
-- Note: PENDING_COMMIT_TIMESTAMP() provides auto-timestamp (like update trigger)
-- Note: Row deletion policies provide TTL-based cleanup
-- Note: Application code handles complex business logic
-- Note: Cloud Functions can react to change stream events
