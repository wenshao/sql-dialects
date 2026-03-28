# MySQL: 全文搜索

> 参考资料:
> - [MySQL 8.0 Reference Manual - Full-Text Search](https://dev.mysql.com/doc/refman/8.0/en/fulltext-search.html)
> - [MySQL 8.0 Reference Manual - MATCH ... AGAINST](https://dev.mysql.com/doc/refman/8.0/en/fulltext-natural-language.html)
> - [MySQL 8.0 Reference Manual - Boolean Full-Text Search](https://dev.mysql.com/doc/refman/8.0/en/fulltext-boolean.html)

创建全文索引（5.6+ InnoDB，之前只有 MyISAM）
```sql
CREATE FULLTEXT INDEX idx_ft_bio ON users (bio);
CREATE FULLTEXT INDEX idx_ft_multi ON articles (title, content);
```

自然语言模式（默认）
```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('database performance');
```

带相关度分数
```sql
SELECT title, MATCH(title, content) AGAINST('database performance') AS score
FROM articles
WHERE MATCH(title, content) AGAINST('database performance')
ORDER BY score DESC;
```

布尔模式
```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('+database -mysql +performance' IN BOOLEAN MODE);
```

+: 必须包含
-: 必须不包含
*: 通配符（前缀匹配）
"": 短语匹配
>: 增加权重
<: 降低权重

短语搜索
```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('"full text search"' IN BOOLEAN MODE);
```

查询扩展模式（自动扩展相关词）
```sql
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('database' WITH QUERY EXPANSION);
```

最小词长度配置
ft_min_word_len = 4 (MyISAM 默认)
innodb_ft_min_token_size = 3 (InnoDB 默认)

5.7.6+: 支持中文、日文、韩文分词器（ngram）
建表时指定: WITH PARSER ngram
```sql
CREATE FULLTEXT INDEX idx_ft_cjk ON articles (content) WITH PARSER ngram;
```
