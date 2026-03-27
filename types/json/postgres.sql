-- PostgreSQL: JSON 类型
--
-- 参考资料:
--   [1] PostgreSQL Documentation - JSON Types
--       https://www.postgresql.org/docs/current/datatype-json.html
--   [2] PostgreSQL Documentation - JSON Functions
--       https://www.postgresql.org/docs/current/functions-json.html
--   [3] PostgreSQL Source - jsonb.c / jsonb_gin.c
--       https://github.com/postgres/postgres/blob/master/src/backend/utils/adt/jsonb.c

-- ============================================================
-- 1. JSON vs JSONB: 两种存储策略
-- ============================================================

-- JSON:  存储原始文本，每次访问重新解析（9.2+）
-- JSONB: 存储二进制格式，支持索引，查询更快（9.4+，推荐）

CREATE TABLE events (
    id   BIGSERIAL PRIMARY KEY,
    data JSONB                    -- 几乎总是应该用 JSONB
);

-- JSONB 的内部存储格式:
--   二进制树结构，每个键值对存储为: offset + type_tag + data
--   键按排序存储（查找是 O(log n) 二分查找）
--   去除空格和重复键，键顺序可能改变
--
-- JSON vs JSONB 的 trade-off:
--   JSON:  写入快（不解析），保留格式/键顺序/重复键
--   JSONB: 写入慢（需解析为二进制），查询快，支持索引和操作符

-- ============================================================
-- 2. JSON 访问运算符
-- ============================================================

INSERT INTO events (data) VALUES
    ('{"name":"alice","age":25,"tags":["vip","new"]}');

-- -> : 返回 JSON 类型
SELECT data->'name' FROM events;              -- "alice" (JSON)
SELECT data->'tags'->0 FROM events;           -- "vip" (JSON)

-- ->> : 返回 TEXT 类型
SELECT data->>'name' FROM events;             -- alice (TEXT)

-- #> / #>> : 路径访问
SELECT data#>'{tags,0}' FROM events;          -- "vip" (JSON)
SELECT data#>>'{tags,0}' FROM events;         -- vip (TEXT)

-- 14+: 下标访问（更直观）
SELECT data['name'] FROM events;              -- "alice"
SELECT data['tags'][0] FROM events;           -- "vip"

-- 设计分析: -> vs ->>
--   -> 返回 JSON（可以链式调用: data->'a'->'b'）
--   ->> 返回 TEXT（终止链式调用，用于最终取值）
--   这种设计让链式访问既灵活又安全。

-- ============================================================
-- 3. JSONB 包含与存在运算符
-- ============================================================

SELECT * FROM events WHERE data @> '{"name":"alice"}';   -- 包含（JSONB only）
SELECT * FROM events WHERE data ? 'name';                -- 键存在
SELECT * FROM events WHERE data ?& ARRAY['name','age'];  -- 所有键存在
SELECT * FROM events WHERE data ?| ARRAY['name','email'];-- 任一键存在

-- ============================================================
-- 4. JSONB 修改操作 (9.5+)
-- ============================================================

SELECT data || '{"email":"a@e.com"}' FROM events;        -- 合并
SELECT data - 'tags' FROM events;                         -- 删除键
SELECT data #- '{tags,0}' FROM events;                    -- 删除路径
SELECT jsonb_set(data, '{age}', '26') FROM events;       -- 设置值
SELECT jsonb_set(data, '{address,city}', '"NYC"', true) FROM events; -- 创建嵌套路径

-- 设计启示:
--   JSONB 的修改不是原地更新——每次修改都创建新的 JSONB 值。
--   这与 PostgreSQL 的 MVCC（不可变 tuple）一致。
--   对比 MongoDB: 文档可以原地修改（不同的存储哲学）。

-- ============================================================
-- 5. GIN 索引: JSONB 查询性能的关键
-- ============================================================

-- 默认 jsonb_ops（支持 @>, ?, ?&, ?|, @?, @@）
CREATE INDEX idx_data ON events USING GIN (data);

-- jsonb_path_ops（只支持 @>，但索引更小更快）
CREATE INDEX idx_path ON events USING GIN (data jsonb_path_ops);

-- GIN 索引选择:
--   jsonb_ops: 索引每个键和值，支持键存在查询，索引较大
--   jsonb_path_ops: 只索引值路径的哈希，只支持 @> 查询，索引小 2-3x
--   建议: 如果只用 @> 查询，选 jsonb_path_ops

-- 在特定路径上创建 B-tree 索引
CREATE INDEX idx_name ON events ((data->>'name'));
-- 查询: WHERE data->>'name' = 'alice'（走 B-tree 索引）

