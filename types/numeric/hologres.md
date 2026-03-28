# Hologres: 数值类型

Hologres 兼容 PostgreSQL 类型系统

> 参考资料:
> - [Hologres - Data Types](https://help.aliyun.com/zh/hologres/user-guide/data-types)
> - [Hologres Built-in Functions](https://help.aliyun.com/zh/hologres/user-guide/built-in-functions)


整数
SMALLINT / INT2:  2 字节，-32768 ~ 32767
INTEGER / INT4:   4 字节，-2^31 ~ 2^31-1
BIGINT / INT8:    8 字节，-2^63 ~ 2^63-1

```sql
CREATE TABLE examples (
    small_val  SMALLINT,
    int_val    INTEGER,
    big_val    BIGINT
);
```

注意：没有 TINYINT（与 PostgreSQL 一致）
注意：没有 UNSIGNED 类型
自增序列
SERIAL: 4 字节自增
BIGSERIAL: 8 字节自增

```sql
CREATE TABLE t (id BIGSERIAL PRIMARY KEY);
```

浮点数
REAL / FLOAT4:             4 字节，约 6 位有效数字
DOUBLE PRECISION / FLOAT8: 8 字节，约 15 位有效数字
定点数
NUMERIC(p, s) / DECIMAL(p, s): 精确数值

```sql
CREATE TABLE prices (
    price      NUMERIC(10, 2),            -- 精确到分
    value      DOUBLE PRECISION           -- 浮点数
);
```

## 布尔

```sql
CREATE TABLE t (active BOOLEAN DEFAULT TRUE);
```

## 类型转换（PostgreSQL 语法）

```sql
SELECT CAST('123' AS INTEGER);
SELECT '123'::INTEGER;                    -- :: 转换语法
```

注意：与 PostgreSQL 的主要区别
不支持 MONEY 类型
不支持 NUMERIC 不指定精度（任意精度）
支持 MaxCompute 类型映射（BIGINT -> BIGINT, DOUBLE -> DOUBLE PRECISION）
注意：列存模式下数值类型有更高的压缩效率
