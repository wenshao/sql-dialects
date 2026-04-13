# 分词器与文本分析器 (Tokenizers and Text Analyzers)

全文检索的命中率，70% 取决于分词质量。索引结构、相关性算法、查询优化都只是放大器——如果第一步就把"北京大学生"切成了"北京大学/生"而不是"北京/大学生"，后面再精巧的 BM25 也救不回来。分词器是搜索引擎里最朴素、最容易被忽略、却最决定上限的组件。

## 为什么分词是全文检索的第一步

倒排索引的本质是 `term -> postings list` 的映射。把一段自然语言文本"切碎"成索引项 (term) 的过程就是 tokenization，而围绕 tokenization 添加的字符过滤、归一化、词形还原、停用词、同义词等一系列处理，则统称为 analyzer pipeline。一个典型的 Elasticsearch 风格 analyzer 由三段组成：

```
char_filter -> tokenizer -> token_filter (chain)
```

字符过滤负责在分词前清洗文本 (例如去 HTML 标签)；分词器把字符流切成 token 流；token 过滤器是一条链路，按顺序对每个 token 做小写化、词干提取、停用词剔除、同义词扩展、ASCII 折叠等变换。

对于英文这类有空格分隔的语言，简单的"按空格切分 + 小写 + Snowball 词干"已经能覆盖大部分场景；但对中文、日文、韩文 (CJK) 这种没有词边界的连续字符流，分词复杂度立刻上升一个数量级。中文有歧义切分 ("南京市/长江大桥" vs "南京/市长/江大桥")、新词发现、专有名词识别等难题；日文混合了汉字、平假名、片假名以及罗马字；韩文虽然有空格但单词内部的助词需要形态分析。

因此，"是否支持自定义 analyzer"以及"是否内置 CJK 分词器"几乎成了评判一个数据库 FTS 能力是否生产可用的硬指标。本文聚焦在 tokenizer 与 analyzer pipeline 配置层面，与 [full-text-search.md](./full-text-search.md) 中关于查询语法、相关性排序、索引结构的内容互补。

> 本文不存在"SQL 标准"一节：分词器配置完全是 vendor-specific，SQL:2003/2016 全文检索章节只规定了 `CONTAINS()` 等查询函数语法，从未触及 analyzer 层面。

## 支持矩阵

下面分十一张表对 49 个数据库引擎逐一打分。统一的列含义：

- **是**：引擎原生或通过官方扩展直接提供该能力
- **扩展**：需要第三方扩展、插件或外部服务
- **--**：不支持或需要应用层实现

### 内置基础分词器 (simple / standard / whitespace)

| 引擎 | 内置基础分词器 | 备注 |
|------|--------------|------|
| PostgreSQL | 是 | tsearch2 内置 `simple`、`english` 等 cfg |
| MySQL | 是 | InnoDB FTS 默认 built-in parser |
| MariaDB | 是 | 继承 MySQL FTS parser |
| SQLite | 是 | FTS5 `unicode61`、`ascii`、`porter` |
| Oracle | 是 | Oracle Text `BASIC_LEXER` |
| SQL Server | 是 | `Neutral` word breaker |
| DB2 | 是 | Net Search Extender + Text Search |
| Snowflake | 是 | SEARCH 内置默认 analyzer |
| BigQuery | 是 | `LOG_ANALYZER`、`PATTERN_ANALYZER`、`NO_OP_ANALYZER` |
| Redshift | -- | 无 FTS，仅 LIKE/regex |
| DuckDB | 是 | `fts` 扩展提供 `default` stemmer/tokenizer |
| ClickHouse | 是 | `tokens()`、`splitByNonAlpha()`、tokenbf_v1 索引 |
| Trino | -- | 无内置 FTS |
| Presto | -- | 无内置 FTS |
| Spark SQL | -- | 需调用 Spark ML `Tokenizer` |
| Hive | -- | 无 FTS，需 UDF |
| Flink SQL | -- | 无 FTS |
| Databricks | -- | 同 Spark，需 ML 库 |
| Teradata | 是 | Teradata Search 模块 (已弃用) |
| Greenplum | 是 | 继承 PostgreSQL tsearch2 |
| CockroachDB | 是 | 22.2+ 引入 tsvector/tsquery 子集 |
| TiDB | -- | 无内置 FTS (8.4 实验性) |
| OceanBase | 是 | 4.x 起兼容 MySQL FTS |
| YugabyteDB | 是 | 继承 PostgreSQL |
| SingleStore | 是 | 内置 FTS v2 (Lucene 风格) |
| Vertica | 是 | Text Search 内置 tokenizer |
| Impala | -- | 无 FTS |
| StarRocks | 是 | 2.5+ 倒排索引 + tokenizer |
| Doris | 是 | 2.0+ inverted index + tokenizer |
| MonetDB | -- | 无 FTS |
| CrateDB | 是 | 基于 Lucene，全套 analyzer |
| TimescaleDB | 是 | 继承 PostgreSQL |
| QuestDB | -- | 无 FTS |
| Exasol | -- | 仅 LIKE/REGEXP_LIKE |
| SAP HANA | 是 | 内置 Text Analysis (TA) |
| Informix | 是 | Basic Text Search / bts |
| Firebird | -- | 无 FTS |
| H2 | 是 | `FT_*` 函数 (Lucene 模式) |
| HSQLDB | -- | 无 FTS |
| Derby | -- | 无 FTS |
| Amazon Athena | -- | 继承 Trino |
| Azure Synapse | 是 | 继承 SQL Server (Dedicated SQL pool 不支持) |
| Google Spanner | 是 | 2023 GA Search index |
| Materialize | -- | 无 FTS |
| RisingWave | -- | 无 FTS |
| InfluxDB (SQL) | -- | 无 FTS |
| DatabendDB | 是 | 1.2+ 倒排索引 |
| Yellowbrick | -- | 无 FTS |
| Firebolt | -- | 无 FTS |

