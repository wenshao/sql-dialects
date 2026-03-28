-- StarRocks: 字符串拆分为行
--
-- 参考资料:
--   [1] StarRocks - UNNEST / SPLIT
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/

-- UNNEST + SPLIT (3.1+，SQL 标准风格)
SELECT t.id, t.name, tag
FROM tags_csv t, UNNEST(SPLIT(t.tags, ',')) AS tmp(tag);

-- 对比 Doris: LATERAL VIEW explode_split(Hive 风格)
-- StarRocks 的 UNNEST 更接近 SQL 标准(BigQuery/PG 风格)。
