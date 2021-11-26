-- march components in a directed acyclic graph (DAG) with an out-degree of two

DROP TYPE IF EXISTS args CASCADE;
CREATE TYPE args AS (current int[], goal int[], "track?" bool);

------------------------------------------------------------------------

DROP TYPE IF EXISTS K CASCADE;
CREATE TYPE K AS (clos char, current int[], "track?" boolean, args args);

-- memoization table
DROP TABLE IF EXISTS memo;
CREATE TABLE memo (
  args  args PRIMARY KEY,
  x     int[][]
);

DROP FUNCTION IF EXISTS march(int[], int[], boolean);
CREATE FUNCTION march(current int[], goal int[], "track?" boolean) RETURNS int[][] AS
$$
  WITH RECURSIVE recurse(fn, current, goal, "track?", x, k) AS MATERIALIZED (
    -- invocation
    SELECT  'march' AS fn, march.current, march.goal, march."track?", NULL :: int[][] AS x,
            array[ROW('0', NULL, NULL, (march.current, march.goal, march."track?") :: args) :: K] AS k

      UNION ALL

    SELECT  trampoline.*
    FROM    recurse AS r,
    LATERAL (SELECT (r.k[1]).*) AS TOP(clos, current, "track?", args),
    LATERAL (SELECT COALESCE(m."memo?", false) AS "memo?", m.val
             FROM   (SELECT NULL) AS _ LEFT OUTER JOIN
                    (SELECT true AS "memo?", m.x AS val
                     FROM   memo AS m
                     WHERE  (r.current, r.goal, r."track?") = m.args) AS m
                      ON true) AS memo("memo?", val),
    LATERAL (SELECT 'apply' AS fn, r.current, r.goal, r."track?", memo.val, r.k
             WHERE  memo."memo?" AND r.fn = 'march'
               UNION ALL
             SELECT 'apply' AS fn, NULL AS current, NULL AS goal, NULL AS "track?",
                    ARRAY[] :: int[][] AS x, r.k
             WHERE  NOT memo."memo?" AND r.fn = 'march' AND r."track?" AND r.current = r.goal
               UNION ALL
             SELECT 'march' AS fn, ARRAY[r.current[1] + d.dir[0], r.current[2] + d.dir[1]] :: int[] AS current,
                    r.goal, d."track?", NULL AS x,
                    ROW('1', r.current, r."track?", (ARRAY[r.current[1] + d.dir[0],
                        r.current[2] + d.dir[1]] :: int[], r.goal, d."track?") :: args) :: K || r.k AS k
             FROM squares AS s, directions AS d
             WHERE  NOT memo."memo?" AND r.fn = 'march' AND NOT(r."track?" AND r.current = r.goal) AND
                        r.current = s.xy AND (s.ll,s.lr,s.ul,s.ur) = (d.ll,d.lr,d.ul,d.ur) AND d."track?"
               UNION ALL
             SELECT 'march' AS fn, ARRAY[r.current[1] + d.dir[0], r.current[2] + d.dir[1]] :: int[] AS current,
                    ARRAY[r.current[1] + d.dir[0], r.current[2] + d.dir[1]] :: int[] AS goal, d."track?", NULL AS x,
                    ROW('1', r.current, r."track?", (ARRAY[r.current[1] + d.dir[0],
                        r.current[2] + d.dir[1]] :: int[], ARRAY[r.current[1] + d.dir[0],
                        r.current[2] + d.dir[1]] :: int[], d."track?") :: args) :: K || r.k AS k
             FROM squares AS s, directions AS d
             WHERE  NOT memo."memo?" AND r.fn = 'march' AND NOT(r."track?" AND r.current = r.goal) AND
                        r.current = s.xy AND (s.ll,s.lr,s.ul,s.ur) = (d.ll,d.lr,d.ul,d.ur) AND NOT(d."track?")
               UNION ALL
             SELECT 'finish' AS fn, NULL AS current, NULL AS goal, NULL AS "track?", r.x, NULL AS k
             WHERE  r.fn = 'apply' AND TOP.clos = '0'
               UNION ALL
             SELECT 'apply' AS fn, NULL AS current, NULL AS goal, NULL AS "track?",
                    ARRAY[TOP.current] || r.x AS x, r.k[2:] AS k
             WHERE  r.fn = 'apply' AND TOP.clos = '1' AND TOP."track?"
               UNION ALL
             SELECT 'apply' AS fn, NULL AS current, NULL AS goal, NULL AS "track?",
                    ARRAY[] :: int[][] || r.x AS x, r.k[2:] AS k
             WHERE  r.fn = 'apply' AND TOP.clos = '1' AND NOT(TOP."track?")
            ) AS trampoline(fn, current, goal, "track?", x, k)
  ),
  -- extract results of all (intermediate) recursive function calls
  --   and insert into memoization table
  memoization AS (
    INSERT INTO memo(args, x)
      SELECT (r.k[1]).args, r.x    -- args closure + result x
      FROM   recurse AS r
      WHERE  r.fn = 'apply'        -- non-recursive calls to apply
    ON CONFLICT (args) DO NOTHING
  )
  -- return final result
  SELECT r.x
  FROM   recurse AS r
  WHERE  r.fn = 'finish';
$$
LANGUAGE SQL VOLATILE STRICT;

-- Trace the shape's border in the 2D map, starting from (x,y)
--

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
         FROM generate_series(1, 100) as s(i), --batch size,
           LATERAL (SELECT x FROM generate_series(0, 57) AS _(x) WHERE s.i = s.i ORDER BY random() LIMIT 1) AS _(x),
           LATERAL (SELECT y FROM generate_series(0, 67) AS _(y) WHERE s.i = s.i ORDER BY random() LIMIT 1) AS __(y)
        )
      LOOP
        PERFORM point(k. x, k.y) AS start, march(array[k. x, k.y], array[k. x, k.y], false) AS border;
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
