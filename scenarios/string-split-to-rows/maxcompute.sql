-- MaxCompute (ODPS): 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] MaxCompute SQL Reference - LATERAL VIEW
--       https://help.aliyun.com/document_detail/73778.html
--   [2] MaxCompute SQL Reference - SPLIT
--       https://help.aliyun.com/document_detail/48974.html
--   [3] MaxCompute SQL Reference - explode / posexplode
--       https://help.aliyun.com/document_detail/73779.html

-- ============================================================
-- 1. 示例数据
-- ============================================================

CREATE TABLE tags_csv (
    id   BIGINT,
    name STRING,
    tags STRING
);

INSERT INTO tags_csv VALUES
    (1, 'Alice', 'python,java,sql'),
    (2, 'Bob',   'go,rust'),
    (3, 'Carol', 'sql,python,javascript,typescript');

-- ============================================================
-- 2. LATERAL VIEW explode + SPLIT（推荐方案）
-- ============================================================

SELECT t.id, t.name, tag
FROM   tags_csv t
LATERAL VIEW explode(split(t.tags, ',')) exploded AS tag;

-- 设计分析: 三步组合
--   SPLIT(t.tags, ','): 字符串 → 数组（'python,java,sql' → ['python','java','sql']）
--   explode(): 数组 → 多行（3 个元素 → 3 行）
--   LATERAL VIEW: 关联外表和展开结果
--   LATERAL VIEW 是 MaxCompute（Hive）特有的语法，等价于标准 SQL 的 LATERAL

-- ============================================================
-- 3. LATERAL VIEW posexplode（带位置序号）
-- ============================================================

SELECT t.id, t.name, pos, tag
FROM   tags_csv t
LATERAL VIEW posexplode(split(t.tags, ',')) exploded AS pos, tag;

-- posexplode 同时返回元素位置（从 0 开始）和值
-- 适用于需要保留原始顺序的场景

-- ============================================================
-- 4. 去除空白 + 过滤空值
-- ============================================================

SELECT t.id, t.name, TRIM(tag) AS tag
FROM   tags_csv t
LATERAL VIEW explode(split(t.tags, ',')) exploded AS tag
WHERE  TRIM(tag) != '';

-- SPLIT 可能产生空白或空字符串（如 'a,,b' → ['a','','b']）
-- TRIM 去除前后空白，WHERE 过滤空值

-- ============================================================
-- 5. 拆分 + 聚合统计
-- ============================================================

SELECT tag, COUNT(*) AS user_count
FROM   tags_csv t
LATERAL VIEW explode(split(t.tags, ',')) exploded AS tag
GROUP  BY tag
ORDER  BY user_count DESC;

-- 每个标签有多少用户使用
-- 结果示例: python(2), sql(2), java(1), go(1), ...

-- ============================================================
-- 6. 多列拆分
-- ============================================================

CREATE TABLE user_skills (
    id        BIGINT,
    name      STRING,
    languages STRING,
    databases STRING
);

INSERT INTO user_skills VALUES
    (1, 'Alice', 'python,java', 'mysql,postgresql'),
    (2, 'Bob',   'go,rust',     'mysql,redis');

-- 同时展开两列
SELECT t.id, t.name, lang AS language, db AS database_name
FROM   user_skills t
LATERAL VIEW explode(split(t.languages, ',')) l AS lang
LATERAL VIEW explode(split(t.databases, ',')) d AS db;

-- 多个 LATERAL VIEW 产生笛卡尔积（2 x 2 = 4 行）
-- 如果需要一一对应，应使用 posexplode + JOIN 条件

-- ============================================================
-- 7. 一一对应的多列拆分
-- ============================================================

SELECT a.id, a.name, a.lang, a.db
FROM   (
    SELECT t.id, t.name, pos, lang
    FROM   tags_csv t
    LATERAL VIEW posexplode(split(t.languages, ',')) l AS pos, lang
) a
JOIN   (
    SELECT t.id, pos, db
    FROM   tags_csv t
    LATERAL VIEW posexplode(split(t.databases, ',')) d AS pos, db
) b ON a.id = b.id AND a.pos = b.pos;

-- 使用 posexplode 的位置序号做等值 JOIN
-- 实现一一对应而非笛卡尔积

-- ============================================================
-- 8. 正则拆分
-- ============================================================

-- SPLIT 支持正则表达式作为分隔符
SELECT t.id, t.name, tag
FROM   tags_csv t
LATERAL VIEW explode(split(t.tags, ',\\s*')) exploded AS tag;

-- ',\\s*' 匹配逗号 + 任意空白，自动去除分隔符后的空格

-- ============================================================
-- 9. 横向对比与对引擎开发者的启示
-- ============================================================

-- 1. MaxCompute 字符串拆分特性:
--   LATERAL VIEW + explode: Hive 生态标准模式
--   SPLIT: 支持正则分隔符
--   posexplode: 提供位置序号
--   多 LATERAL VIEW: 支持多列展开
--
-- 2. 与其他引擎对比:
--   MaxCompute: LATERAL VIEW explode(SPLIT(...))（Hive 语法）
--   Hive:       LATERAL VIEW explode(SPLIT(...))（相同语法）
--   Spark SQL:  LATERAL VIEW 或 CROSS JOIN UNNEST
--   Presto:     CROSS JOIN UNNEST(SPLIT(...))
--   BigQuery:   UNNEST(SPLIT(...))
--
-- 对引擎开发者:
--   LATERAL VIEW 是 Hive 生态的独特设计（等价于标准 LATERAL）
--   explode + SPLIT 的组合与 BigQuery 的 UNNEST + SPLIT 本质相同
--   posexplode 是有价值的增强（同时提供位置信息）
--   多 LATERAL VIEW 的笛卡尔积行为需要用户注意
