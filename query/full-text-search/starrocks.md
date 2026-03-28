# StarRocks: 全文搜索

> 参考资料:
> - [1] StarRocks Documentation - Index
>   https://docs.starrocks.io/docs/table_design/indexes/


## 1. 全文搜索: 追赶 Doris 的领域

 StarRocks 3.1+ 引入 GIN(Generalized Inverted Index) 索引，
 但比 Doris 2.0 的倒排索引晚约一年。

 GIN 索引 (3.1+):
 CREATE INDEX idx_content ON articles (content) USING GIN;

## 2. Bloom Filter 替代 (早期方案)

在 GIN 索引之前，StarRocks 使用 Bloom Filter 近似全文搜索:

```sql
CREATE TABLE articles (
    id BIGINT NOT NULL, content STRING
) DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 16
PROPERTIES ("bloom_filter_columns" = "content");

```

LIKE 查询(无索引加速):

```sql
SELECT * FROM articles WHERE content LIKE '%database%';

```

## 3. 对比 Doris

Doris 2.0+:
- **INVERTED INDEX**: 真正的倒排索引(CLucene)
- **MATCH_ALL/MATCH_ANY/MATCH_PHRASE**: 专用全文检索语法
chinese/english/unicode 分词器

StarRocks 3.1+:
- **GIN Index**: 倒排索引
功能正在追赶 Doris

对引擎开发者的启示:
全文检索是"分析引擎 vs 搜索引擎"的交叉地带。
Doris 选择集成 CLucene(成熟的搜索库)是务实的决策。
StarRocks 选择自研 GIN 可能在长期有更好的集成度。
- **对比 Elasticsearch**: 专业搜索引擎仍是最优选择，
但 Doris 的倒排索引减少了"分析 + 搜索"双引擎的运维成本。
