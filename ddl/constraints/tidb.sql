-- TiDB: Constraints
-- TiDB is MySQL compatible; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] TiDB SQL Reference
--       https://docs.pingcap.com/tidb/stable/sql-statement-overview
--   [2] TiDB - MySQL Compatibility
--       https://docs.pingcap.com/tidb/stable/mysql-compatibility
--   [3] TiDB - Functions and Operators
--       https://docs.pingcap.com/tidb/stable/functions-and-operators-overview

-- PRIMARY KEY (same as MySQL, but consider CLUSTERED/NONCLUSTERED)
CREATE TABLE users (
    id BIGINT NOT NULL AUTO_RANDOM,
    PRIMARY KEY (id) CLUSTERED
);
-- Composite primary key
CREATE TABLE order_items (
    order_id BIGINT NOT NULL,
    item_id  BIGINT NOT NULL,
    PRIMARY KEY (order_id, item_id)
);

-- UNIQUE constraint (same as MySQL)
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);

-- FOREIGN KEY
-- Before 6.6.0: parsed and stored but NOT enforced (silently ignored)
-- 6.6.0+: foreign keys enforced (experimental, off by default)
-- Enable: SET GLOBAL tidb_enable_foreign_key = ON;
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE;
-- Warning: in versions < 6.6, this DDL succeeds but the constraint is NOT checked

-- NOT NULL (same as MySQL)
ALTER TABLE users MODIFY COLUMN email VARCHAR(255) NOT NULL;

-- DEFAULT (same as MySQL)
ALTER TABLE users ALTER COLUMN status SET DEFAULT 1;

-- CHECK constraint (enforced in v7.2+, parsed but not enforced in earlier versions)
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
-- Note: Before v7.2, CHECK constraints were parsed and stored but NOT enforced

-- Drop constraints (same as MySQL)
ALTER TABLE users DROP INDEX uk_email;
ALTER TABLE orders DROP FOREIGN KEY fk_orders_user;
ALTER TABLE users DROP CHECK chk_age;

-- View constraints
SELECT * FROM information_schema.TABLE_CONSTRAINTS
WHERE TABLE_NAME = 'users';
SELECT * FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_NAME = 'users';
-- TiDB-specific: check foreign key status
SELECT * FROM information_schema.REFERENTIAL_CONSTRAINTS;

-- AUTO_RANDOM constraint:
-- Column must be BIGINT
-- Must be the first column of PRIMARY KEY
-- Cannot be used with AUTO_INCREMENT
-- Cannot INSERT explicit values unless SET @@allow_auto_random_explicit_insert = ON
CREATE TABLE t (
    id BIGINT AUTO_RANDOM,
    PRIMARY KEY (id)
);

-- Limitations:
-- Foreign keys not enforced by default (must explicitly enable in 6.6+)
-- No deferred constraint checking
-- CHECK constraints enforced only since v7.2+ (not enforced in earlier versions)
-- AUTO_RANDOM has strict usage rules (see above)
