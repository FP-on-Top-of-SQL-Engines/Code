-----------------------------------------------------------------------
-- Memoization:
--
-- 1. Augment closure with additional field args (nodes, s, e) to hold
--   the argument (nodes, s, e) of the current call to floyd
--
-- 2. Populate the closure field args (nodes, s, e) whenever the trampoline
--   performs a recursive call to floyd (SELECT 'floyd' AS fn, ...): "when this closure
--   is being evaluated, it happens during a call floyd(args.nodes, args.s, args.e)".
--
-- 3. In the resulting working table, identify the rows with calls to apply (fn = 'APPLY')
--   (non-recursive calls that apply a closure to compute a result x).  The fields
--   (args.nodes, args.s, args.e) of the topmost closure indicate the function arguments
--   for which result x was computed.  Insert (args.nodes, args.s, args.e, x) into memo table.


-- Holds argument triple (nodes, s, e) of current floyd function call
DROP TYPE IF EXISTS args CASCADE;
CREATE TYPE args AS (nodes int, s int, e int);

------------------------------------------------------------------------

DROP TYPE IF EXISTS K CASCADE;
CREATE TYPE K AS (clos char, nodes int, s int, e int, s1 int, s2 int, args args);

------------------------------------------------------------------------
-- memoization table
DROP TABLE IF EXISTS memo;
CREATE TABLE memo (
  args  args PRIMARY KEY,
  x     int
);

DROP FUNCTION IF EXISTS floyd(int, int, int);
CREATE FUNCTION floyd(nodes int, s int, e int) RETURNS int AS
$$
  WITH RECURSIVE recurse(fn, nodes, s, e, x, k) AS MATERIALIZED (
    -- invocation
    SELECT  'floyd' AS fn, floyd.nodes, floyd.s, floyd.e, NULL :: int AS x,
            array[ROW('0', NULL, NULL, NULL, NULL, NULL, (floyd.nodes, floyd.s, floyd.e) :: args) :: K] AS k
      UNION ALL

    SELECT  trampoline.*
    FROM    recurse AS r,
    LATERAL (SELECT (r.k[1]).*) AS TOP(clos, nodes, s, e, s1, s2, args),
    LATERAL (-- do we memorize floyd's value val for arguments r.nodes, r.s, r.e?
             SELECT COALESCE(m."memo?", false) AS "memo?", m.val
             FROM   (SELECT NULL) AS _ LEFT OUTER JOIN
                    (SELECT true AS "memo?", m.x AS val
                     FROM   memo AS m
                     WHERE  (r.nodes, r.s, r.e) = m.args) AS m
                      ON true) AS memo("memo?", val),
    LATERAL (-- recursive calls to floyd that could be memorized turn into base cases,
             -- pass memorized value to current continuation r.k
             SELECT 'apply' AS fn, r.nodes, r.s, r.e, memo.val, r.k
             WHERE  memo."memo?" AND r.fn = 'floyd'
               UNION ALL
             SELECT 'apply' AS fn, NULL AS nodes, NULL AS s, NULL AS e,
                    (SELECT edge.weight
                     FROM   edges AS edge
                     WHERE  (edge.here, edge.there) = (r.s, r.e)) AS x, r.k
             WHERE  NOT memo."memo?" AND r.fn = 'floyd' AND r.nodes = 0
               UNION ALL
             SELECT 'floyd' AS fn, r.nodes-1 AS nodes, r.s, r.e, NULL AS x,
                    ROW('1', r.nodes, r.s, r.e, NULL, NULL, (r.nodes-1, r.s, r.e) :: args) :: K || r.k AS k
             WHERE  NOT memo."memo?" AND r.fn = 'floyd' AND NOT r.nodes = 0
               UNION ALL
             SELECT 'finish' AS fn, NULL AS nodes, NULL AS s, NULL AS e, r.x, NULL AS k
             WHERE  r.fn = 'apply' AND TOP.clos = '0'
               UNION ALL
             SELECT 'floyd' AS fn, TOP.nodes-1 AS nodes, TOP.s, TOP.nodes AS e, NULL AS x,
                    ROW('2', TOP.nodes, NULL, TOP.e, r.x, NULL, (TOP.nodes-1, TOP.s, TOP.nodes) :: args) :: K || r.k[2:] AS k
             WHERE  r.fn = 'apply' AND TOP.clos = '1'
               UNION ALL
             SELECT 'floyd' AS fn, TOP.nodes-1 AS nodes, TOP.nodes AS s, TOP.e, NULL AS x,
                    ROW('3', NULL, NULL, NULL, TOP.s1, r.x, (TOP.nodes-1, TOP.nodes, TOP.e) :: args) :: K || r.k[2:] AS k
             WHERE  r.fn = 'apply' AND TOP.clos = '2'
               UNION ALL
             SELECT 'apply' AS fn, NULL AS nodes, NULL AS s, NULL AS e, LEAST(TOP.s1, TOP.s2+r.x) AS x, r.k[2:] AS k
             WHERE  r.fn = 'apply' AND TOP.clos = '3'
            ) AS trampoline(fn, nodes, s, e, x, k)
  ),
  -- extract results of all (intermediate) recursive function calls
  --   and insert into memoization table
  memoization AS (
    INSERT INTO memo(args, x)
      SELECT (r.k[1]).args, r.x    -- args.nodes, args.s, args.e of topmost closure + result x
      FROM   recurse AS r
      WHERE  r.fn = 'apply'        -- non-recursive calls to apply
    ON CONFLICT (args) DO NOTHING
  )
  -- return final result
  SELECT r.x
  FROM   recurse AS r
  WHERE  r.fn = 'finish';
$$
LANGUAGE SQL VOLATILE;

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
        (SELECT here, there
         FROM generate_series(1, 100) as s(i), --batch size
           (SELECT MAX(node) FROM nodes) AS _(max),
           LATERAL (SELECT h FROM generate_series(1, max) as _(h) WHERE s.i = s.i ORDER BY random() LIMIT 1) AS __(here),
           LATERAL (SELECT t FROM generate_series(1, max) as _(t) WHERE s.i = s.i ORDER BY random() LIMIT 1) AS ___(there))
      LOOP
        PERFORM k.here,
                k.there,
                floyd((SELECT COUNT(*) FROM nodes) :: int, k.here, k.there);
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
