-- TDengine: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] TDengine Documentation - SQL Reference
--       https://docs.tdengine.com/reference/sql/
--   [2] TDengine 是时序数据库，对字符串拆分的支持有限

-- ============================================================
-- 注意: TDengine 是专用时序数据库
-- ============================================================
-- TDengine 不原生支持字符串拆分为多行
-- 建议方案:
-- 1. 在应用层处理字符串拆分
-- 2. 使用 UDF（用户自定义函数）
-- 3. 将数据预处理为多行后再写入

-- 示例: 建议数据模型 —— 直接用标签列或多行
CREATE STABLE sensor_tags (
    ts    TIMESTAMP,
    value DOUBLE
) TAGS (
    device_id INT,
    tag1 NCHAR(50),
    tag2 NCHAR(50),
    tag3 NCHAR(50)
);

-- 如果使用 TDengine 3.x，可用 UDF 扩展
-- CREATE FUNCTION split_str AS '/path/to/libudf.so' OUTPUTTYPE VARCHAR(100);
