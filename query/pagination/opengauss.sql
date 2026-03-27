-- openGauss/GaussDB: 分页
-- PostgreSQL compatible syntax.
--
-- 参考资料:
--   [1] openGauss SQL Reference
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html
--   [2] GaussDB Documentation
--       https://support.huaweicloud.com/gaussdb/index.html

-- LIMIT / OFFSET
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- SQL 标准语法
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;

-- 窗口函数
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 游标分页
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- 注意事项：
-- 语法与 PostgreSQL 完全兼容
-- 支持 SQL 标准的 FETCH FIRST 语法
-- GaussDB 分布式版本中分页需要跨 DN 合并结果
