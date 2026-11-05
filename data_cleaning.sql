-- =====================================================
-- Project: Data Cleaning – World Layoffs (MySQL)
-- Dataset: layoffs.csv (2,361 rows, 9 columns)
--          Source: https://www.kaggle.com/datasets/swaptr/layoffs-2022
-- Author:  Andres Argeñal
-- Goal:    Clean the raw data so it's ready for analysis
--
-- Plan:
--   0. Setup (staging table + initial checks)
--   1. Remove duplicates
--   2. Standardize data
--   3. Convert data types (date)
--   4. Handle NULL and blank values
--   5. Remove unusable rows and helper columns
--   6. Final checks
--
-- Final result: 2,361 -> 1,995 rows
-- =====================================================


-- =====================================================
-- 0. SETUP
-- =====================================================

-- 0.1 Reset: drop staging tables so the script can be re-run from scratch
DROP TABLE IF EXISTS layoffs_staging2;
DROP TABLE IF EXISTS layoffs_staging;

-- 0.2 Check how many records we start with
SELECT COUNT(*) FROM layoffs;
-- Result: 2361 rows

-- 0.3 Create a staging table so the raw data stays untouched
CREATE TABLE layoffs_staging LIKE layoffs;

INSERT INTO layoffs_staging
SELECT * FROM layoffs;

SELECT COUNT(*) FROM layoffs_staging;
-- Result: 2361 rows (copy matches the original)

-- 0.4 Check whether missing values were imported as real NULLs or as the text 'NULL'
--     (WHERE x IS NULL would miss the text version)
SELECT
  SUM(industry IS NULL)  AS industry_real_null,
  SUM(industry = 'NULL') AS industry_text_null,
  SUM(industry = '')     AS industry_blank,
  SUM(stage IS NULL)     AS stage_real_null,
  SUM(stage = 'NULL')    AS stage_text_null
FROM layoffs_staging;
-- Result: 1 real NULL + 3 blanks in industry, 6 real NULLs in stage, no text 'NULL'
-- Conclusion: IS NULL works; blanks in industry are handled in section 4


-- =====================================================
-- 1. REMOVE DUPLICATES
-- =====================================================

-- 1.1 Number each row within groups of identical rows.
--     The first copy gets row_num = 1, any identical copy gets 2, 3...
--     All 9 columns are included so only truly identical rows are flagged.
--     Note: `date` must use backticks; single quotes would treat it as text
--     and wrongly flag 16 legitimate events (same company, different date)
--     as duplicates.
WITH duplicate_cte AS
(
  SELECT *,
    ROW_NUMBER() OVER(
      PARTITION BY company, location, industry, total_laid_off,
                   percentage_laid_off, `date`, stage, country,
                   funds_raised_millions
    ) AS row_num
  FROM layoffs_staging
)
SELECT *
FROM duplicate_cte
WHERE row_num > 1;
-- Result: 5 true duplicates (Casper, Cazoo, Hibob, Wildlife Studios, Yahoo)

-- 1.2 MySQL can't DELETE from a CTE, so create a second staging table
--     that stores row_num as a real column.
CREATE TABLE layoffs_staging2 (
  company text,
  location text,
  industry text,
  total_laid_off int DEFAULT NULL,
  percentage_laid_off text,
  `date` text,
  stage text,
  country text,
  funds_raised_millions int DEFAULT NULL,
  row_num INT
);

INSERT INTO layoffs_staging2
SELECT *,
  ROW_NUMBER() OVER(
    PARTITION BY company, location, industry, total_laid_off,
                 percentage_laid_off, `date`, stage, country,
                 funds_raised_millions
  ) AS row_num
FROM layoffs_staging;

SELECT COUNT(*) FROM layoffs_staging2;
-- Result: 2361 (all rows copied)

-- 1.3 Delete the extra copies (row_num > 1), keeping one of each
DELETE FROM layoffs_staging2
WHERE row_num > 1;

SELECT COUNT(*) FROM layoffs_staging2;
-- Result: 2356 rows, no row_num > 1 left


-- =====================================================
-- 2. STANDARDIZE DATA
-- =====================================================

-- 2.1 Remove leading/trailing spaces from company names
SELECT company, TRIM(company)
FROM layoffs_staging2
WHERE company <> TRIM(company);
-- Result: 11 rows with extra spaces

UPDATE layoffs_staging2
SET company = TRIM(company);

-- 2.2 Standardize industry: 'Crypto', 'Crypto Currency' and 'CryptoCurrency'
--     are the same industry, so set them all to 'Crypto'
SELECT industry, COUNT(*)
FROM layoffs_staging2
WHERE industry LIKE 'Crypto%'
GROUP BY industry;
-- Result: Crypto 99, Crypto Currency 2, CryptoCurrency 1

UPDATE layoffs_staging2
SET industry = 'Crypto'
WHERE industry LIKE 'Crypto%';
-- Result: 102 rows now 'Crypto'

