-- SQL 标准: 锁机制 (Locking)
--
-- 参考资料:
--   [1] ISO/IEC 9075-2:2023 - SQL/Foundation
--       https://www.iso.org/standard/76583.html
--   [2] SQL:2023 Standard - Transaction isolation levels
--   [3] SQL:2023 Standard - Cursor positioning and FOR UPDATE

-- ============================================================
-- SQL 标准定义的隔离级别
-- ============================================================

-- SQL 标准定义了四个隔离级别:
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;  -- 允许脏读
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;    -- 禁止脏读
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;   -- 禁止不可重复读
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;      -- 完全隔离

-- ============================================================
-- SELECT FOR UPDATE（SQL 标准）
-- ============================================================

-- SQL 标准定义了 FOR UPDATE 子句
SELECT * FROM orders WHERE id = 100 FOR UPDATE;

-- FOR UPDATE OF 指定列
SELECT * FROM orders WHERE id = 100 FOR UPDATE OF status;

-- FOR READ ONLY（显式声明只读）
SELECT * FROM orders WHERE id = 100 FOR READ ONLY;

-- ============================================================
-- 事务管理
-- ============================================================

-- 开始事务
START TRANSACTION;
-- 或
BEGIN;

-- 提交
COMMIT;
-- 或
COMMIT WORK;

-- 回滚
ROLLBACK;
-- 或
ROLLBACK WORK;

-- 保存点
SAVEPOINT sp1;
ROLLBACK TO SAVEPOINT sp1;
RELEASE SAVEPOINT sp1;

-- 事务访问模式
SET TRANSACTION READ ONLY;
SET TRANSACTION READ WRITE;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. SQL 标准定义了隔离级别和 FOR UPDATE 语法
-- 2. 具体的锁实现由各数据库供应商决定
-- 3. LOCK TABLE 不是 SQL 标准的一部分
-- 4. Advisory locks 不是 SQL 标准的一部分
-- 5. NOWAIT / SKIP LOCKED 不在原始 SQL 标准中
-- 6. 各数据库的实际锁行为可能与标准定义有差异
