-- MariaDB: 复合类型 (Array / Map / Struct)
-- MariaDB 不原生支持数组/映射/结构体类型
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - Data Types
--       https://mariadb.com/kb/en/data-types/

-- ============================================================
-- 1. 无原生复合类型
-- ============================================================
-- MariaDB (同 MySQL) 不支持 ARRAY、MAP、STRUCT 类型
-- 对比 PostgreSQL: 原生 ARRAY 类型 (从第一版就有)
-- 对比 ClickHouse: Array(T), Map(K,V), Tuple(T1,T2,...) 全支持

-- ============================================================
-- 2. JSON 模拟
-- ============================================================
-- 使用 JSON 数组模拟 ARRAY
INSERT INTO events (data) VALUES ('{"tags": ["vip", "new", "premium"]}');
SELECT JSON_EXTRACT(data, '$.tags[0]') FROM events;
SELECT JSON_LENGTH(data, '$.tags') FROM events;

-- 使用 JSON 对象模拟 MAP
INSERT INTO events (data) VALUES ('{"config": {"theme": "dark", "lang": "zh"}}');
SELECT JSON_EXTRACT(data, '$.config.theme') FROM events;
SELECT JSON_KEYS(data, '$.config') FROM events;

-- ============================================================
-- 3. SET 类型 (有限的"数组")
-- ============================================================
CREATE TABLE user_roles (
    id    INT PRIMARY KEY,
    roles SET('admin', 'editor', 'viewer', 'moderator')
);
INSERT INTO user_roles VALUES (1, 'admin,editor');
SELECT * FROM user_roles WHERE FIND_IN_SET('admin', roles);
-- SET 限制: 最多 64 个值, 值必须预定义, 不能动态扩展

-- ============================================================
-- 4. 对引擎开发者的启示
-- ============================================================
-- MySQL/MariaDB 不支持复合类型的原因:
--   1. 设计哲学: 关系模型第一范式要求列是原子值
--   2. 索引难题: B-Tree 不能高效索引数组元素
--   3. 存储复杂: 变长嵌套数据增加行格式复杂度
-- PostgreSQL 的 ARRAY 证明复合类型在关系数据库中是可行的
-- 但 PostgreSQL ARRAY 的 GIN 索引维护成本高 (写放大)
-- 务实方案: 用 JSON 模拟复合类型, 用生成列 + 索引加速查询
