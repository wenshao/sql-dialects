-- Apache Impala: 分页
--
-- 参考资料:
--   [1] Impala SQL Reference
--       https://impala.apache.org/docs/build/html/topics/impala_langref.html
--   [2] Impala Built-in Functions
--       https://impala.apache.org/docs/build/html/topics/impala_functions.html

-- LIMIT / OFFSET
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- LIMIT（无 OFFSET 时获取前 N 行）
SELECT * FROM users ORDER BY id LIMIT 10;

-- 窗口函数辅助分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 性能优化：游标分页
-- 已知上一页最后一条 id = 100
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- Top-N 查询
SELECT * FROM users ORDER BY created_at DESC LIMIT 10;

-- 分组后 Top-N
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;

-- 注意：Impala 支持 LIMIT 和 OFFSET
-- 注意：不支持 FETCH FIRST / FETCH NEXT 语法
-- 注意：大 OFFSET 值会导致性能问题
-- 注意：推荐使用游标分页（基于上一页最后一条记录的排序值）
