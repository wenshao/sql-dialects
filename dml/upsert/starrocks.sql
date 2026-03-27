-- StarRocks: UPSERT
--
-- 参考资料:
--   [1] StarRocks - INSERT
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/loading_unloading/INSERT/
--   [2] StarRocks - Primary Key Table
--       https://docs.starrocks.io/docs/table_design/table_types/primary_key_table/

-- 注意: StarRocks 主键模型表天然支持 UPSERT 语义
-- 其他模型（更新模型）也支持部分 UPSERT 功能

-- === 方式一: INSERT INTO 主键模型表（主键自动去重） ===
-- 主键模型表 INSERT 相同主键的行时自动替换旧行

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

-- === 方式二: INSERT INTO 更新模型表 ===
-- 更新模型表根据 UNIQUE KEY 自动合并
INSERT INTO users (username, email, age)
VALUES ('alice', 'new@example.com', 26);

-- === 方式三: 部分列更新（主键模型表，3.0+） ===
-- 只更新指定列，其他列保持不变
-- 需要建表时设置 partial_update = true

-- Stream Load 方式:
-- curl -H "partial_update:true" -H "columns:id,email" \
--   -T data.csv http://fe_host:8030/api/db/users/_stream_load

-- INSERT 方式（需设置 session 变量）:
-- SET partial_update = true;
-- INSERT INTO users (id, email) VALUES (1, 'new@example.com');

-- === 方式四: 条件更新（主键模型表，2.5+） ===
-- 只在满足条件时才更新（如只更新较新的数据）
-- Stream Load 时指定 merge_condition 列

-- === Stream Load UPSERT（推荐大批量场景） ===
-- curl -H "label:upsert_20240115" -T data.csv \
--   http://fe_host:8030/api/db/users/_stream_load
-- 主键模型表自动实现 UPSERT 语义

-- === 不支持 MERGE 语法 ===
-- StarRocks 目前不支持 SQL 标准的 MERGE 语句
-- 使用主键模型表的 INSERT 替代
