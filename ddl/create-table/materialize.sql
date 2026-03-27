-- Materialize: CREATE TABLE / CREATE SOURCE / CREATE VIEW
--
-- 参考资料:
--   [1] Materialize SQL Reference
--       https://materialize.com/docs/sql/
--   [2] Materialize SQL Functions
--       https://materialize.com/docs/sql/functions/

-- Materialize 是流式 SQL 物化视图引擎，PostgreSQL 协议兼容
-- 核心概念：SOURCE（数据源）→ VIEW/MATERIALIZED VIEW（增量维护）

-- ============================================================
-- CREATE SOURCE（从外部系统摄入数据）
-- ============================================================

-- 从 Kafka 创建 SOURCE
CREATE SOURCE kafka_orders
FROM KAFKA CONNECTION kafka_conn (TOPIC 'orders')
FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn;

-- 从 PostgreSQL CDC 创建 SOURCE
CREATE SOURCE pg_source
FROM POSTGRES CONNECTION pg_conn (PUBLICATION 'mz_source')
FOR TABLES (users, orders, products);

-- 从 Kafka + JSON 格式
CREATE SOURCE sensor_data
FROM KAFKA CONNECTION kafka_conn (TOPIC 'sensors')
FORMAT JSON;

-- 从负载生成器（测试用）
CREATE SOURCE counter
FROM LOAD GENERATOR COUNTER;

-- ============================================================
-- CREATE TABLE（Materialize 托管表）
-- ============================================================

-- 基本建表
CREATE TABLE users (
    id          INT,
    username    TEXT NOT NULL,
    email       TEXT NOT NULL,
    age         INT,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- IF NOT EXISTS
CREATE TABLE IF NOT EXISTS products (
    id          INT,
    name        TEXT NOT NULL,
    price       NUMERIC(10,2),
    category    TEXT
);

-- ============================================================
-- CREATE VIEW（非物化，每次查询时计算）
-- ============================================================

CREATE VIEW active_users AS
SELECT * FROM users WHERE age > 18;

-- ============================================================
-- CREATE MATERIALIZED VIEW（增量维护，核心功能）
-- ============================================================

-- 从 SOURCE 创建物化视图
CREATE MATERIALIZED VIEW order_summary AS
SELECT user_id,
       COUNT(*) AS order_count,
       SUM(amount) AS total_amount
FROM orders
GROUP BY user_id;

-- 多源 JOIN 的物化视图
CREATE MATERIALIZED VIEW enriched_orders AS
SELECT o.id, o.amount, u.username, p.name AS product_name
FROM orders o
JOIN users u ON o.user_id = u.id
JOIN products p ON o.product_id = p.id;

-- 带窗口函数的物化视图
CREATE MATERIALIZED VIEW ranked_users AS
SELECT username, age,
    ROW_NUMBER() OVER (ORDER BY age DESC) AS rank
FROM users;

-- IN CLUSTER（指定计算集群）
CREATE MATERIALIZED VIEW stats IN CLUSTER default AS
SELECT COUNT(*) AS total FROM users;

-- ============================================================
-- CREATE CONNECTION（连接配置）
-- ============================================================

CREATE CONNECTION kafka_conn TO KAFKA (BROKER 'broker:9092');

CREATE CONNECTION pg_conn TO POSTGRES (
    HOST 'postgres', PORT 5432,
    USER 'materialize', PASSWORD SECRET pg_password,
    DATABASE 'mydb'
);

CREATE CONNECTION csr_conn TO CONFLUENT SCHEMA REGISTRY (
    URL 'http://schema-registry:8081'
);

-- 注意：Materialize 的核心是增量维护物化视图
-- 注意：SOURCE 是数据的入口，TABLE 用于手动管理的数据
-- 注意：MATERIALIZED VIEW 一旦创建就会持续更新
-- 注意：兼容 PostgreSQL 协议，可使用 psql 等工具连接
