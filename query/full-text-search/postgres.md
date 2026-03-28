# PostgreSQL: 全文搜索

> 参考资料:
> - [PostgreSQL Documentation - Full Text Search](https://www.postgresql.org/docs/current/textsearch.html)
> - [PostgreSQL Documentation - GIN Indexes](https://www.postgresql.org/docs/current/gin.html)
> - [PostgreSQL Source - tsearch2 / tsvector_op.c](https://github.com/postgres/postgres/tree/master/src/backend/tsearch)

## 核心概念: tsvector 与 tsquery

tsvector: 文档的规范化词汇表示（分词+词干提取+去停用词+位置信息）
```sql
SELECT to_tsvector('english', 'The quick brown fox jumps over the lazy dog');
```

结果: 'brown':3 'dog':9 'fox':4 'jump':5 'lazi':8 'quick':2

tsquery: 搜索条件的结构化表示
```sql
SELECT to_tsquery('english', 'quick & fox');
```

结果: 'quick' & 'fox'

@@ 匹配运算符
```sql
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database & performance');
```

设计分析: 为什么 PostgreSQL 内置全文搜索
  大多数数据库的全文搜索是附加模块（MySQL FULLTEXT, Oracle Text）。
  PostgreSQL 从 8.3 开始将 tsearch2 贡献回核心，与 GIN 索引深度集成。
  优势: 全文搜索与 SQL 完全融合（可在 WHERE/JOIN/CTE 中使用），
  不需要外部引擎（如 Elasticsearch）即可处理中等规模的文本搜索。

## 搜索运算符

& AND, | OR, ! NOT
```sql
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database & !mysql');
```

<-> 相邻运算符（9.6+ 短语搜索）
```sql
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'full <-> text <-> search');
```

<N> N词距离（9.6+）
```sql
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database <2> optimization');
```

## 便捷查询函数

plainto_tsquery: 空格自动转 AND
```sql
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ plainto_tsquery('english', 'database performance');
```

phraseto_tsquery (9.6+): 空格转相邻
```sql
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ phraseto_tsquery('english', 'full text search');
```

websearch_to_tsquery (11+): 支持搜索引擎语法
```sql
SELECT * FROM articles
WHERE to_tsvector('english', content) @@ websearch_to_tsquery('english', '"full text" -mysql OR postgres');
```

双引号=短语, -=排除, OR=或

## 排名与高亮

ts_rank: 基于词频的排名
```sql
SELECT title,
    ts_rank(to_tsvector('english', content), to_tsquery('english', 'database')) AS rank
FROM articles
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'database')
ORDER BY rank DESC;
```

ts_rank_cd: 覆盖密度排名（考虑匹配词距离）
```sql
SELECT title,
    ts_rank_cd(to_tsvector('english', content),
               to_tsquery('english', 'database & performance')) AS rank
FROM articles ORDER BY rank DESC LIMIT 10;
```

ts_headline: 高亮显示匹配片段
```sql
SELECT ts_headline('english', content,
    to_tsquery('english', 'database'),
    'StartSel=<b>, StopSel=</b>, MaxFragments=3')
FROM articles;
```

## GIN 索引: 全文搜索的性能关键

在表达式上创建 GIN 索引
```sql
CREATE INDEX idx_ft ON articles USING gin (to_tsvector('english', content));
```

优化方案: 存储 tsvector 列（避免每次查询重新计算）
```sql
ALTER TABLE articles ADD COLUMN search_vector tsvector;
CREATE INDEX idx_search ON articles USING gin (search_vector);
```

用触发器自动维护 tsvector 列
```sql
CREATE OR REPLACE FUNCTION articles_search_update() RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector = to_tsvector('english',
        COALESCE(NEW.title, '') || ' ' || COALESCE(NEW.content, ''));
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_search_update
    BEFORE INSERT OR UPDATE ON articles
    FOR EACH ROW EXECUTE FUNCTION articles_search_update();
```

为什么不用 GENERATED ALWAYS AS:
  to_tsvector() 不是 IMMUTABLE 函数（依赖字典配置），
  PostgreSQL 生成列要求表达式必须是 IMMUTABLE。
  因此只能用触发器维护 tsvector 列。

## GIN 索引的内部实现

GIN (Generalized Inverted Index) 是倒排索引的通用框架:
  key → posting list (行ID列表)
  对全文搜索: 每个词汇(lexeme) → 包含该词的所有行

GIN 的 fast update 机制:
  INSERT 时不立即更新索引树，而是放入 pending list
  vacuum 或 gin_pending_list_limit 触发批量合并
  gin_pending_list_limit 默认 4MB

GIN vs GiST 用于全文搜索:
  GIN: 查询快，更新慢（推荐读多写少）
  GiST: 查询慢，更新快（有损索引，可能有误报）

## 中文全文搜索

PostgreSQL 默认的分词器不支持中文（基于空格分词）
解决方案:

方案 1: zhparser 扩展（基于 SCWS）
```sql
CREATE EXTENSION zhparser;
CREATE TEXT SEARCH CONFIGURATION chinese (PARSER = zhparser);
ALTER TEXT SEARCH CONFIGURATION chinese ADD MAPPING FOR n,v,a,i,e,l WITH simple;
```

SELECT to_tsvector('chinese', '全文搜索引擎开发');

方案 2: pg_jieba 扩展（基于结巴分词）
```sql
CREATE EXTENSION pg_jieba;
```

SELECT to_tsvector('jiebacfg', '全文搜索引擎开发');

## 横向对比: 全文搜索能力

### 集成度

  PostgreSQL: 内置核心（tsvector/tsquery/GIN），SQL 完全融合
  MySQL:      FULLTEXT 索引（InnoDB 5.6+），功能有限
  Oracle:     Oracle Text（独立组件，功能丰富但配置复杂）
  SQL Server: Full-Text Search（独立服务进程）
  Elasticsearch: 专用搜索引擎（功能最强但需要独立部署和同步）

### 短语搜索

  PostgreSQL: <-> 运算符 (9.6+)
  MySQL:      不支持原生短语搜索
  Elasticsearch: match_phrase

### 排名算法

  PostgreSQL: ts_rank（词频）, ts_rank_cd（覆盖密度）
  Elasticsearch: BM25（更先进，考虑文档长度和词频饱和）

## 对引擎开发者的启示

(1) 全文搜索集成在 SQL 引擎内的优势:
    可以在 WHERE/JOIN/聚合 中直接使用文本搜索，不需要外部同步。
    但搜索质量和性能无法与专用引擎（Elasticsearch）竞争。
    定位: 中等规模（<1TB 文本）的全文搜索无需引入额外基础设施。

(2) GIN 索引框架的通用性:
    GIN 不仅用于全文搜索，还用于 JSONB、数组、三元组相似度。
    "一个索引框架服务多种数据类型"是优秀的架构设计。

(3) 分词器的可扩展性:
    PostgreSQL 的 TEXT SEARCH CONFIGURATION 允许自定义分词器+字典。
    中文/日文等需要特殊分词的语言可以通过扩展支持。

## 版本演进

PostgreSQL 8.3:  全文搜索纳入核心（tsearch2 → 内置）
PostgreSQL 9.6:  短语搜索 (<->)
PostgreSQL 11:   websearch_to_tsquery（搜索引擎风格查询）
PostgreSQL 12:   ts_headline 性能改进
PostgreSQL 14:   GIN 索引压缩改进
