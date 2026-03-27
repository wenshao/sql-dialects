-- Hive: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] Hive Language Manual - LATERAL VIEW
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+LateralView
--   [2] Hive Language Manual - UDF - explode
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE tags_csv (
    id   INT,
    name STRING,
    tags STRING
) ROW FORMAT DELIMITED FIELDS TERMINATED BY ',' STORED AS TEXTFILE;

-- ============================================================
-- 方法 1: LATERAL VIEW explode + split（推荐）
-- ============================================================
SELECT t.id, t.name, tag
FROM   tags_csv t
LATERAL VIEW explode(split(t.tags, ',')) exploded AS tag;

-- ============================================================
-- 方法 2: LATERAL VIEW posexplode（带位置序号, Hive 0.13+）
-- ============================================================
SELECT t.id, t.name, pos, tag
FROM   tags_csv t
LATERAL VIEW posexplode(split(t.tags, ',')) exploded AS pos, tag;

-- ============================================================
-- 方法 3: LATERAL VIEW OUTER（保留空值行）
-- ============================================================
SELECT t.id, t.name, tag
FROM   tags_csv t
LATERAL VIEW OUTER explode(split(t.tags, ',')) exploded AS tag;
