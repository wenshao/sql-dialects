-- PostgreSQL: UPSERT (INSERT ... ON CONFLICT / MERGE)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - INSERT ... ON CONFLICT
--       https://www.postgresql.org/docs/current/sql-insert.html
--   [2] PostgreSQL Documentation - MERGE (15+)
--       https://www.postgresql.org/docs/current/sql-merge.html
--   [3] PostgreSQL Wiki - UPSERT
--       https://wiki.postgresql.org/wiki/UPSERT

-- ============================================================
-- ON CONFLICT 基础（9.5+）
-- ============================================================
-- ON CONFLICT 是 PostgreSQL 的原生 UPSERT，原子性操作，无竞态条件
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username)
DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age;

-- EXCLUDED 是一个特殊表，代表"被拒绝的待插入行"
-- 可以同时引用 EXCLUDED（新值）和目标表（旧值）:
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 30)
ON CONFLICT (username)
DO UPDATE SET
    email = EXCLUDED.email,
    age = GREATEST(users.age, EXCLUDED.age);   -- 只保留更大的 age

-- DO NOTHING: 冲突时忽略，不报错
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username) DO NOTHING;

-- 指定约束名（而非列名）
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT ON CONSTRAINT users_username_key
DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age;
-- 两种写法的区别:
--   ON CONFLICT (column): 根据列推断唯一约束，更灵活
--   ON CONFLICT ON CONSTRAINT name: 精确指定约束，更明确
--   推荐: 大多数情况用列名，多列唯一约束或有歧义时用约束名

-- ============================================================
-- 条件 UPSERT（WHERE 子句）
-- ============================================================
-- DO UPDATE 的 WHERE: 只在满足条件时才执行更新
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username)
DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age
WHERE users.age < EXCLUDED.age;
-- 如果 WHERE 不满足: 不更新，也不报错，该行保持不变
-- 注意: 这不影响 RETURNING（即使没有更新，该行也会出现在 RETURNING 结果中）
-- 实际上不会: 只有真正被 INSERT 或 UPDATE 的行才出现在 RETURNING 中

-- ON CONFLICT 的 WHERE（部分唯一索引匹配）:
-- 见下文"部分唯一索引"章节

-- ============================================================
-- RETURNING 子句 —— UPSERT 的最佳搭档
-- ============================================================
-- 基本 RETURNING
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username)
DO UPDATE SET email = EXCLUDED.email
RETURNING id, username, email;

-- 常见需求: 区分是 INSERT 还是 UPDATE
-- 方法 1: 利用系统列 xmax（经典技巧）
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username)
DO UPDATE SET email = EXCLUDED.email
RETURNING id, username, (xmax = 0) AS inserted;
-- xmax = 0 表示新插入的行（没有被任何事务删除/更新过）
-- xmax != 0 表示被更新的行（ON CONFLICT 触发了 UPDATE）
-- 注意: 这是利用了 MVCC 的实现细节，不是官方 API，但在实践中广泛使用且可靠

-- 方法 2: 利用 updated_at 列
INSERT INTO users (username, email, age, updated_at)
VALUES ('alice', 'alice@example.com', 25, now())
ON CONFLICT (username)
DO UPDATE SET email = EXCLUDED.email, updated_at = now()
RETURNING id, username, (updated_at = created_at) AS is_new;

-- DO NOTHING 的 RETURNING 陷阱:
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON CONFLICT (username) DO NOTHING
RETURNING id;
-- 如果冲突了（DO NOTHING 生效），RETURNING 返回空集！不会返回已存在的行
-- 这是最常见的 UPSERT 错误之一: 期望 DO NOTHING + RETURNING 能返回已有行的 id
-- 解决方案: 用 DO UPDATE SET username = EXCLUDED.username（无效更新）来触发 RETURNING
-- 或用 CTE 组合:
WITH ins AS (
    INSERT INTO users (username, email, age)
    VALUES ('alice', 'alice@example.com', 25)
    ON CONFLICT (username) DO NOTHING
    RETURNING id, username
)
SELECT id, username FROM ins
UNION ALL
SELECT id, username FROM users
WHERE username = 'alice' AND NOT EXISTS (SELECT 1 FROM ins);

