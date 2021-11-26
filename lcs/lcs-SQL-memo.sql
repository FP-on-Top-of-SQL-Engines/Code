-- Find the length of the longest common subsequence.
--
-- For example, consider the sequences (ABCD) and (ACBAD).
-- They have 5 length-2 common subsequences: (AB), (AC), (AD), (BD), and (CD);
-- 2 length-3 common subsequences: (ABD) and (ACD); and no longer common subsequences.
-- So (ABD) and (ACD) are their longest common subsequences.
--
-- Example source: https://en.wikipedia.org/wiki/Longest_common_subsequence_problem

DROP TYPE IF EXISTS args CASCADE;
CREATE TYPE args AS (l text, r text);

------------------------------------------------------------------------

DROP TYPE IF EXISTS K CASCADE;
CREATE TYPE K AS (clos char, l text, r text, x int, args args);

-- memoization table
DROP TABLE IF EXISTS memo;
CREATE TABLE memo (
  args  args PRIMARY KEY,
  x     int
);

DROP FUNCTION IF EXISTS lcs(text, text);
CREATE FUNCTION lcs(l text, r text) RETURNS int AS
$$
  WITH RECURSIVE recurse(fn, l, r, x, k) AS MATERIALIZED (
    -- invocation
    SELECT  'lcs' AS fn, lcs.l, lcs.r, NULL :: int AS x,
            array[ROW('0', NULL, NULL, NULL, (lcs.l, lcs.r) :: args) :: K] AS k

      UNION ALL

    SELECT  trampoline.*
    FROM    recurse AS r,
    LATERAL (SELECT (r.k[1]).*) AS TOP(clos, l, r, x, args),
    LATERAL (SELECT COALESCE(m."memo?", false) AS "memo?", m.val
             FROM   (SELECT NULL) AS _ LEFT OUTER JOIN
                    (SELECT true AS "memo?", m.x AS val
                     FROM   memo AS m
                     WHERE  (r.l, r.r) = m.args) AS m
                      ON true) AS memo("memo?", val),
    LATERAL (SELECT 'apply' AS fn, r.l, r.r, memo.val, r.k
             WHERE  memo."memo?" AND r.fn = 'lcs'
               UNION ALL
             SELECT 'apply' AS fn, NULL AS l, NULL AS r, 0 AS x, r.k
             WHERE  NOT memo."memo?" AND r.fn = 'lcs'
                    AND ((r.l = '' AND r.r = '')
                         OR (r.l = '' AND r.r <> '')
                         OR (r.l <> '' AND r.r = ''))
               UNION ALL
             SELECT 'lcs' AS fn, right(r.l,-1) AS l, right(r.r,-1) AS r, NULL AS x,
                    ROW('1', r.l, r.r, NULL, (right(r.l,-1), right(r.r,-1)) :: args) :: K || r.k AS k
             WHERE  NOT memo."memo?" AND r.fn = 'lcs' AND left(r.l,1) = left(r.r,1)
                    AND NOT(r.l = '' OR r.r = '')
               UNION ALL
             SELECT 'lcs' AS fn, right(r.l,-1) AS l, r.r AS r, NULL AS x,
                    ROW('2', r.l, r.r, NULL, (right(r.l,-1), r.r) :: args) :: K || r.k AS k
             WHERE  NOT memo."memo?" AND r.fn = 'lcs' AND left(r.l,1) <> left(r.r,1)
                    AND NOT(r.l = '' OR r.r = '')
               UNION ALL
             SELECT 'finish' AS fn, NULL AS l, NULL AS r, r.x, NULL AS k
             WHERE  r.fn = 'apply' AND TOP.clos = '0'
               UNION ALL
             SELECT 'apply' AS fn, NULL AS l, NULL AS r, 1+r.x AS x, r.k[2:] AS k
             WHERE  r.fn = 'apply' AND TOP.clos = '1'
               UNION ALL
             SELECT 'lcs' AS fn, TOP.l AS l, right(TOP.r,-1) AS r, NULL AS x,
                    ROW('3', NULL, NULL, r.x, (TOP.l, right(TOP.r,-1)) :: args) :: K || r.k[2:] AS k
             WHERE  r.fn = 'apply' AND TOP.clos = '2'
               UNION ALL
             SELECT 'apply' AS fn, NULL AS l, NULL AS r, GREATEST(TOP.x, r.x) AS x, r.k[2:] AS k
             WHERE  r.fn = 'apply' AND TOP.clos = '3'
            ) AS trampoline(fn, l, r, x, k)
  ),
  -- extract results of all (intermediate) recursive function calls
  --   and insert into memoization table
  memoization AS (
    INSERT INTO memo(args, x)
      SELECT (r.k[1]).args, r.x    -- args closure + result x
      FROM   recurse AS r
      WHERE  r.fn = 'apply'              -- non-recursive calls to apply
    ON CONFLICT (args) DO NOTHING
  )
  -- return final result
  SELECT r.x
  FROM   recurse AS r
  WHERE  r.fn = 'finish';
$$
LANGUAGE SQL VOLATILE STRICT;

-----------------------------------------------------------------------
-- Determine the length of the longest common subsequence of seq1 and seq2

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
      (SELECT s1, s2
        FROM (SELECT s1.seq, s2.seq
              FROM   sequences AS s1, sequences AS s2
              ORDER BY random()
              LIMIT 100) AS s1s2(s1, s2))
    LOOP
      PERFORM k.s1, k.s2, lcs(k.s1,k.s2);
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
