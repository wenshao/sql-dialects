# BigQuery: 将分隔字符串拆分为多行 (String Split to Rows)

> 参考资料:
> - [1] BigQuery SQL Reference - SPLIT
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#split
> - [2] BigQuery SQL Reference - UNNEST
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#unnest


## 1. SPLIT + UNNEST（最简洁）


将逗号分隔字符串拆分为多行:

```sql
SELECT value FROM UNNEST(SPLIT('a,b,c,d', ',')) AS value;
```

输出: a, b, c, d

从表中拆分:

```sql
SELECT id, tag
FROM users, UNNEST(SPLIT(tags, ',')) AS tag;

```

保留位置信息:

```sql
SELECT id, tag, pos
FROM users, UNNEST(SPLIT(tags, ',')) AS tag WITH OFFSET AS pos;

```

## 2. SPLIT + UNNEST + 清洗


去除空白:

```sql
SELECT TRIM(value) AS tag
FROM UNNEST(SPLIT('a, b , c, d', ',')) AS value;

```

过滤空值:

```sql
SELECT tag
FROM UNNEST(SPLIT('a,,b,,c', ',')) AS tag
WHERE tag != '';

```

## 3. 拆分 + 聚合


统计每个标签:

```sql
SELECT tag, COUNT(*) AS cnt
FROM users, UNNEST(SPLIT(tags, ',')) AS tag
GROUP BY tag ORDER BY cnt DESC;

```

## 4. REGEXP_EXTRACT_ALL（正则拆分）


提取所有数字:

```sql
SELECT num FROM UNNEST(REGEXP_EXTRACT_ALL('foo123bar456', r'\d+')) AS num;

```

提取所有单词:

```sql
SELECT word FROM UNNEST(REGEXP_EXTRACT_ALL('hello-world_foo', r'[a-zA-Z]+')) AS word;

```

## 5. 设计分析


 BigQuery 的 SPLIT + UNNEST 是最简洁的字符串拆分方案:
   SPLIT('a,b,c', ',') → ['a', 'b', 'c']（返回 ARRAY）
   UNNEST(ARRAY) → 3 行（数组展开为行）
 两步操作，语义清晰。

 对比:
   PostgreSQL: string_to_array('a,b,c', ',') + unnest()（类似）
   ClickHouse: splitByChar(',', 'a,b,c') + arrayJoin()（类似）
   MySQL:      无 SPLIT + UNNEST，需要 JSON_TABLE 或递归 CTE
   SQLite:     无 SPLIT，需要递归 CTE 或 json_each

## 6. 对比与引擎开发者启示

BigQuery 字符串拆分:
SPLIT → 标准函数名
UNNEST → 标准展开语法
REGEXP_EXTRACT_ALL → 正则提取
WITH OFFSET → 保留位置信息

对引擎开发者的启示:
SPLIT + UNNEST 是字符串拆分的最佳设计:
分割和展开分离 → 组合灵活 → 中间结果（数组）可以复用。
WITH OFFSET 是有价值的细节（保留元素在原始数组中的位置）。

