-- Teradata: Constraints
--
-- 参考资料:
--   [1] Teradata SQL Reference
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates
--   [2] Teradata Database Documentation
--       https://docs.teradata.com/

-- PRIMARY INDEX (determines distribution, not a constraint)
-- Note: Teradata distinguishes PRIMARY INDEX from PRIMARY KEY
CREATE TABLE users (
    id       INTEGER NOT NULL,
    username VARCHAR(64) NOT NULL
)
UNIQUE PRIMARY INDEX (id);

-- PRIMARY KEY (constraint, enforced as USI if different from PI)
CREATE TABLE orders (
    order_id INTEGER NOT NULL,
    user_id  INTEGER NOT NULL,
    PRIMARY KEY (order_id)
)
PRIMARY INDEX (user_id);

-- Composite primary key
CREATE TABLE order_items (
    order_id INTEGER NOT NULL,
    item_id  INTEGER NOT NULL,
    PRIMARY KEY (order_id, item_id)
)
PRIMARY INDEX (order_id);

-- UNIQUE constraint
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);

-- FOREIGN KEY
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id);

-- Foreign key with REFERENCES
CREATE TABLE order_items (
    order_id INTEGER NOT NULL REFERENCES orders (order_id),
    item_id  INTEGER NOT NULL,
    quantity INTEGER
)
PRIMARY INDEX (order_id);

-- NOT NULL
-- Defined at column level during CREATE TABLE or ALTER TABLE
ALTER TABLE users ALTER email NOT NULL;
ALTER TABLE users ALTER email NULL;

-- DEFAULT
ALTER TABLE users ALTER status DEFAULT 1;

-- CHECK constraint
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
ALTER TABLE events ADD CONSTRAINT chk_dates CHECK (end_date > start_date);

-- Named constraints at creation
CREATE TABLE products (
    product_id INTEGER NOT NULL,
    price      DECIMAL(10,2) CONSTRAINT chk_price CHECK (price > 0),
    quantity   INTEGER CONSTRAINT chk_qty CHECK (quantity >= 0),
    CONSTRAINT pk_products PRIMARY KEY (product_id)
)
UNIQUE PRIMARY INDEX (product_id);

-- Drop constraint
ALTER TABLE users DROP CONSTRAINT uk_email;
ALTER TABLE users DROP CONSTRAINT fk_orders_user;

-- Note: Teradata enforces UNIQUE and PRIMARY KEY via USI
-- Note: Foreign key enforcement depends on referential integrity settings
-- Note: CHECK constraints are enforced on INSERT and UPDATE
-- Note: SET tables have an implicit uniqueness constraint (no duplicate rows)

-- View constraints
SHOW TABLE users;
HELP CONSTRAINT users;
SELECT * FROM DBC.IndicesV WHERE DatabaseName = 'mydb' AND TableName = 'users';
