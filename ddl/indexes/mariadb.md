# MariaDB: 索引 (Indexes)

与 MySQL 语法基本一致, 关键差异在 IGNORED 索引和特有索引类型

参考资料:
[1] MariaDB Knowledge Base - CREATE INDEX
https://mariadb.com/kb/en/create-index/

## 1. 基本索引类型

```sql
CREATE INDEX idx_age ON users (age);
CREATE UNIQUE INDEX idx_email ON users (email);
CREATE INDEX idx_name_age ON users (username, age);    -- 复合索引
CREATE INDEX idx_bio ON users (bio(100));               -- 前缀索引
```


## 2. IGNORED 索引 (10.6+) -- 对比 MySQL 的 INVISIBLE INDEX

```sql
CREATE INDEX idx_test ON users (age) IGNORED;
ALTER TABLE users ALTER INDEX idx_test NOT IGNORED;
```

功能: 优化器忽略该索引, 但 DML 仍然维护
用途: 安全测试删除索引的影响 (先 IGNORED, 观察, 再 DROP)
关键词差异: MySQL 用 INVISIBLE/VISIBLE, MariaDB 用 IGNORED/NOT IGNORED
这是 fork 后设计分歧的典型案例: 同一功能不同语法

## 3. 全文索引

```sql
CREATE FULLTEXT INDEX ft_bio ON users (bio);
```

MariaDB 默认使用 Mroonga 引擎的全文索引 (如果安装)
Mroonga 是基于 Groonga 的全文搜索引擎, 支持 CJK 分词
**对比 MySQL: InnoDB 全文索引 (5.6+) 对中日韩支持较差 (需要 ngram parser)**


## 4. 空间索引

```sql
CREATE TABLE locations (
    id   INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100),
    pos  POINT NOT NULL SRID 4326,
    SPATIAL INDEX idx_pos (pos)
);
-- MariaDB 与 MySQL 空间索引语法相同, 基于 R-Tree
```


## 5. Hash 索引 (MEMORY/Aria 引擎)

```sql
CREATE TABLE cache_data (
    cache_key VARCHAR(255) NOT NULL,
    cache_val TEXT,
    INDEX USING HASH (cache_key)
) ENGINE=MEMORY;
-- MEMORY 引擎默认 HASH 索引, InnoDB 只支持 B-Tree (自适应 Hash 是内部优化)
```


## 6. 降序索引

MariaDB 10.8+: 真正的降序索引
```sql
CREATE INDEX idx_created_desc ON users (created_at DESC);
```

10.8 之前: DESC 被解析但忽略 (与 MySQL 5.7 行为相同)
MySQL 8.0: 也支持降序索引

## 7. 对引擎开发者: 索引实现差异

MariaDB InnoDB 与 MySQL InnoDB 的索引实现已有差异:
1. MariaDB 的 InnoDB 由 MariaDB 团队独立维护 (从 10.2 开始)
2. 压缩页面格式: MariaDB 10.1+ 独有的页面压缩 (innodb_compression_algorithm)
3. 加密: MariaDB 10.1+ 的表空间加密实现与 MySQL 不同
4. 即时 DDL: 索引元数据的 INSTANT 变更路径不同
两者虽然都叫 InnoDB, 但代码已经显著分叉
