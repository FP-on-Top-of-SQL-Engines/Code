-- In database representation of a file system
-- Based on: https://stackoverflow.com/questions/18789502/how-to-solve-this-issue-with-cte

-- Beginning at a directory, we begin backtracking towards the root directory
-- concatenating the file path in the process.
DROP FUNCTION IF EXISTS file_path(text, text);
CREATE FUNCTION file_path(dir text, file_path text) RETURNS text AS
$$
  SELECT CASE
    WHEN (SELECT d.PARENT_DIR_ID FROM DIRS AS d WHERE d.DIR_NAME = dir) IS NULL THEN '/'||dir||file_path
    ELSE file_path((
      SELECT d2.DIR_NAME
      FROM DIRS AS d, DIRS AS d2
      WHERE d.DIR_NAME = dir
      AND d.PARENT_DIR_ID = d2.DIR_ID),
      '/'||dir||file_path)
  END;
$$ LANGUAGE SQL STABLE STRICT;

-----------------------------------------------------------------------
-- Produce the absolute paths of all directories in the hierarchy

SELECT setseed(0.42);
\timing on
SELECT d.DIR_NAME, file_path(d.DIR_NAME, '') AS PATH
FROM DIRS AS d;
\timing off