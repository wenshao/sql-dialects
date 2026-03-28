# DamengDB (达梦): INSERT

Oracle compatible syntax.

> 参考资料:
> - [DamengDB SQL Reference](https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html)
> - [DamengDB System Admin Manual](https://eco.dameng.com/document/dm/zh-cn/pm/index.html)
> - 单行插入

```sql
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);
```

## 多行插入（达梦支持标准多行 VALUES）

```sql
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);
```

## Oracle 风格多行插入（INSERT ALL）

```sql
INSERT ALL
    INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25)
    INTO users (username, email, age) VALUES ('bob', 'bob@example.com', 30)
    INTO users (username, email, age) VALUES ('charlie', 'charlie@example.com', 35)
SELECT 1 FROM DUAL;
```

## 条件多表插入

```sql
INSERT ALL
    WHEN age < 30 THEN INTO young_users (username, age) VALUES (username, age)
    WHEN age >= 30 THEN INTO senior_users (username, age) VALUES (username, age)
SELECT username, age FROM candidates;
```

## INSERT FIRST

```sql
INSERT FIRST
    WHEN age < 18 THEN INTO minors (username, age) VALUES (username, age)
    WHEN age < 65 THEN INTO adults (username, age) VALUES (username, age)
    ELSE INTO seniors (username, age) VALUES (username, age)
SELECT username, age FROM candidates;
```

## 从查询结果插入

```sql
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;
```

## 使用序列获取自增 ID

```sql
INSERT INTO orders (id, user_id, amount)
VALUES (seq_orders.NEXTVAL, 1, 99.99);
```

## IDENTITY 列自动生成

```sql
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);
```

## 指定默认值

```sql
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', DEFAULT);
```

RETURNING（PL/SQL 中使用）
INSERT INTO users (...) VALUES (...) RETURNING id INTO v_id;
注意事项：
支持 Oracle 风格的 INSERT ALL 语法
支持序列和 IDENTITY 两种自增方式
DUAL 表可以使用
大小写敏感性取决于数据库初始化配置
