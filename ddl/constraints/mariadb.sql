-- MariaDB: Constraints
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- PRIMARY KEY (same as MySQL)
CREATE TABLE users (
    id BIGINT NOT NULL AUTO_INCREMENT,
    PRIMARY KEY (id)
);

-- UNIQUE (same as MySQL)
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);

-- FOREIGN KEY (same as MySQL, fully enforced with InnoDB)
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE;

-- CHECK constraint (10.2.1+, enforced from the start)
-- MariaDB enforced CHECK constraints years before MySQL 8.0.16
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
-- In-line check
CREATE TABLE products (
    id    BIGINT NOT NULL AUTO_INCREMENT,
    price DECIMAL(10,2) CHECK (price > 0),
    qty   INT CHECK (qty >= 0),
    PRIMARY KEY (id)
);

-- WITHOUT OVERLAPS (10.5.3+): prevent overlapping periods
-- Unique to MariaDB, not available in MySQL
CREATE TABLE room_bookings (
    room_id    INT NOT NULL,
    start_date DATE NOT NULL,
    end_date   DATE NOT NULL,
    guest      VARCHAR(100),
    PERIOD FOR booking_period (start_date, end_date),
    UNIQUE (room_id, booking_period WITHOUT OVERLAPS)
);
-- Prevents double-booking: the UNIQUE constraint ensures no two rows
-- with the same room_id have overlapping booking_period

-- Application-time periods (10.5+)
ALTER TABLE contracts
    ADD PERIOD FOR valid_period (valid_from, valid_to);
-- Once period is defined, can use temporal DML:
-- DELETE FROM contracts FOR PORTION OF valid_period FROM '2024-01-01' TO '2024-06-01';
-- UPDATE contracts FOR PORTION OF valid_period FROM '2024-01-01' TO '2024-06-01' SET ...;

-- NOT NULL (same as MySQL)
ALTER TABLE users MODIFY COLUMN email VARCHAR(255) NOT NULL;

-- DEFAULT with expressions (10.2.1+)
-- MariaDB allows expressions as DEFAULT values earlier than MySQL
ALTER TABLE users ALTER COLUMN created_at SET DEFAULT (CURRENT_TIMESTAMP + INTERVAL 8 HOUR);

-- Drop constraints
ALTER TABLE users DROP INDEX uk_email;
ALTER TABLE orders DROP FOREIGN KEY fk_orders_user;
ALTER TABLE users DROP CONSTRAINT chk_age;

-- View constraints (same as MySQL)
SELECT * FROM information_schema.TABLE_CONSTRAINTS
WHERE TABLE_NAME = 'users';
SELECT * FROM information_schema.CHECK_CONSTRAINTS
WHERE TABLE_NAME = 'users';

-- Differences from MySQL 8.0:
-- CHECK constraints enforced since 10.2.1 (MySQL only since 8.0.16)
-- WITHOUT OVERLAPS constraint is MariaDB-specific
-- PERIOD FOR application-time periods is MariaDB-specific
-- Expression defaults supported earlier than MySQL
-- No functional differences in PRIMARY KEY, UNIQUE, FOREIGN KEY handling
