-- PolarDB: 分页
-- PolarDB-X (distributed, MySQL compatible).
--
-- 参考资料:
--   [1] PolarDB-X SQL Reference
--       https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/
--   [2] PolarDB MySQL Documentation
--       https://help.aliyun.com/zh/polardb/polardb-for-mysql/

-- LIMIT / OFFSET
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 简写形式：LIMIT offset, count
SELECT * FROM users ORDER BY id LIMIT 20, 10;

-- 窗口函数辅助分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 游标分页（避免大 OFFSET 性能问题）
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- 注意事项：
-- 分布式环境下 LIMIT/OFFSET 需要从各分片收集数据后统一排序
-- 大 OFFSET 值性能差（需要跳过所有分片的前 N 行）
-- 游标分页在分布式环境下性能更好（可以利用分区键路由）
-- 如果排序键是分区键，排序可以在各分片内完成
