-- MySQL: 索引
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - CREATE INDEX
--       https://dev.mysql.com/doc/refman/8.0/en/create-index.html
--   [2] MySQL 8.0 Reference Manual - InnoDB Indexes
--       https://dev.mysql.com/doc/refman/8.0/en/innodb-index-types.html
--   [3] MySQL 8.0 Reference Manual - Invisible Indexes
--       https://dev.mysql.com/doc/refman/8.0/en/invisible-indexes.html
--   [4] MySQL 8.0 Reference Manual - EXPLAIN Output
--       https://dev.mysql.com/doc/refman/8.0/en/explain-output.html

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- 普通索引
CREATE INDEX idx_age ON users (age);

-- 唯一索引
CREATE UNIQUE INDEX uk_email ON users (email);

-- 复合索引（最左前缀原则: 查询必须从最左列开始才能利用索引）
CREATE INDEX idx_city_age ON users (city, age);

-- 前缀索引（对长字符串只索引前 N 个字符，节省空间但无法用于 ORDER BY）
CREATE INDEX idx_email_prefix ON users (email(20));

-- 全文索引（5.6+ InnoDB 支持，之前仅 MyISAM）
CREATE FULLTEXT INDEX idx_ft_bio ON users (bio);

-- 空间索引（SPATIAL，要求列为 NOT NULL 的 GEOMETRY 类型）
CREATE SPATIAL INDEX idx_location ON places (geo_point);

-- 降序索引（8.0+ 才真正支持; 5.7 解析语法但忽略 DESC，实际仍 ASC）
CREATE INDEX idx_created_desc ON users (created_at DESC);

-- 函数索引 / 表达式索引（8.0+，底层通过隐藏的虚拟生成列实现）
CREATE INDEX idx_upper_name ON users ((UPPER(username)));
CREATE INDEX idx_json_name ON users ((CAST(data->>'$.name' AS CHAR(64))));

-- 指定索引类型
CREATE INDEX idx_age ON users (age) USING BTREE;      -- 默认（InnoDB 只支持 BTREE）
CREATE INDEX idx_hash ON users (username) USING HASH;  -- 仅 MEMORY/NDB 引擎

-- 删除索引
DROP INDEX idx_age ON users;
ALTER TABLE users DROP INDEX idx_age;  -- 等价语法
-- 注意: MySQL 不支持 DROP INDEX IF EXISTS（MariaDB 扩展语法）

-- 查看索引
SHOW INDEX FROM users;

-- ============================================================
-- 2. InnoDB 聚集索引与二级索引（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 聚集索引（Clustered Index）
-- InnoDB 的表数据按主键（聚集索引）的 B+树组织存储:
--   - 叶子节点存储完整的行数据（数据和索引合一）
--   - 每张表有且仅有一个聚集索引
--   - 选择规则: 显式 PRIMARY KEY > 第一个 NOT NULL UNIQUE 索引 > 隐藏 ROW_ID（6字节）
--
-- 对引擎开发者的启示:
--   聚集索引 vs 堆表（Heap Table）是存储引擎的核心设计选择:
--   InnoDB/SQL Server: 聚集索引模型，主键查找 O(log n)，但主键变更代价高
--   PostgreSQL:        堆表模型，所有索引平等指向 ctid（物理地址），HOT 优化减少索引更新
--   Oracle:            默认堆表，IOT（Index-Organized Table）需显式创建
--   优劣: 聚集索引主键范围扫描效率极高（数据物理连续）；堆表对非主键索引更友好

-- 2.2 二级索引（Secondary Index）与回表问题
-- InnoDB 二级索引的叶子节点存储: 索引列值 + 主键值（不是行地址）
-- 通过二级索引查询非索引列时:
--   Step 1: 在二级索引 B+树中找到匹配的主键值
--   Step 2: 用主键值到聚集索引 B+树中查找完整行（回表, Table Lookup）
--
-- 性能影响:
--   回表的随机 I/O 可能成为瓶颈（尤其当结果集大且数据不在 Buffer Pool 中时）
--   优化器会估算回表代价，如果太高则放弃使用二级索引，改为全表扫描
--   经验值: 当查询结果超过全表约 15-25% 时，优化器可能选择全表扫描
--
-- 对比 PostgreSQL 的设计:
--   PG 的索引叶子节点存储 ctid（物理位置），不需要经过聚集索引跳转
--   代价: 行移动时（UPDATE）需要更新所有索引，或使用 HOT 链指向新位置
--   InnoDB 的优势: UPDATE 主键值以外的列时，二级索引无需更新（主键值不变）

-- ============================================================
-- 3. 覆盖索引（Covering Index）
-- ============================================================

-- 如果查询所需的所有列都在索引中，则无需回表（Extra: Using index）
-- 这是 InnoDB 下最重要的索引优化技术之一

CREATE INDEX idx_covering ON users (city, age, username);

-- 以下查询完全在索引中完成，不需要回表:
-- SELECT username, age FROM users WHERE city = 'Beijing' ORDER BY age;
-- EXPLAIN 输出: Extra 列显示 "Using index"

-- 覆盖索引的设计原则:
--   1) 将 WHERE 条件列放在索引前面（满足最左前缀）
--   2) 将 ORDER BY 列紧跟其后（避免 filesort）
--   3) 将 SELECT 需要的列也加入索引（避免回表）
--   4) 权衡: 宽索引增加写入开销和存储空间

