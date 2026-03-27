-- PostgreSQL: 表分区 (Partitioning)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Table Partitioning
--       https://www.postgresql.org/docs/current/ddl-partitioning.html
--   [2] PostgreSQL Source - partbounds.c
--       https://github.com/postgres/postgres/blob/master/src/backend/partitioning/partbounds.c

-- ============================================================
-- 1. 声明式分区 (10+, 推荐)
-- ============================================================

-- RANGE 分区
CREATE TABLE orders (
    id BIGSERIAL, user_id BIGINT, amount NUMERIC(10,2), order_date DATE NOT NULL
) PARTITION BY RANGE (order_date);

CREATE TABLE orders_2023 PARTITION OF orders FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');
CREATE TABLE orders_2024 PARTITION OF orders FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE orders_2025 PARTITION OF orders FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
CREATE TABLE orders_default PARTITION OF orders DEFAULT;   -- 11+ 默认分区

-- LIST 分区
CREATE TABLE users_region (
    id BIGSERIAL, username VARCHAR(100), region VARCHAR(20) NOT NULL
) PARTITION BY LIST (region);
CREATE TABLE users_east PARTITION OF users_region FOR VALUES IN ('Shanghai', 'Hangzhou');
CREATE TABLE users_north PARTITION OF users_region FOR VALUES IN ('Beijing', 'Tianjin');

-- HASH 分区 (11+)
CREATE TABLE sessions (
    id BIGSERIAL, user_id BIGINT NOT NULL, data JSONB
) PARTITION BY HASH (user_id);
CREATE TABLE sessions_0 PARTITION OF sessions FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE sessions_1 PARTITION OF sessions FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE sessions_2 PARTITION OF sessions FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE sessions_3 PARTITION OF sessions FOR VALUES WITH (MODULUS 4, REMAINDER 3);

-- ============================================================
-- 2. 多级分区（子分区）
-- ============================================================

CREATE TABLE sales (
    id BIGSERIAL, sale_date DATE NOT NULL, region VARCHAR(20) NOT NULL, amount NUMERIC
) PARTITION BY RANGE (sale_date);

CREATE TABLE sales_2024 PARTITION OF sales
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01')
    PARTITION BY LIST (region);
CREATE TABLE sales_2024_east PARTITION OF sales_2024 FOR VALUES IN ('East');
CREATE TABLE sales_2024_west PARTITION OF sales_2024 FOR VALUES IN ('West');

-- ============================================================
-- 3. 分区的内部实现
-- ============================================================

-- PostgreSQL 声明式分区的本质:
--   父表是一个"空壳"——没有实际数据存储。
--   每个分区是一个独立的表（有自己的 pg_class 条目、存储、索引）。
--   INSERT 时通过分区路由（partition routing）将数据定向到正确的分区。
--   SELECT 时通过分区裁剪（partition pruning）跳过不相关的分区。
--
-- 分区路由内部:
--   INSERT 时，executor 调用 ExecFindPartition()
--   对 RANGE: 二分查找确定分区
--   对 LIST:  哈希表查找确定分区
--   对 HASH:  计算 hash(partition_key) % modulus 确定分区
--
-- 与 MySQL 的区别:
--   PostgreSQL: 分区是独立表（可以有自己的索引、约束、存储参数）
--   MySQL:      分区是 InnoDB 表的内部概念（用户看到的仍是一张表）

-- ============================================================
-- 4. 分区索引 (11+): 自动传播
-- ============================================================

-- 在父表上创建索引，自动传播到所有现有和未来的分区
CREATE INDEX ON orders (user_id);
CREATE INDEX ON orders (order_date, amount);

-- 分区表的主键和唯一约束必须包含分区键
ALTER TABLE orders ADD PRIMARY KEY (id, order_date);
-- 原因: 唯一性检查是分区级的，不包含分区键则无法保证全局唯一

-- ============================================================
-- 5. 分区管理
-- ============================================================

-- 添加新分区
CREATE TABLE orders_2026 PARTITION OF orders
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');

-- 分离分区（保留数据，变成普通表）
ALTER TABLE orders DETACH PARTITION orders_2023;
-- 14+: CONCURRENTLY（不阻塞查询）
ALTER TABLE orders DETACH PARTITION orders_2023 CONCURRENTLY;

