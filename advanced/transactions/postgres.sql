-- PostgreSQL: 事务（Transaction）
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Transactions
--       https://www.postgresql.org/docs/current/tutorial-transactions.html
--   [2] PostgreSQL Documentation - Transaction Isolation
--       https://www.postgresql.org/docs/current/transaction-iso.html
--   [3] PostgreSQL Documentation - Explicit Locking
--       https://www.postgresql.org/docs/current/explicit-locking.html
--   [4] PostgreSQL Documentation - Two-Phase Transactions
--       https://www.postgresql.org/docs/current/sql-prepare-transaction.html

-- ============================================================
-- 基本事务
-- ============================================================
BEGIN;  -- 或 START TRANSACTION，两者完全等价
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;  -- 或 END

-- 回滚
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;  -- 所有修改撤销

-- PostgreSQL 的一个重要特性: DDL 也是事务性的！
BEGIN;
CREATE TABLE temp_data (id INT);
INSERT INTO temp_data VALUES (1), (2), (3);
-- 如果后续操作失败:
ROLLBACK;  -- CREATE TABLE 也被撤销！temp_data 不存在
-- 这是 PostgreSQL 相对 MySQL 的重大优势（MySQL 的 DDL 隐式 COMMIT，无法回滚）

-- ============================================================
-- 隔离级别详解
-- ============================================================
-- PostgreSQL 支持四个隔离级别，但实际只有三种行为:
BEGIN TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;   -- 实际行为等同 READ COMMITTED（不允许脏读）
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;     -- 默认级别
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;    -- 快照隔离
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;       -- SSI（见下文详解）

-- READ COMMITTED（默认）:
--   每条 SQL 语句看到的是该语句开始时已提交的数据
--   同一事务内两次 SELECT 可能看到不同结果（如果中间有其他事务提交）
--   适用: 大多数 OLTP 场景，简单且性能好

-- REPEATABLE READ:
--   整个事务看到的是事务开始时的快照（Snapshot Isolation）
--   同一事务内多次 SELECT 结果一致（快照不变）
--   如果尝试修改被其他事务已修改并提交的行 → 报错（serialization failure）
--   需要应用层重试逻辑！
--   注意: PostgreSQL 的 REPEATABLE READ 不会出现幻读（与 SQL 标准不同）

-- SERIALIZABLE（SSI，9.1+）:
--   见下文专门章节

-- 设置会话默认隔离级别:
SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SET default_transaction_isolation = 'serializable';
SHOW transaction_isolation;

-- ============================================================
-- SSI: 可串行化快照隔离（Serializable Snapshot Isolation）
-- ============================================================
-- PostgreSQL 的 SERIALIZABLE 不是传统的锁定式串行化（如 MySQL/SQL Server）
-- 而是 SSI——基于快照隔离 + 冲突检测的乐观方式（9.1+ 引入）
--
-- 传统锁定式串行化:
--   读加共享锁，写加排他锁，按顺序执行
--   优点: 简单，不会有串行化失败
--   缺点: 性能差，死锁多，读写互相阻塞
--
-- PostgreSQL SSI:
--   基于快照隔离（和 REPEATABLE READ 一样的快照），额外检测"危险结构"
--   读不阻塞写，写不阻塞读（和低隔离级别一样高效）
--   如果检测到可能导致不可串行化的读写依赖 → 中止一个事务
--   优点: 高并发，读写不互相阻塞
--   缺点: 需要应用层重试逻辑（事务可能被中止）
--
-- SSI 的实际影响:
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- 如果出现 serialization failure:
-- ERROR: could not serialize access due to read/write dependencies among transactions
-- 应用层处理:
-- try {
--     BEGIN SERIALIZABLE;
--     ... SQL ...
--     COMMIT;
-- } catch (serialization_failure) {
--     ROLLBACK;
--     retry;  -- 重新执行整个事务！
-- }
--
-- 性能建议:
--   SSI 会跟踪读写依赖，增加内存开销
--   短事务比长事务好（减少冲突窗口）
--   只读事务声明 READ ONLY 可以减少跟踪开销
COMMIT;

-- ============================================================
-- DEFERRABLE 事务（9.1+）
-- ============================================================
-- 只对 SERIALIZABLE + READ ONLY 的事务有意义
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE READ ONLY DEFERRABLE;
-- 行为:
--   事务开始后可能会"等待"一段时间，直到获得一个不会被中止的快照
--   一旦开始执行，保证不会因为串行化冲突而失败
--   适用: 长时间运行的只读报表查询（不想被 serialization failure 中断）
--
-- 不加 DEFERRABLE 的 SERIALIZABLE READ ONLY:
--   立即开始执行，但如果检测到冲突可能被中止
--
-- 总结: DEFERRABLE = "我宁可等一会儿开始，也不想中途被中止"
-- 非 READ ONLY 事务: DEFERRABLE 没有任何效果（静默忽略）
COMMIT;