-- 对比 PostgreSQL INCLUDE 索引（11+）:
--   CREATE INDEX idx ON users (city, age) INCLUDE (username);
--   INCLUDE 列: 只存储在叶子节点，不参与 B 树排序，不增加非叶节点大小
--   MySQL 没有 INCLUDE 语法，只能把所有列都放入索引键（增加索引层数）
--   SQL Server 也支持 INCLUDE（2005+），设计与 PostgreSQL 一致
--
-- 对引擎开发者的启示:
--   INCLUDE 语法是更优的覆盖索引设计:
--   - 非叶节点更小 -> 扇出度更高 -> 树更矮 -> 更少的 I/O
--   - 明确区分 "用于搜索" 和 "用于投影" 的列
--   - MySQL 至今（8.4）仍未支持 INCLUDE，这是一个已知的功能缺失

-- ============================================================
-- 4. 不可见索引（Invisible Index，8.0+）
-- ============================================================

-- 4.1 基本语法
CREATE INDEX idx_age ON users (age) INVISIBLE;
ALTER TABLE users ALTER INDEX idx_age INVISIBLE;   -- 设为不可见
ALTER TABLE users ALTER INDEX idx_age VISIBLE;     -- 恢复可见

-- 4.2 语义: 优化器忽略该索引（不用于查询计划），但 InnoDB 仍然维护它
-- 索引仍会在 INSERT/UPDATE/DELETE 时更新，唯一索引的唯一性约束仍然生效

-- 4.3 使用场景（这是一个极其实用的运维特性）:
--   a. 安全删除索引的前置测试:
--      先 ALTER INDEX ... INVISIBLE -> 观察慢查询日志/性能指标 -> 确认无影响再 DROP
--      比直接 DROP INDEX 安全得多（DROP 后重建大表索引可能耗时数小时）
--   b. 灰度测试新索引:
--      先创建 INVISIBLE 索引（不影响现有查询计划）-> 用 EXPLAIN 验证 -> 确认有效再 VISIBLE
--   c. 调试性能问题: 逐个 INVISIBLE 索引来确定哪个索引对特定查询至关重要

-- 4.4 绕过不可见: 会话级 optimizer switch 可以强制使用不可见索引
-- SET SESSION optimizer_switch = 'use_invisible_indexes=on';

-- 对比其他引擎:
--   Oracle:    11g+ 支持 INVISIBLE INDEX，语义与 MySQL 相同，实现更早
--   PG:        没有原生的不可见索引，但可以通过 pg_hint_plan + 手动 DROP/CREATE 间接实现
--   SQL Server: 没有不可见索引，可以用 DISABLE/REBUILD 但 DISABLE 会停止维护（完全不同语义）
--
-- 对引擎开发者的启示:
--   不可见索引的核心价值是将 "索引存在" 和 "优化器使用" 解耦
--   实现成本低（只需要在优化器的索引枚举阶段过滤掉 INVISIBLE 标记的索引）
--   但收益极高（安全运维、性能调试），建议所有引擎都支持此特性

-- ============================================================
-- 5. 横向对比: 各引擎的索引设计
-- ============================================================

-- 5.1 索引结构对比:
--   MySQL InnoDB: B+树（聚集索引 + 二级索引），所有索引都是 B+树
--   PostgreSQL:   B-tree(默认)、Hash、GiST（空间/范围）、GIN（倒排/全文）、BRIN（块范围摘要）、SP-GiST
--                 PG 的索引类型远比 MySQL 丰富，可通过 Extension 添加自定义索引类型
--   Oracle:       B-tree(默认)、Bitmap（低基数列，OLAP 场景）、Bitmap Join Index
--   SQL Server:   B+树（Clustered/Nonclustered），Columnstore Index（列存索引，OLAP 加速）
--   ClickHouse:   没有传统 B+树索引! 使用跳数索引（Skip Index）:
--                 minmax（范围摘要）、set（集合）、bloom_filter（布隆过滤器）、ngrambf（n-gram 布隆过滤器）
--                 设计理由: 列存引擎的查询模式是大范围扫描，B+树的随机 I/O 无意义
--                 跳数索引只判断 "某个数据块是否值得读取"，不做精确定位

-- 5.2 索引创建的并发控制:
--   MySQL:      CREATE INDEX 默认 INPLACE + LOCK=NONE（8.0+），仍会短暂阻塞
--   PostgreSQL: CREATE INDEX CONCURRENTLY（不阻塞写，但耗时更长，需两遍扫描）
--               失败时不自动清理（留下 INVALID 索引），需要手动 DROP
--   Oracle:     CREATE INDEX ... ONLINE（阻塞最小化）
--   SQL Server: CREATE INDEX ... WITH (ONLINE = ON)（仅 Enterprise Edition）

-- 5.3 索引提示对比:
--   MySQL:      USE INDEX / FORCE INDEX / IGNORE INDEX（查询级别）
--   PostgreSQL: 无原生语法，社区使用 pg_hint_plan 扩展
--   Oracle:     /*+ INDEX(t idx_name) */ 提示语法（最成熟的 hint 体系）
--   SQL Server: WITH (INDEX(idx_name)) 提示

-- 对引擎开发者的总结:
--   1) B+树聚集索引 vs 堆表是存储模型的根本选择，影响所有后续设计
--   2) 覆盖索引 + INCLUDE 列是减少回表的标准方案，新引擎应从一开始就支持 INCLUDE
--   3) 不可见索引是低成本高收益特性，强烈建议实现
--   4) 列存/分析引擎不要照搬 B+树索引，跳数索引（zone map / min-max index）更合理
--   5) 在线索引创建（不阻塞 DML）是生产环境的刚需
