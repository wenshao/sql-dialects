-- Oracle: DELETE
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - DELETE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/DELETE.html
--   [2] Oracle SQL Language Reference - TRUNCATE TABLE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/TRUNCATE-TABLE.html

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- 关联子查询删除
DELETE FROM users u
WHERE EXISTS (SELECT 1 FROM blacklist b WHERE b.email = u.email);

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- RETURNING（PL/SQL 中使用）
-- DELETE FROM users WHERE username = 'alice' RETURNING id INTO v_id;

-- ROWNUM 限制删除行数
DELETE FROM users WHERE status = 0 AND ROWNUM <= 100;

-- 12c+: FETCH 限制
DELETE FROM (SELECT * FROM users WHERE status = 0 ORDER BY created_at FETCH FIRST 100 ROWS ONLY);

-- 删除所有行
DELETE FROM users;
TRUNCATE TABLE users;                -- 更快，不可回滚，重置高水位线
TRUNCATE TABLE users CASCADE;        -- 12c+: 级联截断

-- 闪回：恢复误删数据（10g+）
-- FLASHBACK TABLE users TO BEFORE DROP;
-- SELECT * FROM users AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '1' HOUR);
