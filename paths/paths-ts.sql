-----------------------------------------------------------------------
-- Translation into a UDF using trampolined style

-- In database representation of a file system
-- Based on: https://stackoverflow.com/questions/18789502/how-to-solve-this-issue-with-cte

-- Beginning at a directory, we begin backtracking towards the root directory
-- concatenating the file path in the process.

DROP FUNCTION IF EXISTS file_pathTS(text, text);

CREATE FUNCTION file_pathTS(dir text, file_path text) RETURNS text AS
$$
WITH RECURSIVE tramp(fn, dir, file_path) AS (
  SELECT 'file_path', dir, file_path
    UNION ALL
  SELECT _.*
  FROM   tramp AS t, LATERAL
          (SELECT 'file_path',
                  (SELECT d2.DIR_NAME
                  FROM DIRS AS d, DIRS AS d2
                  WHERE d.DIR_NAME = t.dir
                  AND d.PARENT_DIR_ID = d2.DIR_ID),
                  '/'||t.dir||t.file_path
          WHERE t.fn = 'file_path' AND
                (SELECT d.PARENT_DIR_ID FROM DIRS AS d WHERE d.DIR_NAME = t.dir) IS NOT NULL
            UNION ALL
          SELECT 'finish', t.dir, '/'||t.dir||t.file_path
          WHERE t.fn = 'file_path' AND
                (SELECT d.PARENT_DIR_ID FROM DIRS AS d WHERE d.DIR_NAME = t.dir) IS NULL
          ) AS _
) SELECT t.file_path FROM tramp AS t WHERE t.fn = 'finish';
$$ LANGUAGE SQL STABLE STRICT;

-----------------------------------------------------------------------
-- Produce the absolute paths of all directories in the hierarchy

SELECT setseed(0.42);

\timing on
SELECT d.DIR_NAME, file_pathTS(d.DIR_NAME, '') AS PATH
FROM DIRS AS d;
\timing off
