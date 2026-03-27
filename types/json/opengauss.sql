-- openGauss/GaussDB: JSON 类型
-- PostgreSQL compatible JSON/JSONB support with Oracle-compatible extensions.
--
-- 参考资料:
--   [1] openGauss SQL Reference - JSON Types
--       https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html
--   [2] GaussDB Documentation
--       https://support.huaweicloud.com/gaussdb/index.html
--   [3] PostgreSQL Documentation - JSON Types
--       https://www.postgresql.org/docs/current/datatype-json.html

-- ============================================================
-- 1. JSON 类型: JSON vs JSONB
-- ============================================================

-- JSON:  存储原始文本，每次查询时解析，保留格式信息
-- JSONB: 二进制格式存储，插入时验证并解析，支持索引（推荐）
CREATE TABLE events (
    id   BIGSERIAL PRIMARY KEY,
    data JSONB                               -- 推荐使用 JSONB
);

-- 插入 JSON
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');
INSERT INTO events (data) VALUES ('{"name": "bob", "age": 30, "address": {"city": "Beijing"}}');

-- JSON vs JSONB 的关键差异:
--   JSON 插入时不验证格式（查询时才解析）
--   JSONB 插入时验证并转换为二进制格式
--   JSON 保留空格、键顺序、重复键；JSONB 不保留
--   JSONB 支持 GIN 索引和丰富的操作符
--   JSONB 查询性能显著优于 JSON

-- ============================================================
-- 2. JSON 字段读取
-- ============================================================

-- 基本访问操作符
SELECT data->'name' FROM events;               -- JSONB 值: "alice"（带引号）
SELECT data->>'name' FROM events;              -- TEXT 值: alice（不带引号）
SELECT data->'tags'->0 FROM events;            -- 数组索引: "vip"
SELECT data#>'{tags,0}' FROM events;           -- 路径表达式: "vip"
SELECT data#>>'{tags,0}' FROM events;          -- 路径文本: vip

-- 嵌套路径访问
SELECT data->'address'->>'city' FROM events;   -- 'Beijing'

-- 类型转换（openGauss 继承 PostgreSQL 的 :: 语法）
SELECT (data->>'age')::INT FROM events;        -- 25（整数）
SELECT (data->>'age')::NUMERIC FROM events;    -- 25（数值）

-- ============================================================
-- 3. JSON 查询条件
-- ============================================================

-- 等值比较
SELECT * FROM events WHERE data->>'name' = 'alice';

-- 包含操作符 @>（左侧是否包含右侧的键值对）
SELECT * FROM events WHERE data @> '{"name": "alice"}';
SELECT * FROM events WHERE data @> '{"tags": ["vip"]}';

-- 键存在检查
SELECT * FROM events WHERE data ? 'name';                 -- 键 'name' 存在
SELECT * FROM events WHERE data ?& ARRAY['name', 'age'];  -- 所有键都存在
SELECT * FROM events WHERE data ?| ARRAY['name', 'email']; -- 任一键存在

-- jsonpath 查询（openGauss 继承 PostgreSQL 12+ 功能）
SELECT * FROM events WHERE jsonb_path_exists(data, '$.tags[*] ? (@ == "vip")');
SELECT jsonb_path_query(data, '$.tags[*]') FROM events;
SELECT jsonb_path_query_array(data, '$.tags[*]') FROM events;

-- ============================================================
-- 4. JSONB 修改操作
-- ============================================================

-- 合并（|| 操作符: 右侧覆盖左侧同名键）
SELECT data || '{"email": "a@e.com"}' FROM events;
SELECT data || '{"age": 26}' FROM events;

-- 删除
SELECT data - 'tags' FROM events;                   -- 删除顶层键
SELECT data - 0 FROM events;                         -- 删除数组第一个元素
SELECT data #- '{tags,0}' FROM events;              -- 按路径删除

-- 设置值
SELECT jsonb_set(data, '{age}', '26') FROM events;
SELECT jsonb_set(data, '{email}', '"a@e.com"') FROM events;
SELECT jsonb_insert(data, '{tags,0}', '"new_tag"') FROM events;

-- ============================================================
-- 5. JSONB 索引
-- ============================================================

-- GIN 默认索引: 支持 @>、?、?&、?| 操作符
CREATE INDEX idx_data ON events USING gin (data);

-- GIN jsonb_path_ops: 仅支持 @> 操作符，索引更小更快
CREATE INDEX idx_data_path ON events USING gin (data jsonb_path_ops);

