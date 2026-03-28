# MaxCompute (ODPS): ALTER TABLE

> 参考资料:
> - [1] MaxCompute SQL - ALTER TABLE
>   https://help.aliyun.com/zh/maxcompute/user-guide/alter-table
> - [2] MaxCompute Transactional Tables
>   https://help.aliyun.com/zh/maxcompute/user-guide/transactional-tables


## 1. 列操作


添加列（注意: 关键字是 ADD COLUMNS，复数形式，Hive 兼容）

```sql
ALTER TABLE users ADD COLUMNS (phone STRING COMMENT '手机号');

ALTER TABLE users ADD COLUMNS (
    city    STRING COMMENT '城市',
    country STRING COMMENT '国家',
    tags    ARRAY<STRING> COMMENT '标签列表'
);

```

修改列名和注释（CHANGE COLUMN 语法，Hive 兼容）

```sql
ALTER TABLE users CHANGE COLUMN phone mobile STRING COMMENT '手机号';
ALTER TABLE users CHANGE COLUMN email email STRING COMMENT '新的邮箱注释';

```

 设计决策: 为什么 Schema Evolution 能力有限?
   MaxCompute 使用 AliORC 列式存储，数据按分区存储在盘古上:
   - ADD COLUMNS: 仅修改元数据（新列在已有文件中读取为 NULL），代价极低
   - DROP COLUMN: 列式存储理论上只需标记元数据，但 MaxCompute 不直接支持
   - 类型变更: 需要重写所有 AliORC 数据文件（代价极高，选择不支持）
   - 列顺序: 列式存储按列名引用，物理顺序无意义

   对比:
     BigQuery:    支持 ADD/DROP COLUMN，不支持类型变更
     Snowflake:   最灵活 — ADD/DROP/RENAME/ALTER TYPE 均支持
     ClickHouse:  ALTER 是异步的元数据操作，非常快
     Hive:        与 MaxCompute 几乎相同（共同的架构决策）

 不支持的列操作及替代方案:

### 1.1 不支持 DROP COLUMN -> CTAS 重建

```sql
CREATE TABLE users_new AS
SELECT id, username, email, age, created_at
FROM users;                                 -- 不包含要删除的列
DROP TABLE users;
ALTER TABLE users_new RENAME TO users;

```

### 1.2 不支持修改列类型 -> CTAS + CAST

```sql
CREATE TABLE users_v2 AS
SELECT id, username, email,
       CAST(age AS BIGINT) AS age,
       created_at
FROM users;

```

### 1.3 不支持修改列顺序 -> CTAS 指定列顺序

```sql
CREATE TABLE users_v3 AS
SELECT id, email, username, age, phone, created_at
FROM users;

```

 限制: 分区列不能被 ADD/DROP/CHANGE（分区列编码在目录路径中）

## 2. 分区操作 —— 数据管理的核心单元


```sql
ALTER TABLE orders ADD PARTITION (dt = '20240115', region = 'cn');
ALTER TABLE orders ADD IF NOT EXISTS PARTITION (dt = '20240115');

ALTER TABLE orders DROP PARTITION (dt = '20240115');
ALTER TABLE orders DROP IF EXISTS PARTITION (dt = '20240115');

```

批量删除分区（表达式）

```sql
ALTER TABLE orders DROP PARTITION (dt >= '20240101' AND dt <= '20240131');

```

合并小文件 —— 重要的运维操作

```sql
ALTER TABLE orders PARTITION (dt = '20240115') MERGE SMALLFILES;

```

 设计分析: 为什么小文件是大问题?
   每次 INSERT INTO 都会产生新的 AliORC 文件
   大量小文件导致: 伏羲调度开销大（每个文件一个 task）、读取 I/O 放大
   MERGE SMALLFILES 将小文件合并为大文件，减少 task 数量
   对比:
     Hive:       ALTER TABLE ... CONCATENATE（类似功能）
     Delta Lake: OPTIMIZE 命令合并小文件
     Iceberg:    RewriteDataFiles Action

## 3. 表属性操作


```sql
ALTER TABLE users SET COMMENT '用户信息表 v2';
ALTER TABLE users SET LIFECYCLE 180;        -- 修改生命周期
ALTER TABLE users SET LIFECYCLE 0;          -- 永不过期
ALTER TABLE users RENAME TO members;
TRUNCATE TABLE users;

```

表属性

```sql
ALTER TABLE users SET TBLPROPERTIES ('comment' = 'User table');

```

## 4. 事务表的 Schema Evolution


将普通表转换为事务表（不可逆!）

```sql
ALTER TABLE users SET TBLPROPERTIES ('transactional' = 'true');

```

设计决策: 为什么不可逆?
事务表的底层存储格式不同（增加了 delta 文件和事务元数据）
转换后: 原有数据仍可读，新增 UPDATE/DELETE 能力
对比:
Hive: 也是不可逆的 ACID 表转换
Delta Lake: 所有表天生就是事务表（无此问题）
Iceberg: 同上
教训: 如果重新设计，应让所有表默认支持事务（Delta Lake 的做法更优）

事务表支持的 ALTER:

```sql
ALTER TABLE users ADD COLUMNS (phone STRING);
ALTER TABLE users CHANGE COLUMN phone mobile STRING;
ALTER TABLE users SET COMMENT '事务用户表';

```

 事务表不支持:
   DROP COLUMN（与普通表相同）
   修改列类型（与普通表相同）
   CLUSTERED BY（事务表不支持聚簇属性）
   转回非事务表

## 5. INSERT OVERWRITE 作为数据修复手段


对于不需要改 schema 的数据清洗，INSERT OVERWRITE 是核心手段:

```sql
INSERT OVERWRITE TABLE users
SELECT id, username, email, age, created_at
FROM users
WHERE status = 'active';                    -- 过滤掉无效数据

```

 这是 Hive 族引擎的核心设计:
   不做行级 UPDATE，而是重写整个表/分区
   优势: 实现简单（文件级替换）且幂等（重跑不会产生重复数据）
   代价: 必须读写全量数据，不适合大表频繁更新

## 6. 横向对比: ALTER TABLE 能力


 ADD COLUMN:
   MaxCompute: 支持（元数据操作，即时完成）
   Hive:       支持（相同机制）
   BigQuery:   支持（元数据操作）
   Snowflake:  支持（元数据操作）
   MySQL:      支持（INSTANT 8.0.12+，否则需 copy/inplace）
   PostgreSQL: 支持（11+ 带 DEFAULT 也是即时的）

 DROP COLUMN:
   MaxCompute: 不支持（需 CTAS 重建）
   Hive:       支持（通过 REPLACE COLUMNS 间接实现）
   BigQuery:   支持（元数据操作）
   Snowflake:  支持（元数据操作）
   MySQL:      支持（需要表重建）

 ALTER TYPE:
   MaxCompute: 不支持
   Hive:       不支持（需 CTAS）
   BigQuery:   不支持
   Snowflake:  支持（部分类型间）
   MySQL:      支持（可能需表重建）

## 7. 对引擎开发者的启示


### 1. 列式存储下 ADD COLUMN 几乎零成本（只改元数据），应优先支持

### 2. DROP COLUMN 在列式存储中也可以只标记元数据（惰性删除）

### 3. 类型变更需要重写数据文件，代价高但用户需求强烈 — 值得投资

### 4. 小文件合并（MERGE SMALLFILES）是批处理引擎的必备运维操作

### 5. 事务表转换应该是默认行为而非单向操作（Delta Lake 的教训）

### 6. 分区列不可变更是目录编码设计的必然结果 — 设计时需权衡

