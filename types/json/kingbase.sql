-- KingbaseES (人大金仓): JSON 类型
-- PostgreSQL compatible JSON/JSONB support with Oracle-compatible extensions.
--
-- 参考资料:
--   [1] KingbaseES SQL Reference
--       https://help.kingbase.com.cn/v8/index.html
--   [2] KingbaseES Oracle Compatibility Guide
--       https://help.kingbase.com.cn/v8/development/sql-plsql/oracle-compat.html
--   [3] PostgreSQL Documentation - JSON Types
--       https://www.postgresql.org/docs/current/datatype-json.html

-- ============================================================
-- 1. JSON 类型: JSON vs JSONB
-- ============================================================

-- JSON:  存储原始文本，每次查询时解析
-- JSONB: 二进制格式存储，解析一次后缓存，支持索引（推荐）
CREATE TABLE events (
    id      BIGSERIAL PRIMARY KEY,
    data    JSONB,                           -- 推荐使用 JSONB
    raw     JSON                             -- 需要保留原始格式时使用
);

-- 插入 JSON
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');
INSERT INTO events (data) VALUES ('{"name": "bob", "age": 30, "address": {"city": "Beijing"}}');

-- JSON vs JSONB 的差异:
--   JSON 插入时不验证，JSONB 插入时验证并规范化
--   JSON 保留空格、键顺序、重复键；JSONB 不保留
--   JSONB 支持 GIN 索引，JSON 不支持
--   JSONB 查询性能远优于 JSON（无需重复解析）

-- ============================================================
-- 2. JSON 字段读取
-- ============================================================

-- 基本访问操作符
SELECT data->'name' FROM events;               -- JSONB 值: "alice"（带引号）
SELECT data->>'name' FROM events;              -- TEXT 值: alice（不带引号）
SELECT data->'tags'->0 FROM events;            -- 数组索引: "vip"
SELECT data#>'{tags,0}' FROM events;           -- 路径表达式: "vip"
SELECT data#>>'{tags,0}' FROM events;          -- 路径表达式文本: vip

-- 嵌套访问
SELECT data->'address'->>'city' FROM events;   -- 'Beijing'

-- 类型转换
SELECT (data->>'age')::INT FROM events;        -- 25（整数）
SELECT (data->>'age')::NUMERIC FROM events;    -- 25（数值）

-- ============================================================
-- 3. JSON 查询条件
-- ============================================================

-- 等值比较
SELECT * FROM events WHERE data->>'name' = 'alice';

-- 包含操作符 @>（左侧是否包含右侧的键值对）
SELECT * FROM events WHERE data @> '{"name": "alice"}';

-- 键存在检查
SELECT * FROM events WHERE data ? 'name';                -- 键 'name' 存在
SELECT * FROM events WHERE data ?& ARRAY['name', 'age']; -- 所有键都存在
SELECT * FROM events WHERE data ?| ARRAY['name', 'email']; -- 任一键存在

-- JSONB 路径查询（KingbaseES 继承 PostgreSQL 12+ 的 jsonpath 支持）
SELECT * FROM events WHERE data @? '$.name';
SELECT * FROM events WHERE jsonb_path_exists(data, '$.tags[*] ? (@ == "vip")');
SELECT jsonb_path_query(data, '$.tags[*]') FROM events;

-- ============================================================
-- 4. JSONB 修改操作
-- ============================================================

-- 合并（|| 操作符: 右侧覆盖左侧同名键）
SELECT data || '{"email": "a@e.com"}' FROM events;
SELECT data || '{"age": 26}' FROM events;          -- 更新 age

-- 删除键
SELECT data - 'tags' FROM events;                   -- 删除顶层键
SELECT data - 0 FROM events;                         -- 删除数组第一个元素
SELECT data #- '{tags,0}' FROM events;              -- 按路径删除

-- 设置值
SELECT jsonb_set(data, '{age}', '26') FROM events;               -- 替换已有键
SELECT jsonb_set(data, '{email}', '"a@e.com"') FROM events;      -- 添加新键
SELECT jsonb_insert(data, '{tags,0}', '"new_tag"') FROM events;  -- 插入数组元素

-- ============================================================
-- 5. JSONB 索引
-- ============================================================

-- GIN 索引: 支持 @>、?、?&、?| 操作符
CREATE INDEX idx_data ON events USING gin (data);