-- 重新附加分区
ALTER TABLE orders ATTACH PARTITION orders_2023
    FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');
-- ATTACH 时 PostgreSQL 会验证数据是否满足分区约束（可能很慢）

-- 删除分区 = 删除表（O(1)，最快的"大批量删除"方式）
DROP TABLE orders_2023;

-- ============================================================
-- 6. 分区裁剪 (Partition Pruning)
-- ============================================================

SET enable_partition_pruning = on;  -- 默认开启

EXPLAIN SELECT * FROM orders WHERE order_date = '2024-06-15';
-- 只扫描 orders_2024（其他分区被裁剪）

-- 运行时分区裁剪 (11+):
--   不仅在计划时裁剪（静态裁剪），还在执行时裁剪（动态裁剪）。
--   场景: WHERE order_date = $1（参数化查询，计划时不知道值）
--   11+ 在执行时根据实际参数值裁剪分区。

-- ============================================================
-- 7. pg_partman: 自动分区管理
-- ============================================================

-- CREATE EXTENSION pg_partman;
-- SELECT partman.create_parent(
--     p_parent_table := 'public.orders',
--     p_control := 'order_date',
--     p_type := 'native',
--     p_interval := 'monthly',
--     p_premake := 3
-- );
-- SELECT partman.run_maintenance();  -- 定期运行

-- ============================================================
-- 8. 横向对比: 分区设计
-- ============================================================

-- 1. 分区类型:
--   PostgreSQL: RANGE / LIST / HASH (10+)，多级分区
--   MySQL:      RANGE / LIST / HASH / KEY，分区键必须在唯一索引中
--   Oracle:     RANGE / LIST / HASH / INTERVAL / REFERENCE（最丰富）
--   SQL Server: PARTITION FUNCTION + PARTITION SCHEME（步骤最多）
--   ClickHouse: PARTITION BY 表达式（最灵活）
--
-- 2. 分区键与唯一约束:
--   PostgreSQL: 唯一约束必须包含分区键（分区级唯一性检查）
--   MySQL:      同样要求（相同限制）
--   Oracle:     无此限制（分区表可以有不含分区键的唯一约束）
--
-- 3. 分区管理:
--   PostgreSQL: ATTACH/DETACH PARTITION（14+ CONCURRENTLY）
--   MySQL:      ALTER TABLE REORGANIZE/EXCHANGE PARTITION
--   Oracle:     ALTER TABLE SPLIT/MERGE/EXCHANGE PARTITION（功能最丰富）
--
-- 4. 自动分区创建:
--   PostgreSQL: 无内置（需要 pg_partman 扩展或触发器）
--   Oracle:     INTERVAL PARTITION（自动创建新分区，最方便）
--   MySQL:      无自动创建

-- ============================================================
-- 9. 对引擎开发者的启示
-- ============================================================

-- (1) "分区是独立表"的设计比"分区是表的内部结构"更灵活:
--     PostgreSQL 的分区可以有不同的存储参数、不同的表空间、
--     独立的 VACUUM 和分析。MySQL 的分区则共享表属性。
--
-- (2) 分区裁剪是分区的核心价值:
--     如果优化器不能裁剪分区，分区反而因为元数据开销降低性能。
--     运行时裁剪 (11+) 对参数化查询至关重要。
--
-- (3) DETACH CONCURRENTLY (14+) 解决了运维痛点:
--     分离旧分区（归档/删除）不应阻塞在线查询。
--     实现: 两阶段提交——先标记分区为"detaching"，
--     等待所有使用该分区的快照结束后，再完成分离。

-- ============================================================
-- 10. 版本演进
-- ============================================================
-- PostgreSQL 10:  声明式分区（RANGE, LIST）
-- PostgreSQL 11:  HASH 分区, DEFAULT 分区, 分区索引自动传播, 运行时裁剪
-- PostgreSQL 12:  支持外键引用分区表, COPY 性能提升
-- PostgreSQL 13:  逻辑复制支持分区表
-- PostgreSQL 14:  DETACH PARTITION CONCURRENTLY
-- PostgreSQL 15:  ALTER TABLE ... MERGE PARTITIONS / SPLIT PARTITION
