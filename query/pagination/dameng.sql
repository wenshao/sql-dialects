-- DamengDB (达梦): 分页
-- Oracle compatible syntax.
--
-- 参考资料:
--   [1] DamengDB SQL Reference
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html
--   [2] DamengDB System Admin Manual
--       https://eco.dameng.com/document/dm/zh-cn/pm/index.html

-- ROWNUM（传统 Oracle 方式）
SELECT * FROM (
    SELECT t.*, ROWNUM AS rn FROM (
        SELECT * FROM users ORDER BY id
    ) t WHERE ROWNUM <= 30
) WHERE rn > 20;

-- SQL 标准语法（推荐）
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- FETCH NEXT
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- 窗口函数
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- TOP（达梦扩展）
SELECT TOP 10 * FROM users ORDER BY id;

-- LIMIT 语法（MySQL 兼容模式下支持）
-- SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 游标分页
SELECT * FROM users WHERE id > 100 ORDER BY id
FETCH FIRST 10 ROWS ONLY;

-- 注意事项：
-- 推荐使用 SQL 标准的 OFFSET/FETCH 语法
-- ROWNUM 是 Oracle 兼容的传统方式
-- 支持 TOP 语法（类似 SQL Server）
-- MySQL 兼容模式下也支持 LIMIT 语法
