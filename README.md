# AdventureWorks HR Workforce Analytics & Department Health Scorecard

## Project Overview
An end-to-end HR analytics project utilizing the **AdventureWorks** database to evaluate workforce stability, pay equity, employee burnout risk, labor costs across shifts, and compensation growth. The project culminates in a **Composite Department Health Scorecard** that ranks departments by operational and retention risk.

---

## Key SQL Techniques & Concepts Applied
* **Window Functions:** `ROW_NUMBER()`, `LAG()`, and `RANK()` for tracking current salary rates, raise intervals, and multi-metric department scoring.
* **Complex Aggregations & Conditional Logic:** `CASE WHEN` statements for conditional counting and rate calculations without integer truncation.
* **CTE Modular Architecture:** Structured, multi-stage Common Table Expressions for readability and performance.
* **Safe Mathematical Operations:** `NULLIF()` to avoid division-by-zero crashes during ratio calculations.

---

## Business Metrics & Analytical Queries (6 Key Signals)

1. **Internal Transfer & Turnover Rate:** Measures employee mobility and department stability across historical assignments.
2. **Pay Disparity Ratio:** Calculates the spread, standard deviation, and disparity ratio (`Max Rate / Min Rate`) per department.
3. **Burnout Risk Index:** Identifies departments with high unused vacation hours (>70 banked hours threshold).
4. **Shift Cost & Premium Analysis:** Calculates shift headcount, average pay premiums versus company baseline, and monthly labor costs.
5. **Raise Frequency & Compensation Growth:** Measures days between pay adjustments (`LAG()`) and average percentage increases.
6. **Composite Health Scorecard:** Ranks departments across transfer rate, burnout risk, and pay disparity to flag critical departments requiring intervention.

---

## Project Structure
* `AdvWorks HR.sql` – Production-ready T-SQL script containing all 6 analytical queries.
* `1_technical_walkthrough.txt` – Detailed technical documentation on query logic, variables, and T-SQL optimizations.
* `2_plain_english_executive_summary.txt` – Non-technical executive summary translating data findings into HR insights.
