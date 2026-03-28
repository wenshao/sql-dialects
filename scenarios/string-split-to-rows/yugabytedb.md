# YugabyteDB: 字符串拆分

> 参考资料:
> - [YugabyteDB 兼容 PostgreSQL 语法](https://docs.yugabyte.com/latest/api/ysql/)
> - [PostgreSQL String Functions](https://www.postgresql.org/docs/current/functions-string.html)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

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

## 方法 1: STRING_TO_ARRAY + UNNEST（推荐，与 PostgreSQL 完全相同）

```sql
SELECT id, name, UNNEST(STRING_TO_ARRAY(tags, ',')) AS tag
FROM   tags_csv;

```

## 方法 2: regexp_split_to_table

```sql
SELECT id, name, regexp_split_to_table(tags, ',') AS tag
FROM   tags_csv;

```

## 方法 3: LATERAL + UNNEST 带序号

```sql
SELECT t.id, t.name, s.ordinality, s.tag
FROM   tags_csv t,
       LATERAL UNNEST(STRING_TO_ARRAY(t.tags, ','))
              WITH ORDINALITY AS s(tag, ordinality);

```
