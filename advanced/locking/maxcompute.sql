-- MaxCompute (ODPS): 锁机制 (Locking)
--
-- 参考资料:
--   [1] MaxCompute 文档 - 事务表
--       https://help.aliyun.com/document_detail/415788.html
--   [2] MaxCompute 文档 - 并发控制
--       https://help.aliyun.com/document_detail/27820.html

-- ============================================================
-- MaxCompute 并发模型概述
-- ============================================================
-- MaxCompute 是阿里云的大数据计算平台:
-- 1. 传统表不支持行级操作，只支持分区/表级别的操作
-- 2. 事务表（Transaction Table）支持 ACID
-- 3. 使用乐观并发控制
-- 4. 不支持 SELECT FOR UPDATE

-- ============================================================
-- 事务表（MaxCompute 2.0+）
-- ============================================================

-- 创建事务表
CREATE TABLE orders (
    id      BIGINT,
    status  STRING,
    amount  DECIMAL(10,2)
)
TBLPROPERTIES ('transactional'='true');

-- 事务表支持 UPDATE/DELETE
UPDATE orders SET status = 'shipped' WHERE id = 100;
DELETE FROM orders WHERE status = 'cancelled';

-- MERGE（upsert）
MERGE INTO orders t
USING updates s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.status = s.status
WHEN NOT MATCHED THEN INSERT VALUES (s.id, s.status, s.amount);

-- ============================================================
-- 并发冲突
-- ============================================================

-- 同一分区的并发写入可能冲突
-- 不同分区可以并行写入

-- 传统表: INSERT OVERWRITE 是原子操作
INSERT OVERWRITE TABLE orders PARTITION (dt='2024-01-15')
SELECT * FROM staging_orders;

-- ============================================================
-- 乐观锁（应用层）
-- ============================================================

ALTER TABLE orders ADD COLUMNS (version BIGINT);

UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 不支持 SELECT FOR UPDATE / FOR SHARE
-- 2. 不支持 LOCK TABLE
-- 3. 事务表支持 ACID（UPDATE/DELETE/MERGE）
-- 4. 传统表只支持 INSERT OVERWRITE
-- 5. 并发控制通过乐观机制
-- 6. 适合批量处理场景
