/*
Final Project SQL Queries
Project: Underserved Intercity Air Routes

*/

-- Query 1: Count final route records and basic flight supply coverage.
-- Why: confirms the route-level table has enough rows for final analysis.
-- Output summary: 115 route records, 214 observed flights, average 1.86 flights per route.
SELECT
    COUNT(*) AS route_count,
    SUM(flight_count) AS observed_flights,
    AVG(flight_count) AS avg_flights_per_route
FROM routes;

-- Query 2: Check domestic versus cross-border route counts.
-- Why: domestic and cross-border routes have different planning implications.
-- Output summary: 32 cross-border routes and 83 domestic routes; average economic gap is similar across both groups.
SELECT
    is_domestic,
    COUNT(*) AS route_count,
    AVG(flight_count) AS avg_flight_count,
    AVG(economic_underserved_score) AS avg_economic_underserved_score
FROM routes
GROUP BY is_domestic;

-- Query 3: Rank routes by GDP-adjusted underserved score.
-- Why: this identifies routes with high economic demand relative to observed supply.
-- Output summary: top routes include Guangzhou-Shanghai and Beijing-Guangzhou corridors.
SELECT
    route,
    city_pair,
    dep_country_name,
    arr_country_name,
    flight_count,
    economic_underserved_score,
    RANK() OVER (ORDER BY economic_underserved_score DESC) AS economic_gap_rank
FROM routes
WHERE economic_underserved_score IS NOT NULL
ORDER BY economic_gap_rank
LIMIT 20;

-- Query 4: Join routes to country GDP for origin and destination checks.
-- Why: independently verifies the notebook's country-level GDP join and exposes missing economic data.
-- Output summary: 3 routes have missing origin or destination GDP, mainly involving Taiwan ISO code coverage.
SELECT
    r.route,
    r.city_pair,
    r.dep_country_iso3,
    dep_gdp.gdp_current_usd AS dep_gdp_current_usd,
    r.arr_country_iso3,
    arr_gdp.gdp_current_usd AS arr_gdp_current_usd
FROM routes AS r
LEFT JOIN country_gdp AS dep_gdp
    ON r.dep_country_iso3 = dep_gdp.country_iso3
LEFT JOIN country_gdp AS arr_gdp
    ON r.arr_country_iso3 = arr_gdp.country_iso3
WHERE dep_gdp.gdp_current_usd IS NULL
   OR arr_gdp.gdp_current_usd IS NULL;

-- Query 5: Aggregate route gaps by continent pair.
-- Why: identifies regional corridors with stronger underserved-route signals.
-- Output summary: AS-EU has the highest average economic gap, followed by AS-AS; note AS-EU has only 4 routes in this sample.
SELECT
    continent_pair,
    COUNT(*) AS route_count,
    SUM(flight_count) AS observed_flights,
    AVG(population_underserved_score) AS avg_population_gap,
    AVG(tourism_underserved_score) AS avg_tourism_gap,
    AVG(economic_underserved_score) AS avg_economic_gap
FROM routes
GROUP BY continent_pair
ORDER BY avg_economic_gap DESC;

-- Query 6: Window function comparing each route to its continent-pair average.
-- Why: shows which routes are unusually underserved within their own region type.
-- Output summary: Guangzhou-Shanghai is far above the AS-AS corridor average.
SELECT
    route,
    city_pair,
    continent_pair,
    economic_underserved_score,
    AVG(economic_underserved_score) OVER (PARTITION BY continent_pair) AS continent_pair_avg_gap,
    economic_underserved_score
        - AVG(economic_underserved_score) OVER (PARTITION BY continent_pair) AS gap_above_region_avg
FROM routes
WHERE economic_underserved_score IS NOT NULL
ORDER BY gap_above_region_avg DESC
LIMIT 20;

-- Query 7: Window function ranking routes within domestic/cross-border groups.
-- Why: creates separate ranked lists for different route-planning strategies.
-- Output summary: ranks separate domestic and cross-border opportunities; Shanghai-Istanbul leads cross-border routes.
SELECT
    route,
    city_pair,
    is_domestic,
    economic_underserved_score,
    DENSE_RANK() OVER (
        PARTITION BY is_domestic
        ORDER BY economic_underserved_score DESC
    ) AS group_rank
