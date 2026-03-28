# SQLite: 数组/映射/结构体

> 参考资料:
> - [SQLite Documentation - JSON Functions](https://www.sqlite.org/json1.html)
> - [SQLite Documentation - The JSON1 Extension](https://www.sqlite.org/json1.html)

## SQLite 没有原生的 ARRAY / MAP / STRUCT 类型

使用 JSON 函数（json1 扩展，SQLite 3.9.0+ 内置）

## 

```sql
CREATE TABLE users (
    id       INTEGER PRIMARY KEY AUTOINCREMENT,
    name     TEXT NOT NULL,
    tags     TEXT,                             -- 存储 JSON 数组
    metadata TEXT                              -- 存储 JSON 对象
);
```

## JSON 数组（代替 ARRAY）

插入
```sql
INSERT INTO users (name, tags) VALUES
    ('Alice', json_array('admin', 'dev')),
    ('Bob',   '["user", "tester"]'),
    ('Carol', json_array('dev'));
```

访问元素
```sql
SELECT json_extract(tags, '$[0]') FROM users;    -- 第一个元素
SELECT tags -> '$[0]' FROM users;                -- SQLite 3.38.0+ 简写
SELECT tags ->> '$[0]' FROM users;               -- 去引号（3.38.0+）

-- 数组长度
SELECT json_array_length(tags) FROM users;
```

## JSON 数组操作

json_insert: 插入元素
```sql
SELECT json_insert(tags, '$[#]', 'new_tag') FROM users;  -- 追加到末尾

-- json_set: 设置/替换元素
SELECT json_set(tags, '$[0]', 'replaced') FROM users;
```

json_remove: 删除元素
```sql
SELECT json_remove(tags, '$[0]') FROM users;
```

json_group_array: 聚合为数组（= ARRAY_AGG）
```sql
SELECT department, json_group_array(name) AS members
FROM employees
GROUP BY department;
```

## json_each / json_tree: 展开 JSON（= UNNEST）

json_each: 展开一层
```sql
SELECT u.name, je.value AS tag
FROM users u, json_each(u.tags) je;
```

json_each 返回的列:
key: 数组索引（整数）或对象键（字符串）
value: 值
type: 类型（text, integer, real, true, false, null, object, array）
atom: 标量值
path: JSON 路径

json_tree: 递归展开所有层级
```sql
SELECT *
FROM json_tree('{"a": [1, 2], "b": {"c": 3}}');
```

## JSON 对象（代替 MAP / STRUCT）

```sql
UPDATE users SET metadata = json_object(
    'city', 'New York',
    'country', 'US',
    'settings', json_object('theme', 'dark')
) WHERE id = 1;
```

访问字段
```sql
SELECT json_extract(metadata, '$.city') FROM users;
SELECT metadata ->> '$.city' FROM users;
```

嵌套访问
```sql
SELECT json_extract(metadata, '$.settings.theme') FROM users;
```

json_group_object: 聚合为对象（= MAP 构造）
```sql
SELECT json_group_object(name, salary) FROM employees;
```

## 嵌套 JSON

```sql
INSERT INTO users (name, tags, metadata) VALUES ('Dan', '["dev"]', '{
    "addresses": [
        {"type": "home", "city": "NYC"},
        {"type": "work", "city": "Boston"}
    ]
}');
```

多层 json_each
```sql
SELECT u.name, je.value ->> '$.city' AS city
FROM users u, json_each(u.metadata, '$.addresses') je
WHERE u.name = 'Dan';
```

json_extract 深层访问
```sql
SELECT json_extract(metadata, '$.addresses[0].city') FROM users WHERE name = 'Dan';
```

## 包含检查

检查数组是否包含某值（使用 json_each）
```sql
SELECT * FROM users
WHERE EXISTS (
    SELECT 1 FROM json_each(tags) WHERE value = 'admin'
);
```

json_type: 获取类型
```sql
SELECT json_type(tags) FROM users;                -- 'array'
SELECT json_type(metadata) FROM users;            -- 'object'

-- json_valid: 验证 JSON
SELECT json_valid(tags) FROM users;
```

## JSON 补丁（SQLite 3.38.0+）

json_patch: 合并 JSON 对象
```sql
SELECT json_patch('{"a":1,"b":2}', '{"b":3,"c":4}');
```

结果: {"a":1,"b":3,"c":4}

## 注意事项

1. SQLite 没有原生 ARRAY / MAP / STRUCT 类型
2. 使用 TEXT 列 + json1 扩展函数
3. json1 从 SQLite 3.9.0 (2015) 开始内置
4. -> 和 ->> 操作符从 3.38.0 (2022) 开始支持
5. json_each 提供 UNNEST 功能
6. json_group_array / json_group_object 提供聚合功能
7. 没有 JSON 类型约束（需要应用层或触发器验证）
