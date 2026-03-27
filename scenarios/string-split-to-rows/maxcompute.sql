-- MaxCompute (ODPS): 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] MaxCompute SQL Reference - LATERAL VIEW
--       https://help.aliyun.com/document_detail/73778.html
--   [2] MaxCompute SQL Reference - SPLIT
--       https://help.aliyun.com/document_detail/48974.html

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE tags_csv (
    id   BIGINT,
    name STRING,
    tags STRING
);

-- ============================================================
-- 方法 1: LATERAL VIEW explode + split（推荐）
-- ============================================================
SELECT t.id, t.name, tag
FROM   tags_csv t
LATERAL VIEW explode(split(t.tags, ',')) exploded AS tag;

-- ============================================================
-- 方法 2: LATERAL VIEW posexplode（带位置序号）
-- ============================================================
SELECT t.id, t.name, pos, tag
FROM   tags_csv t
LATERAL VIEW posexplode(split(t.tags, ',')) exploded AS pos, tag;
