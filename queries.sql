-- ============================================================
-- День 2 — Retention, когорты, конверсия
-- Отработано на нескольких датасетах (стриминг, школа, еда)
-- ============================================================


-- ------------------------------------------------------------
-- 1. КОГОРТА: месяц первого действия каждого пользователя
-- ------------------------------------------------------------
-- Когорта = месяц, в котором пользователь впервые проявил активность.
-- Считается от MIN(дата), потом форматируется в месяц.

WITH first_action AS (
  SELECT user_id, MIN(play_date) AS start_date
  FROM plays
  GROUP BY user_id
)
SELECT user_id,
       strftime('%Y-%m', start_date) AS cohort_month
FROM first_action;


-- ------------------------------------------------------------
-- 2. РАЗМЕР КОГОРТ: сколько пользователей стартовало в каждом месяце
-- ------------------------------------------------------------

WITH first_action AS (
  SELECT user_id, MIN(play_date) AS start_date
  FROM plays
  GROUP BY user_id
)
SELECT strftime('%Y-%m', start_date) AS cohort_month,
       COUNT(*) AS cohort_size
FROM first_action
GROUP BY cohort_month
ORDER BY cohort_month;


-- ------------------------------------------------------------
-- 3. MONTH-1 RETENTION по когортам
-- ------------------------------------------------------------
-- Доля пользователей когорты, вернувшихся в следующем
-- КАЛЕНДАРНОМ месяце после первого (start + 1 month).

WITH first_action AS (
  SELECT user_id, MIN(play_date) AS start_date
  FROM plays
  GROUP BY user_id
),
flags AS (
  SELECT f.user_id,
         strftime('%Y-%m', f.start_date) AS cohort,
         MAX(CASE WHEN strftime('%Y-%m', p.play_date)
                       = strftime('%Y-%m', f.start_date, '+1 month')
                  THEN 1 ELSE 0 END) AS returned
  FROM first_action f
  JOIN plays p ON p.user_id = f.user_id
  GROUP BY f.user_id, cohort
)
SELECT cohort,
       COUNT(*) AS cohort_size,
       SUM(returned) AS returned_count,
       ROUND(AVG(returned) * 100, 1) AS retention_pct
FROM flags
GROUP BY cohort
ORDER BY cohort;


-- ------------------------------------------------------------
-- 4. ПОЛНАЯ КОГОРТНАЯ ТАБЛИЦА RETENTION (m0..m3)
-- ------------------------------------------------------------
-- Каждый столбец = ОТДЕЛЬНЫЙ месяц (=, не >), иначе перекрытие.
-- m0 всегда 100% (все активны в свой первый месяц).

WITH first_action AS (
  SELECT user_id, MIN(play_date) AS start_date
  FROM plays
  GROUP BY user_id
),
flags AS (
  SELECT f.user_id,
         strftime('%Y-%m', f.start_date) AS cohort,
         MAX(CASE WHEN strftime('%Y-%m', p.play_date) = strftime('%Y-%m', f.start_date)               THEN 1 ELSE 0 END) AS m0,
         MAX(CASE WHEN strftime('%Y-%m', p.play_date) = strftime('%Y-%m', f.start_date, '+1 month')   THEN 1 ELSE 0 END) AS m1,
         MAX(CASE WHEN strftime('%Y-%m', p.play_date) = strftime('%Y-%m', f.start_date, '+2 month')   THEN 1 ELSE 0 END) AS m2,
         MAX(CASE WHEN strftime('%Y-%m', p.play_date) = strftime('%Y-%m', f.start_date, '+3 month')   THEN 1 ELSE 0 END) AS m3
  FROM first_action f
  JOIN plays p ON p.user_id = f.user_id
  GROUP BY f.user_id, cohort
)
SELECT cohort,
       COUNT(*) AS cohort_size,
       ROUND(AVG(m0) * 100, 1) AS m0,
       ROUND(AVG(m1) * 100, 1) AS m1,
       ROUND(AVG(m2) * 100, 1) AS m2,
       ROUND(AVG(m3) * 100, 1) AS m3
FROM flags
GROUP BY cohort
ORDER BY cohort;


-- ------------------------------------------------------------
-- 5. АКТИВНОСТЬ: уроки/сессии в первый месяц vs последующие
-- ------------------------------------------------------------
-- Приём: SUM(CASE WHEN ... THEN 1) — количество,
--        SUM(CASE WHEN ... THEN amount) — сумма.

WITH first_lesson AS (
  SELECT student_id, MIN(lesson_date) AS start_date
  FROM lessons
  GROUP BY student_id
)
SELECT f.student_id,
       SUM(CASE WHEN strftime('%Y-%m', l.lesson_date) = strftime('%Y-%m', f.start_date)  THEN 1 ELSE 0 END) AS lessons_first_month,
       SUM(CASE WHEN strftime('%Y-%m', l.lesson_date) != strftime('%Y-%m', f.start_date) THEN 1 ELSE 0 END) AS lessons_later
FROM first_lesson f
JOIN lessons l ON l.student_id = f.student_id
GROUP BY f.student_id;


-- ------------------------------------------------------------
-- 6. КОНВЕРСИЯ из регистрации в действие (формула-шаблон)
-- ------------------------------------------------------------
-- LEFT JOIN — сохранить всех (незаказавшие = знаменатель).
-- COUNT(DISTINCT ...) — считаем ЛЮДЕЙ, не действия.
-- Условие статуса в ON (не WHERE!), чтобы не терять NULL-строки.

SELECT segment,
       COUNT(DISTINCT c.customer_id) AS total,
       COUNT(DISTINCT o.customer_id) AS buyers,
       COUNT(DISTINCT o.customer_id) * 100.0
         / COUNT(DISTINCT c.customer_id) AS conversion_pct
FROM customers c
LEFT JOIN orders o
  ON o.customer_id = c.customer_id
  AND o.status = 'delivered'
GROUP BY segment;


-- ------------------------------------------------------------
-- 7. АКТИВНЫЕ МЕСЯЦЫ: в скольких разных месяцах был активен клиент
-- ------------------------------------------------------------
-- COUNT(DISTINCT strftime(...)) — считаем уникальные месяцы.

SELECT name,
       COUNT(DISTINCT strftime('%Y-%m', order_date)) AS active_months
FROM customers
JOIN orders ON orders.customer_id = customers.customer_id
GROUP BY name
HAVING active_months > 1;


-- ------------------------------------------------------------
-- 8. МЕСЯЧНАЯ ВЫРУЧКА С ПРИРОСТОМ (LAG)
-- ------------------------------------------------------------
-- Сначала агрегируем по месяцам (CTE), потом LAG поверх.

WITH monthly AS (
  SELECT strftime('%Y-%m', order_date) AS month,
         SUM(amount) AS revenue
  FROM orders
  WHERE status = 'delivered'
  GROUP BY month
)
SELECT month,
       revenue,
       revenue - LAG(revenue) OVER (ORDER BY month) AS growth
FROM monthly
ORDER BY month;
