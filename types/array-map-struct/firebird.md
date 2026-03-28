# Firebird: 复合/复杂类型 (Array, Map, Struct)

> 参考资料:
> - [Firebird Documentation - Array Data Type](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html#fblangref40-datatypes-array)


## ARRAY 类型（Firebird 原生支持）


## Firebird 支持固定维度的数组

```sql
CREATE TABLE users (
    id     INTEGER NOT NULL PRIMARY KEY,
    name   VARCHAR(100) NOT NULL,
    scores INTEGER[5],                         -- 5 个元素的一维数组
    matrix INTEGER[3][3]                       -- 3x3 二维数组
);
```

## 插入（使用 PSQL 或客户端 API）

SQL 中不支持数组字面量，需要通过 UPDATE 逐元素设置

```sql
UPDATE users SET scores[1] = 90, scores[2] = 85, scores[3] = 95 WHERE id = 1;
```

## 数组索引（从 1 开始）

```sql
SELECT scores[1] FROM users;
SELECT matrix[1][2] FROM users;
```

## MAP / STRUCT 替代方案


Firebird 没有 MAP 或 STRUCT 类型
替代方案: 使用关联表或 JSON 字符串（需要应用层解析）
注意: Firebird 4.0+ 没有内置 JSON 函数

## 注意事项


## Firebird 支持原生 ARRAY 类型（固定维度）

## 数组大小在建表时确定，不能动态增长

## SQL 中不能直接构造数组字面量

## 没有 MAP / STRUCT / JSON 类型

## 没有 UNNEST / ARRAY_AGG 函数

## 数组功能相对有限，主要通过客户端 API 操作
