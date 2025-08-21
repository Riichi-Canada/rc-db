BEGIN;

-- region Drop existing
DROP PROCEDURE IF EXISTS log_changes CASCADE;
DROP FUNCTION IF EXISTS trigger_log_generic() CASCADE;

DROP TRIGGER IF EXISTS log_regions ON regions;
DROP TRIGGER IF EXISTS log_event_types ON event_types;
DROP TRIGGER IF EXISTS log_clubs ON clubs;
DROP TRIGGER IF EXISTS log_events ON events;
DROP TRIGGER IF EXISTS log_players ON players;
DROP TRIGGER IF EXISTS log_event_results ON event_results;
DROP TRIGGER IF EXISTS log_event_scores_2025_cycle ON event_scores_2025_cycle_log;
DROP TRIGGER IF EXISTS log_event_scores_2028_cycle ON event_scores_2028_cycle_log;
DROP TRIGGER IF EXISTS log_player_scores_2025_cycle ON player_scores_2025_cycle_log;
DROP TRIGGER IF EXISTS log_player_scores_2028_cycle ON player_scores_2028_cycle_log;
-- endregion Drop existing

-- region Generic logging functions

CREATE OR REPLACE PROCEDURE log_changes(
    operation_type CHAR(1),
    table_name TEXT,
    data JSONB
)
AS $$
BEGIN
    EXECUTE format('INSERT INTO %I_log (operation_type, timestamp, data) VALUES ($1, current_timestamp, $2)',
                table_name)
        USING operation_type, data;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trigger_log_generic()
RETURNS TRIGGER AS $$
DECLARE
    data JSONB;
    operation_type CHAR(1);
BEGIN
    IF tg_op = 'DELETE' THEN
        operation_type = 'D';
        data := to_jsonb(OLD);
    ELSIF tg_op = 'UPDATE' THEN
        operation_type = 'U';
        data := to_jsonb(NEW);
    ELSIF tg_op = 'INSERT' THEN
        operation_type = 'I';
        data := to_jsonb(NEW);
    END IF;

    CALL log_changes(operation_type, tg_table_name, data);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
-- endregion Generic logging functions

-- region Triggers

CREATE TRIGGER log_regions
    AFTER INSERT OR UPDATE OR DELETE ON regions
    FOR EACH ROW
    EXECUTE FUNCTION trigger_log_generic();

CREATE TRIGGER log_event_types
    AFTER INSERT OR UPDATE OR DELETE ON event_types
    FOR EACH ROW
    EXECUTE FUNCTION trigger_log_generic();

CREATE TRIGGER log_clubs
    AFTER INSERT OR UPDATE OR DELETE ON clubs
    FOR EACH ROW
    EXECUTE FUNCTION trigger_log_generic();

CREATE TRIGGER log_events
    AFTER INSERT OR UPDATE OR DELETE ON events
    FOR EACH ROW
    EXECUTE FUNCTION trigger_log_generic();

CREATE TRIGGER log_players
    AFTER INSERT OR UPDATE OR DELETE ON players
    FOR EACH ROW
    EXECUTE FUNCTION trigger_log_generic();

CREATE TRIGGER log_event_results
    AFTER INSERT OR UPDATE OR DELETE ON event_results
    FOR EACH ROW
    EXECUTE FUNCTION trigger_log_generic();

CREATE TRIGGER log_event_scores_2025_cycle
    AFTER INSERT OR UPDATE OR DELETE ON event_scores_2025_cycle
    FOR EACH ROW
    EXECUTE FUNCTION trigger_log_generic();

CREATE TRIGGER log_event_scores_2028_cycle
    AFTER INSERT OR UPDATE OR DELETE ON event_scores_2028_cycle
    FOR EACH ROW
    EXECUTE FUNCTION trigger_log_generic();

CREATE TRIGGER log_player_scores_2025_cycle
    AFTER INSERT OR UPDATE OR DELETE ON player_scores_2025_cycle
    FOR EACH ROW
    EXECUTE FUNCTION trigger_log_generic();

CREATE TRIGGER log_player_scores_2028_cycle
    AFTER INSERT OR UPDATE OR DELETE ON player_scores_2028_cycle
    FOR EACH ROW
    EXECUTE FUNCTION trigger_log_generic();

CREATE TRIGGER log_player_region_changes
    AFTER INSERT OR UPDATE OR DELETE ON player_region_changes
    FOR EACH ROW
    EXECUTE FUNCTION trigger_log_generic();
-- endregion Triggers

COMMIT;