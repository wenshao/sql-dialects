-- Flink SQL: Permissions
--
-- 参考资料:
--   [1] Flink SQL Documentation
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/
--   [2] Flink SQL - Built-in Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/
--   [3] Flink SQL - Data Types
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/

-- Flink SQL does NOT have built-in user authentication or permission management
-- Security is handled at the infrastructure and connector level

-- Flink's security model:

-- 1. Kerberos authentication (for Hadoop ecosystem)
-- Configuration in flink-conf.yaml:
-- security.kerberos.login.keytab: /path/to/keytab
-- security.kerberos.login.principal: flink@EXAMPLE.COM
-- security.kerberos.login.contexts: Client,KafkaClient

-- 2. SSL/TLS encryption
-- For internal communication between Flink components:
-- security.ssl.internal.enabled: true
-- security.ssl.internal.keystore: /path/to/keystore
-- security.ssl.internal.key-password: keystore-password

-- For REST endpoint:
-- security.ssl.rest.enabled: true

-- 3. Connector-level authentication

-- Kafka with SASL authentication
CREATE TABLE kafka_events (
    event_id   BIGINT,
    event_type STRING,
    event_time TIMESTAMP(3)
) WITH (
    'connector' = 'kafka',
    'topic' = 'events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.security.protocol' = 'SASL_SSL',
    'properties.sasl.mechanism' = 'PLAIN',
    'properties.sasl.jaas.config' = 'org.apache.kafka.common.security.plain.PlainLoginModule required username="user" password="pass";',
    'format' = 'json'
);

-- JDBC with credentials
CREATE TABLE jdbc_users (
    id       BIGINT,
    username STRING,
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:mysql://localhost:3306/mydb',
    'table-name' = 'users',
    'username' = 'app_user',
    'password' = 'app_password'
);

-- Elasticsearch with authentication
CREATE TABLE es_docs (
    doc_id  STRING,
    content STRING,
    PRIMARY KEY (doc_id) NOT ENFORCED
) WITH (
    'connector' = 'elasticsearch-7',
    'hosts' = 'https://localhost:9200',
    'index' = 'documents',
    'username' = 'elastic',
    'password' = 'changeme'
);

-- HBase with Kerberos
-- HBase connector inherits Kerberos credentials from Flink configuration

-- 4. Flink SQL Gateway authentication (Flink 1.16+)
-- The SQL Gateway supports pluggable authentication
-- Configuration in flink-conf.yaml:
-- sql-gateway.endpoint.rest.authentication.type: token
-- sql-gateway.endpoint.rest.authentication.token: my-secret-token

-- 5. Catalog-level access control

-- Hive Catalog (inherits Hive permissions)
CREATE CATALOG hive_catalog WITH (
    'type' = 'hive',
    'hive-conf-dir' = '/etc/hive/conf'
);
-- Hive Metastore permissions apply to tables accessed through this catalog

-- 6. Views for data restriction (application-level)
CREATE VIEW public_users AS
SELECT id, username, city FROM users;  -- Hide sensitive columns

-- 7. RBAC through external systems

-- Apache Ranger for Flink (community integration)
-- Provides policy-based access control for Flink SQL
-- Ranger policies can control:
-- - Which tables a user can read/write
-- - Column-level access
-- - Row-level filtering

-- 8. Network security
-- Flink's REST API access control:
-- rest.address: localhost                 -- Bind to specific interface
-- rest.port: 8081
-- Use reverse proxy (nginx, etc.) for authentication

-- 9. Secret management patterns
-- Environment variables for sensitive values:
CREATE TABLE kafka_events (
    event_id BIGINT,
    data     STRING
) WITH (
    'connector' = 'kafka',
    'topic' = 'events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.sasl.jaas.config' = '${KAFKA_JAAS_CONFIG}',
    'format' = 'json'
);
-- Reference: environment variables or Kubernetes secrets for credentials

-- Note: Flink has no CREATE USER, CREATE ROLE, GRANT, or REVOKE statements
-- Note: Authentication is configured at the cluster level (flink-conf.yaml)
-- Note: Connector credentials are specified in WITH clauses
-- Note: Kerberos is the primary authentication mechanism for Hadoop ecosystem
-- Note: SSL/TLS encrypts communication between Flink components
-- Note: For multi-tenant scenarios, use separate Flink clusters or session modes
-- Note: Apache Ranger integration provides fine-grained SQL-level access control
-- Note: Credential management should use external secret stores (Vault, K8s secrets)
