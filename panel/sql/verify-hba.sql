WITH rules AS (
    SELECT :hba_order AS position, type, database, user_name, address, auth_method, error
    FROM pg_hba_file_rules
), routes AS (
    SELECT 'local' AS transport UNION ALL SELECT 'host'
), verified AS (
    SELECT transport,
      MIN(r.position) FILTER (WHERE r.type = transport AND r.auth_method = 'reject'
        AND 'all' = ANY(r.database) AND '+resolve_panel_members' = ANY(r.user_name)
        AND :'agent_user' = ANY(r.user_name)
        AND (transport = 'local' OR r.address = 'all')) AS reject_at,
      MIN(r.position) FILTER (WHERE r.auth_method = 'scram-sha-256' AND :'control_database' = ANY(r.database)
        AND :'agent_user' = ANY(r.user_name)) AS agent_at,
      MIN(r.position) FILTER (WHERE r.auth_method = 'scram-sha-256' AND :'library' = ANY(r.database)
        AND ('+resolve_lib_' || md5(:'library')) = ANY(r.user_name)) AS library_at,
      MIN(r.position) FILTER (WHERE 'all' = ANY(r.user_name)) AS global_at
    FROM routes CROSS JOIN rules r
    WHERE (transport = 'local' AND r.type = 'local') OR (transport = 'host' AND r.type LIKE 'host%')
    GROUP BY transport
)
SELECT (SELECT count(*) FROM verified) = 2
  AND (SELECT bool_and(COALESCE(agent_at < reject_at AND library_at < reject_at AND
        (global_at IS NULL OR reject_at < global_at), false)) FROM verified)
  AND NOT EXISTS (SELECT FROM rules WHERE error IS NOT NULL)
  AND (pg_stat_file(current_setting('hba_file'))).modification <= pg_conf_load_time();