### 语言相关词干提取 (Snowball / Porter / Lancaster)

| 引擎 | Snowball | Porter | 其他 | 备注 |
|------|----------|--------|------|------|
| PostgreSQL | 是 | 是 | -- | tsearch2 内置 15+ 语言 Snowball |
| MySQL | -- | -- | -- | 不做词形还原 |
| MariaDB | -- | -- | -- | 同 MySQL |
| SQLite | -- | 是 | -- | FTS5 `porter` tokenizer |
| Oracle | 是 | -- | `BASIC_LEXER` 多语言 | `index_stems` 参数 |
| SQL Server | -- | -- | 形态分析器 | 各语言独立 word breaker + stemmer |
| DB2 | 是 | -- | -- | Text Search 多语言 |
| Snowflake | -- | -- | -- | 仅 lowercase + ASCII |
| BigQuery | -- | -- | -- | analyzer 不含 stemming |
| DuckDB | 是 | 是 | -- | `stemmer='english'`、`'german'` 等 |
| ClickHouse | -- | -- | -- | 无原生 stemming |
| Greenplum | 是 | 是 | -- | 继承 PostgreSQL |
| CockroachDB | 是 | -- | -- | 继承 tsearch2 |
| OceanBase | -- | -- | -- | 同 MySQL |
| YugabyteDB | 是 | 是 | -- | 继承 PostgreSQL |
| SingleStore | 是 | -- | -- | Lucene Snowball |
| Vertica | -- | -- | -- | 仅 tokenize |
| StarRocks | 是 | -- | -- | english analyzer |
| Doris | 是 | -- | -- | english analyzer |
| CrateDB | 是 | 是 | -- | Lucene 全套 |
| TimescaleDB | 是 | 是 | -- | 继承 PostgreSQL |
| SAP HANA | 是 | -- | 18+ 语言 | TA 内置 |
| Informix | 是 | -- | -- | bts |
| H2 | 是 | -- | -- | Lucene |
| Spanner | 是 | -- | -- | search index 内 |
| DatabendDB | 是 | -- | -- | english/chinese |
| 其他未列出 | -- | -- | -- | 不支持 |

### CJK 分词器 (jieba / IK / MeCab / SCWS / 内置 ngram)

| 引擎 | 中文 | 日文 | 韩文 | 实现 |
|------|------|------|------|------|
| PostgreSQL | 扩展 | 扩展 | 扩展 | `zhparser` (SCWS)、`pgroonga` (MeCab/Mroonga)、`pg_jieba`、`pg_bigm` |
| MySQL | 是 | 扩展 | -- | 内置 `ngram` parser、`mecab` plugin |
| MariaDB | 是 | -- | -- | 继承 MySQL ngram |
| SQLite | 是 | 是 | 是 | FTS5 `trigram` (3.34+) + `unicode61` 处理 CJK code point |
| Oracle | 是 | 是 | 是 | `CHINESE_VGRAM_LEXER`、`CHINESE_LEXER`、`JAPANESE_LEXER`、`KOREAN_MORPH_LEXER` |
| SQL Server | 是 | 是 | 是 | 中/日/韩语言包 word breaker (需安装) |
| DB2 | 是 | 是 | 是 | Net Search Extender 多语言 |
| Snowflake | 是 | 是 | 是 | 2024 SEARCH 默认 analyzer 自动处理 CJK n-gram |
| BigQuery | 是 | 是 | 是 | `LOG_ANALYZER` 配合 token_filter，CJK 走 ICU |
| DuckDB | -- | -- | -- | 仅拉丁语系 stemmer |
| ClickHouse | n-gram | n-gram | n-gram | `tokens('ngrambf')`、`ngrambf_v1` 索引 |
| OceanBase | 是 | -- | -- | MySQL 兼容 ngram parser |
| YugabyteDB | 扩展 | -- | -- | 部分 PG 扩展可用 |
| SingleStore | 是 | 是 | 是 | Lucene CJK analyzer |
| StarRocks | 是 | -- | -- | jieba (3.0+) |
| Doris | 是 | -- | -- | jieba (2.1+) |
| CrateDB | 是 | 是 | 是 | Lucene `smartcn`、`kuromoji`、`nori` |
| SAP HANA | 是 | 是 | 是 | TA 含 `LANG_CHINESE`、`LANG_JAPANESE`、`LANG_KOREAN` 词典 |
| Informix | 是 | 是 | 是 | bts CJK lexer |
| Spanner | 是 | 是 | 是 | search index 自动 ICU |
| DatabendDB | 是 | -- | -- | chinese tokenizer (jieba) |
| TimescaleDB / Greenplum / CockroachDB | 扩展 | 扩展 | 扩展 | 继承 PG 扩展生态 |
| 其他 | -- | -- | -- | 不支持 |

### N-gram 分词器 (固定窗口字符 n-gram)

