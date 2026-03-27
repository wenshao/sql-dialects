-- Oracle: INSERT
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - INSERT
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/INSERT.html
--   [2] Oracle SQL Language Reference - Multitable INSERT
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/INSERT.html

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- 单行插入
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 从查询结果插入
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- 获取自增 ID（序列）
INSERT INTO users (id, username, email)
VALUES (users_seq.NEXTVAL, 'alice', 'alice@example.com');

-- 12c+: IDENTITY 列自动生成 ID，无需指定

-- ============================================================
-- 2. 多行插入（Oracle 独有设计: INSERT ALL）
-- ============================================================

-- 2.1 INSERT ALL（Oracle 9i+，其他数据库无此语法）
INSERT ALL
    INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25)
    INTO users (username, email, age) VALUES ('bob', 'bob@example.com', 30)
    INTO users (username, email, age) VALUES ('charlie', 'charlie@example.com', 35)
SELECT 1 FROM DUAL;

-- 设计分析: 为什么需要 SELECT 1 FROM DUAL?
--   INSERT ALL 的语法设计基于"从源数据分发到目标表"的模型。
--   即使是常量值，也需要一个形式上的 SELECT 子句。
--   这源于 Oracle 不允许无 FROM 的 SELECT（DUAL 表要求）。
--
-- 横向对比: 标准多行 VALUES 语法:
--   MySQL:      INSERT INTO t VALUES (1,'a'), (2,'b'), (3,'c');
--   PostgreSQL: INSERT INTO t VALUES (1,'a'), (2,'b'), (3,'c');
--   SQL Server: INSERT INTO t VALUES (1,'a'), (2,'b'), (3,'c');
--   Oracle:     23c+ 才支持标准多行 VALUES!
--               23c 之前必须用 INSERT ALL ... SELECT FROM DUAL
--
-- 对引擎开发者的启示:
--   标准的多行 VALUES 语法简单实用，应该优先实现。
--   INSERT ALL 的价值在于条件多表插入（见下文），不在于多行插入。

-- 2.2 条件多表插入（Oracle 独有杀手级特性，9i+）
INSERT ALL
    WHEN age < 30 THEN INTO young_users (username, age) VALUES (username, age)
    WHEN age >= 30 THEN INTO senior_users (username, age) VALUES (username, age)
SELECT username, age FROM candidates;

-- INSERT FIRST（只插入第一个匹配的条件）
INSERT FIRST
    WHEN age < 18 THEN INTO minors (username, age) VALUES (username, age)
    WHEN age < 65 THEN INTO adults (username, age) VALUES (username, age)
    ELSE INTO seniors (username, age) VALUES (username, age)
SELECT username, age FROM candidates;

-- 设计分析:
--   INSERT ALL:  每行检查所有条件，可能插入多个目标表
--   INSERT FIRST: 每行只插入第一个匹配的目标表（类似 CASE 的短路逻辑）
--
-- 场景: ETL 数据分流（一次扫描源表，按条件分发到不同目标表）
--
-- 其他数据库的替代方案:
--   PostgreSQL: 多个 INSERT ... SELECT ... WHERE ...（多次扫描源表）
--               或使用 CTE: WITH src AS (...) INSERT INTO t1 SELECT ... UNION ALL INSERT INTO t2 ...
--   MySQL:      多个 INSERT ... SELECT ... WHERE ...
--   SQL Server: 多个 INSERT ... SELECT 或使用 MERGE
--
-- 对引擎开发者的启示:
--   条件多表插入对 ETL 和数据仓库场景非常有价值。
--   实现关键: 只扫描源数据一次，通过条件路由分发到不同目标。

-- ============================================================
-- 3. RETURNING 子句
-- ============================================================

-- PL/SQL 中返回插入的值
DECLARE v_id NUMBER;
BEGIN
    INSERT INTO users (id, username, email)
    VALUES (users_seq.NEXTVAL, 'alice', 'alice@example.com')
    RETURNING id INTO v_id;
    DBMS_OUTPUT.PUT_LINE('Inserted id: ' || v_id);
END;
/

-- 横向对比:
--   Oracle:     RETURNING ... INTO（只在 PL/SQL 中可用）
--   PostgreSQL: RETURNING *（在 SQL 层面直接返回，更强大）
--   SQL Server: OUTPUT inserted.*（类似 PostgreSQL）
--   MySQL:      LAST_INSERT_ID()（只能获取自增 ID）

-- ============================================================
-- 4. '' = NULL 对 INSERT 的影响
-- ============================================================

-- 插入空字符串:
INSERT INTO users (username, email, bio) VALUES ('alice', 'a@e.com', '');
-- bio 列实际存储的是 NULL，不是空字符串！

-- 如果 bio 有 NOT NULL 约束:
--   上面的 INSERT 会报错 ORA-01400: cannot insert NULL
--   因为 '' 就是 NULL，违反 NOT NULL

-- 其他数据库中完全不同:
--   PostgreSQL: '' 是合法的非 NULL 空字符串
--   MySQL:      '' 是合法的非 NULL 空字符串
--   SQL Server: '' 是合法的非 NULL 空字符串

-- 对引擎开发者的启示:
--   '' = NULL 是 Oracle 最大的设计遗留问题。
--   新引擎应严格区分 NULL 和空字符串（SQL 标准行为）。

-- ============================================================
-- 5. 直接路径插入（Direct-Path INSERT，Oracle 独有优化）
-- ============================================================

-- 绕过 Buffer Cache 直接写入数据文件，跳过 undo 生成
INSERT /*+ APPEND */ INTO users_archive
SELECT * FROM users WHERE status = 0;

-- 并行直接路径插入
INSERT /*+ APPEND PARALLEL(8) */ INTO users_archive
SELECT * FROM users WHERE status = 0;

-- 注意:
--   APPEND 提示只适用于 INSERT ... SELECT，不适用于 VALUES
--   直接路径插入后表段会被锁定，需要 COMMIT 后才能查询
--   不记录 redo（NOLOGGING 表）时可获得最大速度
--
-- 对引擎开发者的启示:
--   直接路径插入（绕过缓存直接写入存储）是大批量加载的标准优化。
--   类似概念: ClickHouse 的批量写入、Spark 的 Direct Write。

-- ============================================================
-- 6. 23c+: 标准多行 VALUES 语法
-- ============================================================
-- Oracle 23c 终于支持了其他数据库早已有的标准语法:
-- INSERT INTO users (username, email) VALUES ('alice', 'a@e.com'), ('bob', 'b@e.com');

-- ============================================================
-- 7. 对引擎开发者的总结
-- ============================================================
-- 1. INSERT ALL/FIRST 条件多表插入是 Oracle 独有的 ETL 利器，值得借鉴。
-- 2. DUAL 表的必要性是 Oracle 语法的历史包袱，新引擎应允许无 FROM 的 SELECT。
-- 3. '' = NULL 导致 NOT NULL 列不接受空字符串，这是迁移的最大障碍。
-- 4. APPEND 直接路径插入是大批量加载的标准优化模式。
-- 5. RETURNING 在 PL/SQL 中可用但不如 PostgreSQL 的纯 SQL RETURNING 灵活。
