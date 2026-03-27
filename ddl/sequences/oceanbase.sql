-- OceanBase: Sequences & Auto-Increment
--
-- 参考资料:
--   [1] OceanBase Documentation - AUTO_INCREMENT
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn-1000000000819864
--   [2] OceanBase Documentation - CREATE SEQUENCE (Oracle Mode)
--       https://en.oceanbase.com/docs/common-oceanbase-database-10000000001700648
--   [3] OceanBase Documentation - Distributed ID
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn-1000000000819898

-- ============================================
-- AUTO_INCREMENT（MySQL 兼容模式）
-- ============================================
CREATE TABLE users (
    id       BIGINT NOT NULL AUTO_INCREMENT,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255) NOT NULL,
    PRIMARY KEY (id)
);

-- 获取最后生成的值
SELECT LAST_INSERT_ID();

-- 设置起始值
ALTER TABLE users AUTO_INCREMENT = 1000;

-- 分布式环境下的 AUTO_INCREMENT
-- OceanBase 使用中心化的 ID 分配器，保证全局唯一
-- 可能存在不连续（段预分配机制）

-- ============================================
-- SEQUENCE（Oracle 兼容模式）
-- ============================================
-- Oracle 模式下支持 CREATE SEQUENCE
CREATE SEQUENCE user_id_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 9999999999
    CACHE 20
    NO CYCLE;

-- 使用序列（Oracle 模式）
-- SELECT user_id_seq.NEXTVAL FROM DUAL;
-- SELECT user_id_seq.CURRVAL FROM DUAL;

-- MySQL 模式下的序列模拟
-- 使用 AUTO_INCREMENT 或自定义表模拟

-- ============================================
-- UUID 生成
-- ============================================
-- MySQL 模式
SELECT UUID();

-- Oracle 模式
-- SELECT SYS_GUID() FROM DUAL;

-- ============================================
-- 分布式 ID 策略
-- ============================================
-- OceanBase 的 AUTO_INCREMENT 在分布式架构下：
-- 1. 全局唯一性由 RootServer 保证
-- 2. 每个 OBServer 预分配 ID 段（cache），减少网络交互
-- 3. 值不一定连续，但保证递增
-- 4. 可通过参数调整缓存大小

-- ============================================
-- 序列 vs 自增 权衡
-- ============================================
-- 1. AUTO_INCREMENT（MySQL 模式推荐）：简单，分布式安全
-- 2. SEQUENCE（Oracle 模式）：灵活，可跨表共享
-- 3. UUID()：全局唯一，无中心化依赖
-- 4. OceanBase 的 AUTO_INCREMENT 比 MySQL 更强（分布式保证）