| 引擎 | N-gram | 可配置 N | 备注 |
|------|--------|---------|------|
| PostgreSQL | 扩展 | 是 | `pg_trgm` (trigram)、`pg_bigm` (bigram) |
| MySQL | 是 | 是 | `ngram_token_size` 默认 2 |
| MariaDB | 是 | 是 | 同 MySQL |
| SQLite | 是 | 否 (固定 3) | FTS5 `trigram` |
| Oracle | 是 | 是 | `CHINESE_VGRAM_LEXER`、`WORLD_LEXER` |
| SQL Server | -- | -- | 不直接暴露 n-gram |
| ClickHouse | 是 | 是 | `ngramTokens`、`ngrambf_v1` 索引 (skip index) |
| BigQuery | 否 | -- | analyzer 内部 |
| Snowflake | 否 | -- | analyzer 内部 |
| StarRocks | 是 | 是 | `chinese` 与 `ngram` 双模式 |
| Doris | 是 | 是 | inverted index `parser='ngram'` |
| CrateDB | 是 | 是 | Lucene `nGram` |
| SAP HANA | 是 | 是 | TA "n-gram" 配置 |
| H2 | -- | -- | -- |
| 其他 | -- | -- | -- |

### Edge n-gram (前缀自动完成)

Edge n-gram 用于实时搜索框的"边输入边提示"：把 "elastic" 索引为 `e, el, ela, elas, elast, elasti, elastic`，查询时直接命中前缀。

| 引擎 | Edge n-gram | 备注 |
|------|------------|------|
| PostgreSQL | 扩展 | `pg_trgm` 配合 `LIKE 'foo%'` 索引 |
| MySQL | -- | 仅完整 ngram |
| Oracle | -- | 需 `WILDCARD_INDEX` 配合 |
| SQL Server | -- | -- |
| SingleStore | 是 | Lucene edge_ngram |
| CrateDB | 是 | Lucene edge_ngram |
| StarRocks | -- | -- |
| Doris | -- | -- |
| ClickHouse | -- | 用 prefix bloom 替代 |
| SAP HANA | -- | -- |
| 其他 | -- | -- |

### 停用词过滤 (Stop word filter)

| 引擎 | 停用词 | 自定义词表 | 默认语言 |
|------|--------|----------|---------|
| PostgreSQL | 是 | 是 | 多语言 (`english_stop` 等) |
| MySQL | 是 | 是 | `innodb_ft_server_stopword_table` |
| MariaDB | 是 | 是 | 同 MySQL |
| SQLite | -- | -- | 应用层处理 |
| Oracle | 是 | 是 | `stoplist` 对象 |
| SQL Server | 是 | 是 | `CREATE FULLTEXT STOPLIST` |
| DB2 | 是 | 是 | -- |
| Snowflake | 是 | -- | analyzer 内置 |
| BigQuery | 是 | 是 | `token_filters: stop_words` |
| DuckDB | 是 | 是 | `stopwords='english'` 或自定义表 |
| ClickHouse | -- | -- | 无 |
| Greenplum / TimescaleDB / YugabyteDB / CockroachDB | 是 | 是 | 继承 PG |
| OceanBase | 是 | 是 | 同 MySQL |
| SingleStore | 是 | 是 | Lucene |
| Vertica | 是 | 是 | -- |
| StarRocks | 是 | 是 | analyzer 配置 |
| Doris | 是 | 是 | analyzer 配置 |
| CrateDB | 是 | 是 | Lucene |
| SAP HANA | 是 | 是 | TA 配置 |
| Informix | 是 | 是 | bts |
| H2 | 是 | 是 | Lucene |
| Spanner | 是 | -- | search index 默认 |
| DatabendDB | 是 | 是 | -- |
| 其他 | -- | -- | -- |

### 同义词过滤 (Synonym filter)

| 引擎 | 同义词 | 加载方式 | 备注 |
|------|--------|---------|------|
| PostgreSQL | 是 | `synonym` dictionary 文件 | tsearch2 字典链 |
| MySQL | -- | -- | 无 |
| MariaDB | -- | -- | -- |
| SQLite | -- | -- | -- |
| Oracle | 是 | `CTX_THES` 同义词表 | 支持双向、广义、狭义 |
| SQL Server | 是 | `thesaurus XML` 文件 | 各语言一个 |
| DB2 | 是 | thesaurus | -- |
| Snowflake | -- | -- | -- |
| BigQuery | -- | -- | -- |
| DuckDB | -- | -- | -- |
| ClickHouse | -- | -- | -- |
| Greenplum / TimescaleDB / YugabyteDB / CockroachDB | 是 | 同 PG | -- |
| SingleStore | 是 | analyzer JSON | Lucene synonym filter |
| StarRocks | -- | -- | -- |
| Doris | -- | -- | -- |
| CrateDB | 是 | analyzer JSON | Lucene synonym graph |
| SAP HANA | 是 | TA dictionary | -- |
| Informix | 是 | -- | -- |
| H2 | 是 | -- | Lucene |
| 其他 | -- | -- | -- |

### 小写化 / 重音符号去除 (Lowercase, ASCII folding)

| 引擎 | Lowercase | Accent folding | 备注 |
|------|-----------|---------------|------|
| PostgreSQL | 是 | 扩展 | `unaccent` 扩展 |
| MySQL | 是 | -- | 依赖 collation |
| MariaDB | 是 | -- | 依赖 collation |
| SQLite | 是 | 是 | unicode61 `remove_diacritics=2` |
| Oracle | 是 | 是 | `BASIC_LEXER base_letter` |
| SQL Server | 是 | 依赖 collation | -- |
| DB2 | 是 | 是 | -- |
| Snowflake | 是 | 是 | analyzer 强制 NFKC |
| BigQuery | 是 | 是 | `token_filters: ascii_folding`、`lower_case` |
| DuckDB | 是 | -- | -- |
| ClickHouse | 是 | 是 | `lowerUTF8`、`stripUTF8` |
| 其他主流 (CrateDB / SingleStore / SAP HANA / Doris / StarRocks / DatabendDB / Spanner / H2) | 是 | 是 | Lucene 风格 |
| Greenplum / TimescaleDB / YugabyteDB / CockroachDB | 是 | 扩展 | 继承 PG |
| 其他 | 是 | -- | 通常依赖 collation |

