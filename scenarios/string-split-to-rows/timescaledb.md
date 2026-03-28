# TimescaleDB: 将分隔字符串拆分为多行 (String Split to Rows)

> 参考资料:
> - [TimescaleDB 基于 PostgreSQL，完全兼容其字符串函数](https://www.postgresql.org/docs/current/functions-string.html)
> - [PostgreSQL Documentation - UNNEST](https://www.postgresql.org/docs/current/functions-array.html)


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
