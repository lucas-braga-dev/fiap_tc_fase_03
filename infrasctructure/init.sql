\set ON_ERROR_STOP on

SELECT format('CREATE DATABASE %I', name)
FROM (VALUES ('auth_db'), ('flags_db'), ('targeting_db')) AS databases(name)
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = name)
\gexec

\connect -reuse-previous=on auth_db
\ir ../apps-togglemaster/src/auth-service/db/init.sql

\connect -reuse-previous=on flags_db
\ir ../apps-togglemaster/src/flag-service/db/init.sql

\connect -reuse-previous=on targeting_db
\ir ../apps-togglemaster/src/targeting-service/db/init.sql