# Hologres: 字符串类型

Hologres 兼容 PostgreSQL 类型系统

> 参考资料:
> - [Hologres - Data Types](https://help.aliyun.com/zh/hologres/user-guide/data-types)
> - [Hologres - String Functions](https://help.aliyun.com/zh/hologres/user-guide/string-functions)
> - CHAR(n) / CHARACTER(n): 定长，尾部补空格
> - VARCHAR(n) / CHARACTER VARYING(n): 变长，有长度限制
> - TEXT: 变长，无长度限制（推荐）

```sql
CREATE TABLE examples (
    code       CHAR(10),                  -- 定长
    name       VARCHAR(255),              -- 变长有限制
    content    TEXT                       -- 变长无限制（推荐）
);
```

注意：与 PostgreSQL 语法兼容
VARCHAR 不指定长度等同于 TEXT
实际存储由 Hologres 列存引擎管理
二进制数据
BYTEA: 变长二进制

```sql
CREATE TABLE files (data BYTEA);
```

## 类型转换（PostgreSQL 语法）

```sql
SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;                    -- :: 转换语法
```

## 字符串字面量

```sql
SELECT 'hello world';                     -- 单引号
```

排序规则
Hologres 支持部分 PostgreSQL 排序规则
默认 UTF-8 编码
注意：不支持 CREATE TYPE ... AS ENUM（自定义枚举类型）
注意：TEXT 最大存储受行大小限制
注意：与 PostgreSQL 的区别在于底层存储引擎不同
注意：支持 MaxCompute 类型映射（STRING -> TEXT）