### 自定义 analyzer pipeline (用户可定义完整 char_filter + tokenizer + filter chain)

| 引擎 | 自定义 pipeline | 配置方式 | 难度 |
|------|---------------|---------|------|
| PostgreSQL | 是 | `CREATE TEXT SEARCH CONFIGURATION` | 中 |
| MySQL | 部分 | 仅可替换 parser plugin | 高 (写 C plugin) |
| MariaDB | 部分 | 同 MySQL | 高 |
| SQLite | 是 | C API 注册自定义 tokenizer | 高 |
| Oracle | 是 | `CTX_DDL.CREATE_PREFERENCE` | 中 |
| SQL Server | 部分 | 仅替换语言 word breaker | 高 |
| DB2 | 是 | Text Search 配置 | 中 |
| Snowflake | -- | 仅默认 analyzer (2024) | -- |
| BigQuery | 是 | `CREATE SEARCH INDEX ... OPTIONS(analyzer=..., analyzer_options=...)` | 低 |
| DuckDB | 部分 | `PRAGMA create_fts_index(...stemmer, stopwords, ignore, strip_accents, lower)` | 低 |
| ClickHouse | -- | 仅函数组合 | -- |
| SingleStore | 是 | JSON analyzer 定义 | 低 |
| StarRocks | 部分 | 索引属性 | 低 |
| Doris | 部分 | 索引属性 | 低 |
| CrateDB | 是 | Lucene 完整 analyzer | 低 |
| SAP HANA | 是 | TA configuration XML | 中 |
| Informix | 是 | bts.params | 中 |
| H2 | 是 | Lucene | 中 |
| Spanner | 部分 | search options | 低 |
| 其他 | -- | -- | -- |

### 字符过滤器 (HTML strip / character mapping)

| 引擎 | HTML strip | char mapping | 备注 |
|------|-----------|-------------|------|
| PostgreSQL | -- | -- | 应用层 |
| Oracle | 是 | 是 | `HTML_SECTION_GROUP`、`USER_FILTER` |
| SQL Server | 是 | -- | iFilter (HTML/PDF/Office) |
| DB2 | 是 | 是 | document filter |
| BigQuery | -- | -- | -- |
| Snowflake | -- | -- | -- |
| SingleStore | 是 | 是 | Lucene char_filter |
| CrateDB | 是 | 是 | Lucene char_filter |
| SAP HANA | 是 | 是 | TA + IFilter |
| Informix | 是 | 是 | bts external filter |
| H2 | 是 | -- | Lucene |
| 其他 | -- | -- | -- |

### Token filter chain (按顺序应用多个 filter)

| 引擎 | 链式 filter | 备注 |
|------|-----------|------|
| PostgreSQL | 是 | dictionary chain，按 `ALTER TEXT SEARCH CONFIGURATION ... ADD MAPPING` 顺序 |
| Oracle | 是 | preference chain |
| SQL Server | 部分 | 顺序固定 |
| BigQuery | 是 | `analyzer_options` 数组 |
| DuckDB | 部分 | 函数参数组合 |
| SingleStore / CrateDB / SAP HANA / H2 | 是 | Lucene token filter chain |
| StarRocks / Doris / DatabendDB | 部分 | 索引属性 |
| 其他 | -- | -- |

## 详细引擎实现

### PostgreSQL: 字典链与 CONFIGURATION 模型

PostgreSQL 自 8.3 (2008) 把 tsearch2 contrib 模块吸收进核心，引入 `tsvector` 和 `tsquery` 类型。它的 analyzer 模型与 Lucene 截然不同：tsvector 解析过程是 **parser → token type → dictionary chain**。

```sql
-- 查看默认 english 配置的字典映射
SELECT alias, dictionaries
FROM ts_debug('english', 'The quick brown foxes are jumping');

-- 创建一个自定义 simple_chinese 配置 (假设已安装 zhparser)
CREATE EXTENSION zhparser;
CREATE TEXT SEARCH CONFIGURATION simple_chinese (PARSER = zhparser);
ALTER TEXT SEARCH CONFIGURATION simple_chinese
  ADD MAPPING FOR n,v,a,i,e,l WITH simple;

-- 使用
SELECT to_tsvector('simple_chinese', '我爱北京天安门');
-- '北京':2 '天安门':3 '我':0 '爱':1 (示意)
```

PostgreSQL 内置的核心字典类型有四种：

1. **simple** 字典：把 token 简单小写化、查停用词、不做词形还原
2. **synonym** 字典：单向同义词替换 (postgres -> postgresql)
3. **thesaurus** 字典：多对多短语级同义词
4. **ispell / snowball** 字典：基于 Ispell 词典或 Snowball 词干算法

字典链的关键语义：每个 token 依次穿过映射字典，**任一字典返回 NULL 表示停用**，**任一字典返回非空表示词形已确定**，后续字典不再处理。这种设计让 `synonym -> ispell -> snowball` 这种顺序可以先做精确替换，再退化到形态分析。

PostgreSQL 生态中常见的中文/前缀/相似度扩展：

