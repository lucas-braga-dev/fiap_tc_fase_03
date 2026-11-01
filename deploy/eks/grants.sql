\set ON_ERROR_STOP on
\getenv app_user ROLE_NAME
\getenv app_password ROLE_PASSWORD
SELECT format('CREATE ROLE %I LOGIN', :'app_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')
\gexec
SELECT format('ALTER ROLE %I PASSWORD %L', :'app_user', :'app_password')
\gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', current_database(), :'app_user')
\gexec
SELECT format('GRANT USAGE ON SCHEMA public TO %I', :'app_user')
\gexec
SELECT format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO %I', :'app_user')
\gexec
SELECT format('GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO %I', :'app_user')
\gexec
