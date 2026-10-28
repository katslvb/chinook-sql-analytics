-- Запрос 1: Вывод всех клиентов (тест)
SELECT 
    *
FROM
    Customer
LIMIT 10;


-- Этап 1. Базовая статистика
-- Сколько клиентов в базе, из скольких стран пришли
SELECT 
    COUNT(customerId) count_customers,
    COUNT(DISTINCT country) count_countries
FROM
    Customer;
   
   
-- Какая выручка магазина и средний чек одного заказа?
SELECT 
    SUM(total) AS sum_total, ROUND(AVG(total), 2) AS avg_total
FROM
    Invoice;


-- Сколько всего треков в базе и какова их средняя продолжительность в минутах?
SELECT 
    COUNT(trackId) AS count_tracks,
    COUNT(DISTINCT albumId) AS count_albums,
    ROUND(AVG(Milliseconds) / 60000) AS avg_minutes
FROM
    Track;
    
    
-- Какие 5 жанров музыки представлены большим количеством треков?      
SELECT 
    genre.name AS Genre_name, COUNT(TrackId) AS Count_tracks
FROM
    genre
        INNER JOIN
    track USING (genreid)
GROUP BY genreId
ORDER BY 2 DESC
LIMIT 5;


-- Этап 2: Клиентская аналитика
-- Какие клиенты самые прибыльные (топ 10 клиентов по сумме покупок)?
SELECT 
    CONCAT(FirstName, ' ', LastName) AS FullName,
    SUM(Total) AS Total_all
FROM
    customer
        INNER JOIN
    invoice USING (CustomerId)
GROUP BY CustomerId
ORDER BY 2 DESC
LIMIT 10;


-- Какие страны приносят больше всего выручки (топ 10 стран)?
SELECT 
    Country,
    SUM(Total) AS Total_Country,
    ROUND(AVG(total), 2) AS Avg_Total_Country,
    COUNT(DISTINCT CustomerId) AS Count_Customers
FROM
    customer
        INNER JOIN
    invoice USING (CustomerId)
GROUP BY Country
ORDER BY 2 DESC
LIMIT 10;


-- Какие клиенты сделали больше всего заказов, и совпадает ли это с их суммой покупок?
SELECT 
    CustomerId,
    CONCAT(FirstName, ' ', LastName) AS FullName,
    COUNT(InvoiceId) AS Count_invoice,
    SUM(Total) AS Total_all,
    ROUND(AVG(Total), 2) AS Total_avg
FROM
    customer
        INNER JOIN
    invoice USING (CustomerId)
GROUP BY CustomerId , FirstName , LastName
HAVING COUNT(InvoiceId) >= 7
ORDER BY 4 DESC;


-- Этап 3. 
-- 3.1. Кто является самым ценным клиентом в каждой стране?
with ClientSpending as (
select Country, CustomerId, CONCAT(FirstName, ' ', LastName) AS FullName,
    SUM(Total) AS Total_Spent
FROM
    customer
        INNER JOIN
    invoice USING (CustomerId)
GROUP BY Country, CustomerId, FirstName, LastName
)
SELECT
	dense_rank() over w as RankInCountry,
    Country, FullName, Total_Spent
from ClientSpending
window w as (partition by country
order by Total_Spent desc)
order by Country, RankInCountry;


-- 3.2. как часто клиенты возвращаются? (лояльность)
select CustomerId, CONCAT(FirstName, ' ', LastName) AS FullName, Country, date(InvoiceDate) as Date, 
lag(date(InvoiceDate)) over w as Date_prev, datediff(date(InvoiceDate), lag(date(InvoiceDate)) over w) as Diff_Datess
FROM
    customer
        INNER JOIN
    invoice USING (CustomerId)
window w as (partition by CustomerId order by InvoiceDate)
order by CustomerId, InvoiceDate;


