-- Floyd-Warshall's algorithm to find the length of the shortest path
-- in a weighted, directed graph
--
-- The naive formulation below performs an exponential number of
-- recursive calls (O(3ⁿ) for a graph of n nodes).  Once the
-- UDF is compiled into a CTE and call sharing is applied, we observe
-- the expected O(n³) complexity of the Floyd-Warshall algorithm.
-- Additionally, over time, memoization leads to the materialization of
-- the graph's node distance matrix, which drastically cuts down
-- evaluation time.

-----------------------------------------------------------------------
-- Recursive SQL UDF in functional style that implements
-- Floyd-Warshall's algorithm to find the length of the
-- shortest path between nodes s and e (returns NULL if there
-- is no such path):
--

DROP FUNCTION IF EXISTS shortestpath(int, int, int);
CREATE FUNCTION shortestpath(nodes int, s int, e int) RETURNS int AS
$$
  SELECT CASE
    WHEN nodes = 0 THEN (SELECT edge.weight
                         FROM   edges AS edge
                         WHERE  (edge.here,edge.there) = (s,e))
    ELSE (SELECT LEAST(shortestpath(nodes - 1, s, e),
                       shortestpath(nodes - 1, s, nodes) + shortestpath(nodes - 1, nodes, e)))
  END;
$$ LANGUAGE SQL;

-----------------------------------------------------------------------
-- Find the length of the shortest path from here to there

SELECT setseed(0.42);

\timing on
SELECT here,
       there,
       shortestpath((SELECT COUNT(*) FROM nodes) :: int, here, there)
FROM (SELECT MAX(node) FROM nodes) AS _(max),
     LATERAL generate_series(1, max) as __(here),
     LATERAL generate_series(1, max) as ___(there)
LIMIT :iterations;
\timing off