-- 表达式索引: 对特定 JSON 字段建索引（最常用的优化手段）
CREATE INDEX idx_data_name ON events ((data->>'name'));
CREATE INDEX idx_data_age ON events (((data->>'age')::INT));

-- btree 索引: 用于 JSONB 排序
CREATE INDEX idx_data_btree ON events USING btree (data);

-- 索引选择建议:
--   包含查询 (@>):           jsonb_path_ops（最小最快）
--   键存在检查 (?/?&/?|):    默认 GIN 索引
--   字段等值/范围查询:        表达式索引

-- ============================================================
-- 6. JSON 聚合与构造
-- ============================================================

-- 聚合为 JSON 数组
SELECT jsonb_agg(username) FROM users;
SELECT jsonb_agg(DISTINCT data->>'name') FROM events;

-- 聚合为 JSON 对象
SELECT jsonb_object_agg(username, age) FROM users;

-- 构造 JSON
SELECT jsonb_build_object('name', 'alice', 'age', 25);
SELECT jsonb_build_array(1, 2, 3);
SELECT to_jsonb(ROW('alice', 25));

-- ============================================================
-- 7. JSON 展开
-- ============================================================

-- 展开对象
SELECT * FROM jsonb_each(data) FROM events;            -- (key, value) 行
SELECT * FROM jsonb_each_text(data) FROM events;        -- (key, value) 文本

-- 展开数组
SELECT jsonb_array_elements(data->'tags') FROM events;
SELECT jsonb_array_elements_text(data->'tags') FROM events;

-- 获取键列表
SELECT jsonb_object_keys(data) FROM events;

-- ============================================================
-- 8. openGauss 特有的 JSON 扩展
-- ============================================================

-- 8.1 Oracle 兼容的 JSON 函数
-- openGauss 在 Oracle 兼容模式下支持 SQL/JSON 标准函数:
--   JSON_VALUE(data, '$.name'):  提取标量值
--   JSON_QUERY(data, '$.tags'):  提取对象/数组
--   JSON_TABLE:                  JSON 转关系表
--   JSON_EXISTS:                 路径存在检查

-- 8.2 JSON_TABLE 示例
SELECT jt.*
FROM events e,
JSON_TABLE(e.data, '$' COLUMNS (
    name VARCHAR(64) PATH '$.name',
    age  INT PATH '$.age'
)) jt;

-- 8.3 中文 JSON 处理
-- openGauss 完整支持 JSON 中的中文字符（UTF-8 编码下）
INSERT INTO events (data) VALUES ('{"姓名": "张三", "年龄": 30, "标签": ["管理员", "开发者"]}');
SELECT data->>'姓名' FROM events;                  -- '张三'
SELECT jsonb_array_elements_text(data->'标签') FROM events;

-- 8.4 性能优化
-- openGauss 对 JSONB 的 GIN 索引进行了优化:
--   支持并行 JSONB 索引构建
--   大 JSONB 文档使用 TOAST 压缩存储
--   jsonpath 查询支持 JIT 编译加速

-- ============================================================
-- 9. 横向对比: JSON 支持
-- ============================================================

-- JSON/JSONB 支持:
--   openGauss:   JSON + JSONB，GIN 索引，jsonpath，Oracle 兼容函数
--   PostgreSQL:  JSON + JSONB，GIN 索引，jsonpath
--   KingbaseES:  JSON + JSONB，GIN 索引，jsonpath，Oracle 兼容函数
--   Oracle:      无原生 JSON 类型（VARCHAR2/CLOB），SQL/JSON 函数
--   MySQL:       原生 JSON 类型，$. 路径语法
--   达梦:        无原生 JSON 类型，SQL/JSON 函数
--   TDSQL:       MySQL 兼容 JSON 类型

-- ============================================================
-- 10. 注意事项与最佳实践
-- ============================================================

-- 1. 推荐使用 JSONB（支持索引和更多操作符）
-- 2. 高频查询字段创建表达式索引: CREATE INDEX ON t ((data->>'key'))
-- 3. @> 操作符配合 jsonb_path_ops 索引性能最优
-- 4. Oracle 兼容模式下可使用 JSON_VALUE/JSON_QUERY/JSON_TABLE
-- 5. jsonpath 提供强大的路径查询和过滤能力
-- 6. JSONB 插入时不保留格式信息（空格、键顺序）
-- 7. 大 JSONB 文档更新代价高（TOAST 重写），建议只读场景使用大文档
-- 8. 中文 JSON 字段正常工作，确保数据库编码为 UTF-8
