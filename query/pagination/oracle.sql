-- Oracle: 分页
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Row Limiting Clause
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/SELECT.html
--   [2] Oracle SQL Language Reference - ROWNUM
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/ROWNUM-Pseudocolumn.html

-- 12c+: OFFSET / FETCH（SQL 标准语法，推荐）
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- 12c+: 取前 N 行
SELECT * FROM users ORDER BY id FETCH FIRST 10 ROWS ONLY;

-- 12c+: PERCENT
SELECT * FROM users ORDER BY id FETCH FIRST 10 PERCENT ROWS ONLY;

-- 12c+: WITH TIES（包含同值行）
SELECT * FROM users ORDER BY age FETCH FIRST 10 ROWS WITH TIES;

-- 传统方式：ROWNUM（所有版本，但注意 ROWNUM 在 ORDER BY 之前分配）
SELECT * FROM (
    SELECT t.*, ROWNUM AS rn FROM (
        SELECT * FROM users ORDER BY id
    ) t
    WHERE ROWNUM <= 30
)
WHERE rn > 20;

-- 传统方式：ROW_NUMBER()（8i+）
SELECT * FROM (
    SELECT u.*, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users u
) t
WHERE rn BETWEEN 21 AND 30;
