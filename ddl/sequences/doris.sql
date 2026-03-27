-- Apache Doris: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] Apache Doris Documentation - Auto Increment
--       https://doris.apache.org/docs/sql-manual/sql-statements/Data-Definition-Statements/Create/CREATE-TABLE
--   [2] Apache Doris Documentation - Sequence Column
--       https://doris.apache.org/docs/data-operate/update/update-of-unique-model
--   [3] Apache Doris Documentation - UUID
--       https://doris.apache.org/docs/sql-manual/sql-functions/string-functions/uuid

-- ============================================
-- Doris 不支持 CREATE SEQUENCE
-- ============================================

-- ============================================
-- AUTO_INCREMENT（Doris 2.1+）
-- ============================================
CREATE TABLE users (
    id       BIGINT NOT NULL AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255) NOT NULL
) UNIQUE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8
PROPERTIES ("replication_num" = "3");

-- 插入时不指定自增列
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');

-- AUTO_INCREMENT 的特点：
-- 1. 保证唯一但不保证连续
-- 2. 每个 BE 节点有独立的 ID 分配区间（默认 100000）
-- 3. 不同批次的 INSERT 可能有间隙

-- ============================================
-- SEQUENCE 列（用于 Unique Key 模型的版本控制）
-- 注意：这不是 SQL 标准的 SEQUENCE，而是 Doris 特有的版本控制机制
-- ============================================
CREATE TABLE orders (
    user_id  BIGINT,
    order_id BIGINT,
    amount   DECIMAL(10,2),
    update_time DATETIME
) UNIQUE KEY(user_id, order_id)
DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES (
    "replication_num" = "3",
    "function_column.sequence_col" = "update_time"  -- 指定版本列
);
-- SEQUENCE 列用于确定相同 Key 的哪条记录最新

-- ============================================
-- UUID 生成
-- ============================================
SELECT uuid();
-- 结果示例：'7f1b7e42-3a1c-4b5d-8f2e-9c0d1e2f3a4b'

SELECT uuid_numeric();
-- 返回 LARGEINT 类型的 UUID 数值

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- 1. AUTO_INCREMENT（推荐，2.1+）：简单易用，分布式唯一
-- 2. uuid()：全局唯一，适合不需要排序的场景
-- 3. 在 ETL 管道中生成 ID：适合批量数据导入
-- 4. SEQUENCE 列不是自增，是版本控制机制

-- 限制：
-- 不支持 CREATE SEQUENCE
-- 不支持 IDENTITY / SERIAL
-- AUTO_INCREMENT 需要 Doris 2.1+
-- AUTO_INCREMENT 列必须是 Key 列的一部分
