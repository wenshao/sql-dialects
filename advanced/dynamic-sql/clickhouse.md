# ClickHouse: 动态 SQL（Dynamic SQL）

> 参考资料:
> - [1] ClickHouse Documentation - HTTP Interface
>   https://clickhouse.com/docs/en/interfaces/http
> - [2] ClickHouse - Parameterized Views
>   https://clickhouse.com/docs/en/sql-reference/statements/create/view#parameterized-view

## 1. ClickHouse 没有传统动态 SQL

ClickHouse 不支持 PREPARE/EXECUTE、EXECUTE IMMEDIATE 或存储过程。
但提供了几种独特的替代机制:
(a) HTTP 接口的参数化查询
(b) 参数化视图（22.x+）
(c) 字典（Dictionary）替代动态查找
(d) 用户定义函数（UDF）封装逻辑

## 2. HTTP 接口参数化查询

ClickHouse HTTP 接口支持类型化参数:
curl 'http://localhost:8123/' \
--data-binary "SELECT * FROM users WHERE id = {id:UInt64} AND name = {name:String}" \
--data-urlencode "param_id=42" \
--data-urlencode "param_name=alice"

参数语法: {name:Type}
参数通过 URL param_name=value 传递
类型安全: 服务端会验证参数类型

clickhouse-client 也支持:
```sql
 clickhouse-client --param_id=42 --param_name='alice' \
```

--query "SELECT * FROM users WHERE id = {id:UInt64}"

## 3. 参数化视图（22.x+）

参数化视图是 ClickHouse 独有的"动态查询模板":
```sql
 CREATE VIEW user_orders AS
 SELECT * FROM orders WHERE user_id = {user_id:UInt64};
 SELECT * FROM user_orders(user_id = 42);
```

设计分析:
参数化视图填补了"无存储过程"和"无动态 SQL"之间的空白。
它允许在 SQL 层面定义带参数的查询模板，
而不需要应用层拼接 SQL 或使用存储过程。

## 4. 字典替代动态查找

```sql
CREATE DICTIONARY user_dict (
    id UInt64,
    username String,
    email String
) PRIMARY KEY id
SOURCE(CLICKHOUSE(TABLE 'users'))
LAYOUT(FLAT())
LIFETIME(MIN 300 MAX 600);
```

使用字典查找（替代动态 SQL 构建的 JOIN 查询）

```sql
SELECT dictGet('user_dict', 'username', toUInt64(42));
SELECT dictGet('user_dict', ('username', 'email'), toUInt64(42));
```

字典的设计优势:
(a) 预加载到内存 → 查找比 JOIN 快几个数量级
(b) 自动刷新 → LIFETIME 控制刷新间隔
(c) 多数据源 → 可以从 MySQL/PostgreSQL/HTTP/文件加载
对于"根据 ID 查找名称"这类常见的动态查询，字典是最优方案。

## 5. 用户定义函数（UDF）

SQL UDF（lambda 表达式）

```sql
CREATE FUNCTION linear_transform AS (x, k, b) -> k * x + b;
SELECT linear_transform(age, 1.5, 10) FROM users;
```

外部 UDF（通过可执行文件，21.11+）
在 user_defined_functions.xml 中配置外部脚本

## 6. 对比与引擎开发者启示

```sql
 ClickHouse 的动态 SQL 替代方案:
   (1) HTTP 参数化查询 → 类型安全的参数绑定
   (2) 参数化视图 → SQL 层面的查询模板
   (3) 字典 → 内存缓存的动态查找
   (4) SQL UDF → 表达式封装
```

对引擎开发者的启示:
OLAP 引擎不需要传统的 EXECUTE IMMEDIATE。
参数化视图是更好的抽象: 声明式 + 类型安全 + 可优化。
字典（预加载的键值缓存）是 OLAP 引擎的杀手级特性，
替代了大量"动态 JOIN"的需求。
