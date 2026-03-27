-- Derby: 约束
--
-- 参考资料:
--   [1] Derby SQL Reference
--       https://db.apache.org/derby/docs/10.16/ref/
--   [2] Derby Developer Guide
--       https://db.apache.org/derby/docs/10.16/devguide/

-- Derby 支持标准 SQL 约束

-- ============================================================
-- PRIMARY KEY
-- ============================================================

CREATE TABLE users (
    id       INT NOT NULL GENERATED ALWAYS AS IDENTITY,
    username VARCHAR(64) NOT NULL,
    PRIMARY KEY (id)
);

-- 复合主键
CREATE TABLE order_items (
    order_id INT NOT NULL,
    item_id  INT NOT NULL,
    quantity INT,
    PRIMARY KEY (order_id, item_id)
);

-- 命名主键
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id);

-- ============================================================
-- UNIQUE
-- ============================================================

CREATE TABLE members (
    id    INT NOT NULL GENERATED ALWAYS AS IDENTITY,
    email VARCHAR(128) NOT NULL,
    phone VARCHAR(20),
    PRIMARY KEY (id),
    UNIQUE (email),
    CONSTRAINT uq_phone UNIQUE (phone)
);

ALTER TABLE members ADD CONSTRAINT uq_email UNIQUE (email);
ALTER TABLE members DROP CONSTRAINT uq_email;

-- ============================================================
-- NOT NULL
-- ============================================================

CREATE TABLE products (
    id    INT NOT NULL,
    name  VARCHAR(100) NOT NULL,
    price DECIMAL(10,2) NOT NULL
);

-- 添加 NOT NULL（通过 ALTER COLUMN）
ALTER TABLE products ALTER COLUMN name NOT NULL;

-- 注意：Derby 不支持 DROP NOT NULL

-- ============================================================
-- DEFAULT
-- ============================================================

CREATE TABLE events (
    id         INT NOT NULL GENERATED ALWAYS AS IDENTITY,
    status     INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
);

ALTER TABLE events ALTER COLUMN status DEFAULT 1;
ALTER TABLE events ALTER COLUMN status DROP DEFAULT;

-- ============================================================
-- CHECK
-- ============================================================

CREATE TABLE employees (
    id     INT NOT NULL GENERATED ALWAYS AS IDENTITY,
    age    INT,
    salary DECIMAL(10,2),
    PRIMARY KEY (id),
    CHECK (age BETWEEN 16 AND 150),
    CONSTRAINT chk_salary CHECK (salary >= 0)
);

ALTER TABLE employees ADD CONSTRAINT chk_age CHECK (age >= 16);
ALTER TABLE employees DROP CONSTRAINT chk_age;

-- ============================================================
-- FOREIGN KEY
-- ============================================================

CREATE TABLE orders (
    id      INT NOT NULL GENERATED ALWAYS AS IDENTITY,
    user_id INT NOT NULL,
    amount  DECIMAL(10,2),
    PRIMARY KEY (id),
    CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES users(id)
);

-- 级联操作
CREATE TABLE comments (
    id      INT NOT NULL GENERATED ALWAYS AS IDENTITY,
    user_id INT NOT NULL,
    content VARCHAR(1000),
    PRIMARY KEY (id),
    FOREIGN KEY (user_id) REFERENCES users(id)
        ON DELETE CASCADE
        ON UPDATE RESTRICT
);

-- ON DELETE 选项: CASCADE, SET NULL, SET DEFAULT, RESTRICT, NO ACTION

ALTER TABLE orders ADD CONSTRAINT fk_user
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE orders DROP CONSTRAINT fk_user;

-- ============================================================
-- 查看约束
-- ============================================================

SELECT * FROM SYS.SYSCONSTRAINTS c
JOIN SYS.SYSTABLES t ON c.TABLEID = t.TABLEID
WHERE t.TABLENAME = 'USERS';

SELECT c.CONSTRAINTNAME, c.TYPE FROM SYS.SYSCONSTRAINTS c
JOIN SYS.SYSTABLES t ON c.TABLEID = t.TABLEID;
-- TYPE: P=主键, U=唯一, C=CHECK, F=外键

-- 注意：Derby 支持所有标准约束
-- 注意：不支持 DROP NOT NULL
-- 注意：不支持延迟约束检查（DEFERRABLE）
-- 注意：约束名在 schema 内唯一
