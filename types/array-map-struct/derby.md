# Apache Derby: 复合/复杂类型 (Array, Map, Struct)

> 参考资料:
> - [Apache Derby Documentation - Data Types](https://db.apache.org/derby/docs/10.16/ref/crefsqlj31068.html)


## Derby 不支持原生的 ARRAY / MAP / STRUCT 类型


## 替代方案 1: 使用关联表（规范化设计）

```sql
CREATE TABLE users (
    id   INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    name VARCHAR(100) NOT NULL
);

CREATE TABLE user_tags (
    user_id INTEGER NOT NULL REFERENCES users(id),
    tag     VARCHAR(50) NOT NULL,
    PRIMARY KEY (user_id, tag)
);

INSERT INTO users (name) VALUES ('Alice');
INSERT INTO user_tags VALUES (1, 'admin'), (1, 'dev');
```

## 查询所有标签

```sql
SELECT u.name, t.tag
FROM users u
JOIN user_tags t ON u.id = t.user_id;
```

## 替代方案 2: 使用分隔符字符串

```sql
CREATE TABLE products (
    id    INTEGER PRIMARY KEY,
    name  VARCHAR(100),
    tags  VARCHAR(1000)                       -- 逗号分隔
);

INSERT INTO products VALUES (1, 'Laptop', 'electronics,computer,tech');
```

## 替代方案 3: 使用 XML

Derby 不支持 XML 数据类型

## 注意事项


## Derby 不支持 ARRAY / MAP / STRUCT 类型

## 不支持 JSON 数据类型或函数

## 不支持 XML 数据类型

## 使用关联表是最佳替代方案

## Derby 是嵌入式数据库，功能相对简单
