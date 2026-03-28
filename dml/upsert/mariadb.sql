-- MariaDB: UPSERT (INSERT ... ON DUPLICATE KEY UPDATE / REPLACE)
-- 与 MySQL 语法一致, 增加 RETURNING 支持
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - INSERT ON DUPLICATE KEY UPDATE
--       https://mariadb.com/kb/en/insert-on-duplicate-key-update/

-- ============================================================
-- 1. INSERT ... ON DUPLICATE KEY UPDATE
-- ============================================================
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 26)
ON DUPLICATE KEY UPDATE age = VALUES(age), email = VALUES(email);

-- 10.5+: 使用行别名 (类似 MySQL 8.0.19+ 语法)
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 26) AS new_row
ON DUPLICATE KEY UPDATE age = new_row.age, email = new_row.email;

-- ============================================================
-- 2. REPLACE INTO (同 MySQL)
-- ============================================================
REPLACE INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 26);
-- 内部机制: 先 DELETE 冲突行, 再 INSERT (不是原地更新!)
-- 陷阱: AUTO_INCREMENT 会分配新值, 子表外键级联删除会触发

-- ============================================================
-- 3. UPSERT + RETURNING (10.5+) -- MariaDB 独有组合
-- ============================================================
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 26)
ON DUPLICATE KEY UPDATE age = VALUES(age)
RETURNING id, username, age;
-- 同时完成 upsert 和获取结果, 避免 SELECT 回查

-- ============================================================
-- 4. 对比其他数据库的 UPSERT
-- ============================================================
-- MySQL:      INSERT ... ON DUPLICATE KEY UPDATE (同 MariaDB)
-- PostgreSQL: INSERT ... ON CONFLICT DO UPDATE (9.5+, 更灵活: 可指定冲突列)
-- Oracle:     MERGE INTO ... USING ... WHEN MATCHED/NOT MATCHED
-- SQL Server: MERGE (但有已知 Bug, 社区不推荐)
-- SQLite:     INSERT ... ON CONFLICT (3.24+, 类似 PostgreSQL)
-- Firebird:   UPDATE OR INSERT (独有语法)

-- ============================================================
-- 5. 对引擎开发者的启示
-- ============================================================
-- UPSERT 的实现策略:
--   乐观策略: 先 INSERT, 冲突时转为 UPDATE (MySQL/MariaDB 方式)
--   悲观策略: 先检查冲突, 再决定 INSERT 或 UPDATE (MERGE 方式)
--   乐观策略更适合冲突率低的场景 (大部分是 INSERT)
--   悲观策略更适合冲突率高的场景 (大部分是 UPDATE)