-- ============================================================
-- 部分唯一索引与 ON CONFLICT（高级用法）
-- ============================================================
-- 场景: 用户可以有多个邮箱，但只能有一个"主邮箱"
CREATE UNIQUE INDEX idx_user_primary_email
    ON user_emails (user_id) WHERE is_primary = true;
-- 这个索引只对 is_primary = true 的行生效

-- ON CONFLICT 可以匹配这个部分索引:
INSERT INTO user_emails (user_id, email, is_primary)
VALUES (1, 'new@example.com', true)
ON CONFLICT (user_id) WHERE is_primary = true
DO UPDATE SET email = EXCLUDED.email;
-- 只有 is_primary = true 的行才会触发冲突检测
-- 这是 PostgreSQL ON CONFLICT 相对于标准 MERGE 的独特优势

-- ============================================================
-- 批量 UPSERT
-- ============================================================
INSERT INTO users (username, email, age)
VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35)
ON CONFLICT (username)
DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age
RETURNING id, username, (xmax = 0) AS inserted;
-- 批量 UPSERT 是原子操作: 要么全部成功，要么全部回滚

-- 从其他表批量 UPSERT:
INSERT INTO users (username, email, age)
SELECT username, email, age FROM staging_users
ON CONFLICT (username)
DO UPDATE SET
    email = EXCLUDED.email,
    age = EXCLUDED.age;

-- ============================================================
-- MERGE（15+）—— SQL 标准语法
-- ============================================================
MERGE INTO users AS t
USING (VALUES ('alice', 'alice@example.com', 25)) AS s(username, email, age)
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- MERGE 比 ON CONFLICT 更灵活的地方:
--   1. 可以有多个 WHEN MATCHED 分支（带不同条件）
--   2. 可以在匹配时 DELETE
--   3. 不需要唯一索引（ON CONFLICT 必须有唯一约束）
--   4. 17+: MERGE 支持 RETURNING
MERGE INTO users AS t
USING new_users AS s ON t.username = s.username
WHEN MATCHED AND s.age > t.age THEN
    UPDATE SET age = s.age
WHEN MATCHED AND s.is_deleted THEN
    DELETE
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);

-- ON CONFLICT vs MERGE 选择指南:
--   ON CONFLICT 优势:
--     - 真正的原子性，无竞态条件（内部使用 speculative insertion）
--     - 支持部分唯一索引
--     - 支持 DO NOTHING
--     - 9.5+ 就有，兼容性更好
--   MERGE 优势:
--     - SQL 标准语法，跨数据库可移植
--     - 支持多条件分支
--     - 支持匹配时 DELETE
--     - 不要求唯一约束
--   MERGE 劣势:
--     - 15 才支持，较新
--     - 并发安全性不如 ON CONFLICT（可能有竞态，需要额外加锁）
--   结论: 简单 upsert 用 ON CONFLICT，复杂同步逻辑用 MERGE

-- ============================================================
-- 并发安全与常见陷阱
-- ============================================================
--
-- 1. ON CONFLICT 是并发安全的:
--    内部使用 speculative insertion + 冲突检测，不会出现竞态条件
--    即使两个事务同时 INSERT 相同的 username，一个会 INSERT，另一个会 UPDATE
--
-- 2. MERGE 不是完全并发安全的:
--    两个事务同时 MERGE 相同的不存在的行，可能都走 NOT MATCHED 分支
--    导致 unique violation 错误（需要应用层重试或提高隔离级别）
--
-- 3. ON CONFLICT DO NOTHING 不锁定任何行:
--    如果冲突了，不做任何事（不锁行、不返回行）
--    DO UPDATE 会对冲突行加行锁（和普通 UPDATE 一样）
--
-- 4. 死锁风险:
--    批量 UPSERT 时如果多个事务以不同顺序插入相同的冲突行，可能死锁
--    解决: 确保批量 UPSERT 的行按一致的顺序排列（如按主键排序）
--
-- 5. 触发器行为:
--    ON CONFLICT DO UPDATE: INSERT 触发器不触发，UPDATE 触发器触发
--    ON CONFLICT DO NOTHING: 没有触发器触发
--    这可能导致审计日志等基于触发器的逻辑出现遗漏
--
-- 6. 忘记 RETURNING:
--    UPSERT 最常见的错误是忘了加 RETURNING
--    大多数场景都需要知道操作后的 id 或其他生成值，记得加上

