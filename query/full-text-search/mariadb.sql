-- MariaDB: Full-Text Search
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- Create fulltext index (same as MySQL, InnoDB and MyISAM)
CREATE FULLTEXT INDEX idx_ft_bio ON users (bio);
CREATE FULLTEXT INDEX idx_ft_multi ON articles (title, content);

-- Natural language mode (same as MySQL)
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('database performance');

-- With relevance score
SELECT title, MATCH(title, content) AGAINST('database performance') AS score
FROM articles
WHERE MATCH(title, content) AGAINST('database performance')
ORDER BY score DESC;

-- Boolean mode (same as MySQL)
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('+database -mysql +performance' IN BOOLEAN MODE);

-- Phrase search
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('"full text search"' IN BOOLEAN MODE);

-- Query expansion
SELECT * FROM articles
WHERE MATCH(title, content) AGAINST('database' WITH QUERY EXPANSION);

-- Mroonga storage engine: superior CJK full-text search (bundled with MariaDB)
-- Mroonga provides better tokenization for Chinese, Japanese, Korean
CREATE TABLE articles_mroonga (
    id      BIGINT NOT NULL AUTO_INCREMENT,
    title   VARCHAR(255),
    content TEXT,
    PRIMARY KEY (id),
    FULLTEXT INDEX idx_ft (title, content)
) ENGINE=Mroonga DEFAULT CHARSET=utf8mb4;

-- Mroonga: search with weights
SELECT *, MATCH(title) AGAINST('database') * 10 +
          MATCH(content) AGAINST('database') AS weighted_score
FROM articles_mroonga
WHERE MATCH(title, content) AGAINST('database')
ORDER BY weighted_score DESC;

-- Mroonga: snippet function (return highlighted matches)
SELECT id, mroonga_snippet_html(content, 'database') AS snippet
FROM articles_mroonga
WHERE MATCH(content) AGAINST('database');

-- Mroonga: escape function for user input
SELECT mroonga_escape('user+input-with*special');

-- InnoDB fulltext: minimum token configuration
-- innodb_ft_min_token_size = 3 (default, same as MySQL)
-- MariaDB-specific: innodb_ft_ignore_stopwords (10.5+)

-- FULLTEXT index with parser (same as MySQL, ngram available)
CREATE FULLTEXT INDEX idx_ft_cjk ON articles (content) WITH PARSER ngram;

-- SphinxSE engine: integration with Sphinx search engine (MariaDB-specific)
-- Allows querying a Sphinx search daemon directly from SQL
CREATE TABLE sphinx_search (
    id     BIGINT NOT NULL,
    weight INT NOT NULL,
    query  VARCHAR(3072) NOT NULL,
    INDEX(query)
) ENGINE=SPHINX CONNECTION="sphinx://localhost:9312/idx_articles";

SELECT * FROM sphinx_search WHERE query = 'database performance';

-- Differences from MySQL 8.0:
-- Mroonga engine bundled (excellent CJK support, not in MySQL)
-- SphinxSE engine for Sphinx integration (MariaDB-specific)
-- mroonga_snippet_html() for search result highlighting
-- Same InnoDB fulltext capabilities as MySQL
-- Different minimum token size defaults may apply
-- No MySQL 8.0 data dictionary changes affect fulltext behavior
