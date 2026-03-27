-- MariaDB: Indexes
-- MariaDB is a MySQL fork; only differences from MySQL are shown here.
--
-- 参考资料:
--   [1] MariaDB Knowledge Base
--       https://mariadb.com/kb/en/documentation/
--   [2] MariaDB vs MySQL Compatibility
--       https://mariadb.com/kb/en/mariadb-vs-mysql-compatibility/

-- Basic indexes (same as MySQL)
CREATE INDEX idx_age ON users (age);
CREATE UNIQUE INDEX uk_email ON users (email);
CREATE INDEX idx_city_age ON users (city, age);
CREATE INDEX idx_email_prefix ON users (email(20));

-- Fulltext index (same as MySQL, InnoDB + MyISAM + Mroonga)
CREATE FULLTEXT INDEX idx_ft_bio ON users (bio);

-- Spatial index (same as MySQL)
CREATE SPATIAL INDEX idx_location ON places (geo_point);

-- Descending index (10.8+)
-- Before 10.8, DESC was parsed but ignored (like MySQL 5.7)
CREATE INDEX idx_age_desc ON users (age DESC);

-- IGNORED indexes (10.6+, MariaDB's version of MySQL's INVISIBLE)
-- Different keyword than MySQL: IGNORED instead of INVISIBLE
CREATE INDEX idx_age ON users (age) IGNORED;
ALTER TABLE users ALTER INDEX idx_age NOT IGNORED;
-- Note: MySQL uses INVISIBLE/VISIBLE; MariaDB uses IGNORED/NOT IGNORED

-- Expression index (virtual/persistent computed columns, 10.2+)
-- MariaDB uses virtual columns instead of direct expression indexes
ALTER TABLE users ADD COLUMN upper_name VARCHAR(64) AS (UPPER(username)) PERSISTENT;
CREATE INDEX idx_upper_name ON users (upper_name);
-- 10.5.3+: direct expression indexes (like MySQL 8.0)
CREATE INDEX idx_upper_name ON users ((UPPER(username)));

-- Hash index (MEMORY/HEAP engine only, same as MySQL)
CREATE INDEX idx_hash ON users (username) USING HASH;

-- DROP INDEX with IF EXISTS (available earlier than MySQL)
DROP INDEX IF EXISTS idx_age ON users;

-- Index hints (same as MySQL)
SELECT * FROM users USE INDEX (idx_age) WHERE age > 25;
SELECT * FROM users FORCE INDEX (idx_city_age) WHERE city = 'Beijing';
SELECT * FROM users IGNORE INDEX (idx_age) WHERE age > 25;

-- Optimizer hints for indexes (10.1+)
-- MariaDB has its own optimizer hint syntax
SELECT * FROM users FORCE INDEX FOR JOIN (idx_age) WHERE age > 25;
SELECT * FROM users FORCE INDEX FOR ORDER BY (idx_age) ORDER BY age;

-- Mroonga engine fulltext (CJK-optimized, bundled with MariaDB)
CREATE TABLE articles (
    id      BIGINT NOT NULL AUTO_INCREMENT,
    title   VARCHAR(255),
    content TEXT,
    PRIMARY KEY (id),
    FULLTEXT INDEX idx_ft (title, content)
) ENGINE=Mroonga DEFAULT CHARSET=utf8mb4;

-- View indexes
SHOW INDEX FROM users;
SHOW CREATE TABLE users;

-- Differences from MySQL 8.0:
-- IGNORED/NOT IGNORED instead of INVISIBLE/VISIBLE
-- No multi-valued index (JSON ARRAY index) until later versions
-- Mroonga fulltext engine bundled (not in MySQL)
-- Direct expression indexes added later (10.5.3+)
-- Different optimizer decisions for index usage