| 扩展 | 用途 | 实现 |
|------|------|------|
| `pg_trgm` | 三元组相似度、前缀通配 | trigram 倒排 |
| `pg_bigm` | 二元组 (适合 CJK) | bigram GIN |
| `zhparser` | 中文分词 | SCWS (Hightman) |
| `pg_jieba` | 中文分词 | jieba C++ port |
| `pgroonga` | 多语言 (含 Mroonga MeCab) | Groonga 引擎 |
| `RUM` | 改进的 GIN，支持距离与排序 | -- |

`RUM` 索引相比 GIN 把 token 位置信息存进倒排表，从而支持 `tsvector @@ tsquery ORDER BY tsvector <=> tsquery` 这种带相关性距离的排序，无需在 heap 上重排。

### MySQL: 内置 ngram parser 与 MeCab 插件

MySQL 5.7.6 在 InnoDB FTS 中加入了 `ngram` parser，专门为 CJK 设计。它没有任何"分词智能"，只是按字符滑窗切 n-gram：

```sql
CREATE TABLE articles (
  id INT PRIMARY KEY,
  body TEXT,
  FULLTEXT INDEX idx_body (body) WITH PARSER ngram
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 控制 n 的大小 (默认 2)
SET GLOBAL innodb_ft_min_token_size = 1;
-- 实际上 ngram 索引使用 ngram_token_size
SET GLOBAL ngram_token_size = 2;  -- 启动参数

INSERT INTO articles VALUES
  (1, '我爱北京天安门'),
  (2, '北京欢迎你');

SELECT * FROM articles
WHERE MATCH(body) AGAINST('北京' IN BOOLEAN MODE);
```

ngram 的优点是无字典依赖、零维护；缺点是索引膨胀严重 (一个 1MB 的中文文档生成的 bigram 索引接近 2MB)，而且无法处理短语级语义。

对于日文，MySQL 提供 **MeCab** 插件 (5.7.6+)，需要单独编译加载：

```sql
-- 在 my.cnf 中
-- plugin-load-add=libpluginmecab.so
-- loose-mecab-rc-file=/etc/mecabrc

INSTALL PLUGIN mecab SONAME 'libpluginmecab.so';

CREATE TABLE jp_articles (
  id INT PRIMARY KEY,
  body TEXT,
  FULLTEXT INDEX idx_body (body) WITH PARSER mecab
) ENGINE=InnoDB;
```

MeCab 是日本京都大学开发的形态素解析器，使用 IPA 词典做日文分词，质量远好于 ngram。MySQL 不提供中文 jieba 插件，社区有第三方 `mysql-fulltext-jieba` 项目但维护不活跃。

### Oracle Text: 多语言 lexer 家族

Oracle Text (前身 ConText / interMedia Text) 自 9i 起就提供了世界上最全面的 SQL 数据库内 FTS 实现之一。它的 analyzer 概念叫 **preference**，包含 datastore、filter、section group、lexer、wordlist、stoplist 等组件。

```sql
-- 创建一个中文 lexer preference
BEGIN
  CTX_DDL.CREATE_PREFERENCE('my_chinese_lexer', 'CHINESE_VGRAM_LEXER');
END;
/

-- 创建索引使用该 lexer
CREATE INDEX articles_idx ON articles(body)
  INDEXTYPE IS CTXSYS.CONTEXT
  PARAMETERS ('LEXER my_chinese_lexer');

SELECT id FROM articles
WHERE CONTAINS(body, '北京') > 0;
```

Oracle 的 lexer 家族：

| Lexer | 用途 |
|-------|------|
| `BASIC_LEXER` | 西方语言 (空格分隔)，含 stem/theme/index_themes |
| `MULTI_LEXER` | 多语言混合，根据语言列分发 |
| `CHINESE_VGRAM_LEXER` | 中文 v-gram (类 bigram) |
| `CHINESE_LEXER` | 基于词典的中文分词 (10g+) |
| `JAPANESE_VGRAM_LEXER` | 日文 v-gram |
| `JAPANESE_LEXER` | 基于词典的日文 (10g+) |
| `KOREAN_MORPH_LEXER` | 韩文形态分析 |
| `WORLD_LEXER` | 自动语言识别 + 多脚本 (11g+) |
| `AUTO_LEXER` | 12c 引入，自动训练词典 |
| `USER_LEXER` | 用户实现 (PL/SQL 回调) |

`USER_LEXER` 是 Oracle 唯一允许在 SQL 引擎里直接 hook PL/SQL 回调做分词的机制，可以接入任意第三方分词器 (例如调用 Java 实现的 jieba)。

### SQL Server Full-Text Search: 语言包安装

SQL Server FTS 的 word breaker 和 stemmer 按语言以 DLL 形式打包，称为 "language pack"。安装 SQL Server 时只默认安装少数几种主流语言 (English、German、French)，**中文/日文/韩文需要单独安装**。

```sql
-- 查看可用语言
SELECT * FROM sys.fulltext_languages;

-- 创建一个中文全文索引
CREATE FULLTEXT CATALOG ft_catalog;

CREATE FULLTEXT INDEX ON articles(body LANGUAGE 2052)  -- 2052 = 简体中文
  KEY INDEX pk_articles ON ft_catalog;

SELECT id FROM articles
WHERE CONTAINS(body, '"北京"');
```

SQL Server 同时支持 thesaurus (按语言一个 XML 文件，例如 `tsZHS.xml`) 和 stoplist (`CREATE FULLTEXT STOPLIST`)。它的 word breaker 实现是闭源的 (源自 MSR 在 1990s 开发的 LSpace)，质量在英文场景非常好，CJK 场景中规中矩。

