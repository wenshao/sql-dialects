-- TDengine: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] TDengine Documentation - JSON 标签
--       https://docs.tdengine.com/taos-sql/data-type/#json
--   [2] TDengine 3.0 支持 JSON 类型标签

-- ============================================================
-- TDengine 仅在标签（TAG）中支持 JSON 类型
-- ============================================================
CREATE STABLE sensor_data (
    ts    TIMESTAMP,
    value DOUBLE
) TAGS (
    meta JSON                   -- JSON 类型标签
);

CREATE TABLE sensor_1 USING sensor_data
    TAGS ('{"location": "Beijing", "type": "temperature", "floor": 3}');

-- ============================================================
-- 提取 JSON 标签字段
-- ============================================================
SELECT ts, value, meta->'location' AS location, meta->'type' AS sensor_type
FROM   sensor_data
WHERE  meta->'location' = '"Beijing"';

-- 注意: TDengine 的 JSON 支持仅限于标签列
-- 数据列不支持 JSON 类型
-- 不支持 JSON 数组展开