-- ============================================================
-- 横向对比: PostgreSQL vs 其他方言的 UPSERT/MERGE
-- ============================================================

-- 1. UPSERT 语法对比:
--   PostgreSQL: INSERT ... ON CONFLICT (col) DO UPDATE SET ...（9.5+）
--               MERGE INTO ... USING ... WHEN MATCHED/NOT MATCHED ...（15+）
--   MySQL:      INSERT ... ON DUPLICATE KEY UPDATE ...（最早支持 UPSERT 的数据库之一）
--               REPLACE INTO ...（删除旧行再插入新行，有严重副作用，见下文）
--   Oracle:     MERGE INTO ... USING ... WHEN MATCHED/NOT MATCHED ...（9i+）
--               Oracle 是最早支持 MERGE 的数据库（9i，约 2001 年）
--               Oracle MERGE 实现成熟稳定，多年来几乎没有并发相关 Bug
--   SQL Server: MERGE INTO ... USING ... WHEN MATCHED/NOT MATCHED ...（2008+）
--   SQLite:     INSERT OR REPLACE（整行替换）/ INSERT ... ON CONFLICT DO UPDATE（3.24+）
--   DB2:        MERGE INTO ... USING ...

-- 2. Oracle MERGE 的先发优势与成熟度:
--   Oracle 9i (2001年) 就引入了 MERGE，是 SQL:2003 标准的主要推动者
--   Oracle MERGE 支持:
--     - WHEN MATCHED THEN UPDATE / DELETE
--     - WHEN NOT MATCHED THEN INSERT
--     - WHERE 子句过滤
--     - 10g+: DELETE WHERE 子句（在 UPDATE 后删除不满足条件的行）
--   Oracle MERGE 在处理 '' 值时的注意事项:
--     Oracle 的 '' = NULL 意味着 MERGE 的 ON 条件中 '' 匹配永远为 UNKNOWN
--     MERGE INTO t USING s ON (t.col = s.col) -- 如果 s.col 是空字符串，永远不匹配
--     需要用 NVL 或 IS NULL 处理: ON (NVL(t.col, 'X') = NVL(s.col, 'X'))
--   Oracle NUMBER 在 MERGE 中的类型转换:
--     NUMBER 是 Oracle 唯一的数值类型，MERGE 中不存在 INT/BIGINT 与 DECIMAL 的类型不匹配问题
--     迁移到 PostgreSQL 时需要确保 INTEGER vs NUMERIC 的对应关系正确

-- 3. SQL Server MERGE 的 Bug 和为什么专家建议避免使用:
--   SQL Server 的 MERGE 有大量已知 Bug（微软 Connect/Feedback 上几十个未修复的报告）:
--     - 并发 MERGE 可能导致死锁或主键违反（即使加了 HOLDLOCK）
--     - 在某些场景下产生错误的查询计划
--     - OUTPUT 子句与 MERGE 组合时可能返回错误结果
--     - 触发器触发顺序可能不正确
--     - 统计信息在 MERGE 后可能不更新
--   Aaron Bertrand、Paul White 等 SQL Server MVP 公开建议:
--     "Don't use MERGE" -- 使用 IF EXISTS ... UPDATE ELSE INSERT 替代
--   SQL Server MERGE 如果非要使用，必须:
--     - SET XACT_ABORT ON（防止部分提交）
--     - 加 WITH (HOLDLOCK) 提示（防止并发问题）
--     - 加 WITH (UPDLOCK, SERIALIZABLE) 提示（最安全但性能差）

-- 4. RETURNING / OUTPUT 对比:
--   PostgreSQL: INSERT ... RETURNING id, col（最自然的语法，所有 DML 都支持）
--   MySQL:      不支持 RETURNING！只能用 LAST_INSERT_ID()（只返回最后一个自增 ID）
--   Oracle:     INSERT ... RETURNING col INTO variable（只在 PL/SQL 中可用，纯 SQL 不支持）
--   SQL Server: OUTPUT inserted.id（语法独特但功能强大，INSERT/UPDATE/DELETE 都支持）
--               OUTPUT 可以同时引用 inserted 和 deleted 伪表（MERGE 中非常有用）
--   SQLite:     RETURNING 子句（3.35+）

