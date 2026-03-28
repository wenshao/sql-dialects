# Trino: 字符串拆分

> 参考资料:
> - [Trino Documentation - String Functions](https://trino.io/docs/current/functions/string.html)
> - [Trino Documentation - UNNEST](https://trino.io/docs/current/sql/select.html#unnest)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

## 示例数据

Trino 使用 VALUES 子句或从已有数据源查询
CREATE TABLE tags_csv AS
SELECT * FROM (VALUES (1,'Alice','python,java,sql'),
                      (2,'Bob','go,rust'),
                      (3,'Carol','sql,python,javascript,typescript'))
         AS t(id, name, tags);

## 方法 1: CROSS JOIN UNNEST + split（推荐）

```sql
SELECT t.id, t.name, tag
FROM   tags_csv t
CROSS JOIN UNNEST(split(t.tags, ',')) AS x(tag);

```

## 方法 2: UNNEST 带序号

```sql
SELECT t.id, t.name, tag, pos
FROM   tags_csv t
CROSS JOIN UNNEST(split(t.tags, ','))
           WITH ORDINALITY AS x(tag, pos);

```

## 方法 3: regexp_extract_all + UNNEST

```sql
SELECT t.id, t.name, tag
FROM   tags_csv t
CROSS JOIN UNNEST(regexp_extract_all(t.tags, '[^,]+')) AS x(tag);

```
