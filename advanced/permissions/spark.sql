-- Spark SQL: Permissions
--
-- 参考资料:
--   [1] Spark SQL Reference
--       https://spark.apache.org/docs/latest/sql-ref.html
--   [2] Spark SQL - Built-in Functions
--       https://spark.apache.org/docs/latest/sql-ref-functions.html
--   [3] Spark SQL - Data Types
--       https://spark.apache.org/docs/latest/sql-ref-datatypes.html

-- Standard open-source Spark SQL has minimal built-in permission management
-- Databricks Unity Catalog provides comprehensive access control

-- 1. Hive Metastore authorization (basic)
-- SET hive.security.authorization.enabled = true;
-- SET hive.security.authorization.manager = org.apache.hadoop.hive.ql.security.authorization.DefaultHiveAuthorizationProvider;

-- 2. SQL Standard Authorization (Spark with HiveServer2/Thrift)
-- SET hive.security.authorization.manager = org.apache.hadoop.hive.ql.security.authorization.plugin.sqlstd.SQLStdHiveAuthorizerFactory;

-- Grant / Revoke (when SQL standard authorization is enabled)
GRANT SELECT ON TABLE users TO USER alice;
GRANT SELECT, INSERT ON TABLE users TO USER alice;
GRANT ALL PRIVILEGES ON TABLE users TO USER alice;
GRANT SELECT ON DATABASE mydb TO USER alice;

-- Revoke
REVOKE SELECT ON TABLE users FROM USER alice;
REVOKE ALL PRIVILEGES ON TABLE users FROM USER alice;

-- Grant to role
CREATE ROLE analyst;
GRANT SELECT ON TABLE users TO ROLE analyst;
GRANT ROLE analyst TO USER alice;

-- Show grants
SHOW GRANT ON TABLE users;
SHOW GRANT USER alice ON TABLE users;

-- 3. Databricks Unity Catalog (comprehensive access control)

-- Create catalog
-- CREATE CATALOG analytics;
-- USE CATALOG analytics;

-- Create schema
-- CREATE SCHEMA analytics.sales;

-- Grant catalog-level permissions
-- GRANT USE CATALOG ON CATALOG analytics TO `alice@company.com`;
-- GRANT CREATE SCHEMA ON CATALOG analytics TO `data_engineers`;

-- Grant schema-level permissions
-- GRANT USE SCHEMA ON SCHEMA analytics.sales TO `analysts`;
-- GRANT SELECT ON SCHEMA analytics.sales TO `analysts`;
-- GRANT CREATE TABLE ON SCHEMA analytics.sales TO `data_engineers`;

-- Grant table-level permissions
-- GRANT SELECT ON TABLE analytics.sales.orders TO `alice@company.com`;
-- GRANT MODIFY ON TABLE analytics.sales.orders TO `data_engineers`;

-- Column-level permissions (Unity Catalog)
-- GRANT SELECT (username, email) ON TABLE users TO `analysts`;

-- Row-level security (Unity Catalog, row filters)
-- ALTER TABLE users SET ROW FILTER filter_by_department ON (department_id);

-- Column masking (Unity Catalog)
-- ALTER TABLE users ALTER COLUMN email SET MASK mask_email;

-- 4. Table/View-based access control (any Spark)
-- Use views to restrict access
CREATE VIEW public_users AS
SELECT id, username, city FROM users;

-- Row-level restriction through views
CREATE VIEW my_department_orders AS
SELECT * FROM orders WHERE department_id = current_user_department();

-- 5. Storage-level permissions
-- HDFS: hadoop fs -chmod 750 /data/users
-- S3: IAM policies control bucket/prefix access
-- ADLS: Azure RBAC and ACLs

-- 6. Spark ACLs for UI and REST API
-- spark.acls.enable = true
-- spark.admin.acls = admin_user
-- spark.modify.acls = data_engineer
-- spark.ui.view.acls = *

-- 7. Apache Ranger integration (fine-grained authorization)
-- External policy engine for Spark, Hive, HBase, etc.
-- Provides column-level, row-level security with audit

-- Note: Open-source Spark SQL has limited built-in access control
-- Note: Databricks Unity Catalog provides comprehensive RBAC
-- Note: Apache Ranger provides fine-grained authorization for Hadoop ecosystem
-- Note: Storage-level permissions (HDFS, S3) provide base-level security
-- Note: Views are a portable way to implement data restriction
-- Note: No built-in authentication; relies on Kerberos, LDAP, or platform identity
-- Note: Column masking and row filters available in Unity Catalog
