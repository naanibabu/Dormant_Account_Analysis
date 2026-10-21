/* =============================================================================
   Czech Bank Data Analysis
   Script  : Database setup, data loading and data cleaning
   Database: czech_bank
   Tool    : MySQL Workbench (MySQL 8.0)

   Contents
     1. Database setup
     2. Load transaction data (trans)
     3. Clean transaction data  -> trans_clean
     4. Clean account table
     5. Clean client table
     6. Review disp and card tables, clean card
     7. Review loan table
     8. Clean order table
     9. Review district table
   ============================================================================= */


/* -----------------------------------------------------------------------------
   1. DATABASE SETUP
   ----------------------------------------------------------------------------- */

-- Create the database for the Czech Bank project
CREATE DATABASE czech_bank;

-- Select the database for analysis
USE czech_bank;


/* -----------------------------------------------------------------------------
   2. LOAD TRANSACTION DATA (trans)
   ----------------------------------------------------------------------------- */

-- Create the raw table to load the data into
CREATE TABLE trans (
    trans_id    INT,
    account_id  INT,
    date        INT,
    type        VARCHAR(20),
    operation   VARCHAR(30),
    amount      DECIMAL(12,2),
    balance     DECIMAL(12,2),
    k_symbol    VARCHAR(30),
    bank        VARCHAR(10),
    account     VARCHAR(20)
);

-- Allow loading local files 
SHOW VARIABLES LIKE 'local_infile';   -- should show ON
SET GLOBAL local_infile = 1;          -- run this if it shows OFF

-- Load the transaction data from the CSV file
LOAD DATA LOCAL INFILE 'C:/Users/ghant/Desktop/Data_Analysis/SQL_project/Czech_Bank_data/trans.csv'
INTO TABLE trans
FIELDS TERMINATED BY ';'
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 ROWS;

-- Check the row count and preview the first rows
SELECT COUNT(*) FROM trans;

SELECT * FROM trans
LIMIT 6;

-- View the unique values in type, operation and k_symbol
SELECT DISTINCT type      FROM trans;
SELECT DISTINCT operation FROM trans;
SELECT DISTINCT k_symbol  FROM trans;


/* -----------------------------------------------------------------------------
   3. CLEAN TRANSACTION DATA  (trans -> trans_clean)
      - Convert the date (YYMMDD) to a DATE
      - Add English columns for type, operation and k_symbol
      - Convert blank values to NULL
   ----------------------------------------------------------------------------- */

CREATE TABLE trans_clean AS
SELECT
    trans_id,
    account_id,
    STR_TO_DATE(CAST(date AS CHAR), '%y%m%d') AS trans_date,

    NULLIF(TRIM(type), '') AS type,
    CASE NULLIF(TRIM(type), '')
        WHEN 'PRIJEM' THEN 'Credit'
        WHEN 'VYDAJ'  THEN 'Debit'
        WHEN 'VYBER'  THEN 'Withdrawal (cash)'
    END AS type_en,

    NULLIF(TRIM(operation), '') AS operation,
    CASE NULLIF(TRIM(operation), '')
        WHEN 'VKLAD'          THEN 'Credit in Cash'
        WHEN 'VYBER'          THEN 'Withdrawal in Cash'
        WHEN 'VYBER KARTOU'   THEN 'Credit card Withdrawal'
        WHEN 'PREVOD Z UCTU'  THEN 'Incoming transfer from another bank'
        WHEN 'PREVOD NA UCET' THEN 'Outgoing transfer to another bank'
    END AS operation_en,

    amount,
    balance,

    NULLIF(TRIM(k_symbol), '') AS k_symbol,
    CASE NULLIF(TRIM(k_symbol), '')
        WHEN 'POJISTNE'    THEN 'Insurance payment'
        WHEN 'SLUZBY'      THEN 'Payment for statement'
        WHEN 'UROK'        THEN 'Interest credited'
        WHEN 'SANKC. UROK' THEN 'Sanction interest (negative balance)'
        WHEN 'SIPO'        THEN 'Household payment'
        WHEN 'DUCHOD'      THEN 'Old-age pension'
        WHEN 'UVER'        THEN 'Loan payment'
    END AS k_symbol_en,

    NULLIF(TRIM(bank), '')    AS bank,
    NULLIF(TRIM(account), '') AS account
FROM trans;

-- Validation 1: the raw and clean tables have the same number of rows
SELECT
    (SELECT COUNT(*) FROM trans)       AS raw_rows,
    (SELECT COUNT(*) FROM trans_clean) AS clean_rows;

-- Validation 2: dates converted correctly (no NULLs, sensible range)
SELECT
    MIN(trans_date)       AS starting_date,
    MAX(trans_date)       AS ending_date,
    SUM(trans_date IS NULL) AS null_dates
FROM trans_clean;

