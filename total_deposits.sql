-- Hourly average prices as basis for value calculation
WITH 
    eth_prices AS (                                                                                       
        SELECT  date_trunc('hour', minute) as hour,                                                         
                AVG(price) as eth_price                                                                                
        FROM prices."layer1_usd"
        WHERE symbol = 'ETH' 
        GROUP BY 1                                                                                      
    ),
    btc_prices AS (                                                                                       
        SELECT  date_trunc('hour', minute) as hour,                                                         
                AVG(price) as btc_price                                                                                
        FROM prices."layer1_usd"
        WHERE symbol = 'BTC'
        GROUP BY 1                                                                                      
    )

SELECT 
    h, amount, collateral_token, collateral,
    CASE 
        WHEN collateral_token = 'WETH' THEN amount * a.eth_price / 1e18 -- value as ETH value converted to USD for pool 1
        WHEN collateral_token = 'WBTC' THEN amount * b.btc_price / 1e8
        WHEN collateral_token = 'COVER' THEN 0
    END AS val 
FROM (
    SELECT 
        sum(amount) AS amount,
        date_trunc('hour',evt_block_time) AS h, -- truncate timestamp to hourly
        collateral,
        CASE -- assign token pair designation based on contract_address
            WHEN collateral = '\xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2' THEN 'WETH' 
            WHEN collateral = '\x4688a8b1f292fdab17e9a90c8bc379dc1dbd8713' THEN 'COVER'
            WHEN collateral = '\x2260fac5e5542a773aa44fbcfedf7c193bc2c599' THEN 'WBTC'
            ELSE 'unidentified collateral'
        END as collateral_token
    
    FROM ruler_protocol."RulerCore_evt_Deposit"
    GROUP by collateral, h -- group by collateral token and hour
    ORDER BY h DESC -- most recent values first
) x
JOIN eth_prices a ON x.h = a.hour 
JOIN btc_prices b ON x.h = b.hour
 

/*
Visualization options:
chart type - bar
x-axis - h
y-axis - deposits BTC, WETH, COVER
stacked
*/

-- Zweiter versuch


-- hourly average ETH price as price for conversion
WITH 
    eth_prices AS (                                                                                       
        SELECT  date_trunc('hour', minute) as hour,                                                         
                AVG(price) as eth_price                                                                                
        FROM prices."layer1_usd"
        WHERE symbol = 'ETH' 
        GROUP BY 1                                                                                      
    ),
    btc_prices AS (                                                                                       
        SELECT  date_trunc('hour', minute) as hour,                                                         
                AVG(price) as btc_price                                                                                
        FROM prices."layer1_usd"
        WHERE symbol = 'BTC'
        GROUP BY 1                                                                                      
    ),
    cover_prices AS (
            WITH weth_pairs AS ( -- Get exchange contract address and "other token" for WETH
            SELECT cr."pair" AS contract, 
                CASE WHEN cr."token0" = '\xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2' then '0' ELSE '1' END  AS eth_token,
                CASE WHEN cr."token1" = '\xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2' then cr."token0" ELSE cr."token1" END  AS other_token 
            FROM uniswap_v2."Factory_evt_PairCreated" cr
            WHERE token0 = '\xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2' OR  token1 = '\xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'
            )
            
        , swap AS ( -- Get all trades on the pair last 14 days
            SELECT
                CASE WHEN eth_token = '0' then sw."amount0In" + sw."amount0Out" ELSE sw."amount1In" + sw."amount1Out"
                END/1e18 AS eth_amt, 
                CASE WHEN eth_token = '1' then sw."amount0In" + sw."amount0Out" ELSE sw."amount1In" + sw."amount1Out"
                END/power(10, tok."decimals") AS other_amt, -- If the token is not in the erc20.tokens list you can manually divide by 10^decimals
                tok."symbol",
                tok."contract_address",
                date_trunc('hour', sw."evt_block_time") AS hour
            FROM uniswap_v2."Pair_evt_Swap" sw
            JOIN weth_pairs ON sw."contract_address" = weth_pairs."contract"
            JOIN erc20."tokens" tok ON weth_pairs."other_token" = tok."contract_address"
            WHERE other_token = '\x4688a8b1f292fdab17e9a90c8bc379dc1dbd8713' --COVER example
            -- To allow users to submit token address in the Dune UI you can use the below line:
            
            AND sw.evt_block_time >= now() - interval '180 days'
            )
            
        , eth_prcs AS (
            SELECT avg(price) eth_prc, date_trunc('hour', minute) AS hour
            FROM prices.layer1_usd_eth
            WHERE minute >= now() - interval '14 days'
            group by 2
            )
        
        SELECT
            AVG((eth_amt/other_amt)*eth_prc) AS cover_price,
            -- swap."symbol" AS symbol,
            -- swap."contract_address" AS contract_address,
            eth_prcs."hour" AS hour
        FROM swap JOIN eth_prcs ON swap."hour" = eth_prcs."hour"
        GROUP BY 2 -- 2,3,4
        
    )


SELECT 
    h, amount, collateral_token, collateral,
    CASE 
        WHEN collateral_token = 'WETH' THEN amount * a.eth_price / 1e18 -- value as ETH value converted to USD for pool 1
        WHEN collateral_token = 'WBTC' THEN amount * b.btc_price / 1e8
        WHEN collateral_token = 'COVER' THEN amount * c.cover_price / 1e18
    END AS val 
FROM (
    SELECT 
        sum(amount) AS amount,
        date_trunc('hour',evt_block_time) AS h, -- truncate timestamp to hourly
        collateral,
        CASE -- assign token pair designation based on contract_address
            WHEN collateral = '\xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2' THEN 'WETH' 
            WHEN collateral = '\x4688a8b1f292fdab17e9a90c8bc379dc1dbd8713' THEN 'COVER'
            WHEN collateral = '\x2260fac5e5542a773aa44fbcfedf7c193bc2c599' THEN 'WBTC'
            ELSE 'unidentified collateral'
        END as collateral_token
    
    FROM ruler_protocol."RulerCore_evt_Deposit"
    -- WHERE contract_address IN ('\xb1EECFea192907fC4bF9c4CE99aC07186075FC51', '\xFAf5125553f669250c44C7A38C4208ba45E3F18E', '\x87619715b9E5beEe8F2CB1d33387ea6fC6b2Ce34', '\x54ca5B62D3D0540fC5be9fC560721797ed202B97') -- select only relevant contract pairs from Sushi pairs dataset
    GROUP by collateral, h -- group by token pair (i.e., Sushi pool) and hour
    ORDER BY h DESC
) x
JOIN eth_prices a ON x.h = a.hour 
JOIN btc_prices b ON x.h = b.hour
JOIN cover_prices c ON x.h = c.hour
 
