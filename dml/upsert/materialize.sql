-- Materialize: UPSERT
--
-- 参考资料:
--   [1] Materialize SQL Reference
--       https://materialize.com/docs/sql/
--   [2] Materialize SQL Functions
--       https://materialize.com/docs/sql/functions/

-- Materialize 的 TABLE 支持 INSERT ... ON CONFLICT（兼容 PostgreSQL）

-- ============================================================
-- INSERT ... ON CONFLICT（需要唯一约束）
-- ============================================================

-- 创建带唯一约束的表
CREATE TABLE users (
    id       INT NOT NULL UNIQUE,
    username TEXT NOT NULL,
    email    TEXT NOT NULL,
    age      INT
);

-- 基本 UPSERT
INSERT INTO users (id, username, email, age)
VALUES (1, 'alice', 'alice@example.com', 25)
ON CONFLICT (id) DO UPDATE
SET username = EXCLUDED.username, email = EXCLUDED.email, age = EXCLUDED.age;

-- ON CONFLICT DO NOTHING
INSERT INTO users (id, username, email, age)
VALUES (1, 'alice', 'alice@example.com', 25)
ON CONFLICT (id) DO NOTHING;

-- 批量 UPSERT
INSERT INTO users (id, username, email, age) VALUES
    (1, 'alice', 'alice@example.com', 25),
    (2, 'bob', 'bob@example.com', 30)
ON CONFLICT (id) DO UPDATE
SET username = EXCLUDED.username, email = EXCLUDED.email;

-- ============================================================
-- SOURCE 中的 UPSERT 语义
-- ============================================================

-- PostgreSQL CDC SOURCE 自带 UPSERT 语义
-- 源表的 UPDATE 操作会自动反映为下游的更新
CREATE SOURCE pg_source
FROM POSTGRES CONNECTION pg_conn (PUBLICATION 'mz_source')
FOR TABLES (users, orders);

-- Kafka SOURCE 的 UPSERT 语义
CREATE SOURCE kafka_users
FROM KAFKA CONNECTION kafka_conn (TOPIC 'users')
FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn
ENVELOPE UPSERT;                   -- 指定 UPSERT envelope

-- ============================================================
-- 物化视图自动处理 UPSERT
-- ============================================================

-- 当上游数据 UPSERT 时，物化视图自动增量更新
CREATE MATERIALIZED VIEW user_stats AS
SELECT COUNT(*) AS total_users, AVG(age) AS avg_age
FROM users;

-- UPSERT users 表后，user_stats 自动更新

-- 注意：TABLE 支持 INSERT ... ON CONFLICT
-- 注意：SOURCE 可以通过 ENVELOPE UPSERT 实现 UPSERT 语义
-- 注意：物化视图自动处理上游的 UPSERT 变更
-- 注意：兼容 PostgreSQL 的 UPSERT 语法