-- ============================================================
-- 6. JSON Path (12+, SQL/JSON 标准)
-- ============================================================

SELECT jsonb_path_query(data, '$.tags[*]') FROM events;
SELECT * FROM events WHERE jsonb_path_exists(data, '$.tags[*] ? (@ == "vip")');
SELECT jsonb_path_query_first(data, '$.name') FROM events;

-- JSON Path 表达式语法:
--   $         : 根节点
--   .key      : 对象成员
--   [n]       : 数组索引
--   [*]       : 所有数组元素
--   ? (cond)  : 过滤条件
--   @         : 当前节点

-- @@ 和 @? 运算符（12+，索引友好）
SELECT * FROM events WHERE data @? '$.tags[*] ? (@ == "vip")';
-- @? 可以使用 GIN 索引

-- ============================================================
-- 7. JSON 聚合与展开
-- ============================================================

-- 聚合
SELECT jsonb_agg(username) FROM users;                    -- JSON 数组
SELECT jsonb_object_agg(username, age) FROM users;        -- JSON 对象

-- 展开
SELECT e.key, e.value FROM events, jsonb_each(data) e;    -- 键值对
SELECT t.value FROM events, jsonb_array_elements(data->'tags') t;-- 数组元素
SELECT * FROM jsonb_to_record('{"a":1,"b":"text"}'::jsonb)
    AS t(a INT, b TEXT);                                   -- 转记录

-- 17+: JSON_TABLE（SQL 标准，将 JSON 展开为关系表）
-- SELECT * FROM events,
--     JSON_TABLE(data, '$.tags[*]' COLUMNS (tag TEXT PATH '$'));

-- ============================================================
-- 8. 横向对比: JSON 类型能力
-- ============================================================

-- 1. 类型系统:
--   PostgreSQL: JSON + JSONB（两种，JSONB 有索引）
--   MySQL:      JSON（5.7+，二进制存储，类似 JSONB）
--   Oracle:     无专用类型（VARCHAR2 存储，21c+ 有 JSON 类型）
--   SQL Server: 无专用类型（NVARCHAR 存储，用函数解析）
--   MongoDB:    BSON（原生文档存储）
--   ClickHouse: JSON 类型（实验性），通常用 String + 函数
--
-- 2. 索引:
--   PostgreSQL: GIN 索引（@>, ?, 路径查询）
--   MySQL:      Multi-Valued Index（8.0.17+，JSON数组索引）
--   MongoDB:    任意路径索引（最灵活）
--
-- 3. 修改操作:
--   PostgreSQL: jsonb_set / || / - / #-（创建新值，不原地修改）
--   MySQL:      JSON_SET / JSON_REPLACE / JSON_REMOVE（类似）
--   MongoDB:    $set / $unset / $push（原地修改）
--
-- 4. 标准化:
--   PostgreSQL 12+: SQL/JSON 标准 (JSON Path)
--   MySQL 8.0:     部分 SQL/JSON 支持
--   PostgreSQL 17+: JSON_TABLE（SQL 标准关系化）

-- ============================================================
-- 9. 对引擎开发者的启示
-- ============================================================

-- (1) JSONB 的二进制存储设计:
--     键排序+offset寻址使得字段查找是 O(log n)，
--     而 JSON 的文本存储需要每次 O(n) 解析。
--     trade-off: JSONB 写入时需要解析序列化开销。
--
-- (2) GIN 索引 + JSONB 是"在关系数据库中做文档存储"的关键:
--     没有 GIN 索引，JSONB 的 @> 查询只能全表扫描。
--     jsonb_path_ops 通过只索引路径哈希实现了 2-3x 的索引压缩。
--
-- (3) JSON 的不可变修改（copy-on-write）:
--     PostgreSQL 每次 jsonb_set 都创建完整的新 JSONB 值。
--     这与 MVCC 一致但对频繁更新的 JSON 文档有性能影响。
--     对比 MongoDB 的原地修改: 更高效但需要 WiredTiger 的 MVCC 配合。

-- ============================================================
-- 10. 版本演进
-- ============================================================
-- PostgreSQL 9.2:  JSON 类型
-- PostgreSQL 9.4:  JSONB 类型（二进制 JSON，支持索引）
-- PostgreSQL 9.5:  jsonb_set, ||, -, #- 修改操作
-- PostgreSQL 12:   JSON Path（SQL/JSON 标准），@?, @@ 运算符
-- PostgreSQL 14:   JSONB 下标访问 data['key']
-- PostgreSQL 16:   JSON 构造函数 (JSON_ARRAY, JSON_OBJECT)
-- PostgreSQL 17:   JSON_TABLE（SQL 标准关系化）
