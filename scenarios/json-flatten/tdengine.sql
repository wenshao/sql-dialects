-- TDengine: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] TDengine Documentation - JSON 数据类型
--       https://docs.tdengine.com/taos-sql/data-type/#json
--   [2] TDengine Documentation - 超级表 (STable)
--       https://docs.tdengine.com/taos-sql/stable/
--   [3] TDengine 3.0 Documentation - JSON 标签
--       https://docs.tdengine.com/3.0/taos-sql/data-type/

-- ============================================================
-- 1. TDengine JSON 支持概述
-- ============================================================

-- TDengine 是专用时序数据库，JSON 支持有以下限制:
--   (a) JSON 类型仅可用于超级表（STable）的标签列（TAG）
--   (b) 数据列不支持 JSON 类型
--   (c) 不支持 JSON 数组展开为多行
--   (d) JSON 查询仅支持基本的键值提取

-- ============================================================
-- 2. 示例数据（时序场景: 传感器 + JSON 标签）
-- ============================================================

-- 创建超级表: JSON 类型作为标签
CREATE STABLE IF NOT EXISTS sensor_data (
    ts             TIMESTAMP,
    temperature    DOUBLE,
    humidity       DOUBLE
) TAGS (
    meta JSON
);

-- 创建子表: 插入时指定 JSON 标签
CREATE TABLE IF NOT EXISTS sensor_1 USING sensor_data
    TAGS ('{"location": "Beijing", "type": "temperature", "floor": 3}');

CREATE TABLE IF NOT EXISTS sensor_2 USING sensor_data
    TAGS ('{"location": "Shanghai", "type": "humidity", "floor": 5}');

CREATE TABLE IF NOT EXISTS sensor_3 USING sensor_data
    TAGS ('{"location": "Beijing", "type": "pressure", "floor": 3, "building": "A"}');

-- 插入时序数据
INSERT INTO sensor_1 VALUES ('2024-01-01 08:00:00', 22.5, 45.0);
INSERT INTO sensor_1 VALUES ('2024-01-01 08:05:00', 23.1, 44.7);
INSERT INTO sensor_2 VALUES ('2024-01-01 08:00:00', 19.8, 62.3);
INSERT INTO sensor_3 VALUES ('2024-01-01 08:00:00', 20.0, 55.0);

-- ============================================================
-- 3. 提取 JSON 标签字段
-- ============================================================

SELECT ts, temperature, humidity,
       meta->'location'     AS location,
       meta->'type'         AS sensor_type,
       meta->'floor'        AS floor_num
FROM   sensor_data
WHERE  ts >= '2024-01-01 00:00:00';

-- 设计分析: meta->'key' 语法提取 JSON 标签值
--   TDengine 的 JSON 标签提取语法与 PostgreSQL 的 -> 运算符类似
--   但返回值为字符串（带引号），如 "Beijing"
--   仅支持单层键提取，不支持嵌套路径如 meta->'a.b'

-- ============================================================
-- 4. JSON 标签过滤查询
-- ============================================================

-- 按位置过滤
SELECT ts, temperature, meta->'location' AS location
FROM   sensor_data
WHERE  meta->'location' = '"Beijing"';

-- 注意: 字符串比较时值需要带引号
-- 'Beijing' 不匹配 '"Beijing"'（JSON 字符串包含双引号）

-- 按数值过滤
SELECT ts, temperature, meta->'floor' AS floor_num
FROM   sensor_data
WHERE  meta->'floor' >= '3';

-- ============================================================
-- 5. 超级表聚合 + JSON 标签分组
-- ============================================================

SELECT meta->'location' AS location,
       COUNT(*)         AS reading_count,
       AVG(temperature) AS avg_temp,
       AVG(humidity)    AS avg_humidity
FROM   sensor_data
WHERE  ts >= '2024-01-01 00:00:00'
GROUP  BY location
ORDER  BY avg_temp DESC;

-- JSON 标签值可以直接用于 GROUP BY
-- 这在物联网场景中非常实用（按设备属性分组统计）

-- ============================================================
-- 6. 多子表联合查询
-- ============================================================

SELECT tbname, ts, temperature, meta->'location' AS location
FROM   sensor_data
WHERE  ts >= '2024-01-01 08:00:00'
  AND  ts <  '2024-01-01 09:00:00'
ORDER  BY ts;

-- tbname 是 TDengine 特殊列，返回子表名称
-- JSON 标签会自动展开到所有子表

-- ============================================================
-- 7. JSON 标签的实际应用模式
-- ============================================================

-- 典型 IoT 场景:
--   每个设备对应一个子表
--   设备的动态属性（位置、类型、楼层等）存储为 JSON 标签
--   时序数据（温度、湿度等）存储为数据列
--   优势: 无需为每种设备类型创建不同的超级表

-- 对比关系型数据库的 JSON 展平:
--   关系型数据库: JSON 在数据列中，需要展开为多行
--   TDengine:     JSON 在标签列中，用于过滤和分组，不需要展开
--   这是时序数据库与关系型数据库的架构差异

-- ============================================================
-- 8. 局限性与替代方案
-- ============================================================

-- 不支持的操作:
--   (a) JSON 数组展开（如 jsonb_array_elements）
--   (b) JSON 路径表达式（如 $.items[*].product）
--   (c) JSON 数据列（JSON 只能是标签）
--   (d) JSON 标签修改（创建后不可更新）
--   (e) JSON 对象嵌套提取

-- 替代方案:
--   1. 需要复杂 JSON 处理时，使用 TDengine 的 UDF 功能
--   2. 将 JSON 字段拆分为多个独立标签列
--   3. 使用 TaosAdapter 将数据导出到外部系统处理

-- 多标签替代方案:
-- CREATE STABLE sensor_data_v2 (
--     ts          TIMESTAMP,
--     temperature DOUBLE,
--     humidity    DOUBLE
-- ) TAGS (
--     location NCHAR(50),
--     type     NCHAR(20),
--     floor    INT
-- );

-- ============================================================
-- 9. 横向对比与对引擎开发者的启示
-- ============================================================

-- 1. TDengine JSON vs 其他数据库:
--   PostgreSQL:  完整 JSONB 支持，LATERAL + SRF 展平
--   MongoDB:     原生文档数据库，JSON 是一等公民
--   InfluxDB:    标签（字符串）+ 字段（数值），无 JSON 标签
--   TDengine:    JSON 仅限标签列，适合元数据管理
--
-- 2. TDengine JSON 标签的设计哲学:
--   时序数据库的核心是数据列（时序指标）
--   JSON 标签用于灵活管理设备元数据
--   不需要展开为多行（标签天然是一对一关系）
--
-- 对引擎开发者:
--   时序数据库的 JSON 使用模式与关系型数据库不同
--   JSON 在标签中用于"描述"而非"存储业务数据"
--   支持基本的键值提取和过滤已满足大多数 IoT 场景
--   若需完整 JSON 处理，考虑与外部计算引擎集成