-- ============================================================
-- SAVEPOINT（保存点 / 子事务）
-- ============================================================
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;

SAVEPOINT sp1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
-- 只回滚到 sp1，前面的 UPDATE 保留
ROLLBACK TO SAVEPOINT sp1;

SAVEPOINT sp2;
UPDATE accounts SET balance = balance + 100 WHERE id = 3;
RELEASE SAVEPOINT sp2;  -- 释放保存点（确认子事务成功）

COMMIT;

-- SAVEPOINT 的性能陷阱:
--   每个 SAVEPOINT 创建一个子事务（subtransaction），有开销:
--   1. 子事务需要分配 XID（事务 ID），pg_subtrans 需要记录父子关系
--   2. 大量子事务（如循环中每次迭代一个 SAVEPOINT）会导致:
--      - pg_subtrans 目录膨胀
--      - 快照管理开销增大
--      - MVCC 可见性判断变慢
--   3. 长事务 + 大量子事务 = 性能灾难
--
--   ORM 的隐患: 很多 ORM（如 Django）在事务内捕获数据库错误时自动创建 SAVEPOINT
--   如果在循环中大量使用，可能不知不觉创建了数千个子事务
--
--   建议: 必要时使用，但避免在循环中创建大量 SAVEPOINT
--          如果需要批量操作容错，考虑分批提交而非子事务

-- ============================================================
-- 行级锁（SELECT ... FOR UPDATE/SHARE）
-- ============================================================
-- 四种行级锁（从弱到强）:
SELECT * FROM accounts WHERE id = 1 FOR KEY SHARE;       -- 最弱: 只阻止删除和主键修改
SELECT * FROM accounts WHERE id = 1 FOR SHARE;           -- 阻止修改和删除
SELECT * FROM accounts WHERE id = 1 FOR NO KEY UPDATE;   -- 阻止修改和删除，但允许非键列被其他 FOR KEY SHARE 读
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;          -- 最强: 阻止任何修改、删除和其他锁

-- FOR UPDATE 在实际场景中最常用:
BEGIN;
SELECT balance FROM accounts WHERE id = 1 FOR UPDATE;  -- 锁住这行
-- 其他事务的 SELECT ... FOR UPDATE 会等待
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;

-- NOWAIT: 获取不到锁立即报错（不等待）
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;
-- ERROR: could not obtain lock on row in relation "accounts"

-- SKIP LOCKED（9.5+）: 跳过被锁定的行（队列模式的利器）
SELECT * FROM task_queue
WHERE status = 'pending'
ORDER BY created_at
LIMIT 1
FOR UPDATE SKIP LOCKED;
-- 多个 worker 并发消费队列时，各自获取不同的任务，不阻塞
-- 这是实现轻量级任务队列的经典模式（不需要额外的 MQ）

-- ============================================================
-- Advisory Locks（建议锁）
-- ============================================================
-- 应用层面的锁，不锁任何行或表，纯粹是一个"协调信号"

-- 会话级别（必须手动释放，或会话结束自动释放）:
SELECT pg_advisory_lock(12345);            -- 阻塞等待
SELECT pg_try_advisory_lock(12345);        -- 非阻塞，返回 true/false
SELECT pg_advisory_unlock(12345);          -- 手动释放

-- 事务级别（事务结束自动释放，推荐）:
SELECT pg_advisory_xact_lock(12345);       -- 事务结束时自动释放
SELECT pg_try_advisory_xact_lock(12345);

-- 双参数形式（两个 INT 组合成一个锁 ID）:
SELECT pg_advisory_lock(classid, objid);   -- 方便按"类型+ID"组织锁

-- 实际模式:
-- 1. 防止重复执行（幂等操作）:
--    SELECT pg_try_advisory_xact_lock(hashtext('send_daily_report'));
--    -- 返回 true 则执行，false 则说明已有其他进程在执行

-- 2. 用户级别锁（防止同一用户并发操作）:
--    SELECT pg_advisory_xact_lock('users'::regclass::int, user_id);

-- Advisory Lock 反模式:
--   1. 忘记释放会话级锁 → 用事务级（pg_advisory_xact_lock）代替
--   2. lock/unlock 不配对（异常路径没有 unlock）→ 用事务级代替
--   3. 锁 ID 冲突（不同业务用了相同的数字）→ 用 hashtext() 或双参数形式
--   4. 在连接池环境中用会话级锁 → 连接归还后锁未释放，影响其他请求

