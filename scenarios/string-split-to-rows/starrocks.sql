-- StarRocks: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] StarRocks Documentation - unnest
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/array-functions/unnest/
--   [2] StarRocks Documentation - split
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/string-functions/split/

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE tags_csv (
    id   INT,
    name VARCHAR(100),
    tags VARCHAR(500)
) DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES ("replication_num" = "1");

INSERT INTO tags_csv VALUES
    (1, 'Alice', 'python,java,sql'),
    (2, 'Bob',   'go,rust'),
    (3, 'Carol', 'sql,python,javascript,typescript');

-- ============================================================
-- 方法 1: unnest + split（推荐，StarRocks 2.5+）
-- ============================================================
SELECT t.id, t.name, tag
FROM   tags_csv t,
       unnest(split(t.tags, ',')) AS t1(tag);

-- ============================================================
-- 方法 2: LATERAL + unnest
-- ============================================================
SELECT t.id, t.name, tag
FROM   tags_csv t,
       LATERAL unnest(split(t.tags, ',')) AS t1(tag);
