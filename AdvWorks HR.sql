/* =====================================================================
   AdventureWorks (2019/2022) - HR Workforce Analytics
   Schema: HumanResources
   ---------------------------------------------------------------------
   1. Employee Turnover & Department Stability   (معدل دوران الموظفين واستقرار الأقسام)
   2. Internal Pay Disparity by Department       (فجوة الأجور والتفاوت الداخلي)
   3. Leave Utilization & Burnout Risk           (استهلاك الإجازات ومخاطر الإرهاق)
   4. Shift Distribution & Labor Cost            (توزيع المناوبات وتكلفة العمل)
   5. Raise Frequency & Compensation Growth      (وتيرة الزيادات ونمو الأجور)
   6. Department Health Scorecard (combines 1-3) (ملخص صحة الأقسام)

   Notes:
   - AdventureWorks has no termination date. EndDate IS NULL in
     EmployeeDepartmentHistory = current assignment; a non-NULL EndDate
     means the person moved to another department. So "turnover" here is
     really internal transfer-out, and I label it that way.
   - The data stops around mid-2014, so tenure is measured against a fixed
     as-of date instead of GETDATE(). Otherwise every tenure would be
     inflated by ~12 years.
   ===================================================================== */
DECLARE @AsOfDate         DATE = '2014-06-30';  -- end of the data window
DECLARE @VacationRiskHrs  INT  = 70;            -- hours banked = "not taking leave"
DECLARE @HoursPerMonth    INT  = 8 * 22;        -- 8 h/day x 22 working days


  -- 1. Turnover & department stability

SELECT
    d.Name                                                    AS DepartmentName,
    COUNT(*)                                                  AS TotalAssignments,
    SUM(CASE WHEN edh.EndDate IS NULL     THEN 1 ELSE 0 END)  AS CurrentHeadcount,
    SUM(CASE WHEN edh.EndDate IS NOT NULL THEN 1 ELSE 0 END)  AS TransferredOutCount,
    CAST(100.0 * SUM(CASE WHEN edh.EndDate IS NOT NULL THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,2))                          AS TransferOutRatePct,
    CAST(AVG(1.0 * DATEDIFF(MONTH, edh.StartDate,
                            COALESCE(edh.EndDate, @AsOfDate))) AS DECIMAL(6,1)) AS AvgTenureMonths
FROM HumanResources.Department AS d
JOIN HumanResources.EmployeeDepartmentHistory AS edh
    ON edh.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentID, d.Name
ORDER BY TransferOutRatePct DESC;


   --2. Internal pay disparity (current employees, latest hourly rate)

WITH LatestPay AS (
    SELECT
        BusinessEntityID,
        Rate,
        ROW_NUMBER() OVER (PARTITION BY BusinessEntityID
                           ORDER BY RateChangeDate DESC) AS rn
    FROM HumanResources.EmployeePayHistory
),
CurrentDept AS (
    SELECT BusinessEntityID, DepartmentID
    FROM HumanResources.EmployeeDepartmentHistory
    WHERE EndDate IS NULL
)
SELECT
    d.Name                                                            AS DepartmentName,
    COUNT(*)                                                          AS ActiveEmployees,
    CAST(MIN(p.Rate)  AS DECIMAL(8,2))                                AS MinHourlyRate,
    CAST(MAX(p.Rate)  AS DECIMAL(8,2))                                AS MaxHourlyRate,
    CAST(AVG(p.Rate)  AS DECIMAL(8,2))                                AS AvgHourlyRate,
    CAST(MAX(p.Rate) - MIN(p.Rate) AS DECIMAL(8,2))                   AS RateSpread,
    CAST(STDEV(p.Rate) AS DECIMAL(8,2))                               AS RateStdDev,
    CAST(MAX(p.Rate) / NULLIF(MIN(p.Rate), 0) AS DECIMAL(6,2))        AS PayDisparityRatio
FROM CurrentDept AS c
JOIN LatestPay AS p
    ON p.BusinessEntityID = c.BusinessEntityID AND p.rn = 1
