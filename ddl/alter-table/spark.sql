-- Spark SQL: ALTER TABLE (Spark 2.0+)
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- Add columns
ALTER TABLE users ADD COLUMNS (phone STRING, address STRING);
ALTER TABLE users ADD COLUMNS (phone STRING COMMENT 'Phone number');

-- Rename column (Spark 3.1+)
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- Change column type (Spark 3.1+ with column type evolution)
ALTER TABLE users ALTER COLUMN age TYPE BIGINT;

-- Change column comment
ALTER TABLE users ALTER COLUMN email COMMENT 'User email address';

-- Change column position (Spark 3.1+)
ALTER TABLE users ALTER COLUMN phone AFTER email;
ALTER TABLE users ALTER COLUMN phone FIRST;

-- Change column nullability (Spark 3.1+, Delta Lake)
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

-- Drop column (Spark 3.1+, requires data source support like Delta)
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMNS (phone, address);

-- Rename table
ALTER TABLE users RENAME TO members;
ALTER TABLE db1.users RENAME TO db1.members;

-- Set table properties
ALTER TABLE users SET TBLPROPERTIES ('comment' = 'User accounts table');
ALTER TABLE users SET TBLPROPERTIES ('delta.autoOptimize.optimizeWrite' = 'true');

-- Unset table properties
ALTER TABLE users UNSET TBLPROPERTIES ('comment');
ALTER TABLE users UNSET TBLPROPERTIES IF EXISTS ('comment');

-- Change storage format (Hive tables)
ALTER TABLE users SET FILEFORMAT PARQUET;
ALTER TABLE users SET SERDEPROPERTIES ('field.delim' = ',');

-- Add/Drop partitions
ALTER TABLE orders ADD PARTITION (order_date='2024-01-15')
    LOCATION '/data/orders/2024-01-15';
ALTER TABLE orders ADD IF NOT EXISTS PARTITION (order_date='2024-01-15');
ALTER TABLE orders DROP PARTITION (order_date='2024-01-15');
ALTER TABLE orders DROP IF EXISTS PARTITION (order_date='2024-01-15');

-- Recover partitions (sync metadata with data on disk)
ALTER TABLE orders RECOVER PARTITIONS;
-- Or: MSCK REPAIR TABLE orders;

-- Set/change table location
ALTER TABLE users SET LOCATION '/new/data/path/';

-- Set table comment (Spark 3.0+)
COMMENT ON TABLE users IS 'User accounts table';

-- Delta Lake specific operations (Databricks)
-- ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id);   -- Delta 3.0+
-- ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age > 0);     -- Delta 3.0+
-- ALTER TABLE users DROP CONSTRAINT pk_users;

-- Note: Many ALTER TABLE operations require data source support (Delta, Iceberg)
-- Note: Hive tables support fewer ALTER operations than Delta tables
-- Note: No traditional constraints (PRIMARY KEY, FOREIGN KEY) except Delta Lake 3.0+
-- Note: Column type changes only allowed for compatible type widening
