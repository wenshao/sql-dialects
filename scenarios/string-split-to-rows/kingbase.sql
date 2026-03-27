-- 人大金仓 (KingbaseES): 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] KingbaseES 兼容 PostgreSQL / Oracle 语法
--       https://help.kingbase.com.cn/
--   [2] KingbaseES SQL 参考手册

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
-- 方法 1: STRING_TO_ARRAY + UNNEST（PostgreSQL 兼容模式，推荐）
-- ============================================================
SELECT id, name, UNNEST(STRING_TO_ARRAY(tags, ',')) AS tag
FROM   tags_csv;

-- ============================================================
-- 方法 2: regexp_split_to_table
-- ============================================================
SELECT id, name, regexp_split_to_table(tags, ',') AS tag
FROM   tags_csv;

-- ============================================================
-- 方法 3: LATERAL + UNNEST 带序号
-- ============================================================
SELECT t.id, t.name, s.ordinality, s.tag
FROM   tags_csv t,
       LATERAL UNNEST(STRING_TO_ARRAY(t.tags, ','))
              WITH ORDINALITY AS s(tag, ordinality);