-- ============================================================
-- 两阶段提交（Two-Phase Commit, PREPARE TRANSACTION）
-- ============================================================
-- 用于分布式事务: 确保多个数据库/系统要么全部提交，要么全部回滚

-- 第一阶段: 准备
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
PREPARE TRANSACTION 'transfer_txn_001';
-- 事务进入"prepared"状态，数据持久化到磁盘
-- 即使数据库崩溃重启，prepared 事务仍然存在

-- 第二阶段: 提交或回滚
COMMIT PREPARED 'transfer_txn_001';    -- 在另一个会话中执行
-- 或
ROLLBACK PREPARED 'transfer_txn_001';

-- 查看 prepared 事务:
SELECT * FROM pg_prepared_xacts;

-- 注意事项:
--   1. 需要设置 max_prepared_transactions > 0（默认为 0，即禁用）
--   2. prepared 事务会持有锁，直到 COMMIT/ROLLBACK PREPARED
--   3. 如果忘记处理 prepared 事务，会阻止 VACUUM 和导致表膨胀
--   4. 主要用于: XA 事务、分布式数据库中间件（如 Citus）
--   5. 大多数应用不需要直接使用，由中间件管理

-- ============================================================
-- 监控事务（pg_stat_activity）
-- ============================================================
-- 查看当前活跃事务:
SELECT pid, state, xact_start, query_start,
       now() - xact_start AS xact_duration,
       now() - query_start AS query_duration,
       wait_event_type, wait_event,
       query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY xact_start;

-- 查找长事务（超过 5 分钟的事务）:
SELECT pid, usename, state, xact_start,
       now() - xact_start AS duration,
       query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND now() - xact_start > INTERVAL '5 minutes'
ORDER BY xact_start;

-- 查找阻塞关系（谁阻塞了谁）:
SELECT blocked.pid AS blocked_pid,
       blocked.query AS blocked_query,
       blocking.pid AS blocking_pid,
       blocking.query AS blocking_query
FROM pg_stat_activity AS blocked
JOIN pg_locks AS bl ON bl.pid = blocked.pid
JOIN pg_locks AS kl ON kl.locktype = bl.locktype
    AND kl.database IS NOT DISTINCT FROM bl.database
    AND kl.relation IS NOT DISTINCT FROM bl.relation
    AND kl.page IS NOT DISTINCT FROM bl.page
    AND kl.tuple IS NOT DISTINCT FROM bl.tuple
    AND kl.transactionid IS NOT DISTINCT FROM bl.transactionid
    AND kl.classid IS NOT DISTINCT FROM bl.classid
    AND kl.objid IS NOT DISTINCT FROM bl.objid
    AND kl.objsubid IS NOT DISTINCT FROM bl.objsubid
    AND kl.pid != bl.pid
JOIN pg_stat_activity AS blocking ON blocking.pid = kl.pid
WHERE NOT bl.granted AND kl.granted;

-- 终止事务（最后手段）:
-- SELECT pg_cancel_backend(pid);       -- 取消当前查询（温和）
-- SELECT pg_terminate_backend(pid);    -- 终止连接（强制）

-- ============================================================
-- 只读事务与只读副本
-- ============================================================
BEGIN TRANSACTION READ ONLY;
-- 只能执行 SELECT 语句，不能 INSERT/UPDATE/DELETE
-- 不能执行 DDL（CREATE/ALTER/DROP）
-- 优点:
--   1. 明确意图，防止误操作
--   2. 在 SERIALIZABLE 级别可以加 DEFERRABLE（见上文）
--   3. 某些连接池可以将 READ ONLY 事务路由到只读副本
SET TRANSACTION READ ONLY;  -- 也可以在事务开始后设置（第一条语句之前）
COMMIT;

-- ============================================================
-- 实践建议总结
-- ============================================================
--
-- 1. 事务尽量短:
--    长事务阻止 VACUUM 回收死元组，导致表膨胀和性能下降
--    长事务持有锁，增加死锁和阻塞风险
--
-- 2. 隔离级别选择:
--    大多数场景 READ COMMITTED（默认）就够了
--    需要一致性快照读: REPEATABLE READ
--    需要完全正确性（如金融）: SERIALIZABLE + 重试逻辑
--
-- 3. 重试逻辑是必须的:
--    REPEATABLE READ 和 SERIALIZABLE 都可能抛出 serialization_failure
--    应用层必须捕获并重试（SQLSTATE = '40001'）
--    重试整个事务，不只是最后一条语句！
--
-- 4. 避免在事务中做非数据库操作:
--    不要在 BEGIN...COMMIT 之间调用外部 API、发邮件等
--    这会无意义地延长事务持有锁的时间
--
-- 5. 监控长事务:
--    设置 idle_in_transaction_session_timeout 自动终止空闲事务
--    SET idle_in_transaction_session_timeout = '5min';
--
-- 6. DDL 在事务中的威力:
--    数据库迁移（migration）可以在一个事务中执行多个 DDL
--    要么全部成功，要么全部回滚，不会出现半完成状态
--    但注意: ALTER TABLE 会锁表，大表迁移要小心

