-- MaxCompute: 分页
--
-- 参考资料:
--   [1] MaxCompute SQL - SELECT
--       https://help.aliyun.com/zh/maxcompute/user-guide/select
--   [2] MaxCompute SQL Overview
--       https://help.aliyun.com/zh/maxcompute/user-guide/sql-overview

-- LIMIT（取前 N 行）
SELECT * FROM users ORDER BY id LIMIT 10;

-- LIMIT / OFFSET（MaxCompute 2.0+）
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 窗口函数分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- TOP N（替代 LIMIT 的写法）
SELECT * FROM users ORDER BY id LIMIT 10;

-- 游标分页
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- 注意：MaxCompute 早期版本不支持 OFFSET
-- 注意：MaxCompute 不支持 FETCH FIRST ... ROWS ONLY 标准语法
-- 注意：ORDER BY + LIMIT 可以利用 Top-K 优化
-- 注意：全表 ORDER BY 在大数据量下非常耗资源，建议配合 LIMIT 使用
-- 注意：MaxCompute 分页查询适用于交互式场景（MCQA），离线任务不建议使用
