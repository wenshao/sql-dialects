# OceanBase: 复合类型

> 参考资料:
> - [OceanBase 文档 - JSON 数据类型](https://www.oceanbase.com/docs/common-oceanbase-database-cn-1000000001577240)
> - [OceanBase 文档 - JSON 函数](https://www.oceanbase.com/docs/common-oceanbase-database-cn-1000000001577241)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## OceanBase 没有原生 ARRAY / MAP / STRUCT 类型

MySQL 兼容模式使用 JSON，Oracle 兼容模式使用集合类型
MySQL 兼容模式 — JSON
```sql
CREATE TABLE users (
    id       BIGINT AUTO_INCREMENT PRIMARY KEY,
    name     VARCHAR(100) NOT NULL,
    tags     JSON,
    metadata JSON
);

INSERT INTO users (name, tags) VALUES
    ('Alice', JSON_ARRAY('admin', 'dev')),
    ('Bob',   '["user", "tester"]');

SELECT JSON_EXTRACT(tags, '$[0]') FROM users;
SELECT tags->'$[0]' FROM users;
SELECT JSON_LENGTH(tags) FROM users;
SELECT * FROM users WHERE JSON_CONTAINS(tags, '"admin"');

UPDATE users SET metadata = JSON_OBJECT('city', 'NYC') WHERE id = 1;
SELECT JSON_VALUE(metadata, '$.city') FROM users;
SELECT JSON_KEYS(metadata) FROM users;

```

聚合
```sql
SELECT JSON_ARRAYAGG(name) FROM users;

```

## Oracle 兼容模式 — 集合类型


VARRAY / Nested Table / Object Type
兼容 Oracle 语法，参见 oracle.sql 和 dameng.sql

## 注意事项


## 不支持原生 ARRAY / MAP / STRUCT 表列类型

## MySQL 模式使用 JSON

## Oracle 模式使用 VARRAY / Nested Table / Object Type

## JSON 函数兼容 MySQL 语法
