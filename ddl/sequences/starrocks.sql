-- StarRocks: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] StarRocks Documentation - AUTO_INCREMENT
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/data-definition/CREATE_TABLE/
--   [2] StarRocks Documentation - UUID
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/utility-functions/uuid/

-- ============================================
-- StarRocks 不支持 CREATE SEQUENCE
-- ============================================

-- ============================================
-- AUTO_INCREMENT（StarRocks 3.0+）
-- ============================================
CREATE TABLE users (
    id       BIGINT NOT NULL AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255) NOT NULL
) PRIMARY KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 8
PROPERTIES ("replication_num" = "3");

-- AUTO_INCREMENT 特点：
-- 1. 全局唯一，但不保证连续
-- 2. 各 BE 节点预分配 ID 段
-- 3. 每个 AUTO_INCREMENT 列自动创建内部序列

-- ============================================
-- UUID 生成
-- ============================================
SELECT uuid();
-- 返回标准 UUID 字符串

SELECT uuid_numeric();
-- 返回 LARGEINT 类型的 UUID 数值

-- ============================================
-- 替代方案
-- ============================================
-- 方法 1：ROW_NUMBER()
SELECT
    ROW_NUMBER() OVER (ORDER BY created_at) AS row_id,
    username, email
FROM users;

-- 方法 2：在 ETL 管道中生成 ID
-- StarRocks 主要通过批量导入数据，ID 在上游生成

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- 1. AUTO_INCREMENT（3.0+推荐）：分布式唯一，简单
-- 2. uuid()：全局唯一，无需协调
-- 3. uuid_numeric()：适合需要数值类型的场景
-- 4. ETL 生成 ID：批量导入场景的传统方式

-- 限制：
-- 不支持 CREATE SEQUENCE
-- 不支持 IDENTITY / SERIAL
-- AUTO_INCREMENT 需要 StarRocks 3.0+
-- AUTO_INCREMENT 值可能不连续
