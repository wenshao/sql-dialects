-- ClickHouse: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] ClickHouse Documentation - splitByChar / splitByString
--       https://clickhouse.com/docs/en/sql-reference/functions/splitting-merging-functions
--   [2] ClickHouse Documentation - arrayJoin
--       https://clickhouse.com/docs/en/sql-reference/functions/array-join

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE tags_csv (
    id   UInt32,
    name String,
    tags String
) ENGINE = MergeTree() ORDER BY id;

INSERT INTO tags_csv VALUES
    (1, 'Alice', 'python,java,sql'),
    (2, 'Bob',   'go,rust'),
    (3, 'Carol', 'sql,python,javascript,typescript');

-- ============================================================
-- 方法 1: arrayJoin + splitByChar（推荐）
-- ============================================================
SELECT id, name, arrayJoin(splitByChar(',', tags)) AS tag
FROM   tags_csv;

-- ============================================================
-- 方法 2: arrayJoin + splitByString
-- ============================================================
SELECT id, name, arrayJoin(splitByString(',', tags)) AS tag
FROM   tags_csv;

-- ============================================================
-- 方法 3: ARRAY JOIN（保留序号）
-- ============================================================
SELECT id, name, tag, idx
FROM   tags_csv
ARRAY JOIN splitByChar(',', tags) AS tag,
           arrayEnumerate(splitByChar(',', tags)) AS idx;

-- ============================================================
-- 方法 4: splitByRegexp
-- ============================================================
SELECT id, name, arrayJoin(splitByRegexp(',\\s*', tags)) AS tag
FROM   tags_csv;
