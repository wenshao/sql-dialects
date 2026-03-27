-- Materialize: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] Materialize Documentation - String Functions
--       https://materialize.com/docs/sql/functions/#string-functions
--   [2] Materialize Documentation - List and Array Functions
--       https://materialize.com/docs/sql/functions/#list-and-array
--   [3] Materialize Documentation - UNNEST
--       https://materialize.com/docs/sql/functions/#unnest

-- ============================================================
-- 1. 示例数据
-- ============================================================

CREATE TABLE tags_csv (
    id   INT,
    name TEXT,
    tags TEXT
);

INSERT INTO tags_csv VALUES
    (1, 'Alice', 'python,java,sql'),
    (2, 'Bob',   'go,rust'),
    (3, 'Carol', 'sql,python,javascript,typescript');

-- ============================================================
-- 2. STRING_TO_ARRAY + UNNEST（推荐）
-- ============================================================

SELECT id, name, UNNEST(STRING_TO_ARRAY(tags, ',')) AS tag
FROM   tags_csv;

-- 设计分析: Materialize 兼容 PostgreSQL 的字符串处理方式
--   STRING_TO_ARRAY: 字符串 → TEXT[] 数组
--   UNNEST: 数组 → 多行
--   可以直接在 SELECT 列表中使用 UNNEST

-- ============================================================
-- 3. LATERAL + UNNEST（显式关联）
-- ============================================================

SELECT t.id, t.name, s.tag
FROM   tags_csv t,
       LATERAL UNNEST(STRING_TO_ARRAY(t.tags, ',')) AS s(tag);

-- LATERAL 显式声明关联关系
-- 与在 SELECT 中直接使用 UNNEST 效果相同
-- 但 LATERAL 形式更清晰，且可以添加额外列

-- ============================================================
-- 4. WITH ORDINALITY（保留序号）
-- ============================================================

SELECT t.id, t.name, s.ordinality, s.tag
FROM   tags_csv t,
       LATERAL UNNEST(STRING_TO_ARRAY(t.tags, ','))
              WITH ORDINALITY AS s(tag, ordinality);

-- WITH ORDINALITY 为每个元素添加从 1 开始的序号
-- 可以保留原始顺序信息

-- ============================================================
-- 5. regexp_split_to_table（正则拆分）
-- ============================================================

SELECT id, name, regexp_split_to_table(tags, ',') AS tag
FROM   tags_csv;

-- regexp_split_to_table 直接返回多行，无需 UNNEST
-- 支持正则分隔符，如 ',\s*' 自动处理逗号后空格

SELECT id, name, regexp_split_to_table(tags, ',\s*') AS tag
FROM   tags_csv;

-- ============================================================
-- 6. 去除空白 + 过滤空值
-- ============================================================

SELECT t.id, t.name, TRIM(s.tag) AS tag
FROM   tags_csv t,
       LATERAL UNNEST(STRING_TO_ARRAY(t.tags, ',')) AS s(tag)
WHERE  TRIM(s.tag) != '';

-- ============================================================
-- 7. 拆分 + 聚合统计
-- ============================================================

SELECT tag, COUNT(*) AS user_count
FROM   tags_csv,
       LATERAL UNNEST(STRING_TO_ARRAY(tags, ',')) AS tag
GROUP  BY tag
ORDER  BY user_count DESC;

-- 结果: python(2), sql(2), java(1), go(1), rust(1), javascript(1), typescript(1)

-- ============================================================
-- 8. Materialize 物化视图（实时拆分）
-- ============================================================

-- Materialize 的核心特性: 创建持续维护的物化视图
CREATE MATERIALIZED VIEW tags_expanded AS
SELECT t.id, t.name, s.tag
FROM   tags_csv t,
       LATERAL UNNEST(STRING_TO_ARRAY(t.tags, ',')) AS s(tag);

-- 物化视图会随着源表数据变化自动更新
-- 查询物化视图时直接读取预计算结果，性能极高

SELECT tag, COUNT(*) AS user_count
FROM   tags_expanded
GROUP  BY tag;

-- ============================================================
-- 9. 拆分 + JOIN 关联查询
-- ============================================================

-- 创建标签维度表
-- CREATE TABLE tag_categories (
--     tag      TEXT PRIMARY KEY,
--     category TEXT
-- );
-- INSERT INTO tag_categories VALUES
--     ('python', 'language'), ('java', 'language'), ('sql', 'language'),
--     ('go', 'language'), ('rust', 'language'),
--     ('javascript', 'language'), ('typescript', 'language');

-- SELECT t.id, t.name, s.tag, tc.category
-- FROM   tags_csv t,
--        LATERAL UNNEST(STRING_TO_ARRAY(t.tags, ',')) AS s(tag)
-- LEFT   JOIN tag_categories tc ON tc.tag = TRIM(s.tag);

-- ============================================================
-- 10. 横向对比与对引擎开发者的启示
-- ============================================================

-- 1. Materialize 字符串拆分特性:
--   兼容 PostgreSQL 的 STRING_TO_ARRAY + UNNEST
--   regexp_split_to_table 支持正则拆分
--   WITH ORDINALITY 保留序号
--   物化视图 + 拆分: 实时预计算
--
-- 2. Materialize 的独特优势:
--   物化视图自动维护拆分结果
--   源数据变化时，展开结果实时更新
--   对高频查询的拆分场景性能极佳
--
-- 3. 与其他流/实时引擎对比:
--   Materialize: STRING_TO_ARRAY + UNNEST + 物化视图
--   ksqlDB:      EXPLODE(SPLIT(...)) + 流
--   Flink SQL:   STRING_TO_ARRAY + UNNEST + 动态表
--   RisingWave:  兼容 PostgreSQL，语法类似 Materialize
--
-- 对引擎开发者:
--   物化视图 + 拆分函数的组合是实时数据库的杀手特性
--   兼容 PostgreSQL 降低了用户迁移成本
--   regexp_split_to_table 比其他引擎的正则方案更直观
--   WITH ORDINALITY 应作为数组展开的标准配套设施