-- GIN jsonb_path_ops: 仅支持 @> 操作符，但索引更小、更快
CREATE INDEX idx_data_path ON events USING gin (data jsonb_path_ops);

-- btree 索引: 对 JSONB 值排序
CREATE INDEX idx_data_btree ON events USING btree (data);

-- 表达式索引: 对特定 JSON 字段建索引（最常用）
CREATE INDEX idx_data_name ON events ((data->>'name'));
CREATE INDEX idx_data_age ON events (((data->>'age')::INT));

-- 索引选择建议:
--   精确匹配 (@>):           jsonb_path_ops（最小最快）
--   键存在检查 (?/ ?&/ ?|): 默认 GIN 索引
--   字符串等值/范围:          表达式索引（data->>'key'）

-- ============================================================
-- 6. JSON 聚合
-- ============================================================

-- 聚合为 JSON 数组
SELECT jsonb_agg(username) FROM users;                     -- ["alice", "bob"]
SELECT jsonb_agg(DISTINCT data->>'name') FROM events;

-- 聚合为 JSON 对象
SELECT jsonb_object_agg(username, age) FROM users;         -- {"alice": 25, "bob": 30}

-- 构造 JSON
SELECT jsonb_build_object('name', 'alice', 'age', 25);
SELECT jsonb_build_array(1, 2, 3);
SELECT to_jsonb(ROW('alice', 25));

-- ============================================================
-- 7. JSON 展开
-- ============================================================

-- 展开对象为 key-value 行
SELECT * FROM jsonb_each(data) FROM events;               -- (key, value) 行
SELECT * FROM jsonb_each_text(data) FROM events;           -- (key, value) 文本

-- 展开数组
SELECT jsonb_array_elements(data->'tags') FROM events;     -- 每个元素一行

-- 获取键列表
SELECT jsonb_object_keys(data) FROM events;                -- 每个键一行

-- ============================================================
-- 8. KingbaseES 特有的 JSON 功能
-- ============================================================

-- 8.1 Oracle 兼容的 JSON 函数
-- Oracle 兼容模式下支持 SQL/JSON 标准函数:
--   JSON_VALUE(data, '$.name'):  提取标量值
--   JSON_QUERY(data, '$.tags'):  提取对象/数组
--   JSON_TABLE:                  JSON 转关系表
--   JSON_EXISTS:                 路径存在检查

-- 8.2 JSON_TABLE 示例（Oracle 兼容）
SELECT jt.*
FROM events e,
JSON_TABLE(e.data, '$' COLUMNS (
    name VARCHAR(64) PATH '$.name',
    age  INT PATH '$.age'
)) jt;

-- 8.3 中文 JSON 处理
-- KingbaseES 完整支持 JSON 中的中文字符
INSERT INTO events (data) VALUES ('{"姓名": "张三", "年龄": 30}');
SELECT data->>'姓名' FROM events;                  -- '张三'

-- ============================================================
-- 9. 横向对比: JSON 支持
-- ============================================================

-- JSON/JSONB 支持:
--   KingbaseES: JSON + JSONB，GIN 索引，jsonpath，Oracle 兼容函数
--   PostgreSQL: JSON + JSONB，GIN 索引，jsonpath
--   Oracle:     无原生 JSON 类型（VARCHAR2/CLOB 存储），SQL/JSON 函数
--   MySQL:      原生 JSON 类型，->>/-> 操作符，无 JSONB
--   达梦:       无原生 JSON 类型，SQL/JSON 函数（对齐 Oracle）
--   openGauss:  JSON + JSONB（PostgreSQL 兼容）

-- ============================================================
-- 10. 注意事项与最佳实践
-- ============================================================

-- 1. 推荐使用 JSONB（支持索引和更多操作符）
-- 2. JSONB 插入时不保留格式（空格、键顺序、重复键），如需保留用 JSON
-- 3. 高频查询字段创建表达式索引: CREATE INDEX ON t ((data->>'key'))
-- 4. @> 操作符配合 jsonb_path_ops 索引性能最优
-- 5. Oracle 兼容模式下可使用 JSON_VALUE/JSON_QUERY/JSON_TABLE
-- 6. jsonpath 提供强大的路径查询和过滤能力
-- 7. JSONB 的 || 合并操作是幂等的（适合 upsert 场景）
-- 8. 大 JSON 文档（> 8KB）建议避免频繁更新（TOAST 重写开销）
