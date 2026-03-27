-- ClickHouse: 分页
--
-- 参考资料:
--   [1] ClickHouse SQL Reference - LIMIT
--       https://clickhouse.com/docs/en/sql-reference/statements/select/limit
--   [2] ClickHouse SQL Reference - SELECT
--       https://clickhouse.com/docs/en/sql-reference/statements/select

-- LIMIT（取前 N 行）
SELECT * FROM users ORDER BY id LIMIT 10;

-- LIMIT / OFFSET
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- LIMIT 简写形式：LIMIT offset, count
SELECT * FROM users ORDER BY id LIMIT 20, 10;

-- 窗口函数分页（21.1+）
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 游标分页
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- LIMIT BY（ClickHouse 特有，分组级别的分页）
SELECT * FROM users
ORDER BY city, age DESC
LIMIT 3 BY city;                -- 每个 city 取前 3 条

-- LIMIT BY + OFFSET
SELECT * FROM users
ORDER BY city, age DESC
LIMIT 2, 3 BY city;            -- 每个 city 跳过 2 条取 3 条

-- LIMIT WITH TIES（保留同值行）
SELECT * FROM users ORDER BY age LIMIT 10 WITH TIES;

-- SAMPLE（近似采样，非精确分页）
SELECT * FROM users SAMPLE 0.1;             -- 约 10% 的数据
SELECT * FROM users SAMPLE 10000;           -- 约 10000 行
SELECT * FROM users SAMPLE 1/10 OFFSET 1/2; -- 采样偏移

-- 注意：ClickHouse 不支持 FETCH FIRST ... ROWS ONLY 标准语法
-- 注意：ClickHouse LIMIT BY 是非常实用的分组分页功能
-- 注意：大 OFFSET 性能较差，建议使用游标分页
