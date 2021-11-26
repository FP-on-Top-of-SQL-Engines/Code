DROP TYPE IF EXISTS args CASCADE;
CREATE TYPE args AS (i int, j int);

------------------------------------------------------------------------

DROP TYPE IF EXISTS K CASCADE;
CREATE TYPE K AS (clos char, i int, j int, d1 double precision, d2 double precision, args args);

-- memoization table
DROP TABLE IF EXISTS memo;
CREATE TABLE memo (
  args  args PRIMARY KEY,
  x     double precision
);

DROP FUNCTION IF EXISTS dtw(int, int);
CREATE FUNCTION dtw(i int, j int) RETURNS double precision AS
$$
  WITH RECURSIVE recurse(fn, i, j, x, k) AS MATERIALIZED (
    -- invocation
    SELECT  'DTW' AS fn, dtw.i, dtw.j, NULL :: double precision AS x,
            array[ROW('0', NULL, NULL, NULL, NULL, (dtw.i, dtw.j) :: args) :: K] AS k

      UNION ALL

    SELECT  trampoline.*
    FROM    recurse AS r,
    LATERAL (SELECT (r.k[1]).*) AS TOP(clos, i, j, d1, d2, args),
    LATERAL (SELECT COALESCE(m."memo?", false) AS "memo?", m.val
             FROM   (SELECT NULL) AS _ LEFT OUTER JOIN
                    (SELECT true AS "memo?", m.x AS val
                     FROM   memo AS m
                     WHERE  (r.i, r.j) = m.args) AS m
                      ON true) AS memo("memo?", val),
    LATERAL (SELECT 'Apply' AS fn, r.i, r.j, memo.val, r.k
             WHERE  memo."memo?" AND r.fn = 'DTW'
               UNION ALL
             SELECT 'Apply' AS fn, NULL AS i, NULL AS j, 0 AS x, r.k
             WHERE  NOT memo."memo?" AND r.fn = 'DTW' AND r.i = 0 AND r.j = 0
               UNION ALL
             SELECT 'Apply' AS fn, NULL AS i, NULL AS j, 'Infinity' :: double precision AS x, r.k
             WHERE  NOT memo."memo?" AND r.fn = 'DTW' AND r.i <> 0 AND r.j = 0
               UNION ALL
             SELECT 'Apply' AS fn, NULL AS i, NULL AS j, 'Infinity' :: double precision AS x, r.k
             WHERE  NOT memo."memo?" AND r.fn = 'DTW' AND r.i = 0 AND r.j <> 0
               UNION ALL
             SELECT 'DTW' AS fn, r.i-1 AS i, r.j-1 AS j, NULL AS x,
                    ROW('1', r.i, r.j, NULL, NULL, (r.i-1, r.j-1) :: args) :: K || r.k AS k
             WHERE  NOT memo."memo?" AND r.fn = 'DTW' AND r.i <> 0 AND r.j <> 0
               UNION ALL
             SELECT 'Finish' AS fn, NULL AS i, NULL AS j, r.x, NULL AS k
             WHERE  r.fn = 'Apply' AND TOP.clos = '0'
               UNION ALL
             SELECT 'DTW' AS fn, TOP.i-1 AS i, TOP.j, NULL AS x,
                    ROW('2', TOP.i, TOP.j, r.x, NULL, (TOP.i-1, TOP.j) :: args) :: K || r.k[2:] AS k
             WHERE  r.fn = 'Apply' AND TOP.clos = '1'
               UNION ALL
             SELECT 'DTW' AS fn, TOP.i AS i, TOP.j-1 AS j, NULL AS x,
                    ROW('3', TOP.i, TOP.j, TOP.d1, r.x, (TOP.i, TOP.j-1) :: args) :: K || r.k[2:] AS k
             WHERE  r.fn = 'Apply' AND TOP.clos = '2'
               UNION ALL
             SELECT 'Apply' AS fn, NULL AS i, NULL AS j, ABS(X.x-Y.y) + LEAST(TOP.d1,
                    TOP.d2, r.x) AS x, r.k[2:] AS k
             FROM X, Y
             WHERE  r.fn = 'Apply' AND TOP.clos = '3' AND (X.t, Y.t) = (TOP.i, TOP.j)
            ) AS trampoline(fn, node, target, x, k)
  ),
  -- extract results of all (intermediate) recursive function calls
  --   and insert into memoization table
  memoization AS (
    INSERT INTO memo(args, x)
      SELECT (r.k[1]).args, r.x    -- args closure + result x
      FROM   recurse AS r
      WHERE  r.fn = 'Apply'        -- non-recursive calls to apply
    ON CONFLICT (args) DO NOTHING
  )
  -- return final result
  SELECT r.x
  FROM   recurse AS r
  WHERE  r.fn = 'Finish';
$$
LANGUAGE SQL VOLATILE STRICT;


DROP FUNCTION IF EXISTS measure(int);

CREATE FUNCTION measure(measurements INT) RETURNS VOID AS
$$
DECLARE
  StartTime timestamptz;
  EndTime timestamptz;
  Delta double precision;
  val RECORD;
BEGIN
   FOR j IN 1 .. measurements LOOP
      Delta := 0.0;
      FOR val IN
        (SELECT x, y
         FROM   generate_series(1, (SELECT COUNT(*)::int FROM X)) AS _(x),
                generate_series(1, (SELECT COUNT(*)::int FROM Y)) AS __(y),
                generate_series(1,greatest(30-j*2, 1)) AS ___(f)
         WHERE  x <= j+1 AND y <= j+1
         ORDER BY f ASC, x DESC, y DESC
         LIMIT 100)
      LOOP
        StartTime := clock_timestamp();
        PERFORM dtw(val.x, val.y);
        EndTime := clock_timestamp();
        Delta := Delta + 1000 * ( extract(epoch from EndTime) - extract(epoch from StartTime) );
      END LOOP;
      RAISE NOTICE 'Time: % ms ', round(Delta::numeric, 2);
      RAISE NOTICE 'memo length: %', (SELECT COUNT(*) FROM memo);
   END LOOP;
END
$$ LANGUAGE PLPGSQL;

SELECT measure(:measurements);
DROP FUNCTION measure;
