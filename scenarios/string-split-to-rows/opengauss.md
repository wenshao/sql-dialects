# openGauss: 将分隔字符串拆分为多行 (String Split to Rows)

> 参考资料:
> - [openGauss Documentation](https://docs.opengauss.org/)
> - openGauss 兼容 PostgreSQL 语法


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

## 方法 1: STRING_TO_ARRAY + UNNEST（推荐，兼容 PostgreSQL）

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
