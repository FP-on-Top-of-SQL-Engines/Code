-----------------------------------------------------------------------
-- SQL UDF in functional style: expression interpreter

DROP TYPE IF EXISTS args CASCADE;
CREATE TYPE args AS (e expression);

------------------------------------------------------------------------

DROP TYPE IF EXISTS K CASCADE;
CREATE TYPE K AS (clos char, arg2 int, e1 numeric, args expression);

-- memoization table
DROP TABLE IF EXISTS memo;
CREATE TABLE memo (
  args  expression PRIMARY KEY,
  x     numeric
);

DROP FUNCTION IF EXISTS eval(expression);
CREATE FUNCTION eval(e expression) RETURNS numeric AS
$$
  WITH RECURSIVE recurse(fn, e, x, k) AS MATERIALIZED (
    -- invocation
    SELECT  'eval' AS fn, eval.e, NULL :: numeric AS x,
            array[ROW('0', NULL, NULL, eval.e) :: K] AS k

      UNION ALL

    SELECT  trampoline.*
    FROM    recurse AS r,
    LATERAL (SELECT (r.k[1]).*) AS TOP(clos, arg2, e1, args),
    LATERAL (SELECT COALESCE(m."memo?", false) AS "memo?", m.val
             FROM   (SELECT NULL) AS _ LEFT OUTER JOIN
                    (SELECT true AS "memo?", m.x AS val
                     FROM   memo AS m
                     WHERE  r.e = m.args) AS m
                      ON true) AS memo("memo?", val),
    LATERAL (SELECT 'apply' AS fn, r.e, memo.val, r.k
             WHERE  memo."memo?" AND r.fn = 'eval'
               UNION ALL
             SELECT 'apply' AS fn, NULL AS e, (r.e).lit AS x, r.k
             WHERE  NOT memo."memo?" AND r.fn = 'eval' AND (r.e).op = 'ℓ'
               UNION ALL
             SELECT 'eval' AS fn, exp :: expression AS e, NULL AS x,
                    ROW('1', (r.e).arg2, NULL, exp) :: K || r.k AS k
             FROM (SELECT e1.* FROM expression AS e1 WHERE e1.node = (r.e).arg1) AS exp
             WHERE  NOT memo."memo?" AND r.fn = 'eval' AND (r.e).op = '+'
               UNION ALL
             SELECT 'eval' AS fn, exp :: expression AS e, NULL AS x,
                    ROW('2', (r.e).arg2, NULL, exp) :: K || r.k AS k
             FROM (SELECT e1.* FROM expression AS e1 WHERE e1.node = (r.e).arg1) AS exp
             WHERE  NOT memo."memo?" AND r.fn = 'eval' AND (r.e).op = '*'
               UNION ALL
             SELECT 'finish' AS fn, NULL AS e, r.x, NULL AS k
             WHERE  r.fn = 'apply' AND TOP.clos = '0'
               UNION ALL
             SELECT 'eval' AS fn, exp :: expression AS e, NULL AS x,
                    ROW('3', NULL, r.x, exp) :: K || r.k[2:] AS k
             FROM (SELECT e2.* FROM expression AS e2 WHERE e2.node = TOP.arg2) AS exp
             WHERE  r.fn = 'apply' AND TOP.clos = '1'
               UNION ALL
             SELECT 'eval' AS fn, exp :: expression AS e, NULL AS x,
                    ROW('4', NULL, r.x, exp) :: K || r.k[2:] AS k
             FROM (SELECT e2.* FROM expression AS e2 WHERE e2.node = TOP.arg2) AS exp
             WHERE  r.fn = 'apply' AND TOP.clos = '2'
               UNION ALL
             SELECT 'apply' AS fn, NULL AS e, TOP.e1 + r.x AS x, r.k[2:] AS k
             WHERE  r.fn = 'apply' AND TOP.clos = '3'
               UNION ALL
             SELECT 'apply' AS fn, NULL AS e, TOP.e1 * r.x AS x, r.k[2:] AS k
             WHERE  r.fn = 'apply' AND TOP.clos = '4'
            ) AS trampoline(fn, e, x, k)
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
LANGUAGE SQL VOLATILE;

-----------------------------------------------------------------------
-- Perform expression evaluation of root expression

DROP FUNCTION IF EXISTS measure(int);

CREATE FUNCTION measure(measurements INT) RETURNS VOID AS
$$
DECLARE
  StartTime timestamptz;
  EndTime timestamptz;
  Delta double precision;
  c expression;
BEGIN
   FOR i IN 1 .. measurements LOOP
      StartTime := clock_timestamp();
      FOR c IN (SELECT * FROM expression ORDER BY random() LIMIT 100)
      LOOP
        PERFORM c.node AS node, eval(c) AS result;
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
