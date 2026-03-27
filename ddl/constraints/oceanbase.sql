-- OceanBase: Constraints
-- OceanBase has dual mode: MySQL mode and Oracle mode. Both shown where relevant.
--
-- 参考资料:
--   [1] OceanBase SQL Reference (MySQL Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase SQL Reference (Oracle Mode)
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- MySQL Mode
-- ============================================================

-- PRIMARY KEY (same as MySQL)
CREATE TABLE users (
    id BIGINT NOT NULL AUTO_INCREMENT,
    PRIMARY KEY (id)
);

-- UNIQUE (same as MySQL)
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);

-- FOREIGN KEY (fully enforced, unlike TiDB)
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE;
-- Actions: CASCADE / SET NULL / RESTRICT / NO ACTION

-- NOT NULL
ALTER TABLE users MODIFY COLUMN email VARCHAR(255) NOT NULL;

-- DEFAULT
ALTER TABLE users ALTER COLUMN status SET DEFAULT 1;

-- CHECK constraint (4.0+, enforced)
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);

-- Drop constraints (same as MySQL)
ALTER TABLE users DROP INDEX uk_email;
ALTER TABLE orders DROP FOREIGN KEY fk_orders_user;
ALTER TABLE users DROP CHECK chk_age;

-- View constraints
SELECT * FROM information_schema.TABLE_CONSTRAINTS
WHERE TABLE_NAME = 'users';
SELECT * FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_NAME = 'users';

-- ============================================================
-- Oracle Mode
-- ============================================================

-- PRIMARY KEY
CREATE TABLE users (
    id   NUMBER NOT NULL,
    name VARCHAR2(64),
    CONSTRAINT pk_users PRIMARY KEY (id)
);

-- UNIQUE
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);

-- FOREIGN KEY (fully enforced)
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE;
-- Note: ON UPDATE CASCADE not supported in Oracle mode

-- NOT NULL
ALTER TABLE users MODIFY (email NOT NULL);

-- CHECK constraint
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);

-- DEFAULT value (Oracle syntax)
ALTER TABLE users MODIFY (status DEFAULT 1);

-- Disable / Enable constraints (Oracle mode only)
ALTER TABLE users DISABLE CONSTRAINT chk_age;
ALTER TABLE users ENABLE CONSTRAINT chk_age;

-- Drop constraints (Oracle syntax)
ALTER TABLE users DROP CONSTRAINT uk_email;
ALTER TABLE users DROP CONSTRAINT fk_orders_user;
ALTER TABLE users DROP CONSTRAINT chk_age;

-- View constraints (Oracle mode)
SELECT * FROM USER_CONSTRAINTS WHERE TABLE_NAME = 'USERS';
SELECT * FROM USER_CONS_COLUMNS WHERE TABLE_NAME = 'USERS';

-- Limitations:
-- MySQL mode: no DEFERRABLE constraints
-- Oracle mode: DEFERRABLE constraints supported
-- Foreign keys on partitioned tables may have restrictions
-- CHECK constraints with subqueries not supported
