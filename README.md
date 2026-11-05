# World Layoffs – Data Cleaning in MySQL

Cleaning a raw dataset of 2,361 tech-industry layoff events (March 2020 – March 2023) so it is reliable and ready for exploratory analysis.

**Tools:** MySQL 8, MySQL Workbench
**Skills:** window functions (`ROW_NUMBER`), CTEs, self-joins, string functions (`TRIM`, `LIKE`), type conversion (`STR_TO_DATE`, `ALTER TABLE`), data validation

---

## Dataset

- **Source:** [Layoffs 2022 – Kaggle](https://www.kaggle.com/datasets/swaptr/layoffs-2022)
- **Size:** 2,361 rows × 9 columns
- **Columns:** company, location, industry, total_laid_off, percentage_laid_off, date, stage, country, funds_raised_millions

## Approach

All work is done on staging copies, so the raw table is never modified. The script can be re-run from top to bottom and produces the same result every time.

| Step | What was done | Rows |
|---|---|---|
| 0. Setup | Created a staging table; checked how missing values were imported | 2,361 |
| 1. Duplicates | Flagged identical rows with `ROW_NUMBER()` over all 9 columns; removed 5 true duplicates | 2,356 |
| 2. Standardize | Trimmed spaces in 11 company names; merged 3 spellings of "Crypto"; fixed "United States." | 2,356 |
| 3. Data types | Converted `date` from text (`3/6/2023`) to a real `DATE` column | 2,356 |
| 4. NULLs & blanks | Converted blanks to NULL; filled missing industry from the same company's other rows | 2,356 |
| 5. Remove rows | Deleted 361 rows with no layoff figures (both total and % missing); dropped helper column | 1,995 |
| 6. Validation | Summary and NULL checks to confirm the final table | 1,995 |

## Results

| | Before | After |
|---|---|---|
| Rows | 2,361 | 1,995 |
| Duplicate rows | 5 | 0 |
| Industry spellings for "Crypto" | 3 | 1 |
| Country values for the US | 2 | 1 |
| Missing industry | 4 | 1 (no source to fill from) |
| `date` column type | text | DATE |

The cleaned table covers **383,659 people laid off** across **30 industries** and **51 countries**.

## Key challenges

**1. A one-character mistake that silently deletes real data.**
In the duplicate check, writing the date column as `'date'` (single quotes) instead of `` `date` `` (backticks) makes MySQL treat it as a fixed piece of text, not the column. The query still runs without errors, but it ignores the date, so separate layoff events from the same company on different days look identical. In this dataset that flags **21 rows instead of 5**, deleting **16 legitimate events**, for example Pear Therapeutics laying off 59 people on both 14 and 16 November 2022. I validated the duplicate count against all 9 columns to catch this.

**2. Blank is not the same as NULL.**
Three companies (Airbnb, Juul, Carvana) had a blank industry `''`, not NULL. A fill query using `IS NULL` skips blanks entirely and updates nothing. Converting blanks to NULL *first*, then running the self-join fill, recovered all three. The fourth (Bally's Interactive) had no other row to copy from, so it was left as NULL rather than guessed.

**3. Deciding which NULLs to keep.**
Only rows with *both* layoff figures missing were removed. Rows with partial information (e.g. a headcount but no percentage) were kept, since aggregate functions like `SUM` and `AVG` skip NULLs and the rest of the row is still useful.

## Files

| File | Description |
|---|---|
| [`data_cleaning.sql`](data_cleaning.sql) | Full cleaning script, commented step by step with the result of each check |
| [`layoffs_raw.csv`](layoffs_raw.csv) | Original dataset |
| [`layoffs_cleaned.csv`](layoffs_cleaned.csv) | Final cleaned table |

## How to run

1. Create a schema in MySQL and import `layoffs_raw.csv` as a table named `layoffs` (Table Data Import Wizard in Workbench).
2. Open `data_cleaning.sql` and run it from top to bottom.
3. The cleaned result is in `layoffs_staging2`.

## Acknowledgements

The project structure follows a guided SQL tutorial by Alex Freberg (Alex The Analyst). The duplicate-detection fix, the blank-vs-NULL ordering fix, and the validation checks are my own additions.

---

**Andres Argeñal** · [LinkedIn](https://www.linkedin.com/in/andresargenal/)