-- ============================================================
-- 横向对比: PostgreSQL vs 其他方言的事务机制
-- ============================================================

-- 事务语法对比:
--   PostgreSQL: BEGIN / START TRANSACTION ... COMMIT / ROLLBACK
--   MySQL:      START TRANSACTION ... COMMIT / ROLLBACK（BEGIN 也可用但不推荐，与 BEGIN...END 冲突）
--   Oracle:     DML 自动开启事务，必须显式 COMMIT（没有 BEGIN TRANSACTION）
--   SQL Server: BEGIN TRAN ... COMMIT / ROLLBACK（T-SQL 语法）
--   SQLite:     BEGIN ... COMMIT / ROLLBACK（最简单）

-- 默认隔离级别对比:
--   PostgreSQL: READ COMMITTED（MVCC 实现，读不阻塞写）
--   MySQL:      REPEATABLE READ（InnoDB 默认，MVCC + Gap Lock）
--   Oracle:     READ COMMITTED（MVCC，读永远不阻塞写，和 PostgreSQL 类似）
--               Oracle 只支持 READ COMMITTED 和 SERIALIZABLE 两种（没有 REPEATABLE READ）
--   SQL Server: READ COMMITTED（默认用锁！读阻塞写，写阻塞读；开启 RCSI 后才类似 MVCC）
--               SNAPSHOT 隔离 vs PostgreSQL/Oracle MVCC:
--                 SQL Server 需要显式开启 ALLOW_SNAPSHOT_ISOLATION 或 READ_COMMITTED_SNAPSHOT
--                 开启后将行版本存储在 tempdb 中（增加 tempdb 压力和每行 14 字节开销）
--                 PostgreSQL/Oracle 的 MVCC 是内置于存储引擎的，不需要额外配置
--   SQLite:     SERIALIZABLE（单写者模型，WAL 模式下读写不阻塞）

-- SERIALIZABLE 实现对比:
--   PostgreSQL: SSI（可串行化快照隔离，9.1+），乐观方式，读写不阻塞，冲突时中止事务
--   MySQL:      传统锁定方式（Gap Lock + Next-Key Lock），读写互相阻塞，死锁风险高
--   Oracle:     不支持真正的 SERIALIZABLE（实际是 Snapshot Isolation，不检测写偏斜 write skew）
--   SQL Server: 传统锁定方式（范围锁），或 SNAPSHOT（MVCC 但不是真正 SERIALIZABLE）
--               WITH (NOLOCK) 文化: SQL Server 社区广泛使用 NOLOCK 来避免锁阻塞
--               这极其危险 -- 可能读到脏数据、跳过行、重复读取行（页分裂期间）
--               正确替代方案: 开启 RCSI（READ_COMMITTED_SNAPSHOT），读不加锁但数据一致

-- DDL 事务性对比:
--   PostgreSQL: DDL 完全事务性！CREATE/ALTER/DROP TABLE 都可以 ROLLBACK
--   MySQL:      DDL 隐式 COMMIT（事务中执行 CREATE TABLE 会自动提交之前的修改）
--   Oracle:     DDL 隐式 COMMIT（同 MySQL），这是 Oracle 迁移到 PostgreSQL 时的重大行为差异
--   SQL Server: DDL 事务性（同 PostgreSQL，可以回滚）
--   SQLite:     DDL 事务性（同 PostgreSQL）

-- SAVEPOINT 与自治事务对比:
--   PostgreSQL: 完整支持 SAVEPOINT，但子事务有性能开销（pg_subtrans 膨胀）
--   MySQL:      完整支持，开销较小
--   Oracle:     完整支持 SAVEPOINT
--               Oracle 独有: 自治事务（PRAGMA AUTONOMOUS_TRANSACTION）
--               自治事务 = 独立于父事务的子事务，可以独立 COMMIT/ROLLBACK
--               典型用途: 在事务回滚后仍保留审计日志
--               PostgreSQL 没有等价功能（需要用 dblink 或独立连接模拟）
--   SQL Server: SAVE TRANSACTION（语法不同），功能类似
--   SQLite:     完整支持 SAVEPOINT / RELEASE / ROLLBACK TO

