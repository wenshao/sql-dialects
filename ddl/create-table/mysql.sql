-- MySQL: CREATE TABLE
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - CREATE TABLE
--       https://dev.mysql.com/doc/refman/8.0/en/create-table.html
--   [2] MySQL 8.0 Reference Manual - Data Types
--       https://dev.mysql.com/doc/refman/8.0/en/data-types.html
--   [3] MySQL 8.0 Reference Manual - AUTO_INCREMENT
--       https://dev.mysql.com/doc/refman/8.0/en/example-auto-increment.html
--   [4] MySQL Internals - InnoDB Row Formats
--       https://dev.mysql.com/doc/refman/8.0/en/innodb-row-format.html

-- ============================================================
-- 1. 基本语法
-- ============================================================
CREATE TABLE users (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    username   VARCHAR(64)  NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        INT,
    balance    DECIMAL(10,2) DEFAULT 0.00,
    bio        TEXT,
    created_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_username (username),
    UNIQUE KEY uk_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- 2. 语法设计分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 ENGINE 子句: 可插拔存储引擎架构
-- MySQL 的 CREATE TABLE 语法中最独特的设计是 ENGINE 子句。
-- 这源于 MySQL 的可插拔存储引擎架构（Pluggable Storage Engine）:
--   - InnoDB: B+树聚集索引，MVCC，行级锁，事务，外键（5.5+ 默认）
--   - MyISAM: 表级锁，无事务，全文索引（5.6 前唯一支持全文的引擎）
--   - MEMORY: 内存表，Hash 索引，重启丢失
--   - Archive: 只支持 INSERT/SELECT，高压缩比
--   - NDB: MySQL Cluster 分布式存储引擎
--
-- 设计 trade-off:
--   优点: 允许针对不同负载选择最优存储引擎，支持第三方引擎（如 RocksDB/TokuDB）
--   缺点: 跨引擎 JOIN 无法利用各引擎的索引优势；DDL 语法复杂度增加；
--         引擎间行为不一致（MyISAM 不支持事务但 InnoDB 支持）
--
-- 对比:
--   PostgreSQL: 无 ENGINE 概念，统一使用 heap 存储 + MVCC（但可通过 Extension 扩展，如 Citus）
--   Oracle:     通过 ORGANIZATION（heap/index/external）区分，但远不如 MySQL 灵活
--   SQL Server: 统一存储引擎，通过 FILEGROUP 和 CLUSTERED/NONCLUSTERED 影响布局
--   ClickHouse: 也有类似的 ENGINE 概念（MergeTree/Log/Memory），且是建表的必选项
--   Hive:       STORED AS (ORC/Parquet/TextFile) 类似但作用于文件格式而非引擎
--
-- 对引擎开发者的启示:
--   如果目标是 OLTP + OLAP 混合负载，可以考虑类似的可插拔架构（如行存 + 列存引擎）。
--   TiDB 通过 TiKV(行存) + TiFlash(列存) 实现了类似效果但不暴露 ENGINE 语法。
--   StarRocks/Doris 通过不同的数据模型（Duplicate/Aggregate/Unique/PrimaryKey）实现类似目的。

-- 2.2 AUTO_INCREMENT: 自增主键设计
-- MySQL 使用 AUTO_INCREMENT 关键字实现自增，这是最早期的自增设计之一。
--
-- 语法特点:
--   - 表级属性: AUTO_INCREMENT = N 可以指定起始值
--   - 每表最多一个 AUTO_INCREMENT 列，且必须是索引（不要求主键）
--   - 不支持 INCREMENT BY（步长需要通过 auto_increment_increment 系统变量设置）
--
-- 实现细节:
--   - InnoDB: 自增锁模式由 innodb_autoinc_lock_mode 控制
--     0 = traditional（语句级锁，最安全但最慢）
--     1 = consecutive（简单 INSERT 不锁，批量 INSERT 使用表锁）
--     2 = interleaved（8.0 默认，最快但批量 INSERT 的 ID 可能不连续）
--   - 5.7 及之前: 自增值存内存，重启取 MAX(id)+1，可能导致 ID 复用
--   - 8.0+: 自增值持久化到 redo log，重启不回退
--
-- 对比其他自增方案:
--   SQL 标准:     GENERATED ALWAYS AS IDENTITY（SQL:2003）
--   PostgreSQL:   SERIAL（语法糖，自动创建 SEQUENCE）→ IDENTITY（10+）
--   Oracle:       SEQUENCE 对象（独立于表）→ IDENTITY 列（12c+）
--   SQL Server:   IDENTITY(seed, increment)，支持步长
--   SQLite:       INTEGER PRIMARY KEY 自动成为 rowid（不需要 AUTOINCREMENT）
--   BigQuery:     无自增（设计哲学: 分布式系统不应依赖全局自增序列）
--   ClickHouse:   无自增（同理，分析型引擎批量写入，ID 应在应用层生成）
--   TiDB:         AUTO_INCREMENT（MySQL 兼容）+ AUTO_RANDOM（分布式推荐，随机分配避免热点）
--   Snowflake:    AUTOINCREMENT 或 IDENTITY（但值不保证连续）
--   Spanner:      无自增（用 UUID 或 bit-reversed sequence 避免热点）
--
-- 对引擎开发者的启示:
--   - OLTP 引擎: 如果要兼容 MySQL，需要实现 AUTO_INCREMENT 及其锁语义
--   - 分布式引擎: 全局自增的实现成本很高（需要全局协调），建议支持但不推荐:
--     方案 A: 段分配（每个节点预分配一段 ID），如 TiDB
--     方案 B: 放弃连续性保证（如 Snowflake）
--     方案 C: 不支持自增，推荐 UUID（如 Spanner、BigQuery）
--   - 分析型引擎: 通常不需要自增（数据是批量加载的）

-- 2.3 ON UPDATE CURRENT_TIMESTAMP: 自动更新时间戳
-- MySQL 独有的列级特性，其他数据库需要触发器实现。
--
-- 设计分析:
--   优点: 简单易用，零开发成本
--   缺点: 耦合在存储层，应用层无感知；只支持 TIMESTAMP/DATETIME 类型
--         批量 UPDATE 时所有行的 updated_at 变为同一时间（语句开始时间）
--
-- 其他数据库的等价实现:
--   PostgreSQL: 需要触发器函数 + CREATE TRIGGER ... BEFORE UPDATE
--   Oracle:     需要 BEFORE UPDATE 触发器，:NEW.updated_at := SYSTIMESTAMP
--   SQL Server: 需要 AFTER UPDATE 触发器
--   SQLite:     需要 AFTER UPDATE 触发器
--
-- 对引擎开发者的启示:
--   这是一个权衡：在存储层内置简化了用户体验，但增加了引擎复杂度。
--   如果引擎已有完善的触发器支持，可能不需要在 DDL 层面增加这个语法。

-- ============================================================
-- 3. 数据类型设计分析
-- ============================================================

-- 3.1 VARCHAR(n) 的 n: 字符数 vs 字节数
-- MySQL: VARCHAR(n) 中 n 是字符数（受字符集影响）
-- Oracle: VARCHAR2(n) 默认是字节数！VARCHAR2(n CHAR) 才是字符数
-- SQL Server: VARCHAR(n) 是字节数，NVARCHAR(n) 是字符数
-- PostgreSQL: VARCHAR(n) 是字符数（但通常推荐直接用 TEXT）
--
-- 存储开销:
--   VARCHAR 实际占用 = 实际字符数 × 字节/字符 + 1-2 字节长度前缀
--   n 的选择影响: 临时表内存分配（按 n × max_bytes_per_char 分配）、索引长度限制
--
-- 索引长度限制:
--   InnoDB: 单列索引最大 3072 字节（innodb_large_prefix=ON，默认）
--   VARCHAR(768) × 4 字节(utf8mb4) = 3072 字节，刚好是上限
--   超过需要使用前缀索引: INDEX idx_name (col(191))

-- 3.2 DATETIME vs TIMESTAMP: 时间类型的设计选择
-- 这是 MySQL 中最经典的类型选择问题，反映了两种不同的时间语义设计。
--
-- DATETIME: 存储字面值，不做时区转换
--   适用场景: 业务时间（订单创建时间、生日等）
--   存储: 5 字节（5.6.4+），范围 1000-01-01 ~ 9999-12-31
--
-- TIMESTAMP: 内部存储 UTC，读取时按 session time_zone 转换
--   适用场景: 系统时间（审计时间、日志时间等）
--   存储: 4 字节，范围 1970-01-01 ~ 2038-01-19（2038 年问题!）
--
-- 对比其他数据库:
--   PostgreSQL: TIMESTAMP vs TIMESTAMPTZ，官方推荐总是用 TIMESTAMPTZ
--   Oracle:     TIMESTAMP vs TIMESTAMP WITH TIME ZONE vs TIMESTAMP WITH LOCAL TIME ZONE
--   SQL Server: DATETIME vs DATETIME2 vs DATETIMEOFFSET
--   BigQuery:   DATETIME(无时区) vs TIMESTAMP(有时区)
--   ClickHouse: DateTime vs DateTime64（支持纳秒精度）
--
-- 对引擎开发者的启示:
--   时间类型至少需要两种: 带时区和不带时区。
--   需要决定: 内部存储 UTC（如 MySQL TIMESTAMP）还是存原值（如 MySQL DATETIME）？
--   带时区类型推荐内部存 UTC + 显示时转换（PostgreSQL 的做法）。
--   精度: 现代引擎应至少支持微秒（6 位小数），纳秒（9 位）更佳。

-- 3.3 TEXT vs VARCHAR: 大文本类型
-- MySQL 将 TEXT 按大小分为 4 级: TINYTEXT(255) / TEXT(64K) / MEDIUMTEXT(16M) / LONGTEXT(4G)
-- 这是独特的设计，其他数据库的做法:
--   PostgreSQL: TEXT 无大小限制（最大 1GB），推荐代替 VARCHAR
--   Oracle:     CLOB（最大 4GB × 块大小）
--   SQL Server: VARCHAR(MAX)（最大 2GB）
--   SQLite:     TEXT（受 SQLITE_MAX_LENGTH 控制）
--
-- MySQL TEXT 的限制:
--   - TEXT 列不能有默认值（8.0.13 之前）
--   - TEXT 列不能完整索引，只能前缀索引
--   - TEXT 列不参与内存临时表，会强制使用磁盘临时表（影响 ORDER BY 性能）
--   - GROUP BY / ORDER BY TEXT 列性能差
--
-- 对引擎开发者的启示:
--   将大文本分级的设计增加了用户认知负担，现代引擎倾向于统一的 STRING/TEXT 类型。
--   ClickHouse 和 BigQuery 只有 String/STRING，内部自动处理存储。

-- ============================================================
-- 4. CHECK 约束: 一个语法设计的教训
-- ============================================================
-- MySQL 5.7 及之前: 解析 CHECK 约束语法但不执行！静默忽略。
-- MySQL 8.0.16+: CHECK 约束真正执行。
--
-- 这是一个著名的设计失误:
--   接受语法但不执行 → 用户误以为约束在工作 → 生产中出现脏数据
--   PostgreSQL/Oracle/SQL Server 从一开始就执行 CHECK 约束
--
-- 更大的约束执行问题（对引擎开发者）:
--   BigQuery/Snowflake: PRIMARY KEY/UNIQUE/FOREIGN KEY 都是信息性的（不强制执行）
--   设计理由: 分布式环境下强制执行唯一性约束代价极高
--   StarRocks/Doris: 同样不强制约束
--   TiDB: 6.6 之前不支持外键，因为分布式外键的开销太大
--
-- 结论: 约束要么执行，要么不接受语法。接受但不执行是最差的设计选择。

-- ============================================================
-- 5. 分区表语法
-- ============================================================
CREATE TABLE access_logs (
    id         BIGINT NOT NULL AUTO_INCREMENT,
    user_id    BIGINT NOT NULL,
    action     VARCHAR(50) NOT NULL,
    created_at DATETIME NOT NULL,
    PRIMARY KEY (id, created_at)           -- 分区键必须是主键的一部分（MySQL 限制）
) ENGINE=InnoDB
PARTITION BY RANGE (YEAR(created_at)) (
    PARTITION p2023 VALUES LESS THAN (2024),
    PARTITION p2024 VALUES LESS THAN (2025),
    PARTITION p2025 VALUES LESS THAN (2026),
    PARTITION pmax  VALUES LESS THAN MAXVALUE
);

-- 分区设计对比:
--   MySQL:      分区键必须包含在所有唯一索引中（最大限制）
--   PostgreSQL: 10+ 声明式分区，无此限制（分区是独立表）
--   Oracle:     分区功能最丰富（RANGE/LIST/HASH/INTERVAL/REFERENCE），无 MySQL 的限制
--   SQL Server: 通过 PARTITION FUNCTION + PARTITION SCHEME 实现（语法最复杂）
--   Hive/Spark:  分区是目录级别的概念，PARTITIONED BY 定义目录结构
--   BigQuery:   只支持按 DATE/TIMESTAMP/INT 列分区，语法最简单
--   ClickHouse: PARTITION BY 表达式非常灵活（可以用任意表达式）
--   Doris/StarRocks: RANGE/LIST 分区 + HASH 分桶（两级数据分布）
--
-- 对引擎开发者的启示:
--   分区的核心价值是 partition pruning（分区裁剪），语法设计应确保优化器能高效推导。
--   MySQL 的"分区键必须在唯一索引中"是全局唯一性检查的实现限制，分布式引擎更是如此。

-- ============================================================
-- 6. 字符集与排序规则（对引擎开发者重要）
-- ============================================================
-- MySQL 的字符集系统是 4 级层次: Server → Database → Table → Column
-- 每级可以独立设置 CHARACTER SET 和 COLLATE
--
-- utf8 vs utf8mb4 教训:
--   MySQL 的 "utf8" 只支持 3 字节（BMP），不是真正的 UTF-8
--   真正的 UTF-8 需要 "utf8mb4"（4 字节）
--   这是历史遗留问题（早期为了性能限制为 3 字节），8.0 默认改为 utf8mb4
--
-- COLLATE 对引擎的影响:
--   排序规则影响: 索引排序、比较运算、UNIQUE 约束判定
--   utf8mb4_unicode_ci: 大小写不敏感，'a' = 'A'
--   utf8mb4_bin: 二进制比较，'a' ≠ 'A'
--   utf8mb4_0900_ai_ci (8.0 默认): 基于 Unicode 9.0，重音不敏感
--
-- 对引擎开发者的启示:
--   字符集和排序规则是数据库引擎中最复杂的子系统之一。
--   建议: 内部统一 UTF-8，排序规则支持 ICU 库（PostgreSQL 12+ 的做法）。
--   如果支持多字符集，需要处理: 隐式转换、索引比较、JOIN 条件匹配等场景。

-- ============================================================
-- 7. CREATE TABLE ... SELECT / LIKE
-- ============================================================
-- CTAS (Create Table As Select):
CREATE TABLE active_users AS SELECT id, username, email FROM users WHERE age >= 18;
-- 注意: 不复制索引、约束、AUTO_INCREMENT（只复制列定义和数据）
-- 对比: PostgreSQL 的 CREATE TABLE AS 行为相同
--       Oracle 的 CREATE TABLE AS 可以通过 INCLUDING INDEXES 复制索引
--       BigQuery 的 CTAS 是最常用的建表方式（不支持空表 DDL + INSERT 模式）

-- LIKE（复制表结构）:
CREATE TABLE users_backup LIKE users;
-- 复制列定义、索引、约束，但不复制数据
-- 类似 PostgreSQL 的 CREATE TABLE ... (LIKE source INCLUDING ALL)

-- IF NOT EXISTS:
CREATE TABLE IF NOT EXISTS audit_log (
    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    action VARCHAR(50) NOT NULL,
    details JSON,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ============================================================
-- 8. MySQL DDL 的实现特点（对引擎开发者）
-- ============================================================

-- 8.1 Online DDL
-- MySQL 5.6+ 引入 Online DDL，大部分 ALTER TABLE 操作不需要锁全表
-- 三种算法: COPY（全表复制）/ INPLACE（原地修改）/ INSTANT（8.0.12+，瞬间完成）
-- INSTANT 支持: ADD COLUMN（末尾）、修改默认值、RENAME TABLE 等
-- 对比:
--   PostgreSQL: ADD COLUMN + DEFAULT 在 11+ 是即时的（之前需要重写全表）
--   Oracle:     ONLINE DDL + Edition-Based Redefinition（不停机变更）

-- 8.2 原子 DDL（8.0+）
-- MySQL 8.0 引入原子 DDL: DDL 操作要么完全成功要么完全回滚
-- 但注意: DDL 仍然会隐式提交当前事务（与 PostgreSQL/SQL Server 不同）
-- 对比:
--   PostgreSQL: DDL 是事务性的，可以 BEGIN; CREATE TABLE ...; ROLLBACK;
--   SQL Server: DDL 是事务性的
--   Oracle:     DDL 隐式提交（与 MySQL 相同）
--   SQLite:     DDL 是事务性的

-- 8.3 不可见索引（8.0+）
-- CREATE INDEX idx ON t(col) INVISIBLE;
-- 优化器忽略但仍维护，用于安全测试删除索引的影响
-- 对比: Oracle 也有 INVISIBLE INDEX（11g+），PostgreSQL 没有

-- ============================================================
-- 9. 版本演进总结
-- ============================================================
-- MySQL 5.5:  InnoDB 成为默认引擎
-- MySQL 5.6:  Online DDL, InnoDB 全文索引, DATETIME 微秒精度
-- MySQL 5.7:  JSON 类型, 虚拟生成列, sys schema, GROUP REPLICATION
-- MySQL 8.0:  窗口函数, CTE, 原子 DDL, 不可见索引, 降序索引,
--             AUTO_INCREMENT 持久化, utf8mb4 默认, CHECK 约束(8.0.16+),
--             表达式默认值(8.0.13+), 函数索引, 角色(ROLE)
-- MySQL 8.0.31: INTERSECT / EXCEPT
-- MySQL 8.4:  LTS 版本（长期支持），新发布模型的第一个 LTS
-- MySQL 9.0 (2024-07): 向量数据类型 (VECTOR)、JavaScript 存储过程（Enterprise）、
--             EXPLAIN ANALYZE JSON 输出
-- MySQL 9.1 (2024-10): 触发器解析优化
-- MySQL 9.2-9.5: Innovation 版本持续发布（快速迭代，非 LTS）
--
-- 新发布模型（8.4 起）:
--   Innovation Release: 约每 3 个月一个，包含最新特性但支持周期短
--   LTS Release: 长期支持版本（8.4 是首个 LTS），生产环境推荐
--   9.x 系列均为 Innovation Release，快速引入实验性功能
--
-- 对引擎开发者的参考:
--   MySQL 的演进轨迹展示了一个成熟 OLTP 引擎的功能补全路径:
--   先解决核心存储和事务 → 再补充分析能力（窗口函数、CTE）→ 最后完善标准合规性
--   9.x 的 VECTOR 类型标志着 MySQL 开始进入 AI/向量搜索领域

-- ============================================================
-- 横向对比: MySQL vs 其他方言的 CREATE TABLE
-- ============================================================

-- 1. 自增策略对比:
--   MySQL:      AUTO_INCREMENT（简单，但重启可能回退 5.7-，分布式不适用）
--   PostgreSQL: SERIAL（语法糖）-> IDENTITY（10+，SQL 标准，推荐）
--   Oracle:     SEQUENCE（传统，8i+，最早的实现）-> IDENTITY（12c+）
--   SQL Server: IDENTITY（传统）-> SEQUENCE（2012+）
--               IDENTITY vs SEQUENCE 权衡:
--                 IDENTITY 绑定到列，简单但不能跨表共享、不能在非 INSERT 中使用
--                 SEQUENCE 独立对象，灵活但需要额外管理
--                 SET IDENTITY_INSERT ON 才能手动指定值（默认禁止）
--   SQLite:     INTEGER PRIMARY KEY（自动成为 rowid，AUTOINCREMENT 只防止复用）
--   TiDB:       AUTO_INCREMENT（单机语义）-> AUTO_RANDOM（分布式推荐）

-- 2. 数值类型对比:
--   MySQL:      INT(4B) / BIGINT(8B) / DECIMAL(p,s)，类型选择细粒度
--   Oracle:     NUMBER 是唯一的数值类型（Oracle 独有行为）
--               NUMBER(10,0) = 整数，NUMBER(10,2) = 定点数，NUMBER 无参数 = 任意精度
--               没有真正的 INT/BIGINT（INT 只是 NUMBER(38) 的别名）
--               迁移到 MySQL: NUMBER(10,0) -> BIGINT, NUMBER(10,2) -> DECIMAL(10,2)
--   SQL Server: INT(4B) / BIGINT(8B) / DECIMAL(p,s) / MONEY
--               MONEY 类型只有 4 位小数精度，不推荐用于需要灵活精度的场景
--   PostgreSQL: INTEGER(4B) / BIGINT(8B) / NUMERIC(p,s)，类似 MySQL

-- 3. '' = NULL（Oracle 独有行为）:
--   Oracle:     空字符串 '' 等于 NULL！这是 Oracle 最大最著名的坑
--               VARCHAR2 列即使有 NOT NULL 约束，INSERT '' 也会失败（因为 '' 就是 NULL）
--               WHERE column = '' 永远不返回行（NULL = NULL 为 UNKNOWN）
--               从 MySQL 迁移到 Oracle 时: 所有空字符串相关逻辑都需要重写
--               从 Oracle 迁移到 MySQL 时: NULL 和 '' 的处理逻辑需要区分
--   MySQL:      '' 是空字符串，与 NULL 完全不同
--   PostgreSQL: '' 是空字符串，与 NULL 完全不同
--   SQL Server: '' 是空字符串，与 NULL 完全不同

-- 4. DDL 事务性对比:
--   MySQL:      DDL 隐式提交事务（不能回滚 CREATE TABLE），8.0+ 原子 DDL 保证单个 DDL 原子性
--   PostgreSQL: DDL 是事务性的！可以 BEGIN; CREATE TABLE ...; ROLLBACK;
--   Oracle:     DDL 隐式提交（同 MySQL），DDL 前后各有一个隐式 COMMIT
--   SQL Server: DDL 是事务性的（同 PostgreSQL），可以在事务中回滚
--   SQLite:     DDL 是事务性的（同 PostgreSQL）

-- 5. 聚集索引概念（SQL Server / InnoDB 共有）:
--   SQL Server: 每表有且仅有一个聚集索引（Clustered Index）= 表的物理排列顺序
--               默认主键就是聚集索引，选择不当严重影响性能
--               非聚集索引的叶节点存储聚集索引键（不是行地址）
--   MySQL:      InnoDB 主键也是聚集索引（二级索引叶节点存主键值），与 SQL Server 类似
--   PostgreSQL: 没有聚集索引概念，所有索引指向堆表的物理位置（ctid）
--   Oracle:     默认堆表，IOT（Index-Organized Table）需显式创建

-- 6. 在线 DDL 对比:
--   MySQL:      5.6+ Online DDL，8.0.12+ ALGORITHM=INSTANT（部分操作不锁表）
--   PostgreSQL: ADD COLUMN + 非 NULL 默认值在 11+ 是即时的
--   Oracle:     ONLINE 关键字，Edition-Based Redefinition（最强大的在线变更能力）
--   SQL Server: ONLINE = ON（仅 Enterprise 版，Standard 版不支持）

-- 7. 类型严格度对比:
--   MySQL:      宽松（会隐式转换，如 '123' + 0 = 123）
--   PostgreSQL: 严格（需要显式 CAST，如 '123'::INTEGER）
--   Oracle:     中等（TO_NUMBER/TO_CHAR 显式转换为主）
--   SQL Server: 中等（CONVERT/CAST，有些隐式转换）
--   SQLite:     极度宽松（动态类型，任何列可以存任何类型，除非 STRICT 模式）

-- 8. 字符集对比:
--   MySQL:      utf8 != UTF-8！utf8 只支持 3 字节，必须用 utf8mb4
--   PostgreSQL: UTF-8 就是真正的 UTF-8，建库时指定
--   Oracle:     AL32UTF8 = 真正的 UTF-8
--   SQL Server: NVARCHAR 用 UTF-16；2019+ VARCHAR 可用 UTF-8 排序规则
--   SQLite:     默认 UTF-8，内置 UTF-16 支持

-- 9. CHECK 约束对比:
--   MySQL:      5.7 及之前解析 CHECK 但不执行！8.0.16+ 才真正生效
--   PostgreSQL: 从第一个版本就完美支持 CHECK
--   Oracle:     完整支持 CHECK
--   SQL Server: 完整支持 CHECK

-- 10. 分区表对比:
--   MySQL:      分区键必须包含在主键和所有唯一索引中（最大限制）
--   PostgreSQL: 声明式分区（10+），主键也必须包含分区键，支持 DEFAULT 分区（11+）
--   Oracle:     分区功能最强大（Composite/Interval/Reference 分区等），不要求分区键在主键中
--               但需要 Enterprise Edition（费用高昂）
--   SQL Server: 需要创建 PARTITION FUNCTION + PARTITION SCHEME（步骤最多）

-- 11. MERGE 语句与 UPSERT 对比:
--   MySQL:      没有 MERGE，使用 INSERT ... ON DUPLICATE KEY UPDATE 或 REPLACE INTO
--   Oracle:     MERGE 从 9i 开始就有，是最早支持的数据库，实现最成熟稳定
--   PostgreSQL: INSERT ... ON CONFLICT (9.5+) 是原生 UPSERT，MERGE 在 15 才加入
--   SQL Server: MERGE 有大量已知 Bug，多位 MVP 公开建议避免使用
--               替代: IF EXISTS UPDATE ELSE INSERT 或单独的 INSERT/UPDATE