### SQLite FTS5: unicode61 / porter / ascii / trigram

SQLite FTS5 (3.9+) 相比 FTS4 几乎重写了 tokenizer 接口。内置四种：

| Tokenizer | 用途 |
|-----------|------|
| `unicode61` | Unicode 6.1 字符类切分 + 可选 ASCII 折叠 |
| `ascii` | 仅 ASCII，速度最快 |
| `porter` | 在 unicode61 之上叠加 Porter 词干 |
| `trigram` (3.34+) | 三元组，支持 LIKE 加速与 CJK |

```sql
CREATE VIRTUAL TABLE docs USING fts5(
  body,
  tokenize = "unicode61 remove_diacritics 2"
);

CREATE VIRTUAL TABLE cn_docs USING fts5(
  body,
  tokenize = "trigram"
);

INSERT INTO cn_docs VALUES('我爱北京天安门');
SELECT * FROM cn_docs WHERE cn_docs MATCH '北京';
```

`remove_diacritics 2` 是 3.27 引入的更准确的 Unicode 重音剥离 (相比 `1` 解决了一些组合字符 bug)。**trigram tokenizer 是 SQLite 在 CJK 场景下的事实标准**，但它会把任何查询都转成至少 3 字符的子串，因此查 "中" 这样的单字符无效。

### Elasticsearch / OpenSearch (参考)

虽然 Elasticsearch/OpenSearch 不是 SQL 数据库，但它们的 analyzer 模型 (char_filter -> tokenizer -> filter chain) 已经成为业界事实标准，CrateDB、SingleStore、StarRocks、Doris 等的 analyzer 设计都明显借鉴了 Lucene。一个典型的 ES analyzer 定义：

```json
{
  "settings": {
    "analysis": {
      "char_filter": {
        "html_strip_filter": { "type": "html_strip" }
      },
      "tokenizer": {
        "my_ik": { "type": "ik_max_word" }
      },
      "filter": {
        "my_synonyms": {
          "type": "synonym_graph",
          "synonyms": ["pg, postgres, postgresql"]
        }
      },
      "analyzer": {
        "my_analyzer": {
          "type": "custom",
          "char_filter": ["html_strip_filter"],
          "tokenizer": "my_ik",
          "filter": ["lowercase", "asciifolding", "my_synonyms"]
        }
      }
    }
  }
}
```

ES 的 IK 分词器是中文场景使用最广的开源实现之一，提供 `ik_smart` (粗粒度) 和 `ik_max_word` (细粒度) 两种切分模式。

### ClickHouse: 函数式分词与 tokenbf_v1 索引

ClickHouse 没有"全文索引"概念 (直到 23.x 加入实验性 `full_text` 索引)，但提供了一系列 **tokenization 函数** 和 **bloom filter skip index**。

```sql
-- 字符串切分函数
SELECT tokens('hello, world!');
-- ['hello', 'world']

SELECT splitByNonAlpha('foo-bar.baz');
-- ['foo', 'bar', 'baz']

SELECT ngrams('北京欢迎你', 2);
-- ['北京', '京欢', '欢迎', '迎你']

-- tokenbf_v1 跳数索引 (v19.6+，2019)
CREATE TABLE logs (
  ts DateTime,
  message String,
  INDEX idx_msg message TYPE tokenbf_v1(8192, 3, 0) GRANULARITY 1
) ENGINE = MergeTree ORDER BY ts;

-- 查询时索引会用 tokens() 切分
SELECT * FROM logs WHERE hasToken(message, 'error');

-- ngrambf_v1 适合 CJK
ALTER TABLE logs ADD INDEX idx_ng message TYPE ngrambf_v1(3, 256, 2, 0) GRANULARITY 1;
```

`tokenbf_v1` 把每个 granule 内出现过的 token 哈希进一个 Bloom filter。`hasToken()`、`hasTokenCaseInsensitive()` 谓词可以利用它跳过 granule。`ngrambf_v1` 是字符 n-gram 版本，参数 `(n, filter_size, num_hashes, seed)`。

ClickHouse 23.x 之后开始引入正式的 `full_text` 索引 (基于 tantivy/Lucene 风格)，但仍然实验性。

### Snowflake SEARCH 函数 (2024)

Snowflake 在 2023 年底以 PrPr 形式、2024 年中以 GA 形式推出 `SEARCH()` 函数和 `SEARCH OPTIMIZATION` 服务。它的 analyzer 不暴露给用户配置，内部使用一个统一的多语言 analyzer (基于 ICU)。

```sql
-- 启用 search optimization
ALTER TABLE articles ADD SEARCH OPTIMIZATION ON SUBSTRING(body);

-- 使用 SEARCH 函数
SELECT * FROM articles
WHERE SEARCH(body, 'Snowflake performance');

SELECT * FROM articles
WHERE SEARCH((title, body), '北京 天安门');
```

Snowflake SEARCH 自动处理 CJK n-gram、大小写、ASCII 折叠，但不允许用户自定义 stopwords 或 synonyms——这是一个有意的"开箱即用"取舍，与 Snowflake 的整体哲学一致。

### BigQuery SEARCH 函数 + 可配置 analyzer

BigQuery 2023 年推出 `SEARCH()` 函数和 `CREATE SEARCH INDEX`，并且 **允许用户选择 analyzer 与 token filter**：

