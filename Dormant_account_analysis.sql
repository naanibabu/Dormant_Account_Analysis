-- ============================================================
-- DORMANT ACCOUNT ANALYSIS: czech_bank
-- ============================================================
-- Reference date    : 1998-12-31 (last transaction in trans_clean)
-- Dormant account   : no customer activity for more than 90 days
-- Customer activity : any transaction except these bank-generated ones:
--                       - Interest credited
--                       - Payment for statement
--                       - Sanction interest (negative balance)
--
-- Contents
--   1. Index
--   2. Activity status per account
--   3. Size of the problem
--   4. Dormant vs active grouping
--   5. Profile: dormant vs active
--        5a. Account age
--        5b. Account owner age
--        5c. Average amount per transaction
--        5d. Accounts with a card
--        5e. Accounts with a loan
--        5f. Accounts with a standing order
--   6. Behaviour before going quiet
--        6a. Last customer transactions of dormant accounts
--        6b. Dormant activity in the 6 months before going quiet
--        6c. Active vs dormant activity in the last 6 months
--        6d. Debits vs credits per dormant account
--        6e. Debits vs credits, all dormant accounts
-- ============================================================

USE czech_bank;


-- ============================================================
-- 1. INDEX
-- Speeds up every query on trans_clean. Run once.
-- ============================================================
CREATE INDEX idx_trans_acc_date ON trans_clean (account_id, trans_date);


-- ============================================================
-- 2. ACTIVITY STATUS PER ACCOUNT
-- One row per account: last customer activity, days inactive
-- at the reference date, and a status label.
-- ============================================================
CREATE OR REPLACE VIEW account_activity AS
WITH customer_txns AS (
  -- only customer activity, newest first within each account
  SELECT account_id,
         trans_date,
         ROW_NUMBER() OVER (PARTITION BY account_id
                            ORDER BY trans_date DESC) AS rn
  FROM trans_clean
  WHERE k_symbol_en IS NULL
     OR k_symbol_en NOT IN ('Interest credited',
                            'Payment for statement',
                            'Sanction interest (negative balance)')
),
last_activity AS (
  -- keep only the latest transaction per account
  SELECT account_id, trans_date AS last_activity_date
  FROM customer_txns
  WHERE rn = 1
),
inactivity AS (
  -- start from account so accounts with no activity are kept
  SELECT a.account_id,
         l.last_activity_date,
         DATEDIFF('1998-12-31', l.last_activity_date) AS days_inactive
  FROM account a
  LEFT JOIN last_activity l ON l.account_id = a.account_id
)
SELECT account_id,
       last_activity_date,
       days_inactive,
       CASE WHEN last_activity_date IS NULL THEN 'Never active'
            WHEN days_inactive > 365 THEN 'Dormant 365+'
            WHEN days_inactive > 180 THEN 'Dormant 180-365'
            WHEN days_inactive > 90  THEN 'Dormant 90-180'
            ELSE 'Active' END AS status
FROM inactivity;

-- Check: accounts per status
SELECT status, COUNT(*) AS count
FROM account_activity
GROUP BY status;


-- ============================================================
-- 3. SIZE OF THE PROBLEM
-- Number and percentage of accounts in each status.
-- ============================================================
CREATE VIEW account_percentage AS
SELECT status,
       COUNT(*) AS accounts,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM account_activity), 2) AS pct
FROM account_activity
GROUP BY status
ORDER BY FIELD(status, 'Active', 'Dormant 90-180', 'Dormant 180-365',
                       'Dormant 365+', 'Never active');

SELECT * FROM account_percentage;


-- ============================================================
-- 4. DORMANT VS ACTIVE GROUPING
-- All dormant bands combined into one group (grp).
-- The view is kept for reference; the table below is a saved
-- copy used by all later queries, because the view is slow
-- to recompute.
-- ============================================================
CREATE OR REPLACE VIEW v_account_group AS
SELECT account_id,
       last_activity_date,
       days_inactive,
       status,
       CASE WHEN status LIKE 'Dormant%' THEN 'Dormant'
            WHEN status = 'Active' THEN 'Active'
            ELSE status END AS grp
FROM account_activity;

DROP TABLE IF EXISTS account_group;

CREATE TABLE account_group AS
SELECT account_id,
       last_activity_date,
       days_inactive,
       status,
       CASE WHEN status LIKE 'Dormant%' THEN 'Dormant'
            WHEN status = 'Active' THEN 'Active'
            ELSE status END AS grp
FROM account_activity;

