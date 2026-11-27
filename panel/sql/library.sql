BEGIN;
SET LOCAL search_path = pg_catalog, pg_temp;
SELECT pg_advisory_xact_lock(912780041);

SELECT 'resolve_lib_' || md5(current_database()) AS editor_role \gset
SELECT format('CREATE ROLE %I NOLOGIN', :'editor_role')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'editor_role') \gexec

CREATE SCHEMA IF NOT EXISTS resolve_library_access;
REVOKE ALL ON SCHEMA resolve_library_access FROM PUBLIC;

-- A restored library may retain helper functions from another installation.
CREATE TEMP VIEW collaboration_schemas AS
SELECT n.oid, n.nspname, n.nspowner FROM pg_namespace n
WHERE n.nspname !~ '^(pg_|information_schema$|resolve_library_access$)'
  AND NOT EXISTS (
      SELECT FROM pg_proc p JOIN pg_roles owner ON owner.oid = p.proowner
      WHERE p.pronamespace = n.oid AND p.proname = 'share_new_objects' AND p.pronargs = 0
        AND p.prorettype = 'event_trigger'::regtype AND p.prosecdef AND p.proowner = n.nspowner AND owner.rolsuper
  );
SELECT format('REVOKE ALL ON SCHEMA %I FROM %I', nspname, :'editor_role')
FROM pg_namespace n WHERE n.nspname !~ '^(pg_|information_schema$)'
  AND NOT EXISTS (SELECT FROM pg_temp.collaboration_schemas allowed WHERE allowed.oid = n.oid) \gexec

SELECT format('GRANT CONNECT, CREATE, TEMPORARY ON DATABASE %I TO %I', current_database(), :'editor_role') \gexec

SELECT format('GRANT USAGE, CREATE ON SCHEMA %I TO %I', nspname, :'editor_role')
FROM pg_temp.collaboration_schemas \gexec

SELECT format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %I TO %I', nspname, :'editor_role')
FROM pg_temp.collaboration_schemas \gexec

SELECT format('GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA %I TO %I', nspname, :'editor_role')
FROM pg_temp.collaboration_schemas \gexec

SELECT format('GRANT SELECT, UPDATE ON LARGE OBJECT %s TO %I', oid, :'editor_role')
FROM pg_largeobject_metadata \gexec

-- Future objects created by the library owner or an existing schema/table owner.
WITH owners AS (
    SELECT datdba AS role_id FROM pg_database WHERE datname = current_database()
    UNION SELECT nspowner FROM pg_temp.collaboration_schemas
    UNION SELECT relowner FROM pg_class JOIN pg_temp.collaboration_schemas n ON n.oid = relnamespace
    UNION SELECT oid FROM pg_roles WHERE rolname = current_user
)
SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I GRANT %s ON %s TO %I', rolname, rights, kind, :'editor_role')
FROM owners JOIN pg_roles ON oid = role_id
CROSS JOIN (VALUES ('SELECT, INSERT, UPDATE, DELETE', 'TABLES'),
                   ('USAGE, SELECT, UPDATE', 'SEQUENCES'), ('USAGE, CREATE', 'SCHEMAS')) AS access(rights, kind)
WHERE rolname <> :'editor_role' AND rolname <> 'pg_database_owner' \gexec
DROP VIEW pg_temp.collaboration_schemas;

-- Share new collaboration objects without replacing each member's SQL identity.
CREATE OR REPLACE FUNCTION resolve_library_access.share_new_objects() RETURNS event_trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp
AS $body$
DECLARE
    editor_role name := 'resolve_lib_' || md5(current_database());
    helper_schemas oid[];
    created_schema name;
    object_record record;
BEGIN
    IF NOT pg_has_role(session_user, 'resolve_panel_members', 'MEMBER')
        OR NOT pg_has_role(session_user, editor_role, 'MEMBER') THEN
        RETURN;
    END IF;

    SELECT array(SELECT p.pronamespace FROM pg_proc p
                 JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspowner = p.proowner
                 JOIN pg_roles owner ON owner.oid = p.proowner AND owner.rolsuper
                 WHERE p.proname = 'share_new_objects' AND p.pronargs = 0
                   AND p.prorettype = 'event_trigger'::regtype AND p.prosecdef)
    INTO helper_schemas;
    FOR created_schema IN
        SELECT DISTINCT n.nspname FROM pg_event_trigger_ddl_commands() d
        JOIN pg_namespace n ON n.oid = d.objid AND d.classid = 'pg_namespace'::regclass
        WHERE NOT d.in_extension AND n.nspname !~ '^(pg_|information_schema$|resolve_library_access$)'
          AND n.oid <> ALL(helper_schemas)
    LOOP
        EXECUTE format('GRANT USAGE, CREATE ON SCHEMA %I TO %I', created_schema, editor_role);
    END LOOP;

    FOR object_record IN
        SELECT DISTINCT n.nspname, c.relname, c.relkind FROM pg_event_trigger_ddl_commands() d
        JOIN pg_class c ON c.oid = d.objid AND d.classid = 'pg_class'::regclass
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE NOT d.in_extension AND n.nspname !~ '^(pg_|information_schema$|resolve_library_access$)'
          AND n.oid <> ALL(helper_schemas)
    LOOP
        IF object_record.relkind = 'S' THEN
            EXECUTE format('GRANT USAGE, SELECT, UPDATE ON SEQUENCE %I.%I TO %I', object_record.nspname, object_record.relname, editor_role);
        ELSIF object_record.relkind IN ('r', 'p', 'v', 'm', 'f') THEN
            EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE %I.%I TO %I', object_record.nspname, object_record.relname, editor_role);
        END IF;
    END LOOP;
END;
$body$;
REVOKE ALL ON FUNCTION resolve_library_access.share_new_objects() FROM PUBLIC;
DROP EVENT TRIGGER IF EXISTS resolve_share_new_objects;
CREATE EVENT TRIGGER resolve_share_new_objects ON ddl_command_end
WHEN TAG IN ('CREATE SCHEMA', 'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO',
             'CREATE SEQUENCE', 'CREATE VIEW', 'CREATE MATERIALIZED VIEW', 'CREATE FOREIGN TABLE')
EXECUTE FUNCTION resolve_library_access.share_new_objects();
COMMIT;
