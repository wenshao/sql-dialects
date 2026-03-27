-- SQLite: INSERT
--
-- 参考资料:
--   [1] SQLite Documentation - INSERT
--       https://www.sqlite.org/lang_insert.html
--   [2] SQLite Documentation - REPLACE
--       https://www.sqlite.org/lang_replace.html
--   [3] SQLite Internals - B-Tree Insert Algorithm
--       https://www.sqlite.org/btreemodule.html

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- 单行插入
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 多行插入（3.7.11+，2012年）
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- 从查询结果插入
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- 指定默认值
INSERT INTO users DEFAULT VALUES;    -- 所有列使用默认值

-- 获取自增 ID
INSERT INTO users (username, email) VALUES ('alice', 'alice@e.com');
SELECT last_insert_rowid();          -- 返回最后插入的 rowid

-- 3.35.0+: RETURNING（直接返回插入结果）
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
RETURNING id, username;

-- ============================================================
-- 2. 冲突处理: INSERT OR ... 五种策略（对引擎开发者）
-- ============================================================

-- SQLite 提供 5 种冲突处理策略（conflict resolution），这是独特设计:

-- ABORT（默认）: 回滚当前语句，事务继续
INSERT OR ABORT INTO users (username, email) VALUES ('alice', 'a@e.com');

-- ROLLBACK: 回滚整个事务（不仅仅是当前语句）
INSERT OR ROLLBACK INTO users (username, email) VALUES ('alice', 'a@e.com');

-- FAIL: 终止当前语句但保留之前的修改（不回滚已执行的行）
INSERT OR FAIL INTO users (username, email) VALUES ('alice', 'a@e.com');

-- IGNORE: 跳过冲突行，继续处理后续行
INSERT OR IGNORE INTO users (username, email) VALUES ('alice', 'a@e.com');

-- REPLACE: 删除冲突行后插入新行（等于 DELETE + INSERT）
INSERT OR REPLACE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 26);

-- 设计分析:
--   5 种策略反映了 SQLite 对嵌入式场景的深入思考:
--   嵌入式应用不像服务端应用可以"重试"，每次 INSERT 需要明确的冲突语义。
--
--   REPLACE 的陷阱:
--     它先 DELETE 再 INSERT，所以:
--     - rowid 会改变（因为是新行）
--     - 未指定的列会被重置为默认值（不是保留原值!）
--     - 触发 DELETE 触发器 + INSERT 触发器
--   推荐: 使用 ON CONFLICT ... DO UPDATE 替代 REPLACE（3.24.0+）
--
-- 对比:
--   MySQL:      INSERT IGNORE / REPLACE INTO / ON DUPLICATE KEY UPDATE
--   PostgreSQL: ON CONFLICT ... DO NOTHING / DO UPDATE（9.5+）
--   SQL Server: MERGE（最复杂但最灵活）
--   ClickHouse: 无冲突处理（主键不唯一，不存在冲突）
--   BigQuery:   无冲突处理（用 MERGE 替代）

-- ============================================================
-- 3. 单文件写入的性能特征
-- ============================================================

-- 3.1 事务批量 INSERT（性能关键!）
-- SQLite 的每个单独 INSERT 默认是一个独立事务（autocommit）。
-- 在 DELETE 日志模式下，每个事务 = 一次 fsync = 约 10ms。
-- 即: 每秒最多约 100 个 INSERT!
--
-- 解决方案: 显式事务
BEGIN;
INSERT INTO users VALUES (1, 'alice', 'a@e.com', 25);
INSERT INTO users VALUES (2, 'bob', 'b@e.com', 30);
-- ...（数千行）
COMMIT;
-- 批量 INSERT 在事务中: 每秒可达 50,000+ 行

-- 3.2 WAL 模式的影响
-- PRAGMA journal_mode = WAL;
-- WAL 模式下 INSERT 性能更好:
--   (a) 写入追加到 WAL 文件（顺序写入，对 SSD 友好）
--   (b) 读写可以并发（读操作不被 INSERT 阻塞）
--   (c) 但 WAL 文件增长需要定期 checkpoint（WAL → 主数据库文件）

-- 3.3 预编译语句（Prepared Statement）
-- 对于循环 INSERT，使用 prepared statement 避免重复解析 SQL:
-- stmt = db.prepare("INSERT INTO users VALUES (?, ?, ?, ?)");
-- for row in data: stmt.execute(row);
-- 性能提升约 2-5 倍（取决于 SQL 复杂度）

-- ============================================================
-- 4. 动态类型对 INSERT 的影响
-- ============================================================

-- 由于 SQLite 的动态类型系统，INSERT 几乎不做类型检查:
-- INSERT INTO users (age) VALUES ('not a number');    -- 成功!
-- INSERT INTO users (age) VALUES (3.14);              -- 成功!
-- INSERT INTO users (age) VALUES (NULL);              -- 成功!
-- INSERT INTO users (age) VALUES (x'DEADBEEF');       -- 成功!
--
-- 只有 STRICT 模式（3.37.0+）的表会拒绝类型不匹配的值。
-- 这意味着: 应用层的类型验证比数据库层更重要。

-- ============================================================
-- 5. 对比与引擎开发者启示
-- ============================================================
-- SQLite INSERT 的设计特征:
--   (1) 5 种冲突策略 → 精细控制，嵌入式场景实用
--   (2) 单文件 + fsync → 批量 INSERT 必须用事务包裹
--   (3) WAL 模式 → 读写并发的关键
--   (4) RETURNING → 3.35.0 才添加（比 PostgreSQL 晚了 20 年）
--   (5) 动态类型 → INSERT 不做类型检查（STRICT 模式除外）
--
-- 对引擎开发者的启示:
--   嵌入式数据库的 INSERT 性能瓶颈是 fsync，不是解析或索引更新。
--   WAL 模式将顺序写入的优势发挥到极致，是现代嵌入式数据库的标配。
--   冲突处理策略应该在 INSERT 语法中暴露（而非只在 UPSERT 中）。