-- 5. ON CONFLICT vs MERGE 核心对比:
--   ON CONFLICT（PostgreSQL 特有）:
--     - 真正原子性，无竞态条件（内部使用 speculative insertion）
--     - 必须有唯一约束/索引
--     - 支持部分唯一索引匹配（其他数据库无此能力）
--     - 支持 DO NOTHING（静默跳过冲突）
--   MERGE（SQL 标准）:
--     - Oracle 实现最早最稳定（9i+），PostgreSQL 最新（15+）
--     - 不要求唯一约束
--     - 支持多条件分支（WHEN MATCHED AND ... THEN）
--     - 支持匹配时 DELETE
--     - 并发安全性不如 ON CONFLICT（可能有竞态）

-- 6. 并发安全性对比:
--   PostgreSQL ON CONFLICT: 最安全，两个事务同时 UPSERT 同一行不会报错
--   MySQL ON DUPLICATE KEY: 安全（利用唯一索引锁）
--   Oracle MERGE:           不完全安全，并发 MERGE 可能 unique violation，需要手动加锁
--                           但 Oracle 实现比 SQL Server 稳定得多
--   SQL Server MERGE:       最不安全！有已知并发 Bug，必须加 WITH (HOLDLOCK) 提示
--                           即使加了提示仍可能有问题，专家建议完全避免 MERGE
--   SQLite ON CONFLICT:     安全（单写者模型，天然串行化）

-- 7. 批量 UPSERT 性能对比:
--   PostgreSQL: INSERT ... VALUES (...),(...),... ON CONFLICT DO UPDATE（一条语句搞定）
--   MySQL:      INSERT ... VALUES (...),(...),... ON DUPLICATE KEY UPDATE（同样一条语句）
--   Oracle:     MERGE + 多行子查询（或用 INSERT ALL，但不支持 ON CONFLICT）
--               Oracle 的自治事务（PRAGMA AUTONOMOUS_TRANSACTION）可用于在批量操作中
--               独立记录审计日志，即使主事务回滚，审计记录仍保留（Oracle 独有能力）
--   SQL Server: MERGE + VALUES 表值构造器或临时表（步骤较多，且有上述 Bug 风险）

-- 8. Oracle Flashback 与 UPSERT 的关系:
--   Oracle 独有: 如果 UPSERT 操作出错，可以用 Flashback Query 查看操作前的数据
--     SELECT * FROM users AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '5' MINUTE);
--   这在其他数据库中无法直接实现（PostgreSQL/MySQL/SQL Server 都没有内置 Flashback）
--   SQL Server 2016+ 的 Temporal Tables 可以查询历史数据，但需要预先配置

-- 9. REPLACE 的危险性（MySQL 特有）:
--   MySQL REPLACE INTO: 先 DELETE 再 INSERT，看起来简单但有严重副作用:
--     1. AUTO_INCREMENT 值会变（新行获得新 ID）
--     2. 触发 DELETE + INSERT 触发器（不是 UPDATE 触发器）
--     3. 级联删除的外键会删除子表数据！
--     4. 其他数据库没有 REPLACE INTO，不可移植
--   PostgreSQL 没有 REPLACE，ON CONFLICT DO UPDATE 是更安全的替代

-- 10. WITH (NOLOCK) 与 UPSERT 的交互（SQL Server 特有问题）:
--   SQL Server 中常见的反模式:
--     MERGE INTO t WITH (NOLOCK) ...
--   这是极其危险的: NOLOCK 允许读到脏数据，MERGE 的匹配条件基于脏数据可能导致:
--     - 本应 UPDATE 的行被 INSERT（数据重复）
--     - 本应 INSERT 的行被 UPDATE（数据丢失）
--   正确做法: 开启 RCSI（READ_COMMITTED_SNAPSHOT），不要在 MERGE 中使用 NOLOCK
