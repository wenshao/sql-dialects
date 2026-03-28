# Apache Doris: 字符串拆分为行

Apache Doris: 字符串拆分为行

参考资料:
[1] Doris - explode_split / LATERAL VIEW
https://doris.apache.org/docs/sql-manual/sql-functions/table-functions/

LATERAL VIEW explode_split (推荐，Hive 风格)

```sql
SELECT t.id, t.name, tag
FROM tags_csv t LATERAL VIEW explode_split(t.tags, ',') tmp AS tag;

```

表函数方式

```sql
SELECT t.id, t.name, e.tag
FROM tags_csv t, explode_split(t.tags, ',') AS e(tag);

```

对比:
StarRocks:  UNNEST + SPLIT(SQL 标准风格)
ClickHouse: arrayJoin(splitByChar(',', tags))
BigQuery:   UNNEST(SPLIT(tags, ','))
PostgreSQL: UNNEST(string_to_array(tags, ','))
MySQL:      JSON_TABLE(需先转为 JSON 数组)

