-- Oracle: ALTER TABLE
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - ALTER TABLE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/ALTER-TABLE.html
--   [2] Oracle Database Administrator's Guide - Managing Tables
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/admin/managing-tables.html

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- 添加列（注意括号是 Oracle 特有要求）
ALTER TABLE users ADD (phone VARCHAR2(20));
ALTER TABLE users ADD (phone VARCHAR2(20) DEFAULT 'N/A' NOT NULL);

-- 添加多列
ALTER TABLE users ADD (
    city    VARCHAR2(64),
    country VARCHAR2(64)
);

-- 修改列类型 / 大小（Oracle 用 MODIFY，不是 ALTER COLUMN）
ALTER TABLE users MODIFY (phone VARCHAR2(32));
ALTER TABLE users MODIFY (phone VARCHAR2(32) NOT NULL);

-- 多列一起修改
ALTER TABLE users MODIFY (
    phone VARCHAR2(32) NOT NULL,
    email VARCHAR2(320)
);

-- 9i R2+: 重命名列
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- 删除列
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP (phone, city);           -- 一次删除多列

-- 标记列为未使用（大表删列更快，先标记再后台清理）
ALTER TABLE users SET UNUSED COLUMN phone;
ALTER TABLE users DROP UNUSED COLUMNS;

-- 修改默认值
ALTER TABLE users MODIFY (status NUMBER(1) DEFAULT 0);

-- 重命名表
ALTER TABLE users RENAME TO members;

-- 只读表（11g+，Oracle 独有）
ALTER TABLE users READ ONLY;
ALTER TABLE users READ WRITE;

-- ============================================================
-- 2. 设计决策分析（对 SQL 引擎开发者）
-- ============================================================

-- 2.1 ADD/MODIFY 语法设计: 括号包裹 vs 逐列声明
-- Oracle 的 ADD/MODIFY 要求括号包裹列定义，这是独特的语法选择。
--
-- 语法对比:
--   Oracle:     ALTER TABLE t ADD (col1 NUMBER, col2 VARCHAR2(10));
--   MySQL:      ALTER TABLE t ADD COLUMN col1 INT, ADD COLUMN col2 VARCHAR(10);
--   PostgreSQL: ALTER TABLE t ADD COLUMN col1 INT, ADD COLUMN col2 VARCHAR(10);
--   SQL Server: ALTER TABLE t ADD col1 INT, col2 VARCHAR(10);
--
-- Oracle 的括号语法更紧凑，但 MODIFY 关键字也是 Oracle 独有:
--   Oracle:     ALTER TABLE t MODIFY (col VARCHAR2(32));
--   PostgreSQL: ALTER TABLE t ALTER COLUMN col TYPE VARCHAR(32);
--   MySQL:      ALTER TABLE t MODIFY COLUMN col VARCHAR(32);  (语法相同但无括号)
--   SQL Server: ALTER TABLE t ALTER COLUMN col VARCHAR(32);
--
-- 对引擎开发者的启示:
--   解析器实现上，Oracle 的括号方式更简单（统一用括号包列列表），
--   但与 SQL 标准差异较大。如果目标是标准兼容，应采用 ALTER COLUMN 语法。

-- 2.2 SET UNUSED: 延迟删除列的设计
-- Oracle 独有的二阶段列删除策略:
--   第一阶段: SET UNUSED -- 立即将列标记为不可见（秒级，只修改数据字典）
--   第二阶段: DROP UNUSED COLUMNS -- 后台物理清理（可以在低峰期执行）
--
-- 设计动机:
--   大表 DROP COLUMN 需要重写所有行，耗时且持有排他锁。
--   SET UNUSED 只修改元数据，不触碰数据页，因此是瞬时操作。
--
-- 横向对比:
--   PostgreSQL: DROP COLUMN 也只修改元数据，不立即重写（MVCC 的优势）
--               已删列在 VACUUM FULL 时才物理清理
--   MySQL:      DROP COLUMN 需要重建表（5.6+ ONLINE DDL 可以减少锁时间）
--   SQL Server: DROP COLUMN 只修改元数据（类似 PostgreSQL）
--
-- 对引擎开发者的启示:
--   如果存储格式支持逻辑删除列（在行头维护列有效性位图），
--   则 DROP COLUMN 可以做到瞬时。Oracle 的 SET UNUSED 是一种折衷方案。

