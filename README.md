# Functional Programming on Top of SQL Engines

This repository contains the 10 recursive UDFs discussed in
Section 4 of the accompanying paper "_Functional Programming
on Top of SQL Engines_".  Each UDF is present in its original
recursive form, the compiled SQL form, as well as the compiled
SQL form with memoization.

The UDFs have been developed on PostgreSQL 13 (but any
recent version of PostgreSQL should run the functions just fine).
We have added SQL DDL and DML statements that set up tables
with test data so that all UDFs should be ready to run
instantly.

Each UDF `<f>` is hosted in a subdirectory of the same name
(the names `<f>` correspond with those in Table 1 of the paper).
Subdirectory `<f>/` contains:

1. A database setup script `<f>-preparation.sql` with a data generator (if that is required).

1. The original, non-compiled PL/SQL UDF `<f>-naive.sql`.

1. The UDF's compiled SQL form `<f>-ts.sql`.

1. The UDF's compiled SQL form with memoization `<f>-SQL-memo.sql`

1. `run-experiment.sh`, which runs the setup, the original recursive UDF, the compiled SQL form,
   as well as the compiled SQL form with memoization.
   You may run this script or invoke the scripts mentioned above individually.

The UDF scenarios are self-contained and generate their own test
data using the `<f>-preparation.sql` script.
