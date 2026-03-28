# MariaDB: 全文搜索

支持 InnoDB FTS 和 Mroonga 引擎

参考资料:
[1] MariaDB Knowledge Base - Full-Text Indexes
https://mariadb.com/kb/en/full-text-indexes/

## 1. InnoDB 全文索引 (同 MySQL)

```sql
CREATE TABLE articles (
    id      BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    title   VARCHAR(255),
    content TEXT,
    FULLTEXT INDEX ft_content (title, content)
) ENGINE=InnoDB;
```


自然语言模式
```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST ('database optimization' IN NATURAL LANGUAGE MODE);
```


布尔模式
```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST ('+database -mysql +optimization' IN BOOLEAN MODE);
```


查询扩展
```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST ('database' WITH QUERY EXPANSION);
```


## 2. Mroonga 全文引擎 (MariaDB 独有)

Mroonga 基于 Groonga 全文搜索引擎, CJK 支持比 InnoDB ngram 更好
```sql
CREATE TABLE articles_mroonga (
    id      BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    title   VARCHAR(255),
    content TEXT,
    FULLTEXT INDEX ft_content (title, content) COMMENT 'tokenizer "TokenBigram"'
) ENGINE=Mroonga DEFAULT CHARSET=utf8mb4;
```

Mroonga 的优势:
1. 原生中日韩分词 (TokenBigram, TokenMecab)
2. 列存储模式 (全文搜索 + 范围查询组合)
3. 实时索引更新 (无 MySQL InnoDB FTS 的延迟问题)
MySQL 对比: 只有 InnoDB FTS + ngram parser, 无等价引擎

## 3. 对引擎开发者: 全文搜索实现

InnoDB FTS 实现:
倒排索引存在辅助表 (FTS_DOC_ID_INDEX 等) 中
增量索引: 新文档先写入 FTS Index Cache, 后台 OPTIMIZE TABLE 合并
删除标记: DELETE 只在 DELETE 辅助表中标记, 不立即删除倒排项
Mroonga 实现:
Groonga 引擎独立维护倒排索引
支持在线索引更新, 无需 OPTIMIZE
可以使用 Wrapper 模式 (Mroonga 包装 InnoDB) 同时获得事务和全文搜索
