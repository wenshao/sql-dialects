-- Snowflake: 事务
--
-- 参考资料:
--   [1] Snowflake SQL Reference - BEGIN
--       https://docs.snowflake.com/en/sql-reference/sql/begin
--   [2] Snowflake SQL Reference - Transactions
--       https://docs.snowflake.com/en/sql-reference/transactions

-- ============================================================
-- 基本事务
-- ============================================================

BEGIN TRANSACTION;  -- 或 BEGIN / BEGIN WORK / START TRANSACTION
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;  -- 或 COMMIT WORK

-- 回滚
BEGIN TRANSACTION;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;

-- ============================================================
-- 自动提交
-- ============================================================

-- Snowflake 默认自动提交（AUTOCOMMIT = TRUE）
-- 每条 DML 语句是独立事务

-- 关闭自动提交
ALTER SESSION SET AUTOCOMMIT = FALSE;
-- 之后的 DML 需要手动 COMMIT 或 ROLLBACK

-- 查看当前设置
SHOW PARAMETERS LIKE 'AUTOCOMMIT';

-- ============================================================
-- 保存点（不支持）
-- ============================================================

-- Snowflake 不支持 SAVEPOINT
-- 事务只能整体 COMMIT 或 ROLLBACK

-- ============================================================
-- 隔离级别
-- ============================================================

-- Snowflake 使用 READ COMMITTED 隔离级别
-- 这是唯一支持的隔离级别，不可更改
-- 语句级别的一致性快照（不是事务级别）

-- ============================================================
-- 存储过程中的事务
-- ============================================================

CREATE OR REPLACE PROCEDURE transfer(
    p_from NUMBER, p_to NUMBER, p_amount NUMBER
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    BEGIN TRANSACTION;

    UPDATE accounts SET balance = balance - :p_amount WHERE id = :p_from;
    UPDATE accounts SET balance = balance + :p_amount WHERE id = :p_to;

    COMMIT;
    RETURN 'Success';

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RETURN 'Error: ' || SQLERRM;
END;
$$;

CALL transfer(1, 2, 100.00);

-- ============================================================
-- 锁
-- ============================================================

-- Snowflake 对修改的行自动加锁
-- 不支持 SELECT ... FOR UPDATE
-- 并发修改同一行时，后执行的事务等待或超时

-- 锁超时设置（秒）
ALTER SESSION SET LOCK_TIMEOUT = 600;  -- 10 分钟

-- ============================================================
-- Time Travel（事务恢复）
-- ============================================================

-- 查看历史数据（不是传统事务功能，但用于数据恢复）
SELECT * FROM users AT (TIMESTAMP => '2024-01-15 10:00:00'::TIMESTAMP);
SELECT * FROM users AT (OFFSET => -3600);  -- 1 小时前
SELECT * FROM users BEFORE (STATEMENT => '<query_id>');

-- 恢复被删除/修改的数据
CREATE TABLE users_restored CLONE users
    AT (TIMESTAMP => '2024-01-15 10:00:00'::TIMESTAMP);

-- UNDROP（恢复被删除的表）
DROP TABLE users;
UNDROP TABLE users;

-- Time Travel 保留时间
ALTER TABLE users SET DATA_RETENTION_TIME_IN_DAYS = 90;

-- ============================================================
-- DDL 和事务
-- ============================================================

-- Snowflake 的 DDL 不是事务性的
-- CREATE TABLE, ALTER TABLE 等 DDL 会隐式提交当前事务

-- ============================================================
-- 查看事务信息
-- ============================================================

-- 查看活跃事务
SHOW TRANSACTIONS;

-- 查看锁
SHOW LOCKS;

-- 注意：唯一支持的隔离级别是 READ COMMITTED
-- 注意：不支持 SAVEPOINT
-- 注意：DDL 会隐式提交事务
-- 注意：Time Travel 提供了强大的数据恢复能力（非传统事务）
-- 注意：默认 AUTOCOMMIT = TRUE