```sql
CREATE SEARCH INDEX articles_idx
ON dataset.articles(ALL COLUMNS)
OPTIONS (
  analyzer = 'LOG_ANALYZER',
  analyzer_options = '''{
    "token_filters": [
      { "lower_case": {} },
      { "ascii_folding": {} },
      { "stop_words": ["the", "a", "an"] }
    ]
  }'''
);

SELECT * FROM dataset.articles
WHERE SEARCH(body, '`error` OR `warning`');
```

可选 analyzer：

- `LOG_ANALYZER`：默认，针对日志型数据 (按非字母数字切分)
- `PATTERN_ANALYZER`：按用户提供的正则切分
- `NO_OP_ANALYZER`：精确匹配整个值

这是公共云数仓里**唯一允许用户配置 token filter 链**的 SEARCH 实现 (Snowflake 不允许，Redshift 没有)。

### TiDB: 长期没有内置 FTS

TiDB 直到 8.4 (2024) 才开始引入实验性的全文索引，此前一直没有内置 FTS：

- 替代方案 1：把 TiDB 数据通过 TiCDC 同步到 Elasticsearch
- 替代方案 2：使用 `LIKE '%xx%'` (全表扫描)
- 替代方案 3：使用 TiFlash 列存做模糊查询

8.4 实验性的全文索引仅支持 ngram parser，能力远不如 MySQL 的 InnoDB FTS。

### Manticore Search

Manticore Search (Sphinx 的活跃 fork) 提供 SQL 接口 (MySQL 协议)，并且是少数把 **完整 analyzer pipeline 暴露在 SQL 层** 的搜索引擎：

```sql
CREATE TABLE articles (
  id BIGINT,
  title TEXT,
  body TEXT
) charset_table='cjk, U+4E00..U+9FFF'
  morphology='stem_en, libstemmer_zh_jieba'
  min_word_len=1
  ngram_chars='cjk'
  ngram_len=2
  html_strip=1
  html_remove_elements='style, script';
```

Manticore 内置了 libstemmer 全套 Snowball stemmer、jieba 中文分词、ICU 段落切分，是开源 SQL 全文搜索里 CJK 能力最强的之一。

## PostgreSQL tsvector / tsquery 深入

`tsvector` 是 PostgreSQL FTS 的核心数据类型，本质是一个 sorted set of (lexeme, position[]) 对。

```sql
SELECT 'a fat cat sat on a mat'::tsvector;
-- 'a' 'cat' 'fat' 'mat' 'on' 'sat'

SELECT to_tsvector('english', 'a fat cat sat on a mat');
-- 'cat':3 'fat':2 'mat':7 'sat':4

-- 注意区别：
--   普通 cast 不应用 analyzer，只是按空格切分
--   to_tsvector 应用配置 (停用词、词形还原、位置标记)
```

`tsquery` 是查询侧表达式，支持 `&`、`|`、`!`、`<->` (FOLLOWED BY) 操作符：

```sql
SELECT to_tsvector('english', 'PostgreSQL is a powerful database') @@
       to_tsquery('english', 'powerful & database');
-- t

SELECT to_tsvector('english', 'the quick brown fox') @@
       phraseto_tsquery('english', 'quick brown');
-- t (phraseto_tsquery 自动用 <-> 连接)
```

`CREATE TEXT SEARCH CONFIGURATION` 是定义 analyzer 的入口：

```sql
-- 完整自定义流程
CREATE TEXT SEARCH DICTIONARY my_synonyms (
  TEMPLATE = synonym,
  SYNONYMS = my_synonyms_file  -- $SHAREDIR/tsearch_data/my_synonyms_file.syn
);

CREATE TEXT SEARCH DICTIONARY my_stop (
  TEMPLATE = simple,
  STOPWORDS = my_stop_file
);

CREATE TEXT SEARCH CONFIGURATION my_cfg (COPY = english);

ALTER TEXT SEARCH CONFIGURATION my_cfg
  ALTER MAPPING FOR asciiword, word
  WITH my_synonyms, my_stop, english_stem;

-- 持久化为表的默认配置
ALTER DATABASE mydb SET default_text_search_config = 'my_cfg';
```

字典链顺序至关重要：先做 synonym (精确替换)，再做 stop (剔除停用词)，最后做 stem (退化形态)。颠倒顺序会导致同义词无法匹配 stop list 之前的形态。

## 中文分词器对比

中文场景下，PostgreSQL 用户面临四种主流方案，没有一个是绝对的最佳选择：

### 算法与词典维度对比

| 维度 | jieba | IK | zhparser (SCWS) | pgroonga (Mroonga) |
|------|-------|-----|----------------|---------------------|
| 算法 | HMM + 前缀树 + Viterbi | 词典正向最大匹配 + 歧义裁决 | 词频统计 + Bi-gram + N-shortest | MeCab 风格双数组 trie |
| 词典 | 35 万词 (开源) | 27 万词 + 量词词典 | 16 万词 (XDB 格式) | IPAdic / mecab-ipadic |
| 新词识别 | 是 (HMM) | 否 (需扩展词典) | 部分 | 否 |
| 多粒度切分 | `cut_all=True` | `ik_max_word` / `ik_smart` | `multi=4` 多模式 | 单一切分 |
| 自定义词典热加载 | 是 | 是 | 需重启 | 是 |
| 数据库集成 | `pg_jieba` (PG)、jieba-mysql 等 | 主要 ES、Lucene、Solr、SingleStore | `zhparser` (PG) | `pgroonga` (PG)、`mroonga` (MySQL) |

### 切分质量举例

输入 "南京市长江大桥"：

