-- TEST_REVERT_ADD_COLUMN.sql
--
-- Author:      Felix Kunde <felix-kunde@gmx.de>
--
--              This script is free software under the LGPL Version 3
--              See the GNU Lesser General Public License at
--              http://www.gnu.org/copyleft/lgpl.html
--              for more details.
-------------------------------------------------------------------------------
-- About:
-- Script that checks log tables when an ADD COLUMN event is reverted
-------------------------------------------------------------------------------
--
-- ChangeLog:
--
-- Version | Date       | Description                                    | Author
-- 0.1.0     2018-10-09   initial commit                                   FKun
--

-- get test number
SELECT nextval('pgmemento.test_seq') AS n \gset

\echo
\echo 'TEST ':n': pgMemento revert ADD COLUMN event'

\echo
\echo 'TEST ':n'.1: Revert ADD COLUMN event'
DO
$$
DECLARE
  test_transaction INTEGER;
  event_op_ids INTEGER[];
BEGIN
  -- set session_info to query logged transaction later
  PERFORM set_config('pgmemento.session_info', '{"message":"Reverting add column"}'::text, FALSE);

  -- get transaction_id of last add column event
  PERFORM
    pgmemento.revert_transaction(transaction_id)
  FROM
    pgmemento.table_event_log
  WHERE
    op_id = 2
    AND transaction_id = 5;

  -- query for logged transaction
  SELECT
    id
  INTO
    test_transaction
  FROM
    pgmemento.transaction_log
  WHERE
    session_info @> '{"message":"Reverting add column"}'::jsonb;

  ASSERT test_transaction IS NOT NULL, 'Error: Did not find test entry in transaction_log table!';

  -- save transaction_id for next tests
  PERFORM set_config('pgmemento.revert_add_column_test', test_transaction::text, FALSE);

  -- query for logged table event
  ASSERT (
    SELECT EXISTS (
      SELECT
        id
      FROM
        pgmemento.table_event_log
      WHERE
        transaction_id = test_transaction
        AND op_id = 6
    )
  ), 'Error: Did not find test entry in table_event_log table!';
END;
$$
LANGUAGE plpgsql;


\echo
\echo 'TEST ':n'.2: Check entries in audit_column_log table'
DO
$$
DECLARE
  test_transaction INTEGER;
  colnames TEXT[];
  datatypes TEXT[];
BEGIN
  test_transaction := current_setting('pgmemento.revert_add_column_test')::int;

  -- get logs of dropped columns
  SELECT
    array_agg(c.column_name ORDER BY c.id),
    array_agg(c.data_type ORDER BY c.id)
  INTO
    colnames,
    datatypes
  FROM
    pgmemento.audit_column_log c
  JOIN
    pgmemento.audit_table_log t
    ON t.id = c.audit_table_id
  WHERE
    t.table_name = 'tests'
    AND t.schema_name = 'public'
    AND upper(c.txid_range) = test_transaction;

  ASSERT colnames[1] = 'test_json_column', 'Expected test_json_column, but found ''%'' instead', colnames[1];
  ASSERT colnames[2] = 'test_tsrange_column', 'Expected test_tsrange_column, but found ''%'' instead', colnames[2];
  ASSERT datatypes[1] = 'json', 'Expected text data type, but found ''%'' instead', datatypes[1];
  ASSERT datatypes[2] = 'tsrange', 'Expected tstzrange data type, but found ''%'' instead', datatypes[2];
END;
$$
LANGUAGE plpgsql;