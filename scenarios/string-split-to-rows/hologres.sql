-- Hologres: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] Hologres 兼容 PostgreSQL 语法
--       https://help.aliyun.com/document_detail/130408.html
--   [2] Hologres SQL Reference - UNNEST
--       https://help.aliyun.com/document_detail/416498.html

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE tags_csv (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(100),
    tags VARCHAR(500)
);

INSERT INTO tags_csv (name, tags) VALUES
    ('Alice', 'python,java,sql'),
    ('Bob',   'go,rust'),
    ('Carol', 'sql,python,javascript,typescript');

-- ============================================================
-- 方法 1: STRING_TO_ARRAY + UNNEST（推荐，兼容 PostgreSQL）
-- ============================================================
SELECT id, name, UNNEST(STRING_TO_ARRAY(tags, ',')) AS tag
FROM   tags_csv;

-- ============================================================
-- 方法 2: regexp_split_to_table
-- ============================================================
SELECT id, name, regexp_split_to_table(tags, ',') AS tag
FROM   tags_csv;
