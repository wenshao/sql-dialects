# ClickHouse: UPDATE

> 参考资料:
> - [1] ClickHouse SQL Reference - ALTER UPDATE
>   https://clickhouse.com/docs/en/sql-reference/statements/alter/update
> - [2] ClickHouse - Mutations
>   https://clickhouse.com/docs/en/sql-reference/statements/alter#mutations
> - [3] ClickHouse - Lightweight Update
>   https://clickhouse.com/docs/en/sql-reference/statements/alter/update#lightweight-update


## 1. 为什么 ClickHouse 没有标准 UPDATE 语句


 ClickHouse 不支持标准 SQL 的 UPDATE 语句。
 更新通过 ALTER TABLE ... UPDATE（mutation）实现。
 这是列式存储 + 不可变 data part 设计的直接后果:

 列存的 UPDATE 问题:
   行存引擎（MySQL/PostgreSQL）:
     UPDATE users SET age=26 WHERE id=1;
     → 定位到行 → 原地修改 age 列的值 → 写入 redo log
     → 微秒级完成

   列存引擎（ClickHouse）:
     UPDATE 一行的 age 值 → 需要找到 age 列文件中的对应位置
     → 列文件是压缩的（LZ4/ZSTD），不能原地修改
     → 必须: 解压整个 data part → 修改 → 重新压缩 → 写入新 part
     → 毫秒到秒级（取决于 part 大小）

 这就是为什么 ClickHouse 的 UPDATE 是"mutation"（变异）:
   它不是"修改一行"，而是"重写包含该行的整个 data part"。

## 2. ALTER TABLE UPDATE（异步 mutation）


基本更新

```sql
ALTER TABLE users UPDATE age = 26 WHERE username = 'alice';

```

多列更新

```sql
ALTER TABLE users UPDATE email = 'new@e.com', age = 26 WHERE username = 'alice';

```

条件更新

```sql
ALTER TABLE users UPDATE status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END WHERE 1 = 1;

```

自引用更新

```sql
ALTER TABLE users UPDATE age = age + 1 WHERE 1 = 1;

```

使用函数

```sql
ALTER TABLE users UPDATE email = lower(email) WHERE email != lower(email);

```

 WHERE 子句是必须的（不能无条件更新）
 全表更新: WHERE 1 = 1

### 2.1 Mutation 执行流程

(1) 提交 mutation → 记录到 system.mutations → 立即返回 mutation_id
(2) 后台逐个 data part 执行: 读取 → 修改 → 写入新 part → 删除旧 part
(3) 所有 part 处理完毕 → mutation 标记为 is_done = 1

查看 mutation 进度

```sql
SELECT mutation_id, command, is_done, parts_to_do, latest_fail_reason
FROM system.mutations
WHERE table = 'users' AND database = currentDatabase();

```

同步等待（阻塞直到 mutation 完成）

```sql
ALTER TABLE users UPDATE age = 26 WHERE username = 'alice'
SETTINGS mutations_sync = 1;     -- 0=异步, 1=等当前副本, 2=等所有副本

```

取消未完成的 mutation

```sql
KILL MUTATION WHERE mutation_id = 'mutation_id_here';

```

## 3. 轻量级 UPDATE（23.3+）


 传统 mutation 的问题: 修改 1 行也要重写整个 data part。
 轻量级 UPDATE 通过"掩码"机制避免重写:

   (1) 在内存中标记哪些行被修改（mask file）
   (2) 查询时: 读取原始数据 + 应用掩码 = 返回修改后的结果
   (3) 后台 merge 时: 将掩码合入数据（真正的物理修改）

 启用:
 SET apply_mutations_on_fly = 1;
 ALTER TABLE users UPDATE age = 26 WHERE username = 'alice';

 性能: 比传统 mutation 快 10-100 倍（小范围修改时）
 限制: 仅 *MergeTree 引擎，实验性功能

## 4. 替代方案: INSERT 新版本（推荐模式）


### 4.1 ReplacingMergeTree: 插入新版本行

```sql
CREATE TABLE users (
    id       UInt64,
    username String,
    email    String,
    version  UInt64
) ENGINE = ReplacingMergeTree(version)
ORDER BY id;

```

"更新": 插入新版本行（version 更大）

```sql
INSERT INTO users VALUES (1, 'alice', 'new@e.com', 2);
```

后台 merge 时保留 version 最大的行
查询时用 FINAL 获取最新版本:

```sql
SELECT * FROM users FINAL WHERE id = 1;

```

### 4.2 CollapsingMergeTree: 取消旧行 + 插入新行

 INSERT INTO users VALUES (1, 'alice', 'old@e.com', 25, -1);  -- 取消
 INSERT INTO users VALUES (1, 'alice', 'new@e.com', 26, 1);   -- 新版本

 设计分析:
   这些方案本质上是用 INSERT 模拟 UPDATE:
   写入新版本 → 后台 merge 去重 → 最终只保留最新值
   这符合 ClickHouse 的 INSERT-only 哲学
   代价: 查询时需要 FINAL（有性能开销），或容忍短暂的数据冗余

## 5. 不支持的 UPDATE 特性


 不支持: 多表 JOIN UPDATE
 不支持: 子查询 UPDATE（如 SET col = (SELECT ...)）
 不支持: RETURNING
 不支持: LIMIT（mutation 处理所有满足 WHERE 的行）
 不支持: 标准 UPDATE 语法（必须用 ALTER TABLE UPDATE）

## 6. 对比与引擎开发者启示

ClickHouse UPDATE 的设计代价:
(1) 语法特殊: ALTER TABLE UPDATE（非标准 SQL）
(2) 异步执行: 不是即时可见的
(3) 性能差: 重写整个 data part（传统 mutation）
(4) 功能受限: 无 JOIN UPDATE，无 RETURNING

但这些代价换来了:
(1) INSERT 吞吐量极高（列存 + 不可变 part）
(2) 查询性能极高（压缩数据不被 UPDATE 破坏）
(3) 存储效率极高（列式压缩不被碎片化）

对引擎开发者的启示:
列存引擎的 UPDATE 是先天劣势。如果必须支持:
(a) 轻量级 UPDATE（掩码机制）是好的折中
(b) ReplacingMergeTree 模式（版本化 INSERT）是更自然的方案
(c) 明确告知用户: UPDATE 是重量级操作，不适合高频使用

