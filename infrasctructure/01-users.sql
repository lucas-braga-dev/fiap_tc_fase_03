\set ON_ERROR_STOP on

-- Executar com psql, conectado como master.
-- Pré-requisito: executar 00-init.sql antes.
-- As senhas serão solicitadas interativamente.

CREATE USER auth_user;
CREATE USER flags_user;
CREATE USER targeting_user;

\password auth_user
\password flags_user
\password targeting_user

GRANT CONNECT ON DATABASE auth_db TO auth_user;
GRANT CONNECT ON DATABASE flags_db TO flags_user;
GRANT CONNECT ON DATABASE targeting_db TO targeting_user;

\connect auth_db
GRANT USAGE ON SCHEMA public TO auth_user;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON TABLE public.api_keys TO auth_user;
GRANT USAGE ON SEQUENCE public.api_keys_id_seq TO auth_user;

\connect flags_db
GRANT USAGE ON SCHEMA public TO flags_user;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON TABLE public.flags TO flags_user;
GRANT USAGE ON SEQUENCE public.flags_id_seq TO flags_user;

\connect targeting_db
GRANT USAGE ON SCHEMA public TO targeting_user;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON TABLE public.targeting_rules TO targeting_user;
GRANT USAGE ON SEQUENCE public.targeting_rules_id_seq TO targeting_user;