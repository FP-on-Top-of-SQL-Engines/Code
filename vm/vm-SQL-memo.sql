-----------------------------------------------------------------------
-- The second parameter represents the machine's register file (each register hold one integer).

DROP TYPE IF EXISTS args CASCADE;
CREATE TYPE args AS (ins instruction, regs int[]);

------------------------------------------------------------------------

-- memoization table
DROP TABLE IF EXISTS memo;
CREATE TABLE memo (
  args  args PRIMARY KEY,
  x     int
);

DROP FUNCTION IF EXISTS run(instruction, int[]);
CREATE FUNCTION run(ins instruction, regs int[]) RETURNS int AS
$$
  WITH RECURSIVE recurse(fn, ins, regs, x, k) AS MATERIALIZED (
    -- invocation
    SELECT  'run' AS fn, run.ins, run.regs, NULL :: int AS x,
            ROW(run.ins, run.regs) :: args AS k

      UNION ALL

    SELECT  trampoline.*
    FROM    recurse AS r,
    LATERAL (SELECT COALESCE(m."memo?", false) AS "memo?", m.val
             FROM   (SELECT NULL) AS _ LEFT OUTER JOIN
                    (SELECT true AS "memo?", m.x AS val
                     FROM   memo AS m
                     WHERE  (r.ins, r.regs) = m.args) AS m
                      ON true) AS memo("memo?", val),
    LATERAL (SELECT 'finish' AS fn, r.ins AS ins, r.regs AS regs, memo.val, r.k AS k
             WHERE  memo."memo?" AND r.fn = 'run'
              UNION ALL
             SELECT 'run' AS fn, _.ins AS ins, __.regs AS regs, NULL AS x, ROW(_.ins, __.regs) :: args AS k
             FROM (SELECT p FROM program AS p WHERE p.loc = (r.ins :: instruction).loc+1) AS _(ins),
                  (SELECT r.regs[:(r.ins :: instruction).reg1-1]
                          || (r.ins :: instruction).reg2
                          || r.regs[(r.ins :: instruction).reg1+1:]) AS __(regs)
             WHERE  NOT memo."memo?" AND r.fn = 'run' AND (r.ins :: instruction).opc = 'lod'
              UNION ALL
             SELECT 'run' AS fn, _.ins AS ins, __.regs AS regs, NULL AS x, ROW(_.ins, __.regs) :: args AS k
             FROM (SELECT p FROM program AS p WHERE p.loc = (r.ins :: instruction).loc+1) AS _(ins),
                  (SELECT r.regs[:(r.ins :: instruction).reg1-1]
                          || r.regs[(r.ins :: instruction).reg2]
                          || r.regs[(r.ins :: instruction).reg1+1:]) AS __(regs)
             WHERE  NOT memo."memo?" AND r.fn = 'run' AND (r.ins :: instruction).opc = 'mov'
              UNION ALL
             SELECT 'run' AS fn, _.ins AS ins, r.regs AS regs, NULL AS x, ROW(_.ins, r.regs) :: args AS k
             FROM (SELECT p FROM program AS p WHERE p.loc = (r.ins :: instruction).reg3) AS _(ins)
             WHERE  NOT memo."memo?" AND r.fn = 'run'
                    AND (r.ins :: instruction).opc = 'jeq'
                         AND r.regs[(r.ins :: instruction).reg1] = r.regs[(r.ins :: instruction).reg2]
              UNION ALL
             SELECT 'run' AS fn, _.ins AS ins, r.regs AS regs, NULL AS x, ROW(_.ins, r.regs) :: args AS k
             FROM (SELECT p FROM program AS p WHERE p.loc = (r.ins :: instruction).loc + 1) AS _(ins)
             WHERE  NOT memo."memo?" AND r.fn = 'run'
                    AND (r.ins :: instruction).opc = 'jeq'
                         AND r.regs[(r.ins :: instruction).reg1] <> r.regs[(r.ins :: instruction).reg2]
              UNION ALL
             SELECT 'run' AS fn, _.ins AS ins, r.regs AS regs, NULL AS x, ROW(_.ins, r.regs) :: args AS k
             FROM (SELECT p FROM program AS p WHERE p.loc = (r.ins :: instruction).reg1) AS _(ins)
             WHERE  NOT memo."memo?" AND r.fn = 'run' AND (r.ins :: instruction).opc = 'jmp'
              UNION ALL
             SELECT 'run' AS fn, _.ins AS ins, __.regs AS regs, NULL AS x, ROW(_.ins, __.regs) :: args AS k
             FROM (SELECT p FROM program AS p WHERE p.loc = (r.ins :: instruction).loc+1) AS _(ins),
                  (SELECT r.regs[:(r.ins :: instruction).reg1-1] ||
                          r.regs[(r.ins :: instruction).reg2] + r.regs[(r.ins :: instruction).reg3] ||
                          r.regs[(r.ins :: instruction).reg1+1:]) AS __(regs)
             WHERE  NOT memo."memo?" AND r.fn = 'run' AND (r.ins :: instruction).opc = 'add'
              UNION ALL
             SELECT 'run' AS fn, _.ins AS ins, __.regs AS regs, NULL AS x, ROW(_.ins, __.regs) :: args AS k
             FROM (SELECT p FROM program AS p WHERE p.loc = (r.ins :: instruction).loc+1) AS _(ins),
                  (SELECT r.regs[:(r.ins :: instruction).reg1-1] ||
                          r.regs[(r.ins :: instruction).reg2] * r.regs[(r.ins :: instruction).reg3] ||
                          r.regs[(r.ins :: instruction).reg1+1:]) AS __(regs)
             WHERE  NOT memo."memo?" AND r.fn = 'run' AND (r.ins :: instruction).opc = 'mul'
              UNION ALL
             SELECT 'run' AS fn, _.ins AS ins, __.regs AS regs, NULL AS x, ROW(_.ins, __.regs) :: args AS k
             FROM (SELECT p FROM program AS p WHERE p.loc = (r.ins :: instruction).loc+1) AS _(ins),
                  (SELECT r.regs[:(r.ins :: instruction).reg1-1] ||
                          r.regs[(r.ins :: instruction).reg2] / r.regs[(r.ins :: instruction).reg3] ||
                          r.regs[(r.ins :: instruction).reg1+1:]) AS __(regs)
             WHERE  NOT memo."memo?" AND r.fn = 'run' AND (r.ins :: instruction).opc = 'div'
              UNION ALL
             SELECT 'run' AS fn, _.ins AS ins, __.regs AS regs, NULL AS x, ROW(_.ins, __.regs) :: args AS k
             FROM (SELECT p FROM program AS p WHERE p.loc = (r.ins :: instruction).loc+1) AS _(ins),
                  (SELECT r.regs[:(r.ins :: instruction).reg1-1] ||
                          r.regs[(r.ins :: instruction).reg2] % r.regs[(r.ins :: instruction).reg3] ||
                          r.regs[(r.ins :: instruction).reg1+1:]) AS __(regs)
             WHERE  NOT memo."memo?" AND r.fn = 'run' AND (r.ins :: instruction).opc = 'mod'
              UNION ALL
             SELECT 'finish' AS fn, NULL AS ins, NULL AS regs, r.regs[(r.ins :: instruction).reg1] AS x, NULL AS k
             WHERE  NOT memo."memo?" AND r.fn = 'run' AND (r.ins :: instruction).opc = 'hlt'
            ) AS trampoline(fn, ins, run, x, k)
  ),
  -- extract results of all (intermediate) recursive function calls
  --   and insert into memoization table
  memoization AS (
    INSERT INTO memo(args, x)
      SELECT r.k, res.x    -- args closure + result x
      FROM   recurse AS r, recurse AS res
      WHERE  r.fn = 'run' AND res.fn = 'finish'
    ON CONFLICT (args) DO NOTHING
  )
  -- return final result
  SELECT r.x
  FROM   recurse AS r
  WHERE  r.fn = 'finish';
$$
LANGUAGE SQL VOLATILE STRICT;

-----------------------------------------------------------------------
-- Compute the length of the Collatz sequence (also known as
-- the "3N + 1 problem") for the value N held in register R1.

DROP FUNCTION IF EXISTS measure(INT);

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
        (SELECT num
         FROM   generate_series(1, 10000) AS _(num)
         ORDER BY random()
         LIMIT 100)
      LOOP
        PERFORM k.num,
                run((SELECT p FROM program AS p WHERE p.loc = 0), -- program entry instruction
                    ARRAY[k.num,0,0,0,0,0,0]) AS collatz;           -- initial register file
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
