-- SQLite: JSON 支持（3.9.0+ 扩展，3.38.0+ 内置）
--
-- 参考资料:
--   [1] SQLite Documentation - JSON Functions
--       https://www.sqlite.org/json1.html
--   [2] SQLite - JSONB (3.45.0+)
--       https://www.sqlite.org/json1.html#jsonb

-- ============================================================
-- 1. JSON 在 SQLite 中的存储模型
-- ============================================================

-- SQLite 没有专用 JSON 类型。JSON 存储为 TEXT:
CREATE TABLE events (
    id   INTEGER PRIMARY KEY AUTOINCREMENT,
    data TEXT    -- 存储 JSON 文本
);

-- 为什么没有专用 JSON 类型?
-- SQLite 只有 5 种存储类，不想增加第 6 种。
-- JSON 函数可以操作 TEXT 类型的 JSON 数据。
-- 3.45.0+ 引入 JSONB（二进制 JSON），但仍然存储为 BLOB，不是新存储类。

INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');
INSERT INTO events (data) VALUES (json_object('name', 'bob', 'age', 30));

-- ============================================================
-- 2. JSON 读取
-- ============================================================

-- json_extract（所有版本）
SELECT json_extract(data, '$.name') FROM events;        -- 'alice'
SELECT json_extract(data, '$.tags[0]') FROM events;     -- 'vip'

-- -> 和 ->> 操作符（3.38.0+，语法糖）
SELECT data->>'$.name' FROM events;                     -- alice（TEXT）
SELECT data->'$.name' FROM events;                      -- "alice"（JSON，带引号）

-- 区别: ->> 返回 TEXT/INTEGER，-> 返回 JSON 值（字符串带引号）

-- 查询条件
SELECT * FROM events WHERE json_extract(data, '$.name') = 'alice';
SELECT * FROM events WHERE data->>'$.age' > 20;

-- ============================================================
-- 3. JSON 修改
-- ============================================================

SELECT json_set(data, '$.age', 26) FROM events;               -- 设置/覆盖
SELECT json_insert(data, '$.email', 'a@e.com') FROM events;   -- 仅在不存在时插入
SELECT json_replace(data, '$.age', 26) FROM events;            -- 仅在存在时替换
SELECT json_remove(data, '$.tags') FROM events;                -- 删除字段

-- json_patch（RFC 7396 合并补丁）
SELECT json_patch(data, '{"age": 26, "email": "a@e.com"}') FROM events;

-- ============================================================
-- 4. JSON 展开与聚合
-- ============================================================

-- json_each: 展开 JSON 对象/数组为行
SELECT key, value, type FROM events, json_each(data);
-- 输出: name/alice/text, age/25/integer, tags/["vip","new"]/array

-- json_tree: 递归展开整个 JSON 树
SELECT fullkey, value, type FROM events, json_tree(data);

-- 数组元素展开
SELECT value FROM events, json_each(json_extract(data, '$.tags'));
-- 输出: vip, new

-- JSON 聚合（3.33.0+）
SELECT json_group_array(username) FROM users;
-- 输出: ["alice", "bob", "charlie"]

SELECT json_group_object(username, age) FROM users;
-- 输出: {"alice": 25, "bob": 30, "charlie": 35}

-- ============================================================
-- 5. JSONB: 二进制 JSON（3.45.0+）
-- ============================================================

-- jsonb() 将 JSON 文本转为二进制格式（BLOB 存储）:
SELECT jsonb('{"name": "alice", "age": 25}');

-- JSONB 的优势:
--   读取速度更快（不需要每次查询解析 JSON 文本）
--   存储空间略大（但避免了重复解析的 CPU 开销）
-- JSONB 函数: jsonb_extract, jsonb_set, jsonb_insert 等
-- 与 json_* 函数用法相同，但输入/输出是 JSONB 格式

-- 对比:
--   PostgreSQL JSONB: 二进制存储 + GIN 索引（最强大的 JSON 实现）
--   MySQL JSON: 二进制存储（内部格式），5.7+ 支持
--   ClickHouse: 无专用 JSON 类型（用 String + JSON 函数，或 Tuple）
--   BigQuery: JSON 类型（内部二进制存储）

-- ============================================================
-- 6. JSON 验证
-- ============================================================

SELECT json_valid('{"a":1}');    -- 1（有效 JSON）
SELECT json_valid('not json');   -- 0（无效 JSON）
SELECT json_type('{"a":1}');     -- 'object'
SELECT json_type('[1,2,3]');     -- 'array'

-- ============================================================
-- 7. 对比与引擎开发者启示
-- ============================================================
-- SQLite JSON 的设计:
--   (1) 存储为 TEXT → 无专用类型但功能完整
--   (2) JSONB（3.45.0+）→ 二进制格式加速读取
--   (3) json_each/json_tree → 强大的展开能力
--   (4) ->/->> 操作符 → 3.38.0+ 的语法简化
--
-- 对引擎开发者的启示:
--   JSON 支持可以分阶段实现:
--   阶段 1: TEXT 存储 + json_extract 函数（最小可用）
--   阶段 2: 二进制存储（JSONB）加速读取
--   阶段 3: 索引支持（如 PostgreSQL 的 GIN 索引）
--   SQLite 用 3 年时间从阶段 1 走到阶段 2，证明了渐进式实现的可行性。
