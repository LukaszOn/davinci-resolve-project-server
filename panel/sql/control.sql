BEGIN;
SET LOCAL search_path = pg_catalog, pg_temp;
SET LOCAL password_encryption = 'scram-sha-256';
SELECT pg_advisory_xact_lock(912780041);

CREATE SCHEMA IF NOT EXISTS resolve_access;
REVOKE ALL ON SCHEMA resolve_access FROM PUBLIC;

CREATE TABLE IF NOT EXISTS resolve_access.libraries (
    name name PRIMARY KEY,
    database_oid oid NOT NULL,
    access_role name NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS resolve_access.people (
    username name PRIMARY KEY,
    login_oid oid NOT NULL UNIQUE,
    label text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE resolve_access.people
    ADD COLUMN IF NOT EXISTS account_role text NOT NULL DEFAULT 'collaborator' CHECK (account_role IN ('administrator', 'collaborator')),
    ADD COLUMN IF NOT EXISTS panel_hash text,
    ADD COLUMN IF NOT EXISTS auth_version bigint NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS avatar bytea,
    ADD COLUMN IF NOT EXISTS removed_at timestamptz;

SELECT 'CREATE ROLE resolve_panel_members NOLOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'resolve_panel_members') \gexec
SELECT 'CREATE ROLE resolve_panel_agent LOGIN'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'resolve_panel_agent') \gexec
\if :{?agent_password}
ALTER ROLE resolve_panel_agent LOGIN NOSUPERUSER NOCREATEROLE NOCREATEDB NOREPLICATION NOBYPASSRLS
    PASSWORD :'agent_password';
\endif

CREATE OR REPLACE VIEW resolve_access.available_libraries AS
SELECT l.name, l.access_role
FROM resolve_access.libraries l
JOIN pg_database d ON d.oid = l.database_oid AND d.datname = l.name
JOIN pg_roles r ON r.rolname = l.access_role;

CREATE OR REPLACE VIEW resolve_access.directory AS
SELECT p.username, p.label, r.rolcanlogin AS enabled,
       COALESCE(ARRAY(
           SELECT l.name FROM resolve_access.available_libraries l
           WHERE pg_has_role(r.oid, l.access_role, 'MEMBER') ORDER BY l.name
       ), '{}'::name[]) AS libraries,
       p.account_role, p.avatar IS NOT NULL AS has_avatar
FROM resolve_access.people p
JOIN pg_roles r ON r.oid = p.login_oid AND r.rolname = p.username
WHERE p.removed_at IS NULL;

CREATE OR REPLACE FUNCTION resolve_access.apply_change(
    action text, login_name text, display_name text, password_verifier text, library_name text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp
AS $body$
DECLARE
    login_id oid;
    library_role name;
BEGIN
    IF action NOT IN ('create', 'grant', 'revoke', 'enable', 'disable', 'password') OR action IS NULL THEN
        RAISE EXCEPTION 'Unknown operation.' USING ERRCODE = 'P0001';
    END IF;
    IF login_name IS NULL OR login_name !~ '^[a-z][a-z0-9_]{1,30}$'
        OR login_name ~ '^(pg_|resolve_panel_|resolve_lib_)' OR login_name = 'postgres' THEN
        RAISE EXCEPTION 'Choose a different username.' USING ERRCODE = 'P0001';
    END IF;

    IF action IN ('create', 'password') AND (
        password_verifier IS NULL OR length(password_verifier) > 250 OR
        password_verifier !~ '^SCRAM-SHA-256\$[0-9]+:[A-Za-z0-9+/=]+\$[A-Za-z0-9+/=]+:[A-Za-z0-9+/=]+$'
    ) THEN
        RAISE EXCEPTION 'Could not prepare the password.' USING ERRCODE = 'P0001';
    END IF;

    IF action = 'create' THEN
        IF display_name IS NULL OR length(btrim(display_name)) NOT BETWEEN 1 AND 80 THEN
            RAISE EXCEPTION 'Enter a display name.' USING ERRCODE = 'P0001';
        END IF;
        IF EXISTS (SELECT FROM pg_roles WHERE rolname = login_name) THEN
            RAISE EXCEPTION 'This username is already taken.' USING ERRCODE = 'P0001';
        END IF;
        EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L IN ROLE resolve_panel_members', login_name, password_verifier);
        SELECT oid INTO STRICT login_id FROM pg_roles WHERE rolname = login_name;
        INSERT INTO resolve_access.people(username, login_oid, label)
            VALUES (login_name, login_id, btrim(display_name));
        RETURN;
    END IF;

    SELECT p.login_oid INTO login_id
    FROM resolve_access.people p JOIN pg_roles r ON r.oid = p.login_oid AND r.rolname = p.username
    WHERE p.username = login_name AND p.removed_at IS NULL
        AND NOT r.rolsuper AND NOT r.rolcreaterole AND pg_has_role(r.oid, 'resolve_panel_members', 'MEMBER')
    FOR UPDATE OF p;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'This account was not found in the panel.' USING ERRCODE = 'P0001';
    END IF;

    IF action IN ('grant', 'revoke') THEN
        SELECT l.access_role INTO library_role FROM resolve_access.available_libraries l WHERE l.name = library_name;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'This library is currently unavailable.' USING ERRCODE = 'P0001';
        END IF;
        IF action = 'grant' THEN
            EXECUTE format('GRANT %I TO %I', library_role, login_name);
        ELSE
            EXECUTE format('REVOKE %I FROM %I', library_role, login_name);
        END IF;
    ELSIF action = 'password' THEN
        EXECUTE format('ALTER ROLE %I PASSWORD %L', login_name, password_verifier);
        UPDATE resolve_access.people SET panel_hash = NULL, auth_version = auth_version + 1 WHERE login_oid = login_id;
    ELSIF action = 'enable' THEN
        EXECUTE format('ALTER ROLE %I LOGIN', login_name);
    ELSE
        EXECUTE format('ALTER ROLE %I NOLOGIN', login_name);
        UPDATE resolve_access.people SET auth_version = auth_version + 1 WHERE login_oid = login_id;
    END IF;
END;
$body$;

CREATE OR REPLACE FUNCTION resolve_access.panel_administrator(login_name text)
RETURNS TABLE (login_oid oid, auth_version bigint, panel_hash text)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, pg_temp
AS $body$
    SELECT p.login_oid, p.auth_version, p.panel_hash
    FROM resolve_access.people p JOIN pg_roles r ON r.oid = p.login_oid AND r.rolname = p.username
    WHERE p.username = login_name AND p.removed_at IS NULL AND p.account_role = 'administrator'
        AND p.panel_hash IS NOT NULL AND r.rolcanlogin AND NOT r.rolsuper AND NOT r.rolcreaterole
        AND pg_has_role(r.oid, 'resolve_panel_members', 'MEMBER');
$body$;

CREATE OR REPLACE FUNCTION resolve_access.member_avatar(login_name text) RETURNS bytea
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, pg_temp
AS $body$
    SELECT p.avatar FROM resolve_access.people p JOIN resolve_access.directory d USING (username)
    WHERE p.username = login_name;
$body$;

CREATE OR REPLACE FUNCTION resolve_access.change_member(
    action text, login_name text, new_login text, display_name text, member_role text,
    password_verifier text, web_hash text, photo bytea, clear_photo boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp
AS $body$
DECLARE
    person resolve_access.people%ROWTYPE;
    library_role name;
BEGIN
    IF action IS NULL OR action NOT IN ('create', 'edit', 'password', 'delete') THEN
        RAISE EXCEPTION 'Unknown operation.' USING ERRCODE = 'P0001';
    END IF;
    IF action IN ('create', 'edit') AND (
        member_role IS NULL OR member_role NOT IN ('administrator', 'collaborator')
        OR display_name IS NULL OR length(btrim(display_name)) NOT BETWEEN 1 AND 80
        OR new_login IS NULL OR new_login !~ '^[a-z][a-z0-9_]{1,30}$'
        OR new_login ~ '^(pg_|resolve_panel_|resolve_lib_)' OR new_login = 'postgres'
    ) THEN
        RAISE EXCEPTION 'Check the display name, username, and account role.' USING ERRCODE = 'P0001';
    END IF;
    IF action IN ('create', 'password') AND (web_hash IS NULL OR octet_length(web_hash) > 250
        OR web_hash NOT LIKE 'scrypt:%') THEN
        RAISE EXCEPTION 'Could not prepare the password.' USING ERRCODE = 'P0001';
    END IF;
    IF octet_length(photo) > 131072 THEN
        RAISE EXCEPTION 'The photo can be up to 128 KB.' USING ERRCODE = 'P0001';
    END IF;

    IF action = 'create' THEN
        PERFORM resolve_access.apply_change('create', new_login, display_name, password_verifier, NULL);
        UPDATE resolve_access.people SET account_role = member_role, panel_hash = web_hash, avatar = photo
        WHERE username = new_login;
        RETURN;
    END IF;

    SELECT p.* INTO person
    FROM resolve_access.people p JOIN pg_roles r ON r.oid = p.login_oid AND r.rolname = p.username
    WHERE p.username = login_name AND p.removed_at IS NULL AND NOT r.rolsuper AND NOT r.rolcreaterole
        AND pg_has_role(r.oid, 'resolve_panel_members', 'MEMBER')
    FOR UPDATE OF p;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'This account was not found in the panel.' USING ERRCODE = 'P0001';
    END IF;

    IF action = 'password' THEN
        PERFORM resolve_access.apply_change('password', login_name, NULL, password_verifier, NULL);
        UPDATE resolve_access.people SET panel_hash = web_hash WHERE login_oid = person.login_oid;
    ELSIF action = 'edit' THEN
        IF member_role = 'administrator' AND person.panel_hash IS NULL THEN
            RAISE EXCEPTION 'Set this account’s password in the panel before assigning the administrator role.' USING ERRCODE = 'P0001';
        END IF;
        IF new_login <> login_name THEN
            IF EXISTS (SELECT FROM pg_roles WHERE rolname = new_login) THEN
                RAISE EXCEPTION 'This username is already taken.' USING ERRCODE = 'P0001';
            END IF;
            EXECUTE format('ALTER ROLE %I RENAME TO %I', login_name, new_login);
        END IF;
        UPDATE resolve_access.people
        SET username = new_login, label = btrim(display_name), account_role = member_role,
            avatar = CASE WHEN clear_photo THEN NULL ELSE COALESCE(photo, person.avatar) END,
            auth_version = auth_version + CASE WHEN new_login <> login_name OR person.account_role <> member_role THEN 1 ELSE 0 END
        WHERE login_oid = person.login_oid;
    ELSE
        PERFORM resolve_access.apply_change('disable', login_name, NULL, NULL, NULL);
        EXECUTE format('ALTER ROLE %I PASSWORD NULL', login_name);
        FOR library_role IN SELECT l.access_role FROM resolve_access.available_libraries l
            WHERE pg_has_role(person.login_oid, l.access_role, 'MEMBER')
        LOOP
            EXECUTE format('REVOKE %I FROM %I', library_role, login_name);
        END LOOP;
        PERFORM resolve_access.close_revoked_sessions(login_name);
        BEGIN
            EXECUTE format('DROP ROLE %I', login_name);
            DELETE FROM resolve_access.people WHERE login_oid = person.login_oid;
        EXCEPTION WHEN dependent_objects_still_exist THEN
            UPDATE resolve_access.people SET removed_at = now(), panel_hash = NULL, avatar = NULL
            WHERE login_oid = person.login_oid;
        END;
    END IF;
END;
$body$;

CREATE OR REPLACE FUNCTION resolve_access.close_revoked_sessions(login_name text) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp
AS $body$
DECLARE
    connection_pid integer;
    stopped integer := 0;
BEGIN
    FOR connection_pid IN
        SELECT s.pid FROM pg_stat_activity s
        JOIN resolve_access.people p ON p.login_oid = s.usesysid AND p.username = s.usename
        JOIN pg_roles r ON r.oid = p.login_oid AND r.rolname = p.username
        LEFT JOIN resolve_access.available_libraries l ON l.name = s.datname
        WHERE p.username = login_name AND NOT r.rolsuper AND s.backend_type = 'client backend'
            AND s.pid <> pg_backend_pid()
            AND (NOT r.rolcanlogin OR l.access_role IS NULL OR NOT pg_has_role(r.oid, l.access_role, 'MEMBER'))
    LOOP
        IF pg_terminate_backend(connection_pid) THEN
            stopped := stopped + 1;
        END IF;
    END LOOP;
    RETURN stopped;
END;
$body$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA resolve_access FROM PUBLIC;
SELECT format('GRANT CONNECT ON DATABASE %I TO resolve_panel_agent', current_database()) \gexec
GRANT USAGE ON SCHEMA resolve_access TO resolve_panel_agent;
GRANT SELECT ON resolve_access.directory, resolve_access.available_libraries TO resolve_panel_agent;
GRANT EXECUTE ON FUNCTION resolve_access.apply_change(text,text,text,text,text),
    resolve_access.close_revoked_sessions(text), resolve_access.panel_administrator(text), resolve_access.member_avatar(text),
    resolve_access.change_member(text,text,text,text,text,text,text,bytea,boolean) TO resolve_panel_agent;
COMMIT;
