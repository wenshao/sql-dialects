-- Apache Derby: 窗口函数实战分析
--
-- 参考资料:
--   [1] Apache Derby Documentation - Window Functions (Derby 10.12+)
--       https://db.apache.org/derby/docs/10.16/ref/rrefsqlj31580.html

-- ============================================================
-- 注意：Derby 对窗口函数支持有限
-- Derby 10.12+ 支持 ROW_NUMBER
-- Derby 不支持大部分窗口函数（RANK, LAG, LEAD 等）
-- ============================================================

-- ============================================================
-- 1. ROW_NUMBER（Derby 支持的主要窗口函数）
-- ============================================================

SELECT emp_id, department, salary,
       ROW_NUMBER() OVER (ORDER BY salary DESC) AS salary_rank
FROM employee_salaries;

-- 按部门排名
SELECT emp_id, department, salary,
       ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary DESC) AS dept_rank
FROM employee_salaries;

-- ============================================================
-- 2. 模拟排名（无 RANK/DENSE_RANK）
-- ============================================================

-- 使用子查询模拟 RANK
SELECT e.emp_id, e.department, e.salary,
       (SELECT COUNT(*) + 1 FROM employee_salaries e2
        WHERE e2.salary > e.salary) AS salary_rank
FROM employee_salaries e
ORDER BY e.salary DESC;

-- ============================================================
-- 3. 模拟 LAG / LEAD（使用自连接）
-- ============================================================

-- 模拟 LAG（前一天数据）
SELECT a.sale_date, a.amount,
       b.amount AS prev_day_amount,
       a.amount - COALESCE(b.amount, 0) AS daily_change
FROM daily_sales a
LEFT JOIN daily_sales b ON b.sale_date = (
    SELECT MAX(sale_date) FROM daily_sales
    WHERE sale_date < a.sale_date
)
ORDER BY a.sale_date;

-- ============================================================
-- 4. 模拟累计求和（使用关联子查询）
-- ============================================================

SELECT a.sale_date, a.amount,
       (SELECT SUM(b.amount) FROM daily_sales b
        WHERE b.sale_date <= a.sale_date) AS running_total
FROM daily_sales a
ORDER BY a.sale_date;

-- ============================================================
-- 5. 占比（使用子查询）
-- ============================================================

SELECT product_id,
       SUM(amount) AS product_total,
       SUM(amount) * 100.0 / (SELECT SUM(amount) FROM daily_sales) AS pct_of_total
FROM daily_sales
GROUP BY product_id;

-- ============================================================
-- 6. 中位数（使用子查询）
-- ============================================================

SELECT department, AVG(salary) AS median_salary
FROM (
    SELECT department, salary,
           ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary) AS rn,
           (SELECT COUNT(*) FROM employee_salaries e2
            WHERE e2.department = e.department) AS cnt
    FROM employee_salaries e
) ranked
WHERE rn IN (cnt / 2, cnt / 2 + 1)
   OR (cnt = 1)
GROUP BY department;

-- Derby 窗口函数支持极为有限：
-- 仅支持 ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...)
-- 不支持 RANK, DENSE_RANK, NTILE, LAG, LEAD
-- 不支持 FIRST_VALUE, LAST_VALUE, NTH_VALUE
-- 不支持 PERCENT_RANK, CUME_DIST
-- 不支持 SUM/AVG/COUNT OVER (...)
-- 需要使用自连接或关联子查询模拟大部分窗口函数
