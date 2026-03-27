-- Oracle: CREATE TABLE
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - CREATE TABLE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-TABLE.html
--   [2] Oracle SQL Language Reference - Data Types
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Data-Types.html

CREATE TABLE users (
    id         NUMBER(19)    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,  -- 12c+
    username   VARCHAR2(64)  NOT NULL,
    email      VARCHAR2(255) NOT NULL,
    age        NUMBER(10),
    balance    NUMBER(10,2)  DEFAULT 0.00,
    bio        CLOB,
    created_at TIMESTAMP     DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMP     DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT uk_username UNIQUE (username),
    CONSTRAINT uk_email UNIQUE (email)
);

-- Oracle 没有 ON UPDATE CURRENT_TIMESTAMP，需要用触发器
CREATE OR REPLACE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
BEGIN
    :NEW.updated_at := CURRENT_TIMESTAMP;
END;
/
