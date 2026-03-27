-- TDSQL: 分页
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

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

-- 游标分页
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- 注意事项：
-- 分布式环境下 LIMIT/OFFSET 需要从各分片收集数据
-- 大 OFFSET 值性能差（需要从所有分片获取 offset+limit 行）
-- 游标分页推荐使用 shardkey 作为排序键
-- 带 shardkey 条件的分页查询只路由到对应分片
