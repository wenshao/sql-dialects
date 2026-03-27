-- PostgreSQL: CREATE TABLE
--
-- 参考资料:
--   [1] PostgreSQL Documentation - CREATE TABLE
--       https://www.postgresql.org/docs/current/sql-createtable.html
--   [2] PostgreSQL Documentation - Data Types
--       https://www.postgresql.org/docs/current/datatype.html

CREATE TABLE users (
    id         BIGSERIAL     PRIMARY KEY,
    username   VARCHAR(64)   NOT NULL UNIQUE,
    email      VARCHAR(255)  NOT NULL UNIQUE,
    age        INTEGER,
    balance    NUMERIC(10,2) DEFAULT 0.00,
    bio        TEXT,
    created_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- PostgreSQL 没有 ON UPDATE CURRENT_TIMESTAMP，需要用触发器实现
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();
