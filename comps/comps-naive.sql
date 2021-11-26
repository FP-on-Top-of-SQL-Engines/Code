-- Connected components in a directed acyclic graph (DAG) with an out-degree of two

DROP FUNCTION IF EXISTS connected(int, int);
CREATE FUNCTION connected(node int, target int) RETURNS boolean AS
$$
  SELECT CASE
    -- Components are connected.
    WHEN node = target THEN TRUE
    -- Reached a leaf without having found the target we are looking for
    WHEN NOT EXISTS (SELECT n.id FROM nodes AS n WHERE n.id = node) THEN FALSE
    -- We found two children and thus, continue to recurse with both child 'l' and 'r' as arguments.
    WHEN (SELECT COUNT(*) FROM nodes AS n WHERE n.id = node) = 2 THEN
      connected((SELECT n.next FROM nodes AS n WHERE (n.id, n.child) = (node, 'l')), target) OR
      connected((SELECT n.next FROM nodes AS n WHERE (n.id, n.child) = (node, 'r')), target)
    ELSE
    -- Only one child was found.
      connected((SELECT n.next FROM nodes AS n WHERE n.id = node), target)
  END;
$$ LANGUAGE SQL STABLE STRICT;

/*
-----------------------------------------------------------------------
-- Check whether node there can be reached from here
*/

SELECT setseed(0.42);
\timing on
SELECT here, there, connected(here,there)
FROM generate_series(1, :iterations) as s(i),
     LATERAL (SELECT n.id FROM nodes AS n WHERE s.i = s.i ORDER BY random() LIMIT 1) as _(here),
     LATERAL (SELECT n.id FROM nodes AS n WHERE s.i = s.i ORDER BY random() LIMIT 1) as __(there);
\timing off