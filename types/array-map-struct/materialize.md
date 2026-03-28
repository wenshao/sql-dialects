# Materialize: 复合/复杂类型 (Array, Map, Struct)

> 参考资料:
> - [Materialize Documentation - Data Types (LIST)](https://materialize.com/docs/sql/types/list/)
> - [Materialize Documentation - Data Types (MAP)](https://materialize.com/docs/sql/types/map/)
> - [Materialize Documentation - Data Types (RECORD)](https://materialize.com/docs/sql/types/record/)
> - [Materialize Documentation - JSONB](https://materialize.com/docs/sql/types/jsonb/)
> - ============================================================
> - LIST 类型（Materialize 的数组类型）
> - ============================================================
> - LIST 类型（类似 PostgreSQL ARRAY，但使用不同的语法）

```sql
SELECT LIST[1, 2, 3];
SELECT LIST['admin', 'dev', 'ops'];
```

## LIST 索引（从 1 开始）

```sql
SELECT LIST[10, 20, 30][1];                    -- 10
```

## LIST 函数

```sql
SELECT list_length(LIST[1,2,3]);               -- 3
SELECT list_cat(LIST[1,2], LIST[3,4]);         -- [1,2,3,4]
SELECT list_append(LIST[1,2], 3);
SELECT list_prepend(0, LIST[1,2]);
```

## UNNEST

```sql
SELECT * FROM UNNEST(LIST[1,2,3]);
```

## list_agg

```sql
SELECT list_agg(name) FROM employees;
```

## MAP 类型


```sql
SELECT '{a => 1, b => 2}'::MAP[TEXT => INT];
```

## Map 访问

```sql
SELECT ('{a => 1, b => 2}'::MAP[TEXT => INT])['a'];
```

## map_length

```sql
SELECT map_length('{a => 1, b => 2}'::MAP[TEXT => INT]);
```

## RECORD 类型（类似 STRUCT/ROW）


```sql
SELECT ROW(1, 'Alice', TRUE);
```

## JSONB


```sql
SELECT '{"tags": ["a", "b"]}'::JSONB;
SELECT ('{"name": "Alice"}'::JSONB)->>'name';
SELECT ('{"tags": ["a","b"]}'::JSONB)->'tags';

SELECT jsonb_array_elements('["a","b","c"]'::JSONB);
SELECT jsonb_each('{"a": 1, "b": 2}'::JSONB);
SELECT jsonb_object_keys('{"a": 1, "b": 2}'::JSONB);
SELECT jsonb_agg(name) FROM employees;
```

## 注意事项


## Materialize 使用 LIST（非 ARRAY）类型

## 支持 MAP 类型

## RECORD 类型类似 STRUCT

## 支持 JSONB（继承自 PostgreSQL）

## LIST 下标从 1 开始
