-- Oracle: INSERT
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - INSERT
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/INSERT.html
--   [2] Oracle SQL Language Reference - Multitable INSERT
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/INSERT.html

-- 单行插入
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 从查询结果插入
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- 多行插入（用 INSERT ALL）
INSERT ALL
    INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25)
    INTO users (username, email, age) VALUES ('bob', 'bob@example.com', 30)
    INTO users (username, email, age) VALUES ('charlie', 'charlie@example.com', 35)
SELECT 1 FROM dual;

-- 条件多表插入
INSERT ALL
    WHEN age < 30 THEN INTO young_users (username, age) VALUES (username, age)
    WHEN age >= 30 THEN INTO senior_users (username, age) VALUES (username, age)
SELECT username, age FROM candidates;

-- INSERT FIRST（只插入第一个匹配的）
INSERT FIRST
    WHEN age < 18 THEN INTO minors (username, age) VALUES (username, age)
    WHEN age < 65 THEN INTO adults (username, age) VALUES (username, age)
    ELSE INTO seniors (username, age) VALUES (username, age)
SELECT username, age FROM candidates;

-- 获取自增 ID（序列）
INSERT INTO users (id, username, email)
VALUES (users_seq.NEXTVAL, 'alice', 'alice@example.com');

-- 12c+: IDENTITY 列自动生成 ID

-- RETURNING（返回插入的值到变量，PL/SQL 中使用）
-- INSERT INTO users (...) VALUES (...) RETURNING id INTO v_id;

-- 指定默认值
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', DEFAULT);

-- 23c+: 直接 VALUES 多行语法（与其他数据库一致）
-- INSERT INTO users (username, email) VALUES ('alice', 'a@e.com'), ('bob', 'b@e.com');
