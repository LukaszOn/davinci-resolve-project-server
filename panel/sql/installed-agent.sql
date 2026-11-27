SELECT to_regclass('resolve_access.panel_service_account') IS NOT NULL AS registered \gset
\if :registered
SELECT COALESCE((SELECT username FROM resolve_access.panel_service_account), '') AS installed_user \gset
\else
-- Old installations granted this function directly to the service account.
-- Desktop-only installations could leave the role without a password.
SELECT COALESCE((SELECT r.rolname
FROM pg_authid r
JOIN pg_proc p ON p.oid = to_regprocedure('resolve_access.panel_administrator(text)')
CROSS JOIN LATERAL aclexplode(p.proacl) a
WHERE r.oid <> p.proowner AND r.rolpassword IS NOT NULL
  AND a.grantee = r.oid AND a.privilege_type = 'EXECUTE'), '') AS installed_user \gset
\endif
SELECT :'installed_user' <> '' AND NOT EXISTS (
    SELECT FROM pg_roles r
    JOIN pg_proc p ON p.oid = to_regprocedure('resolve_access.panel_administrator(text)')
    CROSS JOIN LATERAL aclexplode(p.proacl) a
    WHERE r.rolname = :'installed_user' AND a.grantee = r.oid AND a.privilege_type = 'EXECUTE'
      AND r.rolcanlogin AND NOT (r.rolsuper OR r.rolcreatedb OR r.rolcreaterole OR r.rolreplication OR r.rolbypassrls)
) AS invalid_identity \gset
\if :invalid_identity
DO $$ BEGIN RAISE EXCEPTION 'The registered panel login is missing or no longer has its installed identity and privileges.'; END $$;
\endif
SELECT :'installed_user' WHERE :'installed_user' <> '';
