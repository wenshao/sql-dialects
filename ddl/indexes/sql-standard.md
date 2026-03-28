# SQL 标准: 索引

> 参考资料:
> - [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
> - [Modern SQL - by Markus Winand](https://modern-sql.com/)
> - [SQL Standardization History (Wikipedia)](https://en.wikipedia.org/wiki/SQL#Standardization_history)

## SQL 标准中没有索引的定义！

索引完全是各数据库实现的扩展功能
SQL 标准只定义了逻辑约束（PRIMARY KEY, UNIQUE），不规定物理实现

## SQL-92 (SQL2): 约束导致的隐式索引

PRIMARY KEY 和 UNIQUE 约束在大多数实现中会自动创建索引
但标准本身不要求这样做

```sql
CREATE TABLE users (
    id       INTEGER NOT NULL,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255),
    PRIMARY KEY (id),
    UNIQUE (username)
);
```

大多数数据库会自动为 id 和 username 创建索引

## SQL:2003: 标准仍未定义索引

CREATE INDEX 语法在标准中不存在
以下语法是各数据库的通用扩展（非标准）：

事实上的通用语法（大多数数据库支持但非标准）：
CREATE INDEX idx_name ON table_name (column1, column2);
CREATE UNIQUE INDEX idx_name ON table_name (column);
DROP INDEX idx_name;

## 各数据库的 CREATE INDEX 差异

MySQL:     CREATE INDEX idx ON t (col) USING BTREE;
PostgreSQL: CREATE INDEX idx ON t USING gin (col);
Oracle:    CREATE INDEX idx ON t (col) TABLESPACE ts;
SQL Server: CREATE INDEX idx ON t (col) INCLUDE (col2);
SQLite:    CREATE INDEX idx ON t (col);

## 为什么标准不定义索引？

1. 索引是物理存储层的概念，不是逻辑层
2. SQL 标准关注的是"做什么"，不是"怎么做"
3. 不同存储引擎需要不同的索引实现
4. 索引的存在不应影响查询的逻辑结果

## 标准中与索引相关的概念

PRIMARY KEY: 逻辑上要求唯一和非空，大多数实现用 B-tree 索引
UNIQUE: 逻辑上要求唯一，大多数实现用索引来保证
FOREIGN KEY: 大多数实现建议为外键列创建索引

- **注意：CREATE INDEX 不是 SQL 标准的一部分**
- **注意：所有数据库都通过索引优化查询，但语法和能力各不相同**
- **注意：标准只定义逻辑约束，不规定物理实现方式**
- **注意：分析型数据库（BigQuery、Snowflake 等）通常不支持传统索引**
