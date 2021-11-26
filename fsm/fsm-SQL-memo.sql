-- Demonstrate the use of a recursive SQL UDF to drive a finite state
-- machine (derived from a regular expression) to parse chemical compound
-- formulae.

-- SQL UDF to parse string 'input'. Finite state machine currently is in state 'state'.

DROP TYPE IF EXISTS args CASCADE;
CREATE TYPE args AS (state int, input text);

------------------------------------------------------------------------

-- memoization table
DROP TABLE IF EXISTS memo;
CREATE TABLE memo (
  args  args PRIMARY KEY,
  x     boolean
);

DROP FUNCTION IF EXISTS parse(int, text);
CREATE FUNCTION parse(state int, input text) RETURNS boolean AS
$$
  WITH RECURSIVE recurse(fn, state, input, x, k) AS MATERIALIZED (
    -- invocation
    SELECT  'parse' AS fn, parse.state, parse.input, NULL :: boolean AS x,
            ROW(parse.state, parse.input) :: args AS k

      UNION ALL

    SELECT  trampoline.*
    FROM    recurse AS r,
    LATERAL (SELECT COALESCE(m."memo?", false) AS "memo?", m.val
             FROM   (SELECT NULL) AS _ LEFT OUTER JOIN
                    (SELECT true AS "memo?", m.x AS val
                     FROM   memo AS m
                     WHERE  (r.state, r.input) = m.args) AS m
                      ON true) AS memo("memo?", val),
    LATERAL (SELECT 'finish' AS fn, r.state AS state, r.input AS input, memo.val, r.k AS k
             WHERE  memo."memo?" AND r.fn = 'parse'
               UNION ALL
             SELECT 'finish' AS fn, NULL AS state, NULL AS input,
                    (SELECT DISTINCT edge.final
	                  FROM fsm AS edge
		                WHERE r.state = edge.source) AS x,
                    NULL AS k
             WHERE  NOT memo."memo?" AND r.fn = 'parse' AND length(r.input) = 0 AND
	                  (SELECT DISTINCT edge.final
                    FROM fsm AS edge
	                  WHERE r.state = edge.source) IS NOT NULL
              UNION ALL
             SELECT 'finish' AS fn, NULL AS state, NULL AS input, false AS x, NULL AS k
             WHERE  NOT memo."memo?" AND r.fn = 'parse' AND length(r.input) = 0 AND
	                  (SELECT DISTINCT edge.final
                    FROM fsm AS edge
	                  WHERE r.state = edge.source) IS NULL
              UNION ALL
             SELECT 'parse' AS fn, _.state AS state, __.input AS input, NULL AS x,
                    ROW(_.state, __.input) :: args AS k
             FROM (SELECT edge.target
		    	         FROM fsm AS edge
			             WHERE r.state = edge.source
			             AND strpos(edge.labels, left(r.input, 1)) > 0) AS _(state),
                   right(r.input, -1) AS __(input)
             WHERE  NOT memo."memo?" AND r.fn = 'parse' AND length(r.input) <> 0
            ) AS trampoline(fn, state, input, x, k)
  ),
  -- extract results of all (intermediate) recursive function calls
  --   and insert into memoization table
  memoization AS (
    INSERT INTO memo(args, x)
      SELECT r.k, res.x    -- args closure + result x
      FROM   recurse AS r, recurse AS res
      WHERE  r.fn = 'parse' AND res.fn = 'finish'
    ON CONFLICT (args) DO NOTHING
  )
  -- return final result
  SELECT r.x
  FROM   recurse AS r
  WHERE  r.fn = 'finish';
$$
LANGUAGE SQL VOLATILE;

-----------------------------------------------------------------------
-- Parse chemical compounds and validate their formulae

DROP FUNCTION IF EXISTS measure(int);

CREATE FUNCTION measure(measurements INT) RETURNS VOID AS
$$
DECLARE
  StartTime timestamptz;
  EndTime timestamptz;
  Delta double precision;
  c compounds;
BEGIN
   FOR i IN 1 .. measurements LOOP
      StartTime := clock_timestamp();
      FOR c IN (SELECT * FROM compounds ORDER BY random() LIMIT 100) LOOP
        PERFORM c.*, parse(0, c.formula);
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
