DROP FUNCTION IF EXISTS dtw(int, int);
CREATE FUNCTION dtw(i int, j int) RETURNS double precision AS
$$
  SELECT 0
  WHERE i = 0 AND j = 0
    UNION ALL
  SELECT 'Infinity' :: double precision
  WHERE (i <> 0 AND j = 0) OR (i = 0 AND j <> 0)
    UNION ALL
  SELECT ABS(X.x-Y.y) + LEAST(dtw(i-1, j-1), dtw(i-1, j), dtw(i, j-1))
  FROM X, Y
  WHERE i <> 0 AND j <> 0 AND (X.t, Y.t) = (i, j)
$$ LANGUAGE SQL STABLE STRICT;

SELECT setseed(0.42);
\timing on
SELECT dtw(x, x)
FROM generate_series(1, (SELECT COUNT(*) :: int FROM X)) AS _(x)
LIMIT :iterations;
\timing off
