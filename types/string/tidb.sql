-- TiDB: String Types
-- TiDB is MySQL compatible; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] TiDB SQL Reference
--       https://docs.pingcap.com/tidb/stable/sql-statement-overview
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB - Functions and Operators
--       https://docs.pingcap.com/tidb/stable/functions-and-operators-overview

-- All MySQL string types are supported:
-- CHAR(n), VARCHAR(n), TINYTEXT, TEXT, MEDIUMTEXT, LONGTEXT
-- BINARY(n), VARBINARY(n), TINYBLOB, BLOB, MEDIUMBLOB, LONGBLOB
-- ENUM, SET

CREATE TABLE examples (
    code       CHAR(10),
    name       VARCHAR(255),
    content    TEXT,
    big_data   LONGTEXT
);

-- Character sets and collations (same as MySQL)
CREATE TABLE t (
    name VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
);

-- Default charset: utf8mb4 (same as MySQL 8.0)
-- Default collation: utf8mb4_bin (DIFFERENT from MySQL 8.0)
-- MySQL 8.0 defaults to utf8mb4_0900_ai_ci
-- TiDB uses utf8mb4_bin by default (case-sensitive, binary comparison)
-- This means string comparisons are case-sensitive by default in TiDB!

-- To get case-insensitive behavior like MySQL 8.0:
CREATE TABLE t (
    name VARCHAR(100) COLLATE utf8mb4_general_ci
);
-- Or set at database/server level:
-- SET GLOBAL default_collation_for_utf8mb4 = 'utf8mb4_general_ci';  -- TiDB 7.4+

-- New collation framework (4.0+)
-- TiDB supports utf8mb4_general_ci and utf8mb4_unicode_ci
-- Note: utf8mb4_0900_ai_ci (MySQL 8.0 default) is NOT supported before v7.4

-- Supported collations (may vary by version):
-- utf8mb4_bin, utf8mb4_general_ci, utf8mb4_unicode_ci
-- utf8_bin, utf8_general_ci, utf8_unicode_ci
-- latin1_bin, binary
-- 7.4+: utf8mb4_0900_ai_ci, utf8mb4_0900_as_cs

-- ENUM and SET (same as MySQL)
CREATE TABLE t (
    status ENUM('active', 'inactive', 'deleted'),
    tags   SET('tag1', 'tag2', 'tag3')
);

-- VARCHAR length limit: same as MySQL (65535 bytes per row)
-- But TiDB has a different row size limit:
-- Default txn-entry-size-limit: 6MB per key-value entry
-- Very large TEXT/BLOB values are stored in separate KV pairs

-- Binary types (same as MySQL)
CREATE TABLE t (
    bin_data BINARY(16),
    var_bin  VARBINARY(256),
    blob_col BLOB
);

-- Limitations:
-- Default collation is utf8mb4_bin (case-sensitive), not utf8mb4_0900_ai_ci
-- utf8mb4_0900_ai_ci not supported before TiDB 7.4
-- String comparison behavior may differ from MySQL due to collation defaults
-- Very large strings (>6MB) may hit txn-entry-size-limit
-- WEIGHT_STRING() function supported for collation-aware sorting
