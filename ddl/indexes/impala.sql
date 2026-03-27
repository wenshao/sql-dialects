-- Apache Impala: 索引
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- Impala 本身不支持传统索引（B-tree / Hash）
-- 通过以下机制替代索引功能

-- ============================================================
-- 分区（最重要的"索引"机制）
-- ============================================================

-- 分区裁剪等效于索引查找
CREATE TABLE orders (
    id         BIGINT,
    user_id    BIGINT,
    amount     DECIMAL(10,2)
)
PARTITIONED BY (year INT, month INT)
STORED AS PARQUET;

-- 查询自动裁剪不相关的分区
SELECT * FROM orders WHERE year = 2024 AND month = 1;

-- ============================================================
-- Parquet 文件的 Min/Max 统计信息
-- ============================================================

-- Parquet 格式自动记录每个 Row Group 中列的最小值/最大值
-- 查询时跳过不匹配的 Row Group（类似 BRIN 索引）
-- 需要数据按查询列排序才能最大化效果

-- 通过 INSERT ... ORDER BY 创建排序好的 Parquet 文件
INSERT INTO orders PARTITION (year=2024, month=1)
SELECT id, user_id, amount FROM staging_orders
ORDER BY user_id;

-- ============================================================
-- Kudu 表的主键索引
-- ============================================================

-- Kudu 表自动为主键创建 B-tree 索引
CREATE TABLE users_kudu (
    id         BIGINT,
    username   STRING,
    email      STRING,
    PRIMARY KEY (id)
)
STORED AS KUDU;

-- 主键查询自动使用索引
SELECT * FROM users_kudu WHERE id = 100;

-- ============================================================
-- COMPUTE STATS（统计信息，优化查询计划）
-- ============================================================

-- 收集全表统计信息
COMPUTE STATS users;

-- 增量统计（仅新分区）
COMPUTE INCREMENTAL STATS orders;

-- 指定分区
COMPUTE INCREMENTAL STATS orders PARTITION (year=2024, month=1);

-- 查看统计信息
SHOW TABLE STATS users;
SHOW COLUMN STATS users;

-- 删除统计信息
DROP STATS users;
DROP INCREMENTAL STATS orders PARTITION (year=2024, month=1);

-- ============================================================
-- 数据文件布局优化
-- ============================================================

-- 手动控制 Parquet 文件大小
SET PARQUET_FILE_SIZE=256mb;

-- 控制 Row Group 大小
SET PARQUET_PAGE_SIZE=1mb;

-- 使用排序创建优化的数据布局
CREATE TABLE orders_sorted
STORED AS PARQUET AS
SELECT * FROM orders ORDER BY user_id, order_date;

-- ============================================================
-- 缓存（HDFS Caching）
-- ============================================================

-- 将热数据缓存到内存
ALTER TABLE users SET CACHED IN 'default_pool';
ALTER TABLE orders PARTITION (year=2024, month=1) SET CACHED IN 'default_pool';

-- 注意：Impala 不支持传统索引
-- 注意：分区是最重要的查询优化手段
-- 注意：定期执行 COMPUTE STATS 保持统计信息最新
-- 注意：Parquet 的 Min/Max 过滤需要数据有序
-- 注意：Kudu 表的主键索引自动维护
