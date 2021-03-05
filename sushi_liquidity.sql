-- Sushi pools
-- RULER/ETH 0xb1EECFea192907fC4bF9c4CE99aC07186075FC51
-- rWBTC 25000 / DAI 0xFAf5125553f669250c44C7A38C4208ba45E3F18E
-- rETH 750 / DAI 0x87619715b9E5beEe8F2CB1d33387ea6fC6b2Ce34
-- rCover 750 / DAI 0x54ca5B62D3D0540fC5be9fC560721797ed202B97


-- hourly average ETH price as price for conversion
WITH prices AS (                                                                                       
    SELECT  date_trunc('hour', minute) as hour,                                                         
            AVG(price) as price                                                                                
    FROM prices.layer1_usd
    WHERE symbol = 'ETH'
    GROUP BY 1                                                                                      
)

SELECT 
    hour, pool, price,
    CASE 
        WHEN eth > usd_val THEN eth * 2 * a.price / 1e18 -- value as ETH value converted to USD for pool 1
        WHEN eth < usd_val THEN usd_val * 2 / 1e18 -- value as USD for pools 2-4
    END AS val 
FROM (
    SELECT 
        avg(CASE 
                WHEN contract_address = '\xb1EECFea192907fC4bF9c4CE99aC07186075FC51' THEN reserve0
                ELSE 0  
            END) AS eth,
        avg(CASE
                WHEN contract_address = '\xb1EECFea192907fC4bF9c4CE99aC07186075FC51' THEN 0
                ELSE reserve1
            END) AS usd_val,
        date_trunc('hour',evt_block_time) AS h, -- truncate timestamp to hourly
        CASE -- assign token pair designation based on contract_address
            WHEN contract_address = '\xb1EECFea192907fC4bF9c4CE99aC07186075FC51' THEN 'ruler - eth' 
            WHEN contract_address = '\xFAf5125553f669250c44C7A38C4208ba45E3F18E' THEN 'rwbtc - dai'
            WHEN contract_address = '\x87619715b9E5beEe8F2CB1d33387ea6fC6b2Ce34' THEN 'reth - dai'
            WHEN contract_address = '\x54ca5B62D3D0540fC5be9fC560721797ed202B97' THEN 'rcover - dai'
        END as pool
    
    FROM sushi."Pair_evt_Sync" 
    WHERE contract_address IN ('\xb1EECFea192907fC4bF9c4CE99aC07186075FC51', '\xFAf5125553f669250c44C7A38C4208ba45E3F18E', '\x87619715b9E5beEe8F2CB1d33387ea6fC6b2Ce34', '\x54ca5B62D3D0540fC5be9fC560721797ed202B97') -- select only relevant contract pairs from Sushi pairs dataset
    GROUP by contract_address, h -- group by token pair (i.e., Sushi pool) and hour
    ORDER BY h DESC
) x
JOIN prices a ON x.h = a.hour

/*
Visualization options:
chart type - line
x column - hour
y column - val
group by - pool

(1) stack values in line chart
(2) stack and normalize in bar chart
*/