JOIN HumanResources.Department AS d
    ON d.DepartmentID = c.DepartmentID
GROUP BY d.DepartmentID, d.Name
ORDER BY PayDisparityRatio DESC;


/* ---------------------------------------------------------------------
   3. Leave utilization & burnout risk
   High banked vacation = people aren't taking time off.
   --------------------------------------------------------------------- */
SELECT
    d.Name                                                            AS DepartmentName,
    COUNT(*)                                                          AS TotalEmployees,
    CAST(AVG(1.0 * e.VacationHours) AS DECIMAL(6,1))                  AS AvgUnusedVacationHours,
    CAST(AVG(1.0 * e.SickLeaveHours) AS DECIMAL(6,1))                 AS AvgSickLeaveHours,
    SUM(CASE WHEN e.VacationHours > @VacationRiskHrs THEN 1 ELSE 0 END) AS HighBurnoutRiskCount,
    CAST(100.0 * SUM(CASE WHEN e.VacationHours > @VacationRiskHrs THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,2))                                  AS BurnoutRiskPct
FROM HumanResources.Employee AS e
JOIN HumanResources.EmployeeDepartmentHistory AS edh
    ON edh.BusinessEntityID = e.BusinessEntityID
   AND edh.EndDate IS NULL
JOIN HumanResources.Department AS d
    ON d.DepartmentID = edh.DepartmentID
GROUP BY d.DepartmentID, d.Name
ORDER BY AvgUnusedVacationHours DESC;


/* ---------------------------------------------------------------------
   4. Shift distribution, pay premium and estimated monthly cost
   Premium = how far each shift's average rate sits from the company average.
   --------------------------------------------------------------------- */
WITH LatestPay AS (
    SELECT
        BusinessEntityID,
        Rate,
        ROW_NUMBER() OVER (PARTITION BY BusinessEntityID
                           ORDER BY RateChangeDate DESC) AS rn
    FROM HumanResources.EmployeePayHistory
),
CurrentPay AS (
    SELECT edh.BusinessEntityID, edh.ShiftID, p.Rate
    FROM HumanResources.EmployeeDepartmentHistory AS edh
    JOIN LatestPay AS p
        ON p.BusinessEntityID = edh.BusinessEntityID AND p.rn = 1
    WHERE edh.EndDate IS NULL
),
Overall AS (
    SELECT AVG(Rate) AS CompanyAvgRate FROM CurrentPay
)
SELECT
    s.Name                                                            AS ShiftName,
    s.StartTime,
    s.EndTime,
    COUNT(*)                                                          AS AssignedEmployees,
    CAST(AVG(cp.Rate) AS DECIMAL(8,2))                                AS AvgShiftRate,
    CAST(100.0 * (AVG(cp.Rate) - o.CompanyAvgRate) / o.CompanyAvgRate
         AS DECIMAL(6,2))                                             AS PremiumVsCompanyAvgPct,
    CAST(SUM(cp.Rate * @HoursPerMonth) AS DECIMAL(12,2))              AS EstimatedMonthlyCost
FROM HumanResources.Shift AS s
JOIN CurrentPay AS cp
    ON cp.ShiftID = s.ShiftID
CROSS JOIN Overall AS o
GROUP BY s.ShiftID, s.Name, s.StartTime, s.EndTime, o.CompanyAvgRate
ORDER BY AssignedEmployees DESC;


/* ---------------------------------------------------------------------
   5. Raise frequency & compensation growth
   Pay history only records rate changes, not job titles, so this measures
   raises rather than formal promotions.
   --------------------------------------------------------------------- */
