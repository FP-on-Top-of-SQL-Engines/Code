-- Connected components in a directed acyclic graph (DAG) with an out-degree of two

DROP TYPE IF EXISTS args CASCADE;
CREATE TYPE args AS (node int, target int);

------------------------------------------------------------------------

DROP TYPE IF EXISTS K CASCADE;
CREATE TYPE K AS (clos char, node int, target int, c1 boolean, args args);

-- memoization table
DROP TABLE IF EXISTS memo;
CREATE TABLE memo (
  args  args PRIMARY KEY,
  x     boolean
);

DROP FUNCTION IF EXISTS connected(int, int);
CREATE FUNCTION connected(node int, target int) RETURNS boolean AS
$$
  WITH RECURSIVE recurse(fn, node, target, x, k) AS MATERIALIZED (
    -- invocation
    SELECT  'Connected' AS fn, connected.node, connected.target, NULL :: boolean AS x,
            array[ROW('0', NULL, NULL, NULL, (connected.node, connected.target) :: args) :: K] AS k

      UNION ALL

    SELECT  trampoline.*
    FROM    recurse AS r,
    LATERAL (SELECT (r.k[1]).*) AS TOP(clos, node, target, c1, args),
    LATERAL (SELECT COALESCE(m."memo?", false) AS "memo?", m.val
             FROM   (SELECT NULL) AS _ LEFT OUTER JOIN
                    (SELECT true AS "memo?", m.x AS val
                     FROM   memo AS m
                     WHERE  (r.node, r.target) = m.args) AS m
                      ON true) AS memo("memo?", val),
    LATERAL (SELECT 'Apply' AS fn, r.node, r.target, memo.val, r.k
             WHERE  memo."memo?" AND r.fn = 'Connected'
               UNION ALL
             SELECT 'Apply' AS fn, NULL AS node, NULL AS target, True AS x, r.k
             WHERE  NOT memo."memo?" AND r.fn = 'Connected' AND r.node = r.target
               UNION ALL
             SELECT 'Apply' AS fn, NULL AS node, NULL AS target, False AS x, r.k
             WHERE  NOT memo."memo?" AND r.fn = 'Connected' AND r.node <> r.target
                    AND NOT EXISTS (SELECT n.id FROM nodes AS n WHERE n.id = r.node)
               UNION ALL
             SELECT 'Connected' AS fn, _.node AS node, r.target, NULL AS x,
                     ROW('1', r.node, r.target, NULL, (_.node, r.target) :: args) :: K || r.k AS k
             FROM   (SELECT n.next FROM nodes AS n WHERE (n.id, n.child) = (r.node, 'l')) AS _(node)
             WHERE  NOT memo."memo?" AND r.fn = 'Connected' AND r.node <> r.target
                    AND ((SELECT COUNT(*) FROM nodes AS n WHERE n.id = r.node) = 2)
               UNION ALL
             SELECT 'Connected' AS fn, (SELECT n.next FROM nodes AS n WHERE n.id = r.node) AS node,
                    r.target AS target, NULL AS x, r.k
             WHERE  NOT memo."memo?" AND r.fn = 'Connected' AND r.node <> r.target
                    AND EXISTS (SELECT n.id FROM nodes AS n WHERE n.id = r.node)
                    AND ((SELECT COUNT(*) FROM nodes AS n WHERE n.id = r.node) <> 2)
               UNION ALL
             SELECT 'Finish' AS fn, NULL AS node, NULL AS target, r.x, NULL AS k
             WHERE  r.fn = 'Apply' AND TOP.clos = '0'
               UNION ALL
             SELECT 'Connected' AS fn, _.node AS node, TOP.target, NULL AS x,
                    ROW('2', NULL, NULL, r.x, (_.node, TOP.target) :: args) :: K || r.k[2:] AS k
             FROM   (SELECT n.next FROM nodes AS n WHERE (n.id, n.child) = (TOP.node, 'r')) AS _(node)
             WHERE  r.fn = 'Apply' AND TOP.clos = '1'
               UNION ALL
             SELECT 'Apply' AS fn, NULL AS node, NULL AS target, TOP.c1 or r.x AS x, r.k[2:] AS k
             WHERE  r.fn = 'Apply' AND TOP.clos = '2'
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

/*
-----------------------------------------------------------------------
-- Check whether node there can be reached from here
*/

DROP FUNCTION IF EXISTS measure(int);

CREATE FUNCTION measure(measurements INT) RETURNS VOID AS
$$
DECLARE
  StartTime timestamptz;
  EndTime timestamptz;
  Delta double precision := 0.0;
  c record;
BEGIN
   FOR i IN 1 .. measurements LOOP
      Delta := 0.0;
      FOR c IN (SELECT here, there
                FROM   (SELECT n.id FROM nodes AS n ORDER BY random()) AS _(here), LATERAL
                       (SELECT n.id FROM nodes AS n ORDER BY random()) AS __(there)
                LIMIT 100
               )
      LOOP
        StartTime := clock_timestamp();
        PERFORM c.here, c.there, connected(c.here,c.there);
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
