-- A released access module has these objects under the same administrator.
-- The scalar subquery rejects multiple registries instead of choosing one.
SELECT COALESCE((
    SELECT left(n.nspname, -length('_access'))
    FROM pg_catalog.pg_namespace n
    JOIN pg_catalog.pg_roles owner ON owner.oid = n.nspowner AND owner.rolsuper
    JOIN pg_catalog.pg_proc admin_fn ON admin_fn.pronamespace = n.oid AND admin_fn.proowner = owner.oid
      AND admin_fn.proname = 'panel_administrator' AND admin_fn.prosecdef AND admin_fn.pronargs = 1
      AND admin_fn.proargtypes[0] = 'pg_catalog.text'::pg_catalog.regtype
    JOIN pg_catalog.pg_proc modify_fn ON modify_fn.pronamespace = n.oid AND modify_fn.proowner = owner.oid
      AND modify_fn.proname = 'apply_change' AND modify_fn.prosecdef AND modify_fn.pronargs = 5
      AND 'pg_catalog.text'::pg_catalog.regtype = ALL(modify_fn.proargtypes)
    WHERE n.nspname ~ '^[a-z][a-z0-9_]{0,25}_access$'
      AND (SELECT count(*) FROM pg_catalog.pg_class c
           WHERE c.relnamespace = n.oid AND c.relowner = owner.oid
             AND ((c.relkind = 'r' AND c.relname IN ('people', 'libraries'))
               OR (c.relkind = 'v' AND c.relname IN ('directory', 'available_libraries')))) = 4
      AND NOT EXISTS (
          SELECT FROM pg_catalog.aclexplode(n.nspacl) a
          WHERE a.privilege_type = 'CREATE' AND a.grantee <> owner.oid
      )
), CASE WHEN pg_catalog.to_regnamespace('resolve_access') IS NULL THEN 'resolve' END) AS layout;
