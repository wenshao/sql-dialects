# CockroachDB: 类型转换

> 参考资料:
> - [CockroachDB Documentation - CAST](https://www.cockroachlabs.com/docs/stable/data-types.html#cast-types)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

```sql
SELECT CAST(42 AS TEXT); SELECT CAST('42' AS INT); SELECT CAST('2024-01-15' AS DATE);
SELECT 42::TEXT; SELECT '42'::INT; SELECT '2024-01-15'::DATE;
SELECT '3.14'::DECIMAL; SELECT 'true'::BOOLEAN; SELECT '{"a":1}'::JSONB;

```

格式化函数
```sql
SELECT to_char(123456.789, '999,999.99');
SELECT to_char(now(), 'YYYY-MM-DD HH24:MI:SS');
SELECT to_number('123,456.78', '999,999.99');
SELECT to_date('2024-01-15', 'YYYY-MM-DD');
SELECT to_timestamp('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');

```

隐式转换 (与 PostgreSQL 一致，严格)
```sql
SELECT 1 + 1.5;                                 -- DECIMAL
SELECT 'hello' || 42::TEXT;                      -- 需显式转换

```

更多数值转换
```sql
SELECT CAST(3.14 AS INT);                            -- 3 (截断)
SELECT '100'::INT8;                                  -- 100
SELECT CAST(3.14 AS DECIMAL(10,1));                  -- 3.1
SELECT 42::FLOAT8;                                   -- 42.0

```

布尔转换
```sql
SELECT CAST(1 AS BOOLEAN);                           -- true
SELECT 'yes'::BOOLEAN;                               -- true
SELECT TRUE::INT;                                    -- 1

```

日期/時間格式化
```sql
SELECT to_char(now(), 'YYYY-MM-DD HH24:MI:SS');
SELECT to_char(now(), 'Day, DD Month YYYY');
SELECT to_timestamp(1705276800);                     -- Unix → TIMESTAMP
SELECT EXTRACT(EPOCH FROM now());                    -- TIMESTAMP → Unix

```

UUID 转换 (CockroachDB 推荐)
```sql
SELECT gen_random_uuid()::TEXT;
SELECT 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::UUID;

```

区间转換
```sql
SELECT INTERVAL '2 hours 30 minutes';
SELECT '1 day'::INTERVAL;

```

数组转换
```sql
SELECT ARRAY[1,2,3]::TEXT[];
SELECT '{1,2,3}'::INT[];

```

JSONB 转换
```sql
SELECT '{"a":1}'::JSONB;
SELECT CAST('["a","b"]' AS JSONB);
SELECT '42'::JSONB;

```

精度処理
```sql
SELECT CAST(1.0/3.0 AS DECIMAL(10,4));              -- 0.3333
SELECT round(3.14159, 2);                            -- 3.14

```

错误処理（无 TRY_CAST）
可用 PL/pgSQL 封装安全转换
CREATE FUNCTION safe_cast_int(text) RETURNS INT AS $$
BEGIN RETURN $1::INT;
EXCEPTION WHEN OTHERS THEN RETURN NULL;
END; $$ LANGUAGE plpgsql;

分布式注意事项
unique_rowid() 返回 INT8，可用 ::TEXT 转换
类型转换在各节点独立执行

**注意:** CockroachDB 兼容 PostgreSQL 类型转换
**注意:** 支持 CAST 和 :: 运算符
**注意:** 推荐 UUID 而非 SERIAL 避免热点
**限制:** 无 TRY_CAST（转换失败抛错）
