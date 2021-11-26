#!/bin/bash

ITERATIONS=${1:-8000}
ITERATIONS_MEMO=${2:-150}

PSQL_EXEC="psql"

EXPERIMENT="fsm"

FILE_PREP="${EXPERIMENT}-preparation.sql"
FILE_UDF="${EXPERIMENT}-naive.sql"
FILE_TS="${EXPERIMENT}-ts.sql"
FILE_MEMO="${EXPERIMENT}-SQL-memo.sql"

if [ "$ITERATIONS" -lt 1 ]; then
  echo "Iterations must be greater or equal to 1."
  exit 1
fi

if [ "$ITERATIONS_MEMO" -lt 1 ]; then
  echo "Memoization iterations must be greater or equal to 1."
  exit 1
fi


echo "Running $EXPERIMENT with $ITERATIONS"

echo "Setup database for experiment:"

$PSQL_EXEC --quiet -v iterations="$ITERATIONS" -f $FILE_PREP >> /dev/null

echo -e "\n\n\
=============================\n\
| Run recursive UDF version |\n\
=============================\n"

$PSQL_EXEC --quiet -v iterations="$ITERATIONS" -f $FILE_UDF

echo -e "\n\n\
=============================\n\
| Run translation           |\n\
=============================\n"

$PSQL_EXEC --quiet -v iterations="$ITERATIONS" -f $FILE_TS

echo -e "\n\n\
=============================\n\
| Run memoization version   |\n\
=============================\n"

$PSQL_EXEC --quiet -v measurements="$ITERATIONS_MEMO" -f $FILE_MEMO
