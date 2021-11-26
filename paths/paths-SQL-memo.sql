-----------------------------------------------------------------------
-- Translation into a UDF using trampolined style

-- In database representation of a file system
-- Based on: https://stackoverflow.com/questions/18789502/how-to-solve-this-issue-with-cte

-- Beginning at a directory, we begin backtracking towards the root directory
-- concatenating the file path in the process.

DROP TYPE IF EXISTS args CASCADE;
CREATE TYPE args AS (dir text, file_path text);

------------------------------------------------------------------------

-- memoization table
DROP TABLE IF EXISTS memo;
CREATE TABLE memo (
  args  args PRIMARY KEY,
  x     text
);

DROP FUNCTION IF EXISTS file_path(text, text);
CREATE FUNCTION file_path(dir text, file_path text) RETURNS text AS
$$
  WITH RECURSIVE recurse(fn, dir, file_path, x, k) AS MATERIALIZED (
    -- invocation
    SELECT  'file_path' AS fn, file_path.dir, file_path.file_path, NULL :: text AS x,
            ROW(file_path.dir, file_path.file_path) :: args AS k

      UNION ALL

    SELECT  trampoline.*
    FROM    recurse AS r,
    LATERAL (SELECT COALESCE(m."memo?", false) AS "memo?", m.val
             FROM   (SELECT NULL) AS _ LEFT OUTER JOIN
                    (SELECT true AS "memo?", m.x AS val
                     FROM   memo AS m
                     WHERE  (r.dir, r.file_path) = m.args) AS m
                      ON true) AS memo("memo?", val),
    LATERAL (SELECT 'finish' AS fn, r.dir AS dir, r.file_path AS file_path, memo.val, r.k AS k
             WHERE  memo."memo?" AND r.fn = 'file_path'
               UNION ALL
             SELECT 'file_path' AS fn, _.dir AS dir, __.file_path AS file_path, NULL AS x,
                    ROW(_.dir, __.file_path) :: args AS k
             FROM (SELECT d2.DIR_NAME
                   FROM DIRS AS d, DIRS AS d2
                   WHERE d.DIR_NAME = r.dir
                   AND d.PARENT_DIR_ID = d2.DIR_ID) AS _(dir),
                   (SELECT '/'||r.dir||r.file_path) AS __(file_path)
             WHERE  NOT memo."memo?" AND r.fn = 'file_path' AND
                    (SELECT d.PARENT_DIR_ID FROM DIRS AS d WHERE d.DIR_NAME = r.dir) IS NOT NULL
              UNION ALL
             SELECT 'finish' AS fn, NULL AS dir, NULL AS file_path, '/'||r.dir||r.file_path AS x, NULL AS k
             WHERE  NOT memo."memo?" AND r.fn = 'file_path' AND
                    (SELECT d.PARENT_DIR_ID FROM DIRS AS d WHERE d.DIR_NAME = r.dir) IS NULL
            ) AS trampoline(fn, dir, file_path, x, k)
  ),
  -- extract results of all (intermediate) recursive function calls
  --   and insert into memoization table
  memoization AS (
    INSERT INTO memo(args, x)
      SELECT r.k, res.x
      FROM   recurse AS r, recurse AS res
      WHERE  r.fn = 'file_path' AND res.fn = 'finish'
    ON CONFLICT (args) DO NOTHING
  )
  -- return final result
  SELECT r.x
  FROM   recurse AS r
  WHERE  r.fn = 'finish';
$$
LANGUAGE SQL VOLATILE STRICT;

-----------------------------------------------------------------------
-- Produce the absolute paths of all directories in the hierarchy

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
        (SELECT DIR_NAME
         FROM   DIRS
         ORDER BY random()
         LIMIT 100)
      LOOP
        PERFORM k.DIR_NAME, file_path(k.DIR_NAME, '') AS PATH;
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
