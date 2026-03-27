-- Spark SQL: Constraints
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- Spark SQL has very limited constraint support
-- Traditional databases enforce constraints; Spark generally does not

-- NOT NULL (Spark 3.0+, supported on all table formats)
CREATE TABLE users (
    id       BIGINT NOT NULL,
    username STRING NOT NULL,
    email    STRING NOT NULL,
    age      INT
) USING PARQUET;

-- ALTER to add NOT NULL (Spark 3.1+, Delta Lake)
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

-- DEFAULT values (Spark 3.4+)
CREATE TABLE users (
    id         BIGINT,
    username   STRING NOT NULL,
    status     INT DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) USING PARQUET;

-- Delta Lake constraints (Databricks, Delta Lake 1.0+)

-- CHECK constraints (Delta Lake)
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
ALTER TABLE users ADD CONSTRAINT chk_dates CHECK (end_date > start_date);
ALTER TABLE users DROP CONSTRAINT chk_age;

-- Primary key (Delta Lake 3.0+, informational, not enforced by default)
-- CREATE TABLE users (
--     id       BIGINT,
--     username STRING,
--     CONSTRAINT pk_users PRIMARY KEY (id)
-- ) USING DELTA;

-- Foreign key (Delta Lake 3.0+, informational, not enforced)
-- ALTER TABLE orders ADD CONSTRAINT fk_user
--     FOREIGN KEY (user_id) REFERENCES users(id);

-- Unique constraint (not supported in standard Spark)
-- Enforce uniqueness through application logic or deduplication:
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY id) AS rn
    FROM users
) WHERE rn = 1;

-- Data validation with Spark (application-level constraints)
-- Use DataFrame API to check constraints before writing:
-- df.filter("age >= 0 AND age <= 200").write.saveAsTable("users")

-- Describe constraints
DESCRIBE EXTENDED users;
SHOW TBLPROPERTIES users;

-- Note: Standard Spark SQL (non-Delta) has no PRIMARY KEY, UNIQUE, FOREIGN KEY, or CHECK
-- Note: Delta Lake adds CHECK constraints (enforced) and informational PK/FK (not enforced)
-- Note: NOT NULL is the only widely enforced constraint across all formats
-- Note: Data quality is typically handled at the application/ETL layer
-- Note: Iceberg supports hidden partitioning but not traditional constraints
