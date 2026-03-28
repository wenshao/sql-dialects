-- TiDB: Constraints (约束)
--
-- 参考资料:
--   [1] TiDB Constraints
--       https://docs.pingcap.com/tidb/stable/constraints
--   [2] TiDB Foreign Keys
--       https://docs.pingcap.com/tidb/stable/foreign-key

-- ============================================================
-- 1. 基本语法（MySQL 兼容）
-- ============================================================

-- PRIMARY KEY（聚集索引 vs 非聚集索引）
CREATE TABLE users (
    id       BIGINT NOT NULL AUTO_RANDOM,
    username VARCHAR(100) NOT NULL,
    PRIMARY KEY (id) CLUSTERED             -- TiDB 特有: CLUSTERED/NONCLUSTERED
);

-- UNIQUE 约束
ALTER TABLE users ADD CONSTRAINT uk_username UNIQUE (username);
ALTER TABLE users ADD UNIQUE KEY uk_email (email);

-- NOT NULL
CREATE TABLE orders (
    id     BIGINT NOT NULL AUTO_RANDOM,
    amount DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (id)
);
ALTER TABLE users MODIFY COLUMN email VARCHAR(255) NOT NULL;

-- CHECK 约束（MySQL 8.0.16+ 兼容）
CREATE TABLE accounts (
    id      BIGINT NOT NULL AUTO_RANDOM,
    balance DECIMAL(10,2),
    age     INT,
    PRIMARY KEY (id),
    CONSTRAINT chk_balance CHECK (balance >= 0),
    CONSTRAINT chk_age CHECK (age >= 0 AND age <= 150)
);
ALTER TABLE users ADD CONSTRAINT chk_status CHECK (status IN (0, 1, 2));

-- DEFAULT
CREATE TABLE defaults_example (
    id         BIGINT NOT NULL AUTO_RANDOM,
    status     INT DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
);

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 FOREIGN KEY: 分布式引擎的最大约束挑战
-- TiDB 外键的演进历史反映了分布式约束的工程难度:
--   6.6 之前: 解析 FOREIGN KEY 语法但不执行（与 MySQL 5.7 前的 CHECK 类似）
--   6.6+:     实验性支持外键（强制执行）
--   7.0+:     外键支持改进但仍有限制
--
-- 为什么分布式外键这么难？
--   外键检查需要跨 TiKV Region 的分布式读取:
--   INSERT INTO orders (user_id) VALUES (123) 需要验证 users 表中 id=123 存在
--   如果 users 和 orders 在不同 Region（甚至不同节点），这需要跨节点 RPC
--   高并发写入时，外键检查成为性能瓶颈
--
-- 对比:
--   OceanBase:   完全支持外键（因为 Tablegroup 可以共置相关表）
--   CockroachDB: 完全支持外键（跨 Range 检查有延迟但正确性保证）
--   Spanner:     支持外键（INTERLEAVE 模式下的外键效率更高）
--   MySQL:       完全支持（InnoDB，单机无跨节点问题）
--   BigQuery:    信息性外键（不强制执行，纯 OLAP 不需要）
--   Redshift:    信息性外键（不强制执行）
--
-- 对引擎开发者的启示:
--   分布式引擎实现外键有三种策略:
--   A. 完全支持但接受性能代价（CockroachDB）
--   B. 通过数据共置优化（Spanner INTERLEAVE, OceanBase Tablegroup）
--   C. 不支持或信息性（BigQuery, Redshift, 早期 TiDB）

-- 外键语法（6.6+）
CREATE TABLE order_items (
    id       BIGINT NOT NULL AUTO_RANDOM,
    order_id BIGINT NOT NULL,
    amount   DECIMAL(10,2),
    PRIMARY KEY (id),
    CONSTRAINT fk_order FOREIGN KEY (order_id)
        REFERENCES orders (id) ON DELETE CASCADE
);

-- 2.2 约束执行保证
-- TiDB 的 PRIMARY KEY 和 UNIQUE: 强制执行（分布式唯一性检查）
-- CHECK: 强制执行（本地检查，无跨节点开销）
-- FOREIGN KEY: 6.6+ 强制执行（有跨节点开销）
-- NOT NULL: 强制执行

-- ============================================================
-- 3. 约束管理
-- ============================================================
ALTER TABLE users DROP CONSTRAINT chk_age;
ALTER TABLE order_items DROP FOREIGN KEY fk_order;
ALTER TABLE users DROP INDEX uk_username;
-- TiDB 使用 MySQL 语法: DROP INDEX / DROP FOREIGN KEY / DROP CONSTRAINT

-- 查看约束
SHOW CREATE TABLE users;
SELECT * FROM information_schema.table_constraints WHERE table_name = 'users';
SELECT * FROM information_schema.key_column_usage WHERE table_name = 'users';
SELECT * FROM information_schema.check_constraints;

-- ============================================================
-- 4. 限制与注意事项
-- ============================================================
-- AUTO_RANDOM 列: 必须是 BIGINT + PRIMARY KEY
-- 复合主键: CLUSTERED 主键的复合键顺序影响 TiKV 数据分布
-- 外键: 6.6+ 实验性支持，生产环境建议应用层约束
-- 排他约束 (EXCLUDE): 不支持（MySQL 语法不包含）
-- 延迟约束 (DEFERRABLE): 不支持
-- 部分唯一约束: 不支持（CockroachDB/PostgreSQL 特有）

-- ============================================================
-- 5. 横向对比
-- ============================================================
-- 1. 约束强制执行:
--    TiDB:        PK/UNIQUE/CHECK 强制, FK 实验性（6.6+）
--    CockroachDB: 所有约束强制执行
--    OceanBase:   所有约束强制执行
--    Spanner:     PK/UNIQUE/FK/CHECK 强制执行
--    Redshift:    仅 PK 强制, UK/FK 信息性
--    BigQuery:    所有约束信息性
--
-- 2. 部分唯一约束 (UNIQUE WHERE):
--    CockroachDB + PostgreSQL: 支持
--    MySQL/TiDB/OceanBase/Spanner/Redshift: 不支持
--
-- 3. 延迟约束 (DEFERRABLE):
--    PostgreSQL + Oracle: 支持
--    MySQL/TiDB/CockroachDB/Spanner/Redshift: 不支持
