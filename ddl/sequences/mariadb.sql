-- MariaDB: SEQUENCE (10.3+)
-- Oracle 风格的独立序列对象, MySQL 不支持此特性
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - CREATE SEQUENCE
--       https://mariadb.com/kb/en/create-sequence/

-- ============================================================
-- 1. 创建序列
-- ============================================================
CREATE SEQUENCE seq_user_id
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 9999999999
    CACHE 1000
    NOCYCLE;

CREATE SEQUENCE seq_order_no
    START WITH 10000
    INCREMENT BY 1
    CACHE 100
    CYCLE;                  -- 到达 MAXVALUE 后从 MINVALUE 重新开始

-- ============================================================
-- 2. 使用序列
-- ============================================================
SELECT NEXT VALUE FOR seq_user_id;          -- 获取下一个值
SELECT NEXTVAL(seq_user_id);                 -- 等价简写
SELECT PREVIOUS VALUE FOR seq_user_id;       -- 获取当前值 (本会话最后生成的)
SELECT LASTVAL(seq_user_id);                 -- 等价简写

-- 在 INSERT 中使用
INSERT INTO users (id, username) VALUES (NEXT VALUE FOR seq_user_id, 'alice');

-- ============================================================
-- 3. 序列管理
-- ============================================================
ALTER SEQUENCE seq_user_id RESTART WITH 1000;
ALTER SEQUENCE seq_user_id INCREMENT BY 5;
ALTER SEQUENCE seq_user_id MAXVALUE 999999;
SELECT * FROM seq_user_id;                   -- 查看序列状态 (MariaDB 将序列暴露为表)
DROP SEQUENCE seq_user_id;
DROP SEQUENCE IF EXISTS seq_user_id;         -- IF EXISTS 支持

-- ============================================================
-- 4. 序列实现: 作为特殊表
-- ============================================================
-- MariaDB 的序列在内部是一个只有一行的表
-- SHOW CREATE TABLE seq_order_no 可以看到序列的完整定义
-- 这意味着序列可以用 SELECT/ALTER TABLE 操作, 但不应该直接 UPDATE
--
-- 对比 PostgreSQL: 序列也是一种特殊关系 (relation), 存储在 pg_class 中
-- 对比 Oracle: 序列是独立的 schema 对象, 不是表
-- 对比 Db2: 序列是独立对象, 通过 NEXT VALUE FOR 访问

-- ============================================================
-- 5. SEQUENCE vs AUTO_INCREMENT 的选择
-- ============================================================
-- AUTO_INCREMENT:
--   优点: 简单, 与 MySQL 完全兼容
--   缺点: 绑定单表, 不能跨表共享, 步长只能通过系统变量设置
-- SEQUENCE:
--   优点: 独立对象, 跨表共享, 灵活的起始值/步长/循环
--   缺点: 需要显式调用, 应用代码改造, MySQL 不兼容
--
-- 实际场景: 统一订单号生成 (多表共用一个序列)
-- CREATE SEQUENCE seq_global_order;
-- INSERT INTO orders_2024 (id, ...) VALUES (NEXT VALUE FOR seq_global_order, ...);
-- INSERT INTO orders_2025 (id, ...) VALUES (NEXT VALUE FOR seq_global_order, ...);

-- ============================================================
-- 6. 对引擎开发者的启示
-- ============================================================
-- SEQUENCE 的 CACHE 是性能关键:
--   CACHE 1: 每次取值都写磁盘 (安全但慢)
--   CACHE 1000: 预分配 1000 个值到内存 (快但崩溃丢失至多 999 个值)
--   无 CACHE: 等同于 CACHE 1
-- 分布式环境下的 SEQUENCE:
--   方案 A: 中心化序列服务 (瓶颈)
--   方案 B: 每个节点预分配不同段 (如 node1: 1-1000, node2: 1001-2000)
--   方案 C: 放弃连续性 (Snowflake-like ID)
