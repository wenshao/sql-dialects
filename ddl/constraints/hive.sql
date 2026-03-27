-- Hive: 约束
--
-- 参考资料:
--   [1] Apache Hive Language Manual - DDL (Constraints)
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL#LanguageManualDDL-Constraints
--   [2] Apache Hive Language Manual - DDL
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+DDL

-- Hive 2.1+ 支持约束语法，但默认不强制执行
-- 约束分为：可依赖（RELY）和不可依赖（NORELY）

-- ============================================================
-- PRIMARY KEY（2.1+，不强制执行）
-- ============================================================

CREATE TABLE users (
    id       BIGINT,
    username STRING,
    email    STRING,
    PRIMARY KEY (id) DISABLE NOVALIDATE
);

-- DISABLE NOVALIDATE: 不强制执行，不验证已有数据（默认）
-- ENABLE VALIDATE: 强制执行并验证（仅部分场景支持）

-- ============================================================
-- UNIQUE（2.1+，不强制执行）
-- ============================================================

CREATE TABLE users (
    id       BIGINT,
    username STRING,
    email    STRING,
    PRIMARY KEY (id) DISABLE NOVALIDATE,
    UNIQUE (email) DISABLE NOVALIDATE
);

-- ============================================================
-- FOREIGN KEY（2.1+，不强制执行）
-- ============================================================

CREATE TABLE orders (
    id      BIGINT,
    user_id BIGINT,
    amount  DECIMAL(10,2),
    PRIMARY KEY (id) DISABLE NOVALIDATE,
    FOREIGN KEY (user_id) REFERENCES users (id) DISABLE NOVALIDATE
);

-- ============================================================
-- NOT NULL（2.1+）
-- ============================================================

CREATE TABLE users (
    id       BIGINT NOT NULL,
    username STRING NOT NULL,
    email    STRING           -- 默认允许 NULL
)
STORED AS ORC
TBLPROPERTIES ('transactional' = 'true');

-- 注意：NOT NULL 在 ACID 表上可以强制执行

-- ============================================================
-- CHECK（3.0+，不强制执行；CHECK 约束在 3.0 引入，其他约束在 2.1 引入）
-- ============================================================

CREATE TABLE users (
    id   BIGINT,
    age  INT,
    CHECK (age >= 0) DISABLE NOVALIDATE
);

-- ============================================================
-- DEFAULT（3.0+；DEFAULT 值在 3.0 引入）
-- ============================================================

CREATE TABLE users (
    id       BIGINT,
    status   INT DEFAULT 1,
    created  TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
)
STORED AS ORC
TBLPROPERTIES ('transactional' = 'true');

-- ============================================================
-- RELY / NORELY（约束可依赖性）
-- ============================================================

-- RELY: 告诉优化器可以信赖这个约束（用于查询优化）
CREATE TABLE users (
    id       BIGINT,
    username STRING,
    PRIMARY KEY (id) DISABLE NOVALIDATE RELY
);

-- 优化器可以利用 RELY 约束：
-- 1. 消除不必要的 JOIN
-- 2. 优化 GROUP BY
-- 3. 物化视图重写

-- ============================================================
-- 删除约束
-- ============================================================

ALTER TABLE users DROP CONSTRAINT pk_users;

-- ============================================================
-- 查看约束
-- ============================================================

DESCRIBE EXTENDED users;
SHOW TBLPROPERTIES users;

-- 注意：Hive 2.1 之前不支持约束（PRIMARY KEY/UNIQUE/FOREIGN KEY/NOT NULL 在 2.1 引入，CHECK/DEFAULT 在 3.0 引入）
-- 注意：约束默认 DISABLE NOVALIDATE，不强制执行
-- 注意：RELY 约束仅用于优化器提示
-- 注意：只有 ACID（事务）表才能对 NOT NULL 强制执行
-- 注意：约束主要是元数据信息，帮助工具和优化器理解数据
