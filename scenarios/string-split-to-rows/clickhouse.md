# ClickHouse: 将分隔字符串拆分为多行 (String Split to Rows)

> 参考资料:
> - [1] ClickHouse - splitByChar / splitByString
>   https://clickhouse.com/docs/en/sql-reference/functions/splitting-merging-functions
> - [2] ClickHouse - arrayJoin
>   https://clickhouse.com/docs/en/sql-reference/functions/array-join


## 1. splitByChar + arrayJoin（最常用）


将逗号分隔字符串拆分为多行:

```sql
SELECT arrayJoin(splitByChar(',', 'a,b,c,d')) AS value;
```

输出: a, b, c, d

从表中拆分:

```sql
SELECT id, arrayJoin(splitByChar(',', tags)) AS tag
FROM users;

```

splitByString: 支持多字符分隔符

```sql
SELECT arrayJoin(splitByString(', ', 'hello, world, foo')) AS word;

```

splitByRegexp: 正则分隔

```sql
SELECT arrayJoin(splitByRegexp('[,;|]', 'a,b;c|d')) AS value;

```

## 2. 设计分析: arrayJoin 的独特性


 arrayJoin 是 ClickHouse 独有的函数:
 它将数组"爆炸"为多行，每行一个元素。
 等价于 PostgreSQL 的 unnest() 或 BigQuery 的 UNNEST()。

 但 arrayJoin 的语法更灵活:
 (a) 可以在 SELECT 中使用（不需要 FROM 子句或 JOIN）
 (b) 可以同时 arrayJoin 多个数组（产生笛卡尔积）
 (c) 配合 splitBy* 函数形成强大的字符串处理管道

## 3. 拆分 + 聚合


统计每个标签出现的次数:

```sql
SELECT tag, count() AS cnt
FROM users
ARRAY JOIN splitByChar(',', tags) AS tag
GROUP BY tag
ORDER BY cnt DESC;

```

保留原始行信息:

```sql
SELECT id, username, tag
FROM users
ARRAY JOIN splitByChar(',', tags) AS tag;

```

## 4. 其他字符串拆分函数


extractAll: 正则提取所有匹配（返回数组）

```sql
SELECT arrayJoin(extractAll('foo123bar456', '\\d+')) AS num;
```

输出: 123, 456

splitByWhitespace: 按空白字符分割

```sql
SELECT arrayJoin(splitByWhitespace('hello  world   foo')) AS word;

```

alphaTokens: 提取字母 token

```sql
SELECT arrayJoin(alphaTokens('hello123world456foo')) AS word;
```

 输出: hello, world, foo

## 5. 对比与引擎开发者启示

ClickHouse 字符串拆分:
- splitByChar/splitByString → 分割为数组
- arrayJoin / ARRAY JOIN → 数组展开为行
两步组合 = 完整的 SPLIT-TO-ROWS 管道

对比:
- **PostgreSQL**: string_to_array() + unnest()（最接近）
- **BigQuery**: SPLIT() + UNNEST()
- **MySQL**: 无内置方案（需要递归 CTE 或 JSON_TABLE）
- **SQLite**: 递归 CTE 或 json_each

对引擎开发者的启示:
splitBy* + arrayJoin 的两步设计是最灵活的:
- 分割（返回数组）和展开（数组→行）是独立操作，可以自由组合。
内置多种分割函数（char/string/regexp/whitespace）覆盖各种场景。
