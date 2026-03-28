# CockroachDB: 字符串拆分

> 参考资料:
> - [CockroachDB Documentation - String Functions](https://www.cockroachlabs.com/docs/stable/functions-and-operators#string-and-byte-functions)
> - [CockroachDB Documentation - UNNEST](https://www.cockroachlabs.com/docs/stable/functions-and-operators#array-functions)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

## 示例数据

```sql
CREATE TABLE tags_csv (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(100),
    tags VARCHAR(500)
);

INSERT INTO tags_csv (name, tags) VALUES
    ('Alice', 'python,java,sql'),
    ('Bob',   'go,rust'),
    ('Carol', 'sql,python,javascript,typescript');

```

## 方法 1: UNNEST + STRING_TO_ARRAY（推荐，兼容 PostgreSQL）

```sql
SELECT id, name, UNNEST(STRING_TO_ARRAY(tags, ',')) AS tag
FROM   tags_csv;

```

## 方法 2: regexp_split_to_table

```sql
SELECT id, name, regexp_split_to_table(tags, ',') AS tag
FROM   tags_csv;

```

## 方法 3: UNNEST 带序号

```sql
SELECT t.id, t.name, s.tag, s.ordinality
FROM   tags_csv t,
       LATERAL UNNEST(STRING_TO_ARRAY(t.tags, ','))
              WITH ORDINALITY AS s(tag, ordinality);

```
