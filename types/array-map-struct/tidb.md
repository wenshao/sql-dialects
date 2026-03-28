# TiDB: 复合类型

> 参考资料:
> - [TiDB Documentation - JSON Type](https://docs.pingcap.com/tidb/stable/data-type-json)
> - [TiDB Documentation - JSON Functions](https://docs.pingcap.com/tidb/stable/json-functions)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

## TiDB 没有原生 ARRAY / MAP / STRUCT 类型

使用 JSON 类型替代（兼容 MySQL JSON）
```sql
CREATE TABLE users (
    id       BIGINT AUTO_INCREMENT PRIMARY KEY,
    name     VARCHAR(100) NOT NULL,
    tags     JSON,
    metadata JSON
);

```

JSON 数组
```sql
INSERT INTO users (name, tags) VALUES
    ('Alice', JSON_ARRAY('admin', 'dev')),
    ('Bob',   '["user", "tester"]');

SELECT JSON_EXTRACT(tags, '$[0]') FROM users;
SELECT tags->'$[0]' FROM users;
SELECT tags->>'$[0]' FROM users;
SELECT JSON_LENGTH(tags) FROM users;
SELECT * FROM users WHERE JSON_CONTAINS(tags, '"admin"');
SELECT * FROM users WHERE 'admin' MEMBER OF(tags);           -- TiDB 6.5+

```

JSON 对象
```sql
UPDATE users SET metadata = JSON_OBJECT('city', 'NYC', 'settings', JSON_OBJECT('theme', 'dark'))
WHERE id = 1;
SELECT JSON_VALUE(metadata, '$.city') FROM users;            -- TiDB 6.1+
SELECT JSON_KEYS(metadata) FROM users;

```

JSON_TABLE（TiDB 7.1+）
```sql
SELECT u.name, jt.tag
FROM users u,
JSON_TABLE(u.tags, '$[*]' COLUMNS (tag VARCHAR(50) PATH '$')) AS jt;

```

聚合
```sql
SELECT department, JSON_ARRAYAGG(name) FROM employees GROUP BY department;
SELECT JSON_OBJECTAGG(name, salary) FROM employees;

```

多值索引（TiDB 6.6+）
```sql
CREATE TABLE products (id BIGINT PRIMARY KEY, tags JSON);
CREATE INDEX idx_tags ON products ((CAST(tags AS CHAR(50) ARRAY)));
SELECT * FROM products WHERE 'electronics' MEMBER OF(tags);

```

## 注意事项


## 兼容 MySQL JSON 功能

## 没有原生 ARRAY / MAP / STRUCT 类型

## JSON_TABLE 从 TiDB 7.1 开始支持

## 多值索引从 TiDB 6.6 开始支持

## MEMBER OF 从 TiDB 6.5 开始支持
