-- Apache Impala: 事务
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- Impala 对事务的支持非常有限
-- HDFS 表不支持传统事务，Kudu 表支持部分事务

-- ============================================================
-- Kudu 表的事务支持
-- ============================================================

-- Kudu 提供行级 ACID（单行操作）
-- 单行 INSERT/UPDATE/DELETE 是原子的

INSERT INTO users_kudu VALUES (1, 'alice', 'alice@example.com', 25);
UPDATE users_kudu SET age = 26 WHERE id = 1;
DELETE FROM users_kudu WHERE id = 1;

-- 批量操作（同一语句内的所有行是原子的）
INSERT INTO users_kudu VALUES
    (1, 'alice', 'alice@example.com', 25),
    (2, 'bob', 'bob@example.com', 30);
-- 全部成功或全部失败

-- ============================================================
-- HDFS 表的一致性
-- ============================================================

-- INSERT 是原子的（文件级别）
-- INSERT 成功：新文件可见
-- INSERT 失败：不产生部分文件
INSERT INTO users
SELECT * FROM staging_users;

-- INSERT OVERWRITE 是原子的（分区级别）
INSERT OVERWRITE orders PARTITION (year=2024, month=1)
SELECT id, user_id, amount FROM staging_orders;

-- ============================================================
-- 没有 BEGIN/COMMIT/ROLLBACK
-- ============================================================

-- Impala 不支持多语句事务
-- 每个 SQL 语句是一个独立的操作

-- ============================================================
-- 并发控制
-- ============================================================

-- HDFS 表没有行级锁
-- 并发写入同一分区可能产生问题
-- 建议使用分区级别的写入隔离

-- Kudu 表支持乐观并发控制
-- 并发更新同一行可能冲突，需要重试

-- ============================================================
-- 替代方案
-- ============================================================

-- 方案一：分区级别原子操作
-- 使用 INSERT OVERWRITE 替代 UPDATE/DELETE
-- 每次写入整个分区保证一致性

-- 方案二：通过命名约定实现版本控制
-- orders_v1, orders_v2, orders_current（视图指向最新版本）

-- 方案三：使用 HDFS 的文件原子性
-- 通过临时目录 + 重命名实现原子替换

-- 方案四：使用 Kudu 表
-- 需要事务保证的数据放在 Kudu 表中

-- ============================================================
-- 查询快照
-- ============================================================

-- Impala 查询读取查询开始时的文件快照
-- 查询执行期间新增的文件不影响当前查询结果

-- 注意：Impala 不支持多语句事务（BEGIN/COMMIT/ROLLBACK）
-- 注意：每个 SQL 语句是独立的操作
-- 注意：Kudu 表支持行级 ACID（单行）
-- 注意：HDFS 表的原子性在文件/分区级别
-- 注意：不支持 SAVEPOINT
-- 注意：不支持隔离级别设置
