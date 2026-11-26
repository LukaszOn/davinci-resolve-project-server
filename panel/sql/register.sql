INSERT INTO resolve_access.libraries(name, database_oid, access_role)
SELECT datname, oid, 'resolve_lib_' || md5(datname)
FROM pg_database WHERE datname = :'library' AND NOT datistemplate AND datallowconn
ON CONFLICT (name) DO UPDATE SET database_oid = EXCLUDED.database_oid;