FROM routes
WHERE economic_underserved_score IS NOT NULL
ORDER BY is_domestic, group_rank
LIMIT 30;

-- Query 8: Subquery finding routes above the overall average GDP-adjusted gap.
-- Why: filters the candidate list to routes that are above the project baseline.
-- Output summary: 43 routes are above the overall average economic gap.
SELECT
    route,
    city_pair,
    flight_count,
    economic_underserved_score
FROM routes
WHERE economic_underserved_score > (
    SELECT AVG(economic_underserved_score)
    FROM routes
    WHERE economic_underserved_score IS NOT NULL
)
ORDER BY economic_underserved_score DESC;

-- Query 9: Subquery comparing high-GDP destination routes against all routes.
-- Why: tests whether richer destination markets tend to show larger route gaps.
-- Output summary: top destination-GDP quartile has 28 routes, average 2.54 flights, and lower average economic gap than the full top-gap list.
SELECT
    COUNT(*) AS high_gdp_destination_routes,
    AVG(flight_count) AS avg_flight_count,
    AVG(economic_underserved_score) AS avg_economic_gap
FROM (
    SELECT
        route,
        flight_count,
        economic_underserved_score,
        NTILE(4) OVER (ORDER BY arr_gdp_current_usd) AS destination_gdp_quartile
    FROM routes
    WHERE arr_gdp_current_usd IS NOT NULL
) AS ranked_routes
WHERE destination_gdp_quartile = 4;

-- Query 10: Data quality check for missing GDP and tourism inputs.
-- Why: confirms whether route scores rely on complete outside-data coverage.
-- Output summary: 1 route is missing departure GDP, 2 are missing arrival GDP, and 3 are missing arrival tourism.
SELECT
    SUM(CASE WHEN dep_gdp_current_usd IS NULL THEN 1 ELSE 0 END) AS missing_dep_gdp,
    SUM(CASE WHEN arr_gdp_current_usd IS NULL THEN 1 ELSE 0 END) AS missing_arr_gdp,
    SUM(CASE WHEN arr_tourism_arrivals IS NULL THEN 1 ELSE 0 END) AS missing_arr_tourism,
    COUNT(*) AS route_count
FROM routes;

-- Query 11: Join routes to destination-country GDP and tourism metadata.
-- Why: compares each candidate route against both destination economic scale and tourism demand.
-- Output summary: top rows confirm China-destination routes combine high GDP and tourism demand.
SELECT
    r.route,
    r.city_pair,
    r.arr_country_name,
    g.gdp_year AS destination_gdp_year,
    g.gdp_current_usd AS destination_gdp_current_usd,
    t.tourism_arrivals AS destination_tourism_arrivals,
    r.economic_underserved_score
FROM routes AS r
LEFT JOIN country_gdp AS g
    ON r.arr_country_iso3 = g.country_iso3
LEFT JOIN tourism AS t
    ON r.arr_country_iso3 = t.country_iso3
WHERE r.economic_underserved_score IS NOT NULL
ORDER BY r.economic_underserved_score DESC
LIMIT 20;

-- Query 12: Join origin and destination GDP tables to summarize route gaps by income group pair.
-- Why: checks whether underserved-route patterns differ by economic-development pairing.
-- Output summary: upper-middle to lower-middle income pairs have the highest average economic gap, though based on only 2 routes; NULL groups reflect the missing GDP coverage noted above.
SELECT
    dep_gdp.income_group AS dep_income_group,
    arr_gdp.income_group AS arr_income_group,
    COUNT(*) AS route_count,
    AVG(r.flight_count) AS avg_flight_count,
    AVG(r.economic_underserved_score) AS avg_economic_gap
FROM routes AS r
LEFT JOIN country_gdp AS dep_gdp
    ON r.dep_country_iso3 = dep_gdp.country_iso3
LEFT JOIN country_gdp AS arr_gdp
    ON r.arr_country_iso3 = arr_gdp.country_iso3
GROUP BY
    dep_gdp.income_group,
    arr_gdp.income_group
ORDER BY avg_economic_gap DESC;