-- Validation 3: any code without an English label (should return nothing)
SELECT DISTINCT type, operation, k_symbol
FROM trans_clean
WHERE (type      IS NOT NULL AND type_en      IS NULL)
   OR (operation IS NOT NULL AND operation_en IS NULL)
   OR (k_symbol  IS NOT NULL AND k_symbol_en  IS NULL);

-- Validation 4: blank values became NULL
SELECT
    SUM(k_symbol IS NULL) AS k_symbols_null,
    SUM(bank     IS NULL) AS bank_nulls,
    SUM(account  IS NULL) AS account_nulls
FROM trans_clean;

-- Validation 5: preview a few rows
SELECT * FROM trans_clean
LIMIT 7;


/* -----------------------------------------------------------------------------
   4. CLEAN ACCOUNT TABLE
      - Convert the date to DATETIME (created_date)
      - Add frequency_en with English labels for frequency
   ----------------------------------------------------------------------------- */

-- View the account table and the unique frequency values
SELECT * FROM account
LIMIT 7;

SELECT DISTINCT frequency FROM account;

-- Add the new columns and fill them
SET SQL_SAFE_UPDATES = 0;

ALTER TABLE account
    ADD COLUMN created_date DATETIME,
    ADD COLUMN frequency_en VARCHAR(50);

UPDATE account
SET created_date = STR_TO_DATE(CAST(date AS CHAR), '%y%m%d'),
    frequency_en = CASE TRIM(frequency)
        WHEN 'POPLATEK MESICNE'   THEN 'Monthly issuance'
        WHEN 'POPLATEK TYDNE'     THEN 'Weekly issuance'
        WHEN 'POPLATEK PO OBRATU' THEN 'Issuance after transaction'
    END;

-- Check the changes
SELECT * FROM account
LIMIT 10;

-- Drop the original date column
ALTER TABLE account DROP COLUMN date;


/* -----------------------------------------------------------------------------
   5. CLEAN CLIENT TABLE
      - Convert birth_number to birth_date
        (YYMMDD for men, YYMM+50DD for women: 50 is subtracted from the month)
   ----------------------------------------------------------------------------- */

-- View the client table
SELECT * FROM client
LIMIT 10;

-- Add birth_date and fill it from birth_number
SET SQL_SAFE_UPDATES = 0;

ALTER TABLE client ADD COLUMN birth_date DATE;

UPDATE client
SET birth_date = STR_TO_DATE(
    CONCAT(
        '19',
        LEFT(birth_number, 2),
        LPAD(
            CAST(SUBSTRING(birth_number, 3, 2) AS UNSIGNED)
            - IF(CAST(SUBSTRING(birth_number, 3, 2) AS UNSIGNED) > 12, 50, 0),
            2, '0'),
        RIGHT(birth_number, 2)
    ), '%Y%m%d');


/* -----------------------------------------------------------------------------
   6. REVIEW DISP AND CARD TABLES, CLEAN CARD
      - Convert issued (YYMMDD) to DATETIME
   ----------------------------------------------------------------------------- */

-- View the disp (disposition) table
SELECT * FROM disp
LIMIT 10;

-- View the card (credit card) table
SELECT * FROM card
LIMIT 10;

-- Change the issued data type to DATETIME
SET SQL_SAFE_UPDATES = 0;

ALTER TABLE card ADD COLUMN issued_new DATETIME;

UPDATE card
SET issued_new = STR_TO_DATE(LEFT(issued, 6), '%y%m%d');

ALTER TABLE card DROP COLUMN issued;
ALTER TABLE card CHANGE issued_new issued DATETIME;


/* -----------------------------------------------------------------------------
   7. REVIEW LOAN TABLE
   ----------------------------------------------------------------------------- */

SELECT * FROM loan
LIMIT 10;


/* -----------------------------------------------------------------------------
   8. CLEAN ORDER TABLE
      - Add k_symbol_en with English labels
      - Convert blank k_symbol values to NULL
      Note: `order` needs backticks because ORDER is a reserved word.
   ----------------------------------------------------------------------------- */

-- View the order table and the unique k_symbol values
SELECT * FROM `order`
LIMIT 10;

SELECT DISTINCT k_symbol FROM `order`;

-- Add the English column and convert blanks to NULL
SET SQL_SAFE_UPDATES = 0;

ALTER TABLE `order` ADD COLUMN k_symbol_en VARCHAR(50);

UPDATE `order`
SET k_symbol_en = CASE NULLIF(TRIM(k_symbol), '')
        WHEN 'POJISTNE' THEN 'Insurance payment'
        WHEN 'SIPO'     THEN 'Household payment'
        WHEN 'LEASING'  THEN 'Leasing payment'
        WHEN 'UVER'     THEN 'Loan payment'
    END,
    k_symbol = NULLIF(TRIM(k_symbol), '');


/* -----------------------------------------------------------------------------
   9. REVIEW DISTRICT TABLE
   ----------------------------------------------------------------------------- */

SELECT * FROM district
LIMIT 10;