| 分词器 | 输出 |
|--------|------|
| jieba 精确模式 | 南京市 / 长江大桥 |
| jieba 全模式 | 南京 / 南京市 / 京市 / 市长 / 长江 / 长江大桥 / 大桥 |
| IK ik_smart | 南京市 / 长江大桥 |
| IK ik_max_word | 南京市 / 南京 / 市长 / 长江大桥 / 长江 / 大桥 |
| zhparser 默认 | 南京市 / 长江 / 大桥 |
| zhparser short | 南京 / 市 / 长江 / 大桥 |
| pgroonga (TokenMecab) | 南京 / 市 / 長江 / 大橋 (繁体词典) |
| MySQL ngram (n=2) | 南京 / 京市 / 市长 / 长江 / 江大 / 大桥 |

输入 "结婚的和尚未结婚的"：

| 分词器 | 输出 |
|--------|------|
| jieba 精确 | 结婚 / 的 / 和 / 尚未 / 结婚 / 的 |
| IK ik_smart | 结婚 / 的 / 和尚 / 未 / 结婚 / 的 |
| zhparser | 结婚 / 的 / 和 / 尚未 / 结婚 / 的 |

可以看到 IK 在这个经典歧义句上做出了"和尚"的错误切分，jieba 和 zhparser 正确。这种差异在搜索场景里直接体现为召回率：用 IK 索引过的文档无法被"和尚未结婚"的查询正确召回。

### 选型建议

- **PostgreSQL + 中文要求高**：`pg_jieba` (质量) 或 `pgroonga` (功能全)
- **PostgreSQL + 仅前缀/相似度**：`pg_bigm` (无词典依赖、维护成本最低)
- **MySQL/MariaDB**：内置 ngram，简单可靠但召回率低
- **混合 ES 场景**：用 IK，与 ES 生态打通
- **完全云上**：BigQuery SEARCH 或 Snowflake SEARCH，不要折腾分词器

## 关键发现

1. **没有 SQL 标准**。SQL:2003/2016 全文检索章节只规定了 `CONTAINS()` 等查询函数语法，从未涉及 analyzer 层面。每家数据库的 analyzer 配置语法都是 vendor-specific，几乎没有可移植性。

2. **PostgreSQL 是 SQL 引擎里 analyzer 模型设计最好的之一**。tsearch2 的"字典链"模型 (synonym → stop → stem 顺序传递) 比 Lucene 的 token filter chain 更易理解，并且字典本身可以动态替换。但它不内置 CJK 分词器，必须依赖 `zhparser`、`pg_jieba`、`pgroonga` 等扩展。

3. **MySQL ngram parser 是"够用就好"的典范**。零配置、零词典维护、跨语言通用，但牺牲了召回精度和索引体积。MySQL 至今没有内置中文分词器是一个长期被诟病的问题。

4. **Oracle Text 拥有最完整的 lexer 家族**。`CHINESE_LEXER`、`JAPANESE_LEXER`、`KOREAN_MORPH_LEXER`、`AUTO_LEXER` 覆盖所有主流语言，并且支持 `USER_LEXER` 回调到 PL/SQL，是商业 SQL 数据库里 FTS 能力最强的。

5. **SQL Server 的语言包模式**给运维带来了隐性成本：默认安装不含 CJK，需要额外下载 language pack 并重启服务。这是企业部署 SQL Server 做中文搜索时最常踩的坑。

6. **SQLite FTS5 trigram tokenizer (3.34+) 改变了嵌入式 CJK 搜索格局**。在它出现之前，SQLite 几乎无法做中文搜索；现在哪怕是手机端的笔记应用也能用 SQLite 实现基本的中文模糊检索。

7. **云数仓里 BigQuery 是唯一允许配置 token filter 链的**。Snowflake SEARCH (2024) 和 Redshift 都把 analyzer 隐藏在内部，BigQuery 的 `analyzer_options` JSON 是云数仓里少数的 escape hatch。

8. **ClickHouse 走的是"函数化分词 + Bloom filter skip index"路线**。`tokenbf_v1` 和 `ngrambf_v1` 不是真正的倒排索引，而是 granule 级别的 Bloom filter，适合"日志中是否出现某个 token"这类点查，不适合相关性排序。

9. **新一代 OLAP 引擎 (StarRocks / Doris / DatabendDB) 都把 jieba 列为标准能力**。StarRocks 2.5、Doris 2.0、DatabendDB 1.2 都内置了基于 CLucene 的倒排索引，并集成 jieba 作为中文分词器，反映出国内 OLAP 厂商对中文场景的优先级。

10. **"自定义 analyzer pipeline"在 SQL 数据库里仍是少数派能力**。完整支持 char_filter + tokenizer + filter chain 的 SQL 引擎不超过 10 个 (CrateDB、SingleStore、SAP HANA、Informix、H2、Oracle Text、PostgreSQL tsearch2 部分支持、BigQuery 部分支持)。绝大多数引擎只允许在固定模板里替换组件。

11. **TiDB、Spark SQL、Trino、Presto、Flink SQL、Materialize、RisingWave 等"现代分布式 SQL"都没有内置 FTS**。这反映了分布式查询引擎的设计哲学：把全文搜索留给专门的搜索系统 (ES/OpenSearch)，通过 connector 联邦查询而不是内嵌实现。

12. **49 个引擎里，约 26 个支持某种形式的 tokenizer 配置，约 23 个完全不支持或仅有 LIKE/正则**。FTS 仍然是 SQL 生态里碎片化最严重的功能领域之一，远比窗口函数、JSON、GIS 等更不统一。