-- 2.3 Online DDL 与即时操作
-- 12c+: 添加带 DEFAULT + NOT NULL 的列是即时操作（不重写表）
-- 11g+: 同上（但有更多限制）
--
-- 实现原理:
--   默认值存储在数据字典中，已有行在读取时"虚拟"填充默认值。
--   只有新写入或更新的行才物理写入新列值。
--
-- 对比:
--   PostgreSQL 11+: ADD COLUMN + DEFAULT 也是即时的（相同原理）
--   MySQL 8.0.12+:  ALGORITHM=INSTANT 支持末尾加列（但加在中间不行）
--   SQL Server:     ADD COLUMN + DEFAULT 仍需要重写表
--
-- Oracle 独有的高级 Online DDL:
--   Edition-Based Redefinition (EBR): 通过版本化实现在线表结构变更
--   DBMS_REDEFINITION: 在线重定义表（改分区策略、存储属性等）

-- ============================================================
-- 3. '' = NULL 的影响
-- ============================================================
-- ALTER TABLE 修改默认值时需要注意:
ALTER TABLE users MODIFY (bio VARCHAR2(4000) DEFAULT '');
-- 危险! 上面的 DEFAULT '' 实际等于 DEFAULT NULL，因为 Oracle 中 '' = NULL
-- 如果列有 NOT NULL 约束，插入不带 bio 的行会报错

-- 正确做法: 使用有意义的默认值
ALTER TABLE users MODIFY (bio VARCHAR2(4000) DEFAULT ' ');  -- 一个空格不是NULL

-- ============================================================
-- 4. 虚拟列与不可见列
-- ============================================================

-- 虚拟列（11g+，计算列，类似 PostgreSQL GENERATED ALWAYS AS (STORED)）
ALTER TABLE users ADD (full_name VARCHAR2(200) GENERATED ALWAYS AS (
    first_name || ' ' || last_name
) VIRTUAL);
-- 虚拟列不存储数据，查询时实时计算，可以建索引

-- 不可见列（12c+）
ALTER TABLE users ADD (internal_flag NUMBER(1) INVISIBLE);
-- SELECT * 不返回不可见列，但可以显式查询: SELECT internal_flag FROM users

-- ============================================================
-- 5. 表压缩与存储属性
-- ============================================================
ALTER TABLE orders COMPRESS FOR OLTP;           -- OLTP 压缩（11g R2+）
ALTER TABLE orders COMPRESS FOR QUERY HIGH;     -- 混合列压缩（Exadata）
ALTER TABLE orders NOCOMPRESS;                   -- 取消压缩

ALTER TABLE orders MOVE TABLESPACE archive_ts;  -- 移动到其他表空间
ALTER TABLE orders MOVE ONLINE;                  -- 12c+: 在线移动

-- ============================================================
-- 6. 横向对比: ALTER TABLE 能力矩阵
-- ============================================================

-- 1. DDL 事务性:
--   Oracle:     DDL 隐式提交（DDL 前后各一个 COMMIT），不可回滚
--   PostgreSQL: DDL 是事务性的，可以 ROLLBACK
--   MySQL:      DDL 隐式提交（同 Oracle）
--   SQL Server: DDL 事务性的（同 PostgreSQL）
--
-- 2. 列重命名:
--   Oracle:     ALTER TABLE t RENAME COLUMN old TO new (9i R2+)
--   PostgreSQL: ALTER TABLE t RENAME COLUMN old TO new
--   MySQL:      ALTER TABLE t RENAME COLUMN old TO new (8.0+)
--               ALTER TABLE t CHANGE old new TYPE (旧语法)
--   SQL Server: sp_rename 't.old', 'new', 'COLUMN' (存储过程)
--
-- 3. 只读表:
--   Oracle:     ALTER TABLE t READ ONLY (11g+) -- 唯一原生支持的数据库
--   其他数据库: 需要通过权限控制实现

-- ============================================================
-- 7. 数据字典查询
-- ============================================================

-- Oracle 三层数据字典视图（Oracle 独有架构）:
-- USER_* : 当前用户的对象
-- ALL_*  : 当前用户可访问的对象
-- DBA_*  : 全库对象（需要 DBA 权限）

-- 查看列信息
SELECT column_name, data_type, data_length, nullable, data_default
FROM user_tab_columns
WHERE table_name = 'USERS'
ORDER BY column_id;

-- 查看未使用列
SELECT * FROM user_unused_col_tabs;

-- 查看表属性
SELECT table_name, tablespace_name, compression, read_only
FROM user_tables
WHERE table_name = 'USERS';

-- 对引擎开发者的启示:
--   Oracle 的三层数据字典（USER_/ALL_/DBA_）是一个优秀的元数据设计模式。
--   它通过视图层隔离了权限边界，避免用户看到无权访问的对象。
--   PostgreSQL 的 information_schema 遵循 SQL 标准但功能不如 Oracle 丰富。
--   如果设计新引擎，建议同时提供标准 information_schema 和扩展的系统视图。