ALTER TABLE account_group ADD PRIMARY KEY (account_id);


-- ============================================================
-- 5. PROFILE: DORMANT VS ACTIVE
-- ============================================================

-- 5a. Account age (years open at the reference date)
CREATE OR REPLACE VIEW grp_account_age AS
SELECT g.grp,
       COUNT(*) AS accounts,
       ROUND(AVG(DATEDIFF('1998-12-31', a.created_date)) / 365, 1) AS avg_age_years,
       ROUND(MIN(DATEDIFF('1998-12-31', a.created_date)) / 365, 1) AS min_age_years,
       ROUND(MAX(DATEDIFF('1998-12-31', a.created_date)) / 365, 1) AS max_age_years
FROM account_group g
JOIN account a ON a.account_id = g.account_id
GROUP BY g.grp;


-- 5b. Account owner age (years at the reference date)
CREATE OR REPLACE VIEW grp_owner_age AS
SELECT g.grp,
       COUNT(*) AS owners,
       ROUND(AVG(TIMESTAMPDIFF(YEAR, c.birth_date, '1998-12-31')), 1) AS avg_age,
       MAX(TIMESTAMPDIFF(YEAR, c.birth_date, '1998-12-31')) AS max_age,
       MIN(TIMESTAMPDIFF(YEAR, c.birth_date, '1998-12-31')) AS min_age
FROM account_group g
JOIN disp d   ON d.account_id = g.account_id AND d.type = 'OWNER'
JOIN client c ON c.client_id  = d.client_id
WHERE g.grp IN ('Active', 'Dormant')
GROUP BY g.grp;


-- 5c. Average amount per customer transaction
CREATE OR REPLACE VIEW grp_avg_amount AS
SELECT g.grp,
       COUNT(*) AS transactions,
       ROUND(AVG(t.amount), 0) AS avg_amount
FROM account_group g
JOIN trans_clean t ON t.account_id = g.account_id
WHERE g.grp IN ('Active', 'Dormant')
  AND (t.k_symbol_en IS NULL
       OR t.k_symbol_en NOT IN ('Interest credited',
                                'Payment for statement',
                                'Sanction interest (negative balance)'))
GROUP BY g.grp;


-- 5d. Accounts with a card
CREATE OR REPLACE VIEW has_a_card AS
SELECT g.grp,
       COUNT(*) AS accounts,
       SUM(EXISTS (SELECT 1
                   FROM disp d
                   JOIN card cd ON cd.disp_id = d.disp_id
                   WHERE d.account_id = g.account_id)) AS with_card,
       ROUND(100 * SUM(EXISTS (SELECT 1
                               FROM disp d
                               JOIN card cd ON cd.disp_id = d.disp_id
                               WHERE d.account_id = g.account_id))
             / COUNT(*), 1) AS pct_with_card
FROM account_group g
WHERE g.grp IN ('Active', 'Dormant')
GROUP BY g.grp;


-- 5e. Accounts with a loan
CREATE OR REPLACE VIEW has_a_loan AS
SELECT g.grp,
       COUNT(*) AS accounts,
       SUM(EXISTS (SELECT 1 FROM loan l WHERE l.account_id = g.account_id)) AS with_loan,
       ROUND(100 * SUM(EXISTS (SELECT 1 FROM loan l WHERE l.account_id = g.account_id))
             / COUNT(*), 1) AS pct_with_loan
FROM account_group g
WHERE g.grp IN ('Active', 'Dormant')
GROUP BY g.grp;


-- 5f. Accounts with a standing order
CREATE OR REPLACE VIEW has_a_order AS
SELECT g.grp,
       COUNT(*) AS accounts,
       SUM(EXISTS (SELECT 1 FROM `order` o WHERE o.account_id = g.account_id)) AS with_order,
       ROUND(100 * SUM(EXISTS (SELECT 1 FROM `order` o WHERE o.account_id = g.account_id))
             / COUNT(*), 1) AS pct_with_order
FROM account_group g
WHERE g.grp IN ('Active', 'Dormant')
GROUP BY g.grp;


-- ============================================================
-- 6. BEHAVIOUR BEFORE GOING QUIET
-- ============================================================

-- 6a. Customer transactions on each dormant account's last active day
CREATE OR REPLACE VIEW dormant_lst_trnx AS
SELECT g.account_id,
       g.status,
       g.last_activity_date,
       t.type_en,
       t.operation_en,
       t.k_symbol_en,
       t.amount,
       t.balance
FROM account_group g
JOIN trans_clean t
  ON t.account_id = g.account_id
 AND t.trans_date = g.last_activity_date