-- Oracle Flashback（Oracle 独有特性）:
--   Oracle 可以查询过去某个时间点的数据:
--     SELECT * FROM orders AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '1' HOUR);
--     SELECT * FROM orders AS OF SCN 123456;
--   还支持 Flashback Table（闪回整张表到过去某个时间点）
--   PostgreSQL 没有内置 Flashback，替代方案:
--     - PITR（Point-in-Time Recovery）: 恢复到某个时间点，但需要停机
--     - Temporal Tables（时态表，通过扩展实现）
--     - pg_dirtyread 扩展: 读取已删除但未 VACUUM 的死元组
--   SQL Server 有 Temporal Tables（2016+）实现类似功能（自动记录历史版本）

-- 行级锁对比:
--   PostgreSQL: FOR UPDATE / FOR SHARE / FOR NO KEY UPDATE / FOR KEY SHARE（四级）
--               SKIP LOCKED（9.5+）和 NOWAIT
--   MySQL:      FOR UPDATE / FOR SHARE（8.0+，之前用 LOCK IN SHARE MODE）
--               SKIP LOCKED 和 NOWAIT（8.0+）
--   Oracle:     FOR UPDATE / FOR UPDATE OF column（可以指定列）
--               SKIP LOCKED 和 NOWAIT（最早支持的数据库之一）
--   SQL Server: 通过锁提示实现（语法完全不同于 SQL 标准）:
--               WITH (UPDLOCK) / WITH (XLOCK) / WITH (HOLDLOCK) / WITH (NOLOCK)
--               READPAST（类似 SKIP LOCKED），NOWAIT
--               独有概念: 锁升级（Lock Escalation）
--               当行锁超过约 5000 个时自动升级为表锁，可能导致严重阻塞
--               Oracle 永远不做锁升级（100万行 = 100万个行锁）
--               PostgreSQL 也不做锁升级

-- Advisory Lock 对比:
--   PostgreSQL: pg_advisory_lock()（会话级 + 事务级），应用层分布式锁
--   MySQL:      GET_LOCK() / RELEASE_LOCK()（只有会话级，一次只能持有一个名字的锁，5.7+ 可多个）
--   Oracle:     DBMS_LOCK 包（功能强大但需要权限）
--   SQL Server: sp_getapplock / sp_releaseapplock（应用锁，类似 advisory lock）

-- 两阶段提交对比:
--   PostgreSQL: PREPARE TRANSACTION / COMMIT PREPARED（内置）
--   MySQL:      XA START / XA PREPARE / XA COMMIT（XA 协议）
--   Oracle:     DBMS_XA 包 或 XA 接口
--   SQL Server: MSDTC（分布式事务协调器，操作系统级服务）

-- 错误处理对比:
--   PostgreSQL: 事务中任何错误导致事务进入"aborted"状态，后续语句全部失败，必须 ROLLBACK
--   MySQL:      错误不自动中止事务，可以继续执行其他语句（可能导致部分提交）
--   Oracle:     错误不自动中止事务（同 MySQL）
--               Oracle 的 '' = NULL 在事务中的影响:
--               WHERE column = '' 永远不返回行（因为 '' 被视为 NULL，NULL = NULL 为 UNKNOWN）
--               迁移到 PostgreSQL 时必须将 '' 检查改为 IS NULL 或保持 = '' 语义
--   SQL Server: 取决于 XACT_ABORT 设置（ON=自动回滚，OFF=可继续，默认 OFF）
--               最佳实践: 始终 SET XACT_ABORT ON + TRY/CATCH 组合使用

-- 数值类型在事务中的影响（金融计算场景）:
--   PostgreSQL: NUMERIC(p,s) 精确十进制，还有 INTEGER/BIGINT/REAL/DOUBLE PRECISION
--   Oracle:     NUMBER(p,s) 是唯一的数值类型，涵盖整数和浮点数
--               NUMBER vs NUMERIC: 语义类似，但 NUMBER 是 Oracle 独有类型名
--               NUMBER 无参数时可存储任意精度数值（PostgreSQL 的 NUMERIC 也可以）
--               迁移时: NUMBER(10,0) -> BIGINT, NUMBER(10,2) -> NUMERIC(10,2)
--   SQL Server: INT/BIGINT/DECIMAL(p,s)/MONEY
--               MONEY 类型只有 4 位小数精度，不推荐用于需要灵活精度的场景
--   MySQL:      INT/BIGINT/DECIMAL(p,s)，与 PostgreSQL 最接近
