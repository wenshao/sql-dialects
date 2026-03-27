-- TDSQL: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] TDSQL Documentation - Auto Increment
--       https://cloud.tencent.com/document/product/557/7706
--   [2] TDSQL Documentation - Sequence
--       https://cloud.tencent.com/document/product/557/7707
--   [3] TDSQL Documentation - Distributed Transactions
--       https://cloud.tencent.com/document/product/557

-- ============================================
-- AUTO_INCREMENT（兼容 MySQL）
-- ============================================
CREATE TABLE users (
    id       BIGINT NOT NULL AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255) NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB;

SELECT LAST_INSERT_ID();

-- 分布式 AUTO_INCREMENT：
-- TDSQL 在分布式模式下，AUTO_INCREMENT 由中心化的序列服务管理
-- 保证全局唯一，但可能不连续

-- ============================================
-- SEQUENCE（TDSQL 分布式特有）
-- ============================================
-- TDSQL 分布式版支持 CREATE SEQUENCE
CREATE SEQUENCE order_id_seq
    START WITH 1
    INCREMENT BY 1
    MAXVALUE 9999999999;

-- 使用序列
SELECT NEXT VALUE FOR order_id_seq;
-- 或
SELECT NEXTVAL(order_id_seq);

INSERT INTO orders (id, amount) VALUES (NEXT VALUE FOR order_id_seq, 99.99);

-- 删除序列
DROP SEQUENCE order_id_seq;

-- ============================================
-- UUID 生成
-- ============================================
SELECT UUID();

-- ============================================
-- 分布式 ID 策略
-- ============================================
-- TDSQL 分布式架构下：
-- 1. AUTO_INCREMENT 由 Proxy 统一分配，全局唯一
-- 2. SEQUENCE 提供更灵活的序列管理
-- 3. 分片键（shardkey）选择影响数据分布

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- 1. AUTO_INCREMENT：简单，兼容 MySQL
-- 2. SEQUENCE：灵活，TDSQL 分布式版支持
-- 3. UUID：全局唯一，无需中心化服务
-- 4. 分布式环境下 AUTO_INCREMENT 可能有性能开销

-- 限制：
-- SEQUENCE 仅分布式版支持
-- 不支持 IDENTITY / SERIAL
-- 不支持 GENERATED AS IDENTITY
-- AUTO_INCREMENT 在分布式场景下行为与单机 MySQL 不同
