-- Apache Doris: UPSERT
--
-- 参考资料:
--   [1] Doris Documentation - Unique Key Model
--       https://doris.apache.org/docs/data-table/data-model

-- ============================================================
-- 1. UPSERT 设计: 数据模型天然支持
-- ============================================================
-- Doris Unique Key 模型天然支持 UPSERT 语义:
--   INSERT 相同 Key 的行 → 自动替换旧行(不报错)。
--   不需要 ON CONFLICT 或 MERGE 语法。
--
-- 对比:
--   StarRocks:  Primary Key / Unique Key 同样天然 UPSERT
--   MySQL:      INSERT ... ON DUPLICATE KEY UPDATE / REPLACE INTO
--   PostgreSQL: INSERT ... ON CONFLICT DO UPDATE (9.5+)
--   BigQuery:   MERGE 语句(SQL 标准)
--   ClickHouse: ReplacingMergeTree(异步去重，不是实时 UPSERT)

-- ============================================================
-- 2. INSERT = UPSERT (Unique Key 模型)
-- ============================================================
INSERT INTO users (id, username, email, age)
VALUES (1, 'alice', 'new@e.com', 26);
-- 如果 id=1 已存在，自动替换

-- 批量 UPSERT
INSERT INTO users (id, username, email, age) VALUES
    (1, 'alice', 'alice_new@e.com', 26),
    (2, 'bob', 'bob_new@e.com', 31);

-- 从查询 UPSERT
INSERT INTO users (id, username, email, age)
SELECT id, username, email, age FROM staging_users;

-- ============================================================
-- 3. Partial Column Update (2.0+)
-- ============================================================
-- 只更新指定列，其他列保持不变:
-- SET enable_unique_key_partial_update = true;
-- INSERT INTO users (id, email) VALUES (1, 'new@e.com');
-- Stream Load: curl -H "partial_columns:true" ...

-- ============================================================
-- 4. Sequence Column (条件 UPSERT)
-- ============================================================
-- 通过 sequence_col 控制"哪条更新":
-- PROPERTIES ("function_column.sequence_col" = "updated_at")
INSERT INTO users (id, username, email, updated_at)
VALUES (1, 'alice', 'new@e.com', '2024-06-01 00:00:00');
-- 仅当 updated_at 大于旧行时才覆盖

-- ============================================================
-- 5. Stream Load UPSERT (推荐大批量)
-- ============================================================
-- curl -u user:passwd -H "label:upsert_20240115" -T data.csv \
--   http://fe:8030/api/db/users/_stream_load
-- Unique Key 模型自动实现 UPSERT 语义

-- ============================================================
-- 6. 不支持标准 MERGE 语法
-- ============================================================
-- Doris 不支持 SQL 标准的 MERGE INTO 语句。
-- 使用 Unique Key 模型的 INSERT 替代。
--
-- 对引擎开发者的启示:
--   "模型级 UPSERT" vs "语句级 UPSERT":
--   Doris/StarRocks: 模型决定语义(INSERT = UPSERT when Unique Key)
--   MySQL/PG:        语句决定语义(ON DUPLICATE KEY / ON CONFLICT)
--   模型级更简单(用户不需要特殊语法)，但不灵活(不能选择 INSERT 还是 UPSERT)。
