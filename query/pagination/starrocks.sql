-- StarRocks: 分页
--
-- 参考资料:
--   [1] StarRocks - SELECT (LIMIT)
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/query/SELECT/
--   [2] StarRocks SQL Reference
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/

-- LIMIT / OFFSET
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 简写形式：LIMIT offset, count
SELECT * FROM users ORDER BY id LIMIT 20, 10;

-- 仅 LIMIT
SELECT * FROM users ORDER BY id LIMIT 10;

-- 窗口函数分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 游标分页
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- QUALIFY + ROW_NUMBER 分页（3.2+）
SELECT * FROM users
QUALIFY ROW_NUMBER() OVER (ORDER BY id) BETWEEN 21 AND 30;

-- 注意：StarRocks 兼容 MySQL 协议，分页语法与 MySQL 一致
-- 注意：StarRocks 不支持 FETCH FIRST ... ROWS ONLY 标准语法
-- 注意：StarRocks 优化器会对 ORDER BY + LIMIT 进行 Top-N 优化
-- 注意：大 OFFSET 性能较差，建议使用游标分页