-- 3.3. Частота покупок и как это связано с их общими тратами?
with diff_date as (
select CustomerId, CONCAT(FirstName, ' ', LastName) AS FullName, Country, date(InvoiceDate) as Date, 
lag(date(InvoiceDate)) over w as Date_prev, datediff(date(InvoiceDate), lag(date(InvoiceDate)) over w) as Diff_Dates, Total
FROM
    customer
        INNER JOIN
    invoice USING (CustomerId)
window w as (partition by CustomerId order by InvoiceDate)
)
select CustomerId, FullName, Country, round(avg(Diff_Dates)) as Avg_Diff_Date, sum(Total) as Total
from diff_date
group by CustomerId, FullName, Country
having avg(Diff_Dates) is not null
order by Avg_Diff_Date, Total desc; 


-- 3.4. Клиенты с общей суммой покупок превышающей среднюю по всем клиентам.
with cte as (
select CustomerId, CONCAT(FirstName, ' ', LastName) AS FullName, sum(total) as Client_Total,
round(avg(sum(Total)) over (),2) as All_Avg_Total
FROM
    customer
        INNER JOIN
    invoice USING (CustomerId)
group by CustomerId, FirstName, LastName
)
SELECT 
row_number () over (ORDER BY Client_Total DESC) AS Rank_num,
CustomerId, FullName, Client_Total, All_Avg_Total
FROM cte
WHERE Client_Total > All_Avg_Total
ORDER BY  Client_Total DESC;


-- 3.5. Самый продаваемый трек по каждому жанру музыки
WITH CTE1 AS (
SELECT genre.Name AS GenreName, track.Name AS TrackName, SUM(Quantity) AS TrackSold 
FROM genre 
	INNER JOIN track USING (GenreId)
    INNER JOIN invoiceline USING (TrackId)
GROUP BY genre.Name, track.Name
),
CTE2 AS (
SELECT GenreName, TrackName, TrackSold,
row_number () OVER (PARTITION BY GenreName ORDER BY TrackSold DESC) AS Rank_Num
FROM CTE1
)
SELECT GenreName, TrackName, TrackSold, Rank_Num
FROM CTE2
WHERE Rank_Num = 1
ORDER BY 3 DESC;


-- Этап 4.  Продвинутая аналитика (Оконные функции: Running Total, Moving Average)
-- 4.1. Накопительная выручка
WITH CTE AS (
SELECT DATE(InvoiceDate) AS Day_, SUM(UnitPrice*Quantity) AS Revenue
FROM invoiceline
	INNER JOIN invoice USING (InvoiceId)
GROUP BY DATE(InvoiceDate)
)
SELECT 
	Day_, Revenue, 
    SUM(Revenue) over w AS t_Revenue
FROM CTE
Window w AS (ORDER BY Day_
        ROWS BETWEEN unbounded preceding AND CURRENT ROW)
ORDER BY Day_; 


-- 4.2. Скользящее среднее
WITH CTE AS (
SELECT DATE(InvoiceDate) AS Day_, SUM(UnitPrice*Quantity) AS Revenue
FROM invoiceline
	INNER JOIN invoice USING (InvoiceId)
GROUP BY DATE(InvoiceDate)
)
SELECT 
	Day_, Revenue, 
    ROUND(AVG(Revenue) over w,2) AS Roll_avg_Revenue
FROM CTE
Window w AS (ORDER BY Day_
        ROWS BETWEEN 1 preceding AND 1 FOLLOWING)
ORDER BY Day_; 


-- Процентный ранг топ-10 клиентов в общей базе
WITH CTE AS (
SELECT CustomerId, CONCAT(FirstName, ' ', LastName) AS FullName, SUM(total) as Client_Total
FROM
    customer
        INNER JOIN
    invoice USING (CustomerId)
GROUP BY CustomerId, FirstName, LastName
)
SELECT FullName, Client_Total, ROUND(percent_rank() OVER w,2) as pers_rank
FROM CTE
window w as (order by Client_Total desc)
ORDER BY Client_Total desc
LIMIT 10;
