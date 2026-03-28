# SQL 标准: JSON 类型

> 参考资料:
> - [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
> - [Modern SQL - by Markus Winand](https://modern-sql.com/)
> - [Modern SQL - JSON Support](https://modern-sql.com/blog/2017-06/whats-new-in-sql-2016)

SQL:2016 (SQL/JSON):
首次引入 JSON 支持（作为 SQL 标准的一部分）
JSON_VALUE: 提取标量值
JSON_QUERY: 提取 JSON 对象/数组
JSON_EXISTS: 检查路径是否存在
JSON_TABLE: 将 JSON 转为关系表
JSON_OBJECT: 构造 JSON 对象
JSON_ARRAY: 构造 JSON 数组
JSON_OBJECTAGG: 聚合构造 JSON 对象
JSON_ARRAYAGG: 聚合构造 JSON 数组
IS JSON: 判断是否为有效 JSON

标准 JSON 路径表达式（SQL/JSON Path）
$: 根元素
$.key: 对象成员
$.array[0]: 数组元素
$.array[*]: 所有数组元素
$..key: 递归搜索

SQL:2016 JSON 函数
```sql
SELECT JSON_VALUE('{"name": "alice"}', '$.name');           -- 'alice'
SELECT JSON_QUERY('{"tags": [1,2]}', '$.tags');            -- '[1,2]'
SELECT JSON_EXISTS('{"name": "alice"}', '$.name');         -- TRUE
```

lax vs strict 模式
```sql
SELECT JSON_VALUE('{"a": 1}', 'lax $.b' DEFAULT 'N/A' ON EMPTY);  -- lax: 容错
SELECT JSON_VALUE('{"a": 1}', 'strict $.b' ERROR ON ERROR);        -- strict: 报错
```

JSON_TABLE（SQL:2016，将 JSON 展开为关系表）
```sql
SELECT jt.*
FROM events,
     JSON_TABLE(data, '$'
         COLUMNS (
             name   VARCHAR(100) PATH '$.name',
             age    INTEGER      PATH '$.age',
             NESTED PATH '$.tags[*]'
                 COLUMNS (tag VARCHAR(50) PATH '$')
         )
     ) AS jt;
```

JSON 构造（SQL:2016）
```sql
SELECT JSON_OBJECT(KEY 'name' VALUE 'alice', KEY 'age' VALUE 25);
SELECT JSON_ARRAY(1, 2, 3);
```

JSON 聚合（SQL:2016）
```sql
SELECT JSON_OBJECTAGG(KEY username VALUE age) FROM users;
SELECT JSON_ARRAYAGG(username ORDER BY username) FROM users;
```

IS JSON 谓词（SQL:2016）
```sql
SELECT * FROM events WHERE data IS JSON;
SELECT * FROM events WHERE data IS JSON OBJECT;
SELECT * FROM events WHERE data IS JSON ARRAY;
SELECT * FROM events WHERE data IS JSON SCALAR;
```

SQL:2023:
JSON 数据类型（JSON 作为独立类型，而非通过函数操作字符串）
JSON_SERIALIZE / JSON_PARSE
```sql
SELECT JSON_SERIALIZE(JSON_OBJECT('a' VALUE 1));
SELECT JSON_PARSE('{"a": 1}');
```

- **注意：SQL:2016 之前标准中没有 JSON 支持**
- **注意：各厂商的 JSON 实现差异较大**
- **注意：标准定义了 lax/strict 两种路径模式**
- **注意：JSON_TABLE 是最强大的功能，但支持程度各异**
- **注意：标准中 JSON 存储在 VARCHAR/CLOB 中，SQL:2023 引入独立 JSON 类型**