WITH PayIntervals AS (
    SELECT
        BusinessEntityID,
        RateChangeDate,
        LAG(RateChangeDate) OVER (PARTITION BY BusinessEntityID
                                  ORDER BY RateChangeDate)           AS PrevChangeDate,
        100.0 * (CAST(Rate AS DECIMAL(12,4))
                 - CAST(LAG(Rate) OVER (PARTITION BY BusinessEntityID
                                        ORDER BY RateChangeDate) AS DECIMAL(12,4)))
              / NULLIF(CAST(LAG(Rate) OVER (PARTITION BY BusinessEntityID
                                            ORDER BY RateChangeDate) AS DECIMAL(12,4)), 0) AS RaisePct
    FROM HumanResources.EmployeePayHistory
)
SELECT
    d.Name                                                            AS DepartmentName,
    COUNT(DISTINCT pi.BusinessEntityID)                               AS EmployeesWithRaises,
    COUNT(*)                                                          AS TotalRaises,
    CAST(AVG(1.0 * DATEDIFF(DAY, pi.PrevChangeDate, pi.RateChangeDate)) AS DECIMAL(8,1)) AS AvgDaysBetweenRaises,
    CAST(AVG(pi.RaisePct) AS DECIMAL(6,2))                            AS AvgRaisePct
FROM PayIntervals AS pi
JOIN HumanResources.EmployeeDepartmentHistory AS edh
    ON edh.BusinessEntityID = pi.BusinessEntityID
   AND edh.EndDate IS NULL
JOIN HumanResources.Department AS d
    ON d.DepartmentID = edh.DepartmentID
WHERE pi.PrevChangeDate IS NOT NULL
GROUP BY d.DepartmentID, d.Name
ORDER BY AvgRaisePct DESC;


/* ---------------------------------------------------------------------
   6. Department health scorecard
   Ranks each department on three signals (1 = worst) and adds the ranks.
   A low total means the department is struggling on several fronts.
   --------------------------------------------------------------------- */
WITH Transfers AS (
    SELECT
        DepartmentID,
        100.0 * SUM(CASE WHEN EndDate IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS TransferOutRatePct
    FROM HumanResources.EmployeeDepartmentHistory
    GROUP BY DepartmentID
),
LatestPay AS (
    SELECT BusinessEntityID, Rate,
           ROW_NUMBER() OVER (PARTITION BY BusinessEntityID ORDER BY RateChangeDate DESC) AS rn
    FROM HumanResources.EmployeePayHistory
),
CurrentEmp AS (
    SELECT
        edh.DepartmentID,
        e.VacationHours,
        p.Rate
    FROM HumanResources.EmployeeDepartmentHistory AS edh
    JOIN HumanResources.Employee AS e ON e.BusinessEntityID = edh.BusinessEntityID
    JOIN LatestPay AS p ON p.BusinessEntityID = edh.BusinessEntityID AND p.rn = 1
    WHERE edh.EndDate IS NULL
),
CurrentAgg AS (
    SELECT
        DepartmentID,
        COUNT(*)                                                           AS Headcount,
        AVG(1.0 * VacationHours)                                           AS AvgVacationHours,
        MAX(Rate) / NULLIF(MIN(Rate), 0)                                   AS PayDisparityRatio
    FROM CurrentEmp
    GROUP BY DepartmentID
)
SELECT
    d.Name                                              AS DepartmentName,
    ca.Headcount,
    CAST(t.TransferOutRatePct  AS DECIMAL(5,2))         AS TransferOutRatePct,
    CAST(ca.AvgVacationHours   AS DECIMAL(6,1))         AS AvgUnusedVacationHours,
    CAST(ca.PayDisparityRatio  AS DECIMAL(6,2))         AS PayDisparityRatio,
    RANK() OVER (ORDER BY t.TransferOutRatePct DESC)
  + RANK() OVER (ORDER BY ca.AvgVacationHours  DESC)
  + RANK() OVER (ORDER BY ca.PayDisparityRatio DESC)    AS CombinedRiskRank   -- lower = riskier
FROM HumanResources.Department AS d
JOIN Transfers   AS t  ON t.DepartmentID  = d.DepartmentID
JOIN CurrentAgg  AS ca ON ca.DepartmentID = d.DepartmentID
ORDER BY CombinedRiskRank ASC;