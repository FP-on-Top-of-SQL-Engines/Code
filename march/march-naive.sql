-- The marching squares algorithm.
--
-- Recursive SQL UDF in functional style that wanders the 2D map
-- to detect and track the border of a 2D shape. Returns an array
-- describing a closed path around the shape.
--

DROP FUNCTION IF EXISTS march(int[], int[], bool);
CREATE FUNCTION march(current int[], goal int[], "track?" bool) RETURNS int[][] AS
$$
  SELECT CASE
    WHEN "track?" AND current = goal THEN array[] :: int[][]
    ELSE CASE WHEN "track?"
              THEN array[current]
              ELSE array[] :: int[][]
         END
         ||
         (SELECT march(array[current[1] + d.dir[0], current[2] + d.dir[1]] :: int[],
                       CASE WHEN d."track?"
                            THEN goal
                            ELSE array[current[1] + d.dir[0], current[2] + d.dir[1]] :: int[]
                       END,
                       d."track?")
          FROM   squares AS s, directions AS d
          WHERE  current = s.xy
          AND    (s.ll,s.lr,s.ul,s.ur) = (d.ll,d.lr,d.ul,d.ur)
         )
  END;
$$
LANGUAGE SQL STRICT;

-- Trace the shape's border in the 2D map, starting from (x,y)
--

SELECT setseed(0.42);
\timing on
SELECT point(x, y) AS start, march(array[x, y], array[x, y], false) AS border
FROM (SELECT s.i FROM generate_series(0, 57) AS s(i) ORDER BY random()) AS _(x),
     (SELECT s.i FROM generate_series(0, 67) AS s(i) ORDER BY random()) AS __(y)
LIMIT :iterations;
\timing off