# Trino: 复合类型

> 参考资料:
> - [Trino Documentation - Array Type](https://trino.io/docs/current/language/types.html#array)
> - [Trino Documentation - Map Type](https://trino.io/docs/current/language/types.html#map)
> - [Trino Documentation - Row Type](https://trino.io/docs/current/language/types.html#row)
> - [Trino Documentation - Array Functions](https://trino.io/docs/current/functions/array.html)
> - [Trino Documentation - Map Functions](https://trino.io/docs/current/functions/map.html)

**引擎定位**: 分布式查询引擎（前身 Presto），不存储数据。通过 Connector 查询异构数据源（Hive/Iceberg/RDBMS）。

## ARRAY 类型


数组构造
```sql
SELECT ARRAY[1, 2, 3];
SELECT ARRAY['admin', 'dev', 'ops'];

```

数组索引（从 1 开始）
```sql
SELECT tags[1] FROM users;                    -- 第一个元素

```

ARRAY 函数
```sql
SELECT CARDINALITY(ARRAY[1,2,3]);             -- 长度: 3
SELECT CONTAINS(ARRAY['a','b','c'], 'b');     -- 包含检查
SELECT ELEMENT_AT(ARRAY['a','b','c'], 2);     -- 第二个元素
SELECT ARRAY_SORT(ARRAY[3,1,2]);             -- [1,2,3]
SELECT ARRAY_DISTINCT(ARRAY[1,2,2,3]);       -- [1,2,3]
SELECT ARRAY_JOIN(ARRAY['a','b','c'], ', '); -- 'a, b, c'
SELECT ARRAY_POSITION(ARRAY['a','b','c'], 'b');  -- 2
SELECT ARRAY_REMOVE(ARRAY[1,2,3,2], 2);     -- [1,3]

```

数组合并/连接
```sql
SELECT CONCAT(ARRAY[1,2], ARRAY[3,4]);       -- [1,2,3,4]
SELECT ARRAY_UNION(ARRAY[1,2], ARRAY[2,3]);  -- [1,2,3]
SELECT ARRAY_INTERSECT(ARRAY[1,2,3], ARRAY[2,3,4]); -- [2,3]
SELECT ARRAY_EXCEPT(ARRAY[1,2,3], ARRAY[2]); -- [1,3]

```

高阶函数
```sql
SELECT TRANSFORM(ARRAY[1,2,3], x -> x * 2);  -- [2,4,6]
SELECT FILTER(ARRAY[1,2,3,4], x -> x > 2);   -- [3,4]
SELECT REDUCE(ARRAY[1,2,3], 0, (acc, x) -> acc + x, s -> s);  -- 6
SELECT ZIP_WITH(ARRAY[1,2], ARRAY[3,4], (x, y) -> x + y);     -- [4,6]
SELECT ANY_MATCH(ARRAY[1,2,3], x -> x > 2);  -- true
SELECT ALL_MATCH(ARRAY[1,2,3], x -> x > 0);  -- true
SELECT NONE_MATCH(ARRAY[1,2,3], x -> x > 5); -- true

```

切片
```sql
SELECT SLICE(ARRAY['a','b','c','d'], 2, 2);  -- ['b','c']

```

序列生成
```sql
SELECT SEQUENCE(1, 10);
SELECT SEQUENCE(DATE '2024-01-01', DATE '2024-01-07');

```

FLATTEN: 展平
```sql
SELECT FLATTEN(ARRAY[ARRAY[1,2], ARRAY[3,4]]); -- [1,2,3,4]

```

## UNNEST: 展开数组为行


```sql
SELECT t.val
FROM UNNEST(ARRAY[1,2,3]) AS t(val);

```

WITH ORDINALITY
```sql
SELECT * FROM UNNEST(ARRAY['a','b','c']) WITH ORDINALITY AS t(val, idx);

```

与表关联
```sql
SELECT u.name, t.tag
FROM users u
CROSS JOIN UNNEST(u.tags) AS t(tag);

```

多数组同时展开
```sql
SELECT *
FROM UNNEST(
    ARRAY['a','b','c'],
    ARRAY[1,2,3]
) AS t(letter, number);

```

## ARRAY_AGG: 聚合为数组


```sql
SELECT department, ARRAY_AGG(name ORDER BY name) AS members
FROM employees
GROUP BY department;

```

## MAP 类型


Map 构造
```sql
SELECT MAP(ARRAY['a','b'], ARRAY[1,2]);       -- Trino 风格
SELECT MAP_FROM_ENTRIES(ARRAY[ROW('a',1), ROW('b',2)]);

```

Map 访问
```sql
SELECT attributes['brand'] FROM products;
SELECT ELEMENT_AT(MAP(ARRAY['a'], ARRAY[1]), 'a');

```

Map 函数
```sql
SELECT MAP_KEYS(MAP(ARRAY['a','b'], ARRAY[1,2]));    -- ['a','b']
SELECT MAP_VALUES(MAP(ARRAY['a','b'], ARRAY[1,2]));  -- [1,2]
SELECT MAP_ENTRIES(MAP(ARRAY['a','b'], ARRAY[1,2])); -- [('a',1),('b',2)]
SELECT CARDINALITY(MAP(ARRAY['a','b'], ARRAY[1,2])); -- 2

```

Map 合并
```sql
SELECT MAP_CONCAT(MAP(ARRAY['a'], ARRAY[1]), MAP(ARRAY['b'], ARRAY[2]));

```

Map 过滤/转换
```sql
SELECT MAP_FILTER(MAP(ARRAY['a','b'], ARRAY[1,2]), (k, v) -> v > 1);
SELECT TRANSFORM_KEYS(MAP(ARRAY['a'], ARRAY[1]), (k, v) -> UPPER(k));
SELECT TRANSFORM_VALUES(MAP(ARRAY['a'], ARRAY[1]), (k, v) -> v * 10);

```

Map 展开
```sql
SELECT mk.key, mk.value
FROM UNNEST(MAP(ARRAY['a','b'], ARRAY[1,2])) AS mk(key, value);

```

MAP_AGG: 聚合为 Map
```sql
SELECT MAP_AGG(name, salary) FROM employees;

```

MULTIMAP_AGG: 一键多值
```sql
SELECT MULTIMAP_AGG(department, name) FROM employees;

```

## ROW 类型（= STRUCT）


ROW 构造
```sql
SELECT ROW('Alice', 30);
SELECT CAST(ROW('Alice', 30) AS ROW(name VARCHAR, age INTEGER));

```

命名字段 ROW
```sql
SELECT ROW('Alice', 30) AS person;

```

访问 ROW 字段
```sql
SELECT customer.name FROM orders;

```

## 嵌套类型


ARRAY of ROW
```sql
SELECT ARRAY[ROW('Alice', 30), ROW('Bob', 25)];

```

MAP of ARRAY
```sql
SELECT MAP(ARRAY['tags'], ARRAY[ARRAY['a','b']]);

```

ROW 嵌套 ROW
```sql
SELECT ROW(ROW('Alice', 30), ROW('NYC', 'NY'));

```

## JSON 函数


JSON 解析
```sql
SELECT JSON_PARSE('{"name": "Alice"}');
SELECT JSON_EXTRACT('{"tags": ["a","b"]}', '$.tags');
SELECT JSON_EXTRACT_SCALAR('{"name": "Alice"}', '$.name');

```

JSON_FORMAT: 转为字符串
```sql
SELECT JSON_FORMAT(JSON '{"a": 1}');

```

CAST 与 JSON
```sql
SELECT CAST(JSON '"hello"' AS VARCHAR);

```

## 注意事项


## Trino 原生支持 ARRAY、MAP、ROW

## 数组下标从 1 开始

## 支持高阶函数 (TRANSFORM, FILTER, REDUCE)

## UNNEST 是展开数组/Map 的标准方式

## ROW 类型等价于其他引擎的 STRUCT

## 支持任意深度的嵌套
