-- Teradata: UPDATE
--
-- 参考资料:
--   [1] Teradata SQL Reference
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates
--   [2] Teradata Database Documentation
--       https://docs.teradata.com/
--   [3] Teradata Performance Optimization Guide
--       https://docs.teradata.com/r/Teradata-VantageTM-Database-Administration

-- ============================================================
-- 1. 基本 UPDATE
-- ============================================================

-- 单列更新
UPDATE users SET age = 26 WHERE username = 'alice';

-- 多列更新
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- 全表更新
UPDATE users SET status = 1;

-- ============================================================
-- 2. FROM 子句（JOIN UPDATE）
-- ============================================================

-- 使用 FROM 关联其他表
UPDATE users
FROM orders
SET users.status = 1
WHERE users.id = orders.user_id AND orders.amount > 1000;

-- 多表 FROM
UPDATE target_table
FROM source_table
SET target_table.col1 = source_table.col1,
    target_table.col2 = source_table.col2
WHERE target_table.id = source_table.id;

-- FROM + 聚合子查询
UPDATE users
FROM (
    SELECT user_id, COUNT(*) AS cnt
    FROM orders
    GROUP BY user_id
) AS order_counts
SET users.total_orders = order_counts.cnt
WHERE users.id = order_counts.user_id;

-- ============================================================
-- 3. 子查询更新
-- ============================================================

-- 标量子查询
UPDATE users SET age = (SELECT CAST(AVG(age) AS INTEGER) FROM users) WHERE age IS NULL;

-- 相关子查询
UPDATE users
SET total_orders = (
    SELECT COUNT(*) FROM orders WHERE orders.user_id = users.id
);

-- 排名子查询
UPDATE users
SET city_rank = (
    SELECT COUNT(*) + 1
    FROM users u2
    WHERE u2.city = users.city AND u2.age > users.age
);

-- ============================================================
-- 4. CASE 表达式
-- ============================================================

UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- CASE + WHERE 过滤
UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE status
END
WHERE region = 'US';

-- ============================================================
-- 5. VOLATILE 表更新
-- ============================================================

-- VOLATILE 表是 Teradata 的会话级临时表
-- UPDATE VOLATILE 表的操作不需要记录事务日志，性能更好
UPDATE vt_staging SET processed = 1 WHERE id IN (SELECT id FROM processed_ids);

-- 典型 ETL 模式: 先加载到 VOLATILE 表，更新后再写入目标表
-- CREATE VOLATILE TABLE vt_staging AS (
--     SELECT * FROM source WHERE batch_id = 123
-- ) WITH DATA PRIMARY INDEX (id) ON COMMIT PRESERVE ROWS;
-- UPDATE vt_staging SET processed = 0 WHERE processed IS NULL;
-- INSERT INTO target SELECT * FROM vt_staging;

-- ============================================================
-- 6. PRIMARY INDEX 与 UPDATE 性能
-- ============================================================
-- Teradata 的数据分布基于 PRIMARY INDEX (PI):
--
-- (1) WHERE 条件包含 PI 列:
--     UPDATE users SET age = 30 WHERE id = 123;
--     如果 id 是 UPI（Unique Primary Index），操作路由到单个 AMP（最优）
--     如果 id 是 NUPI，操作路由到少量 AMP（仍然高效）
--
-- (2) WHERE 条件不包含 PI 列:
--     UPDATE users SET status = 1 WHERE email = 'alice@example.com';
--     所有 AMP 都需要参与（all-AMP operation），性能差
--
-- (3) 修改 PI 列值:
--     UPDATE users SET id = 456 WHERE id = 123;
--     行需要在 AMP 之间重新分配（row redistribution）
--     这是一个昂贵的操作: 旧行需要删除，新行需要按新 PI 哈希重分布
--     建议: 避免在 UPDATE 中修改 PI 列

-- ============================================================
-- 7. 大规模 UPDATE 的最佳实践
-- ============================================================
--
-- (1) 使用 PI 列作为 WHERE 条件:
--     确保操作路由到最少的 AMP
--
-- (2) 分批处理:
--     大规模 UPDATE 应拆分为小批次
--     使用 PI 范围或 SAMPLE 分批
--
-- (3) 大量 UPDATE 后收集统计信息:
--     -- COLLECT STATISTICS ON users COLUMN (status);
--     -- COLLECT STATISTICS ON users INDEX (id);
--     这对查询优化器生成正确的执行计划至关重要
--
-- (4) 使用 MERGE INTO 替代 UPDATE + INSERT:
--     MERGE INTO users AS t
--     USING staging_users AS s
--     ON t.id = s.id
--     WHEN MATCHED THEN UPDATE SET t.email = s.email, t.age = s.age
--     WHEN NOT MATCHED THEN INSERT (id, email, age) VALUES (s.id, s.email, s.age);
--     MERGE 比分开的 UPDATE + INSERT 更高效

-- ============================================================
-- 8. UPDATE 与 Teradata 并行架构
-- ============================================================
-- Teradata 的 BYNET 互联架构:
--   UPDATE 操作在多个 AMP 上并行执行
--   每个 AMP 负责自己 vdisk 上的数据
--   all-AMP UPDATE: BYNET 广播给所有 AMP
--   single-AMP UPDATE: 只发送给目标 AMP
--
-- 并行度考虑:
--   Teradata 天然并行，不需要手动设置并行度
--   大范围 UPDATE 自动在所有 AMP 上并行执行
--   性能瓶颈通常在 BYNET 带宽和磁盘 I/O

-- ============================================================
-- 9. 横向对比: Teradata vs 其他数据仓库 UPDATE
-- ============================================================
-- Teradata:        支持 UPDATE（行级），但大数据量更新性能一般
--                  UPDATE 后需要 COLLECT STATISTICS 更新统计信息
-- Redshift:        不建议频繁 UPDATE（列存储，UPDATE = DELETE + INSERT）
-- Snowflake:       支持 UPDATE，但推荐使用 MERGE 或 COPY + SWAP
-- BigQuery:        支持 UPDATE，但每天有 DML 配额限制
-- Hive:            支持 ACID UPDATE（需 ORC + 事务表），性能差
-- Spark:           不支持直接 UPDATE（需要 overwrite 或 merge）
--
-- 结论: 数据仓库场景下，应尽量避免频繁 UPDATE
--        使用 INSERT + MERGE 或分区交换（ALTER TABLE SWAP）替代
