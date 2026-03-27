-- SQL Server: INSERT
--
-- 参考资料:
--   [1] SQL Server T-SQL - INSERT
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/insert-transact-sql
--   [2] SQL Server T-SQL - OUTPUT Clause
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/output-clause-transact-sql

-- ============================================================
-- 1. 基本语法
-- ============================================================

INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 多行 VALUES（2008+, 最多 1000 行/语句）
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob',   'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- 设计分析（对引擎开发者）:
--   1000 行限制是 T-SQL 解析器的硬限制。超过需要分多条语句或用 BULK INSERT。
--   PostgreSQL 无此限制。MySQL 受 max_allowed_packet 限制（通常远大于 1000 行）。
--   对引擎开发者: 批量插入限制应该是可配置的，而非硬编码。

-- 从查询结果插入
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- DEFAULT VALUES: 插入一行，所有列使用默认值
INSERT INTO users DEFAULT VALUES;

-- ============================================================
-- 2. OUTPUT 子句: 获取插入结果（对引擎开发者）
-- ============================================================

-- OUTPUT 返回 inserted 伪表中的值（包括 IDENTITY 生成的 id）
INSERT INTO users (username, email, age)
OUTPUT inserted.id, inserted.username
VALUES ('alice', 'alice@example.com', 25);

-- OUTPUT INTO: 将结果捕获到表变量（可在后续逻辑中使用）
DECLARE @ids TABLE (id BIGINT);
INSERT INTO users (username, email, age)
OUTPUT inserted.id INTO @ids
VALUES ('alice', 'alice@example.com', 25);

-- 批量插入并捕获所有生成的 ID:
DECLARE @new_ids TABLE (id BIGINT, username NVARCHAR(64));
INSERT INTO users (username, email, age)
OUTPUT inserted.id, inserted.username INTO @new_ids
VALUES ('alice', 'alice@example.com', 25),
       ('bob', 'bob@example.com', 30);
SELECT * FROM @new_ids;

-- 设计分析（对引擎开发者）:
--   OUTPUT vs SCOPE_IDENTITY() vs RETURNING:
--
--   SCOPE_IDENTITY(): 只返回最后一行的 IDENTITY 值
--   OUTPUT:           返回所有插入行的所有列（批量安全）
--   PostgreSQL RETURNING: 功能最接近 OUTPUT，但没有 OUTPUT INTO 能力
--
--   OUTPUT 的优势在于 OUTPUT INTO——可以把生成的 ID 直接捕获到表变量中，
--   然后用于后续的关联插入（如先插入 orders，再用生成的 order_id 插入 order_items）。
--   这解决了一个核心问题: 批量插入时获取所有生成 ID 的原子性。

-- ============================================================
-- 3. 获取自增 ID 的三种方式
-- ============================================================

INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');

SELECT SCOPE_IDENTITY();         -- 当前作用域、当前会话（推荐）
SELECT @@IDENTITY;               -- 当前会话（危险: 触发器中的 INSERT 会覆盖）
SELECT IDENT_CURRENT('users');   -- 指定表的最后值（危险: 跨会话）

-- 横向对比:
--   MySQL:      LAST_INSERT_ID()（会话级，不受触发器影响）
--   PostgreSQL: INSERT ... RETURNING id（最安全，无需额外查询）
--   Oracle:     INSERT ... RETURNING id INTO :var（PL/SQL 中使用）
--
-- 对引擎开发者的启示:
--   最佳实践是推荐 OUTPUT/RETURNING 而非 SCOPE_IDENTITY()。
--   OUTPUT 在批量插入时也能工作，SCOPE_IDENTITY() 只返回最后一行。

-- ============================================================
-- 4. IDENTITY_INSERT: 手动指定自增值
-- ============================================================

SET IDENTITY_INSERT users ON;
INSERT INTO users (id, username, email) VALUES (100, 'alice', 'alice@example.com');
SET IDENTITY_INSERT users OFF;

-- 关键限制: 同一时刻整个会话只能有一个表的 IDENTITY_INSERT 为 ON
-- 典型场景: 数据迁移、恢复特定 ID 的记录
--
-- 横向对比:
--   MySQL:      直接插入 AUTO_INCREMENT 列即可（不需要特殊开关）
--   PostgreSQL: 直接指定即可（但 GENERATED ALWAYS 需要 OVERRIDING SYSTEM VALUE）
--
-- 对引擎开发者的启示:
--   IDENTITY_INSERT 的设计理念是"默认保护"——防止用户误操作覆盖自增值。
--   MySQL 的"自由插入"更方便但容易出错。折中方案: 默认允许但可配置禁止。

-- ============================================================
-- 5. SELECT INTO: 创建新表并插入（T-SQL 特色语法）
-- ============================================================

SELECT username, email, age
INTO users_backup
FROM users
WHERE age > 60;

-- SELECT INTO 的特点:
--   (1) 创建新表（如果已存在则报错，不是 INSERT INTO）
--   (2) 复制列定义但不复制约束、索引、触发器
--   (3) 在简单恢复模式下是最小日志操作（非常快）
--   (4) 常用于创建临时表: SELECT ... INTO #temp FROM ...
--
-- 横向对比:
--   PostgreSQL: CREATE TABLE t AS SELECT ...（CTAS 语法）
--   MySQL:      CREATE TABLE t AS SELECT ...
--   Oracle:     CREATE TABLE t AS SELECT ...
--   SQL Server 是唯一使用 SELECT INTO 而非 CREATE TABLE AS SELECT 的主流数据库

-- ============================================================
-- 6. TOP + INSERT（限制插入行数）
-- ============================================================

INSERT TOP (10) INTO users_archive (username, email)
SELECT username, email FROM users ORDER BY created_at;

-- 注意: INSERT TOP 不保证按 ORDER BY 顺序选择行
-- 如需精确控制，应用子查询:
INSERT INTO users_archive (username, email)
SELECT TOP (10) username, email FROM users ORDER BY created_at;

-- ============================================================
-- 7. BULK INSERT: 高性能批量导入
-- ============================================================

BULK INSERT users FROM 'C:\data\users.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2,          -- 跳过表头
    TABLOCK,               -- 表级锁（提升并发写入性能）
    BATCHSIZE = 10000      -- 每批提交行数
);

-- 对引擎开发者的启示:
--   BULK INSERT 通过最小日志记录实现高性能（跳过逐行 WAL 写入）。
--   这需要引擎支持"最小日志"模式——只记录页级分配而非行级变更。
--   PostgreSQL 的 COPY 命令是等价功能，MySQL 的 LOAD DATA INFILE 类似。
--   这三者都是各自引擎中批量导入的最快方式。

-- ============================================================
-- 8. 并发插入与锁行为
-- ============================================================

-- SQL Server 的 INSERT 默认在插入行上获取 X 锁（排他锁），
-- 在涉及的索引页上获取 IX 锁（意向排他锁）。
-- 如果并发插入导致同一个索引页上的争用，可能出现页闩（Page Latch）等待。
-- 这在高并发场景下是 IDENTITY 列的经典问题——所有插入都竞争最后一页。
--
-- 解决方案:
--   (1) 使用 GUID 键（随机分布）——但增加索引碎片
--   (2) 使用反向索引或 Hash 分区
--   (3) In-Memory OLTP 表（无闩锁设计）

-- 版本说明:
-- SQL Server 2005+ : OUTPUT 子句
-- SQL Server 2008+ : 多行 VALUES（最多 1000 行）
-- SQL Server 2008+ : MERGE（见 upsert 章节）
-- SQL Server 2014+ : In-Memory OLTP 优化的 INSERT