WHERE g.grp = 'Dormant'
  AND (t.k_symbol_en IS NULL
       OR t.k_symbol_en NOT IN ('Interest credited',
                                'Payment for statement',
                                'Sanction interest (negative balance)'))
ORDER BY g.days_inactive DESC, g.account_id;


-- 6b. Customer activity per dormant account in the 6 months
--     before it stopped
CREATE OR REPLACE VIEW last_6m_dormant_activity AS
SELECT g.account_id,
       g.status,
       g.last_activity_date,
       COUNT(t.account_id) AS txns_last_6m,
       ROUND(AVG(t.amount), 0) AS avg_amount_last_6m
FROM account_group g
LEFT JOIN trans_clean t
  ON t.account_id = g.account_id
 AND t.trans_date >  DATE_SUB(g.last_activity_date, INTERVAL 6 MONTH)
 AND t.trans_date <= g.last_activity_date
 AND (t.k_symbol_en IS NULL
      OR t.k_symbol_en NOT IN ('Interest credited',
                               'Payment for statement',
                               'Sanction interest (negative balance)'))
WHERE g.grp = 'Dormant'
GROUP BY g.account_id, g.status, g.last_activity_date
ORDER BY g.account_id;


-- 6c. Active vs dormant customer activity in a 6-month window
--     Active  : window ends 1998-12-31
--     Dormant : window ends on the account's own last activity date
CREATE OR REPLACE VIEW active_vs_dormant_actvity_last_6m AS
SELECT grp,
       COUNT(*)               AS accounts,
       ROUND(AVG(n), 1)       AS avg_txns_last_6m,
       ROUND(AVG(avg_amt), 0) AS avg_amount_6m
FROM (
  SELECT g.grp,
         t.account_id,
         COUNT(*)      AS n,
         AVG(t.amount) AS avg_amt
  FROM account_group g
  JOIN trans_clean t
    ON t.account_id = g.account_id
  WHERE g.grp IN ('Active', 'Dormant')
    AND t.trans_date >  DATE_SUB(CASE WHEN g.grp = 'Dormant'
                                      THEN g.last_activity_date
                                      ELSE '1998-12-31' END, INTERVAL 6 MONTH)
    AND t.trans_date <= CASE WHEN g.grp = 'Dormant'
                             THEN g.last_activity_date
                             ELSE '1998-12-31' END
    AND (t.k_symbol_en IS NULL
         OR t.k_symbol_en NOT IN ('Interest credited',
                                  'Payment for statement',
                                  'Sanction interest (negative balance)'))
  GROUP BY g.grp, t.account_id
) s
GROUP BY grp;


-- 6d. Number of debits and credits for each dormant account
--     (6 months before its last activity)
CREATE OR REPLACE VIEW each_dormant_no_of_debit_credit AS
SELECT g.account_id,
       g.status,
       g.last_activity_date,
       SUM(t.type_en = 'Credit')  AS credits,
       SUM(t.type_en <> 'Credit') AS debits,
       COUNT(*)                   AS total_txns
FROM account_group g
JOIN trans_clean t
  ON t.account_id = g.account_id
 AND t.trans_date >  DATE_SUB(g.last_activity_date, INTERVAL 6 MONTH)
 AND t.trans_date <= g.last_activity_date
WHERE g.grp = 'Dormant'
  AND (t.k_symbol_en IS NULL
       OR t.k_symbol_en NOT IN ('Interest credited',
                                'Payment for statement',
                                'Sanction interest (negative balance)'))
GROUP BY g.account_id, g.status, g.last_activity_date
ORDER BY g.account_id;


-- 6e. Overall debits vs credits across all dormant accounts
--     (6 months before each account's last activity)
CREATE OR REPLACE VIEW last_6m_dormant_total_debit_credit AS
SELECT SUM(t.type_en = 'Credit')  AS credits,
       SUM(t.type_en <> 'Credit') AS debits,
       ROUND(100 * SUM(t.type_en = 'Credit') / COUNT(*), 1) AS pct_credit
FROM account_group g
JOIN trans_clean t
  ON t.account_id = g.account_id
 AND t.trans_date >  DATE_SUB(g.last_activity_date, INTERVAL 6 MONTH)
 AND t.trans_date <= g.last_activity_date
WHERE g.grp = 'Dormant'
  AND (t.k_symbol_en IS NULL
       OR t.k_symbol_en NOT IN ('Interest credited',
                                'Payment for statement',
                                'Sanction interest (negative balance)'));