-- Vertica: 约束
--
-- 参考资料:
--   [1] Vertica SQL Reference
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/SQLReferenceManual.htm
--   [2] Vertica Functions
--       https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Functions/Functions.htm

-- Vertica 支持丰富的约束，但默认不强制执行
-- 约束用于优化器生成更好的查询计划

-- ============================================================
-- NOT NULL（强制执行）
-- ============================================================

CREATE TABLE users (
    id       INT NOT NULL,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255) NOT NULL
);

-- NOT NULL 是唯一默认强制执行的约束

-- ============================================================
-- PRIMARY KEY（默认不强制执行）
-- ============================================================

CREATE TABLE users (
    id       INT NOT NULL PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255)
);

-- 启用强制执行
CREATE TABLE users (
    id       INT NOT NULL PRIMARY KEY ENABLED,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255)
);

-- ALTER 方式
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id) ENABLED;

-- ============================================================
-- UNIQUE（默认不强制执行）
-- ============================================================

CREATE TABLE users (
    id       INT NOT NULL PRIMARY KEY,
    email    VARCHAR(255) UNIQUE
);

-- 启用强制执行
ALTER TABLE users ADD CONSTRAINT uq_email UNIQUE (email) ENABLED;

-- ============================================================
-- FOREIGN KEY（默认不强制执行）
-- ============================================================

CREATE TABLE orders (
    id       INT NOT NULL PRIMARY KEY,
    user_id  INT REFERENCES users(id),
    amount   NUMERIC(10,2)
);

-- 命名外键
ALTER TABLE orders ADD CONSTRAINT fk_user
    FOREIGN KEY (user_id) REFERENCES users(id);

-- ============================================================
-- CHECK（默认不强制执行）
-- ============================================================

CREATE TABLE products (
    id       INT NOT NULL,
    name     VARCHAR(128) NOT NULL,
    price    NUMERIC(10,2),
    quantity INT,
    CONSTRAINT chk_price CHECK (price > 0) ENABLED,
    CONSTRAINT chk_qty CHECK (quantity >= 0) ENABLED
);

-- ============================================================
-- DEFAULT
-- ============================================================

CREATE TABLE users (
    id         AUTO_INCREMENT,
    status     INT DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    uuid       VARCHAR(36) DEFAULT UUID_GENERATE()
);

-- ============================================================
-- 约束启用/禁用
-- ============================================================

-- 启用约束强制执行
ALTER TABLE users ALTER CONSTRAINT pk_users ENABLED;
ALTER TABLE users ALTER CONSTRAINT uq_email ENABLED;

-- 禁用约束（保留声明，不再检查）
ALTER TABLE users ALTER CONSTRAINT pk_users DISABLED;

-- ============================================================
-- 约束管理
-- ============================================================

-- 添加约束
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0);

-- 删除约束
ALTER TABLE users DROP CONSTRAINT chk_age;

-- 查看约束
SELECT constraint_name, constraint_type, is_enabled
FROM v_catalog.table_constraints
WHERE table_name = 'users';

-- ============================================================
-- 访问策略（Vertica 独有）
-- ============================================================

-- Row Access Policy（行级安全）
CREATE ACCESS POLICY ON users FOR ROWS
    WHERE username = CURRENT_USER() ENABLE;

-- Column Access Policy（列级安全）
CREATE ACCESS POLICY ON users FOR COLUMN email
    CASE WHEN ENABLED_ROLE('admin') THEN email
         ELSE '***' END ENABLE;

-- 注意：除 NOT NULL 外，约束默认不强制执行（仅声明性）
-- 注意：启用约束强制执行会影响写入性能
-- 注意：声明性约束帮助优化器生成更好的查询计划
-- 注意：Vertica 推荐使用 ENABLED 关键字明确启用需要的约束