-- 2.3 Standardize country: remove the trailing period from 'United States.'
SELECT DISTINCT country, TRIM(TRAILING '.' FROM country) AS fixed
FROM layoffs_staging2
WHERE country LIKE 'United States%';

UPDATE layoffs_staging2
SET country = TRIM(TRAILING '.' FROM country)
WHERE country LIKE 'United States%';

SELECT country, COUNT(*)
FROM layoffs_staging2
WHERE country LIKE 'United States%'
GROUP BY country;
-- Result: United States | 1543 (1539 + 4 fixed)


-- =====================================================
-- 3. CONVERT DATA TYPES
-- =====================================================

-- 3.1 The date column is text (e.g. '3/6/2023'). Preview converting it
--     to MySQL's DATE format (YYYY-MM-DD).
SELECT `date`,
       STR_TO_DATE(`date`, '%m/%d/%Y') AS converted
FROM layoffs_staging2;

-- 3.2 Rewrite the text into YYYY-MM-DD format
UPDATE layoffs_staging2
SET `date` = STR_TO_DATE(`date`, '%m/%d/%Y');

-- 3.3 Now that every value is in YYYY-MM-DD format, change the column type
ALTER TABLE layoffs_staging2
MODIFY COLUMN `date` DATE;

-- 3.4 Check: earliest and latest dates, and any NULLs
SELECT MIN(`date`), MAX(`date`), SUM(`date` IS NULL) AS null_dates
FROM layoffs_staging2;
-- Result: 2020-03-11 | 2023-03-06 | 1 NULL date (Blackbaud)


-- =====================================================
-- 4. NULL AND BLANK VALUES
-- =====================================================

-- 4.1 Industry has both blanks ('') and NULLs. Convert blanks to NULL
--     so every missing value is handled the same way.
SELECT company, `date`, industry
FROM layoffs_staging2
WHERE industry IS NULL OR industry = '';
-- Result: 4 rows (Airbnb, Juul, Carvana blank; Bally's Interactive NULL)

UPDATE layoffs_staging2
SET industry = NULL
WHERE industry = '';

-- 4.2 Where the same company has another row with a known industry, copy it.
--     Must run AFTER 4.1: a blank '' is not NULL, so the fill would skip it.
SELECT t1.company, t1.`date`, t1.industry, t2.industry AS fill_with
FROM layoffs_staging2 t1
JOIN layoffs_staging2 t2
  ON t1.company = t2.company
WHERE t1.industry IS NULL
  AND t2.industry IS NOT NULL;
-- Result: Airbnb -> Travel, Juul -> Consumer, Carvana -> Transportation

UPDATE layoffs_staging2 t1
JOIN layoffs_staging2 t2
  ON t1.company = t2.company
SET t1.industry = t2.industry
WHERE t1.industry IS NULL
  AND t2.industry IS NOT NULL;

-- 4.3 Check: only Bally's Interactive should still be NULL
--     (no other row to copy from; left as NULL rather than guessed)
SELECT company, `date`, industry
FROM layoffs_staging2
WHERE industry IS NULL OR industry = '';
-- Result: 1 row (Bally's Interactive)


-- =====================================================
-- 5. REMOVE UNUSABLE ROWS AND COLUMNS
-- =====================================================

-- 5.1 Rows with BOTH total_laid_off and percentage_laid_off missing
--     have no layoff information and can't be used for analysis.
--     Rows missing only one of the two are kept.
SELECT COUNT(*)
FROM layoffs_staging2
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;
-- Result: 361

DELETE FROM layoffs_staging2
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;

SELECT COUNT(*) FROM layoffs_staging2;
-- Result: 1995 rows

-- 5.2 row_num was only needed to find duplicates; remove it
ALTER TABLE layoffs_staging2
DROP COLUMN row_num;


-- =====================================================
-- 6. FINAL CHECKS
-- =====================================================

-- 6.1 Overall summary
SELECT
  COUNT(*)                 AS total_rows,
  SUM(total_laid_off)      AS total_laid_off,
  COUNT(DISTINCT industry) AS industries,
  COUNT(DISTINCT country)  AS countries,
  MIN(`date`)              AS first_date,
  MAX(`date`)              AS last_date
FROM layoffs_staging2;
-- Result: 1995 | 383659 | 30 | 51 | 2020-03-11 | 2023-03-06

-- 6.2 Remaining NULLs per column (kept on purpose: rows still hold useful data)
SELECT
  SUM(company IS NULL)               AS company,
  SUM(industry IS NULL)              AS industry,
  SUM(total_laid_off IS NULL)        AS total_laid_off,
  SUM(percentage_laid_off IS NULL)   AS pct_laid_off,
  SUM(`date` IS NULL)                AS `date`,
  SUM(stage IS NULL)                 AS stage,
  SUM(funds_raised_millions IS NULL) AS funds
FROM layoffs_staging2;
-- Result: 0 | 1 | 378 | 423 | 1 | 5 | 165

-- 6.3 Confirm final structure (date is DATE, row_num removed)
DESCRIBE layoffs_staging2;
