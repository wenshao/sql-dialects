-- PostgreSQL: 表分区策略
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Table Partitioning
--       https://www.postgresql.org/docs/current/ddl-partitioning.html
--   [2] PostgreSQL Documentation - Partition Pruning
--       https://www.postgresql.org/docs/current/ddl-partitioning.html#DDL-PARTITION-PRUNING

-- ============================================================
-- 声明式分区（10+，推荐）
-- ============================================================

-- RANGE 分区
CREATE TABLE orders (
    id BIGSERIAL,
    user_id BIGINT,
    amount NUMERIC(10,2),
    order_date DATE NOT NULL
) PARTITION BY RANGE (order_date);

-- 创建分区
CREATE TABLE orders_2023 PARTITION OF orders
    FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');
CREATE TABLE orders_2024 PARTITION OF orders
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE orders_2025 PARTITION OF orders
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

-- 默认分区（11+）
CREATE TABLE orders_default PARTITION OF orders DEFAULT;

-- ============================================================
-- LIST 分区
-- ============================================================

CREATE TABLE users_region (
    id BIGSERIAL,
    username VARCHAR(100),
    region VARCHAR(20) NOT NULL
) PARTITION BY LIST (region);

CREATE TABLE users_east PARTITION OF users_region
    FOR VALUES IN ('Shanghai', 'Hangzhou', 'Nanjing');
CREATE TABLE users_north PARTITION OF users_region
    FOR VALUES IN ('Beijing', 'Tianjin');
CREATE TABLE users_south PARTITION OF users_region
    FOR VALUES IN ('Guangzhou', 'Shenzhen');

-- ============================================================
-- HASH 分区（11+）
-- ============================================================

CREATE TABLE sessions (
    id BIGSERIAL,
    user_id BIGINT NOT NULL,
    data JSONB
) PARTITION BY HASH (user_id);

CREATE TABLE sessions_0 PARTITION OF sessions
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE sessions_1 PARTITION OF sessions
    FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE sessions_2 PARTITION OF sessions
    FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE sessions_3 PARTITION OF sessions
    FOR VALUES WITH (MODULUS 4, REMAINDER 3);

-- ============================================================
-- 多级分区（子分区）
-- ============================================================

CREATE TABLE sales (
    id BIGSERIAL,
    sale_date DATE NOT NULL,
    region VARCHAR(20) NOT NULL,
    amount NUMERIC(10,2)
) PARTITION BY RANGE (sale_date);

CREATE TABLE sales_2024 PARTITION OF sales
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01')
    PARTITION BY LIST (region);

CREATE TABLE sales_2024_east PARTITION OF sales_2024
    FOR VALUES IN ('East');
CREATE TABLE sales_2024_west PARTITION OF sales_2024
    FOR VALUES IN ('West');

-- ============================================================
-- 分区上的索引（11+）
-- ============================================================

-- 在分区表上创建索引（自动传播到所有分区）
CREATE INDEX ON orders (user_id);
CREATE INDEX ON orders (order_date, amount);

-- 分区上的主键和唯一约束必须包含分区键
ALTER TABLE orders ADD PRIMARY KEY (id, order_date);

-- ============================================================
-- 分区管理
-- ============================================================

-- 添加新分区
CREATE TABLE orders_2026 PARTITION OF orders
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');

-- 分离分区（不删除数据）
ALTER TABLE orders DETACH PARTITION orders_2023;
-- 14+: 并发分离（不阻塞查询）
ALTER TABLE orders DETACH PARTITION orders_2023 CONCURRENTLY;

-- 重新附加分区
ALTER TABLE orders ATTACH PARTITION orders_2023
    FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');

-- 删除分区（数据也会删除）
DROP TABLE orders_2023;

-- ============================================================
-- 分区裁剪
-- ============================================================

-- 查看分区裁剪效果
EXPLAIN SELECT * FROM orders WHERE order_date = '2024-06-15';
-- 只扫描 orders_2024

-- 运行时分区裁剪（11+）
SET enable_partition_pruning = on;  -- 默认开启

-- ============================================================
-- pg_partman 扩展（自动分区管理）
-- ============================================================

-- 安装扩展
-- CREATE EXTENSION pg_partman;

-- 创建自动分区管理
-- SELECT partman.create_parent(
--     p_parent_table := 'public.orders',
--     p_control := 'order_date',
--     p_type := 'native',
--     p_interval := 'monthly',
--     p_premake := 3
-- );

-- 自动维护（定期运行）
-- SELECT partman.run_maintenance();

-- ============================================================
-- 继承式分区（旧方式，10 以前）
-- ============================================================

-- 父表
-- CREATE TABLE orders_old (id SERIAL, order_date DATE, amount NUMERIC);
-- 子表
-- CREATE TABLE orders_old_2024 () INHERITS (orders_old);
-- 约束
-- ALTER TABLE orders_old_2024 ADD CHECK (order_date >= '2024-01-01' AND order_date < '2025-01-01');
-- 触发器路由
-- 需要手动创建触发器将数据路由到正确的分区

-- 注意：PostgreSQL 10+ 推荐使用声明式分区
-- 注意：11+ 支持默认分区和 HASH 分区
-- 注意：11+ 分区表上的索引自动传播到子分区
-- 注意：14+ 支持 DETACH PARTITION CONCURRENTLY
-- 注意：分区键必须包含在主键和唯一约束中
-- 注意：pg_partman 扩展可以自动管理分区的创建和维护
