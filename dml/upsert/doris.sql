-- Apache Doris: UPSERT
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

-- 注意: Doris Unique Key 模型表天然支持 UPSERT 语义
-- 其他模型也支持部分 UPSERT 功能

-- === 方式一: INSERT INTO Unique Key 模型表（自动去重） ===
-- 相同 Key 的行自动替换旧行

INSERT INTO users (id, username, email, age)
VALUES (1, 'alice', 'new@example.com', 26);
-- 如果 id=1 已存在，自动替换

-- 批量 UPSERT
INSERT INTO users (id, username, email, age) VALUES
    (1, 'alice', 'alice_new@example.com', 26),
    (2, 'bob', 'bob_new@example.com', 31);

-- 从查询 UPSERT
INSERT INTO users (id, username, email, age)
SELECT id, username, email, age FROM staging_users;

-- === 方式二: Merge-on-Write 模型（1.2+，推荐） ===
-- 写入时即合并，读取性能更好
-- 建表时启用：PROPERTIES ("enable_unique_key_merge_on_write" = "true")

INSERT INTO users_mow (id, username, email, age)
VALUES (1, 'alice', 'alice_updated@example.com', 26);

-- === 方式三: 部分列更新（2.0+） ===
-- 只更新指定列，其他列保持不变
-- 需要 Merge-on-Write Unique Key 模型

-- 通过 Session 变量启用
-- SET enable_unique_key_partial_update = true;
-- INSERT INTO users (id, email) VALUES (1, 'new@example.com');

-- Stream Load 方式:
-- curl -H "partial_columns:true" -H "columns:id,email" \
--   -T data.csv http://fe_host:8030/api/db/users/_stream_load

-- === 方式四: 条件更新 ===
-- 通过 Sequence Column 实现（只更新较新的数据）
-- 建表时指定 "function_column.sequence_col" = "updated_at"

-- 新数据 updated_at 更新时才覆盖旧数据
INSERT INTO users (id, username, email, updated_at)
VALUES (1, 'alice', 'new@example.com', '2024-06-01 00:00:00');

-- === Stream Load UPSERT（推荐大批量场景） ===
-- curl -u user:passwd -H "label:upsert_20240115" -T data.csv \
--   http://fe_host:8030/api/db/users/_stream_load
-- Unique Key 模型表自动实现 UPSERT 语义

-- === 不支持标准 MERGE 语法 ===
-- Doris 目前不支持 SQL 标准的 MERGE 语句
-- 使用 Unique Key 模型表的 INSERT 替代
