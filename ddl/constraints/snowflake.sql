-- Snowflake: 约束
--
-- 参考资料:
--   [1] Snowflake SQL Reference - Constraints
--       https://docs.snowflake.com/en/sql-reference/constraints-overview
--   [2] Snowflake SQL Reference - CREATE TABLE
--       https://docs.snowflake.com/en/sql-reference/sql/create-table

-- Snowflake 的约束大多是信息性的，只有 NOT NULL 被强制执行

-- ============================================================
-- NOT NULL（唯一强制执行的约束）
-- ============================================================

CREATE TABLE users (
    id       NUMBER NOT NULL,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255)          -- 默认允许 NULL
);

ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

-- ============================================================
-- PRIMARY KEY（信息性，不强制执行）
-- ============================================================

CREATE TABLE users (
    id       NUMBER NOT NULL,
    username VARCHAR(64) NOT NULL,
    PRIMARY KEY (id)
);

-- 添加主键
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id);

-- 复合主键
CREATE TABLE order_items (
    order_id NUMBER NOT NULL,
    item_id  NUMBER NOT NULL,
    PRIMARY KEY (order_id, item_id)
);

-- ============================================================
-- UNIQUE（信息性，不强制执行）
-- ============================================================

ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);
ALTER TABLE users ADD CONSTRAINT uk_name_email UNIQUE (username, email);

-- ============================================================
-- FOREIGN KEY（信息性，不强制执行）
-- ============================================================

ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id);

-- 不支持 ON DELETE/UPDATE 动作（因为不强制执行）

-- ============================================================
-- DEFAULT
-- ============================================================

CREATE TABLE users (
    id         NUMBER NOT NULL AUTOINCREMENT,
    status     NUMBER DEFAULT 1,
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- ============================================================
-- CHECK（不支持）
-- ============================================================

-- Snowflake 不支持 CHECK 约束

-- ============================================================
-- 删除约束
-- ============================================================

ALTER TABLE users DROP CONSTRAINT uk_email;
ALTER TABLE users DROP CONSTRAINT pk_users;
ALTER TABLE orders DROP CONSTRAINT fk_orders_user;

-- 按类型删除（不需要知道名字）
ALTER TABLE users DROP PRIMARY KEY;
ALTER TABLE users DROP UNIQUE (email);

-- ============================================================
-- 查看约束
-- ============================================================

SHOW PRIMARY KEYS IN users;
SHOW UNIQUE KEYS IN users;
SHOW IMPORTED KEYS IN orders;  -- 外键

-- 或通过 INFORMATION_SCHEMA
SELECT * FROM information_schema.table_constraints
WHERE table_name = 'USERS';

-- ============================================================
-- 数据掩码策略（替代列级约束）
-- ============================================================

CREATE MASKING POLICY email_mask AS (val STRING) RETURNS STRING ->
    CASE WHEN current_role() IN ('ADMIN') THEN val
    ELSE '***@***.***'
    END;

ALTER TABLE users ALTER COLUMN email SET MASKING POLICY email_mask;

-- 注意：除 NOT NULL 外，所有约束都是信息性的，不强制执行！
-- 注意：不会阻止违反约束的数据插入
-- 注意：信息性约束帮助查询优化器和 BI 工具理解数据关系
-- 注意：数据完整性需要在应用层或 ELT 管道中保证
