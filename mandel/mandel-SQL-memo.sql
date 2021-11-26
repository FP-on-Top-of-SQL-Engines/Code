-- Render an ASCII art approximation of the Mandelbrot Set
--
-- This has been directly adapted from SQLite's "Outlandish Recursive Query Examples"
-- found at https://www.sqlite.org/lang_with.html


-----------------------------------------------------------------------
-- SQL UDF to approximate the Mandelbrot Set at point (cx, cy)
--

DROP TYPE IF EXISTS args CASCADE;
CREATE TYPE args AS (iter int, cx float, cy float, x float, y float);

------------------------------------------------------------------------

-- memoization table
DROP TABLE IF EXISTS memo;
CREATE TABLE memo (
  args  args PRIMARY KEY,
  x     int
);

DROP FUNCTION IF EXISTS m(int, float, float, float, float);
CREATE FUNCTION m(iter int, cx float, cy float, x float, y float) RETURNS int AS
$$
  WITH RECURSIVE recurse(fn, iter, cx, cy, x, y, res, k) AS MATERIALIZED (
    -- invocation
    SELECT  'm' AS fn, m.iter, m.cx, m.cy, m.x, m.y, NULL :: int AS res,
            (m.iter, m.cx, m.cy, m.x, m.y) :: args AS k

      UNION ALL

    SELECT  trampoline.*
    FROM    recurse AS r,
    LATERAL (SELECT COALESCE(m."memo?", false) AS "memo?", m.val
             FROM   (SELECT NULL) AS _ LEFT OUTER JOIN
                    (SELECT true AS "memo?", memo.x AS val
                     FROM   memo
                     WHERE  (r.iter, r.cx, r.cy, r.x, r.y) = memo.args) AS m
                      ON true) AS memo("memo?", val),
    LATERAL (SELECT 'finish' AS fn, r.iter, r.cx, r.cy, r.x, r.y, memo.val, r.k
             WHERE  memo."memo?" AND r.fn = 'm'
               UNION ALL
             SELECT 'm' AS fn, r.iter+1 AS iter, r.cx, r.cy, r.x^2 - r.y^2 + r.cx AS x, 2.0 * r.x * r.y + r.cy AS y, NULL AS res,
                    ROW(r.iter+1, r.cx, r.cy, r.x^2 - r.y^2 + r.cx, 2.0 * r.x * r.y + r.cy) :: args AS k
             WHERE  NOT memo."memo?" AND r.fn = 'm' AND (r.x^2 + r.y^2 < 4.0 AND r.iter < 28)
               UNION ALL
             SELECT 'finish' AS fn, NULL AS iter, NULL AS cx, NULL AS cy, NULL AS x, NULL AS y, r.iter AS res, NULL AS k
             WHERE  NOT memo."memo?" AND r.fn = 'm' AND NOT (r.x^2 + r.y^2 < 4.0 AND r.iter < 28)
            ) AS trampoline(fn, iter, cx, cy, x, y, res, k)
  ),
  -- extract results of all (intermediate) recursive function calls
  --   and insert into memoization table
  memoization AS (
    INSERT INTO memo(args, x)
      SELECT r.k, res.res
      FROM   recurse AS r, recurse AS res
      WHERE  r.fn = 'm' AND res.fn = 'finish'
    ON CONFLICT (args) DO NOTHING
  )
  -- return final result
  SELECT r.res
  FROM   recurse AS r
  WHERE  r.fn = 'finish';
$$
LANGUAGE SQL VOLATILE STRICT;

-- Resolution in pixels on the y axis (N ⩾ 5 for sensible results)

DROP FUNCTION IF EXISTS measure(int);

CREATE FUNCTION measure(measurements INT) RETURNS VOID AS
$$
DECLARE
  StartTime timestamptz;
  EndTime timestamptz;
  Delta double precision;
  k RECORD;
BEGIN
   FOR i IN 1 .. measurements LOOP
      StartTime := clock_timestamp();
      FOR k IN
        (SELECT x, y
        FROM (SELECT (random() * 100 + 1) :: int AS N FROM generate_series(1,100)) AS __(N), LATERAL
            (WITH
              xaxis(x) AS (
                SELECT i1 AS x
                FROM   generate_series(-2.0, 1.2, (1.2 - (-2.0)) / (3 * N)) AS i1
              ),
              yaxis(y) AS (
                SELECT i2 AS y
                FROM   generate_series(-1.0, 1.0, (1.0 - (-1.0)) / N) AS i2
              ) SELECT * FROM xaxis AS x, yaxis AS y) AS _(x, y)
        LIMIT 100)
      LOOP
        PERFORM m(0, k.x, k.y, 0.0, 0.0);
      END LOOP;
      EndTime := clock_timestamp();
      Delta := 1000 * ( extract(epoch from EndTime) - extract(epoch from StartTime) );
      RAISE NOTICE 'Time: % ms ', round(Delta::numeric, 2);
      RAISE NOTICE 'memo length: %', (SELECT COUNT(*) FROM memo);
   END LOOP;
END
$$ LANGUAGE PLPGSQL;

SELECT measure(:measurements);
DROP FUNCTION measure;
