-- PolarDB: 约束 (Constraints)
-- PolarDB-X (distributed, MySQL compatible) / PolarDB MySQL (cloud-native).
-- Alibaba Cloud managed database service.
--
-- 参考资料:
--   [1] PolarDB-X SQL Reference - Constraints
--       https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/
--   [2] PolarDB MySQL Documentation
--       https://help.aliyun.com/zh/polardb/polardb-for-mysql/
--   [3] PolarDB-X Global Secondary Index
--       https://help.aliyun.com/zh/polardb/polardb-for-xscale/user-guide/global-secondary-index
--   [4] MySQL 8.0 Reference Manual - Constraints
--       https://dev.mysql.com/doc/refman/8.0/en/create-table-foreign-keys.html

-- ============================================================
-- 1. PRIMARY KEY（主键约束）
-- ============================================================

-- 单列主键
CREATE TABLE users (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    username   VARCHAR(64)  NOT NULL,
    email      VARCHAR(255) NOT NULL,
    PRIMARY KEY (id)
) DBPARTITION BY HASH(id);    -- PolarDB-X 分布式分表语法

-- 复合主键
CREATE TABLE order_items (
    order_id BIGINT NOT NULL,
    item_id  BIGINT NOT NULL,
    user_id  BIGINT NOT NULL,
    PRIMARY KEY (order_id, item_id)
) DBPARTITION BY HASH(user_id);

-- ============================================================
-- 2. UNIQUE 约束（唯一性约束）
-- ============================================================

-- 本地唯一约束（必须包含分区键）
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email, id);
-- 如果 email 是唯一索引但不包含分区键 id → 创建失败

-- 复合唯一约束
ALTER TABLE users ADD CONSTRAINT uk_name_email UNIQUE (username, email, id);

-- 通过 CREATE TABLE 内联定义
CREATE TABLE products (
    id   BIGINT      NOT NULL,
    sku  VARCHAR(64) NOT NULL,
    name VARCHAR(255) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_sku (sku, id)
) DBPARTITION BY HASH(id);

-- ============================================================
-- 3. 全局二级索引与约束的交互（PolarDB-X 核心特性）
-- ============================================================
-- PolarDB-X 的 GSI（Global Secondary Index）是其区别于其他分布式数据库的关键能力。
-- GSI 允许在非分区键列上创建唯一约束和索引。

-- 创建带 GSI 的表（GSI 上可以有 UNIQUE 约束）
CREATE TABLE orders (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    user_id    BIGINT       NOT NULL,
    order_no   VARCHAR(64)  NOT NULL,
    status     TINYINT      DEFAULT 0,
    amount     DECIMAL(10,2) DEFAULT 0,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE GLOBAL KEY uk_order_no (order_no) DBPARTITION BY HASH(order_no)
) DBPARTITION BY HASH(user_id);
-- uk_order_no 是全局唯一索引，按 order_no 独立分片
-- 虽然 order_no 不是主表的分区键，但 GSI 保证了全局唯一性

-- GSI 约束行为:
--   1. GSI 的 UNIQUE 约束通过分布式事务保证全局唯一
--   2. GSI 的写入需要 2PC（两阶段提交），比本地索引慢
--   3. GSI 可以覆盖非分区键列的查询，避免全分片扫描
--   4. GSI 本质上是独立的索引表，有自己的分片策略

-- GSI 与本地唯一索引的对比:
--   本地唯一索引: 只保证分片内唯一，必须包含分区键，无额外开销
--   全局唯一索引 (GSI): 保证全局唯一，不需要包含分区键，有分布式事务开销

-- ============================================================
-- 4. FOREIGN KEY 约束
-- ============================================================
-- 分布式环境下外键支持有限:
--   仅在同一分片键的表之间支持（即父表和子表使用相同分区策略）

-- 同分片外键（user_id 是 orders 和 users 的共同分区键）
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE;

-- 跨分片外键不支持:
-- ALTER TABLE order_items ADD CONSTRAINT fk_items_product
--     FOREIGN KEY (product_id) REFERENCES products (id);
-- 如果 order_items 和 products 不在相同分片 → 创建失败

-- ============================================================
-- 5. NOT NULL / DEFAULT / CHECK 约束
-- ============================================================

-- NOT NULL
ALTER TABLE users MODIFY COLUMN email VARCHAR(255) NOT NULL;

-- DEFAULT
ALTER TABLE users ALTER COLUMN status SET DEFAULT 1;

-- CHECK（MySQL 8.0 兼容模式）
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
ALTER TABLE orders ADD CONSTRAINT chk_amount CHECK (amount >= 0);
-- CHECK 在各分片独立验证，无分布式交互

-- ============================================================
-- 6. 约束管理操作
-- ============================================================

-- 删除约束
ALTER TABLE users DROP INDEX uk_email;
ALTER TABLE orders DROP FOREIGN KEY fk_orders_user;
ALTER TABLE users DROP CHECK chk_age;

-- 查看约束元数据
SELECT * FROM information_schema.TABLE_CONSTRAINTS
WHERE TABLE_SCHEMA = 'mydb' AND TABLE_NAME = 'users';

SELECT * FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA = 'mydb' AND TABLE_NAME = 'users';

-- 查看 GSI 信息（PolarDB-X 扩展）
SELECT * FROM information_schema.ALIOSS_INDEXES
WHERE TABLE_SCHEMA = 'mydb' AND TABLE_NAME = 'orders';

-- ============================================================
-- 7. 设计分析（对 SQL 引擎开发者）
-- ============================================================
-- PolarDB-X 的约束设计在分布式 MySQL 兼容数据库中较为先进:
--
-- 7.1 GSI 解决了分布式唯一性的核心难题:
--   传统方案: 限制唯一约束必须包含分区键（TDSQL 方案）
--   GSI 方案: 通过独立的索引分片 + 分布式事务保证全局唯一
--   代价: 写入时需要维护两份数据（主表 + GSI），2PC 协调
--   对比 TiDB: TiDB 的二级索引也是全局的（所有索引都是全局索引）
--   对比 CockroachDB: 自动分布式，无需显式 GSI
--
-- 7.2 外键的分布式实现:
--   同分片外键: 可以利用本地事务，开销可控
--   跨分片外键: 需要分布式事务验证引用完整性，开销极大
--   PolarDB-X 的选择: 只支持同分片外键（实用主义）
--   TiDB 6.6+: 开始支持外键（通过分布式事务）
--
-- 7.3 跨方言对比:
--   PolarDB-X:  GSI + 同分片外键 + CHECK
--   TDSQL:      shardkey 强制唯一约束 + 无外键 + CHECK
--   TiDB:       全局索引 + 外键(6.6+) + CHECK
--   OceanBase:  全局索引 + 外键 + CHECK（最完整）
--   CockroachDB: 全分布式约束（最激进）
--
-- 7.4 版本演进:
--   PolarDB-X 1.0: 基础分布式约束（同 TDSQL）
--   PolarDB-X 2.0: GSI 支持，突破分区键限制
--   PolarDB-X 2.x: GSI 性能优化，支持更多约束类型
--   PolarDB MySQL: 与 PolarDB-X 共享约束语法（单机模式无分布式限制）

-- ============================================================
-- 8. 最佳实践
-- ============================================================
-- 1. 高频查询使用 GSI 避免全分片扫描
-- 2. GSI 的 UNIQUE 约束用于替代 "唯一约束必须含分区键" 的限制
-- 3. 外键只用在同分片表之间，跨分片用应用层保证
-- 4. CHECK 约束对分布式透明，尽量利用
-- 5. GSI 的写入开销需要在查询性能和数据写入吞吐之间权衡
