-- Doris: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] Apache Doris Documentation - explode_split
--       https://doris.apache.org/docs/sql-manual/sql-functions/table-functions/explode-split
--   [2] Apache Doris Documentation - LATERAL VIEW
--       https://doris.apache.org/docs/sql-manual/sql-statements/lateral-view

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
-- 方法 1: LATERAL VIEW explode_split（推荐）
-- ============================================================
SELECT t.id, t.name, tag
FROM   tags_csv t
LATERAL VIEW explode_split(t.tags, ',') tmp AS tag;

-- ============================================================
-- 方法 2: explode_split 作为表函数
-- ============================================================
SELECT t.id, t.name, e.tag
FROM   tags_csv t,
       explode_split(t.tags, ',') AS e(tag);
