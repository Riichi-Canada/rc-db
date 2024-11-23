BEGIN;

--region Drop existing data
DROP TRIGGER IF EXISTS before_insert_event ON events;
DROP FUNCTION IF EXISTS generate_event_id;
DROP TABLE IF EXISTS event_id_sequences CASCADE;
DROP TRIGGER IF EXISTS after_event_result_insert ON event_results;
DROP FUNCTION IF EXISTS insert_event_score;
--endregion Drop existing data

-- region Event IDs
CREATE OR REPLACE FUNCTION generate_event_id() RETURNS trigger as $$
DECLARE
    year_part TEXT;
    type_part TEXT;
    number_part TEXT;
BEGIN
    year_part := TO_CHAR(NEW.event_start_date, 'YYYY');
    type_part := LPAD(NEW.event_type::TEXT, 2, '0');

    UPDATE event_id_sequences
    SET current_number = current_number + 1
    WHERE year = EXTRACT(YEAR FROM NEW.event_start_date)::INT AND event_type = NEW.event_type;

    IF NOT FOUND THEN
        INSERT INTO event_id_sequences (year, event_type, current_number)
        VALUES (EXTRACT(YEAR FROM NEW.event_start_date)::INT, NEW.event_type, 1);
    END IF;

    SELECT LPAD(current_number::TEXT, 4, '0') INTO number_part
    FROM event_id_sequences
    WHERE year = EXTRACT(YEAR FROM NEW.event_start_date)::INT AND event_type = NEW.event_type;

    NEW.event_id := year_part || '-' || type_part || number_part;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER before_insert_event
    BEFORE INSERT ON events
    FOR EACH ROW
    EXECUTE FUNCTION generate_event_id();
-- endregion Event IDs

-- region Event scores
CREATE OR REPLACE FUNCTION insert_event_score() RETURNS TRIGGER AS $$
DECLARE
    num_of_players INT;
    placement INT;
    main_points NUMERIC(6, 2);
    fsb NUMERIC(6, 2);
    q1s NUMERIC(6, 2);
    q2s NUMERIC(6, 2);
    qsize NUMERIC(6, 2);
    tank_points NUMERIC(5, 2);
BEGIN
    SELECT number_of_players INTO num_of_players FROM events WHERE id = NEW.event_id;
    placement := NEW.placement;

    main_points := ROUND(1000 * (num_of_players - placement) / (num_of_players - 1), 2);

    fsb := 200 + 2.5 * (num_of_players - 16);
    q1s := fsb * 0.5 / (FLOOR(0.25 * num_of_players) - 1);
    q2s := (fsb - 100) * 0.5 / (FLOOR(0.5 * num_of_players - 1) - (FLOOR(0.25 * num_of_players - 1)));
    qsize := FLOOR(num_of_players / 4);
    tank_points := CASE
                WHEN placement > (num_of_players / 2) THEN 0
                ELSE LEAST(
                    200,
                    fsb - (LEAST(placement, qsize) - 1) * q1s
                    - CASE
                        WHEN placement > qsize THEN (placement - qsize) * q2s
                        ELSE 0
                      END
                )
             END;
    tank_points := ROUND(tank_points, 2);

    INSERT INTO event_scores_2025_cycle (result_id, main_score, tank_score)
    VALUES (NEW.id, main_points, tank_points);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- endregion Event scores

-- region Player scores

CREATE OR REPLACE FUNCTION event_is_valid_2025_cycle(end_date DATE, num_of_players INT)
RETURNS BOOLEAN AS $$
DECLARE
    period_start_date DATE;
    period_end_date DATE;
BEGIN
    period_start_date := '2022-01-01'::DATE;
    period_end_date := '2024-12-31'::DATE;

    IF (end_date >= period_start_date AND end_date <= period_end_date AND num_of_players >= 24) THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION event_is_out_of_region(event_region INT, player_region INT)
RETURNS BOOLEAN AS $$
BEGIN
    IF event_region <> player_region
        AND NOT (  -- Québec and Ontario are considered to be in the same region for this purpose
            (event_region = 1 AND player_region = 2)
            OR (event_region = 2 AND player_region = 1)
        )
    THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION compute_tank_points_2025_cycle(player_id INT, event_id INT, new_tank_id INT)
RETURNS VOID AS $$
DECLARE
    current_tank_ids INT[];
    current_tank_scores NUMERIC(5, 2)[];
    new_tank_score NUMERIC(5, 2);
    i INT;
BEGIN
    -- Get current tank IDs
    SELECT ps.tank_1, ps.tank_2, ps.tank_3, ps.tank_4, ps.tank_5
        INTO current_tank_ids
        FROM player_scores_2025_cycles ps
        WHERE ps.player_id = player_id;

    -- Remove NULL values
    current_tank_ids := array_remove(current_tank_ids, NULL);

    -- Get the current tank scores from the corresponding result IDs. If there are no results at all, skip this step
    IF current_tank_ids[1] IS NOT NULL THEN
        FOR i in 1..array_length(current_tank_ids, 1) LOOP
            EXECUTE format(
                'SELECT es.tank_score INTO current_tank_scores[%s] FROM event_scores_2025_cycle es WHERE es.result_id = $1',
                i
            ) USING current_tank_ids[i];
        END LOOP;
    END IF;

    -- Get the new tank score
    SELECT es.tank_score
        INTO new_tank_score
        FROM event_scores_2025_cycle es
        WHERE result_id = new_tank_id;

    IF current_tank_ids[1] IS NULL THEN
        -- This is the first tank score.
        -- Insert tank score's id in tank_score_1 in player_scores
        INSERT INTO player_scores_2025_cycle (tank_1) VALUES (new_tank_id);
    ELSIF array_length(current_tank_ids, 1) < 5 THEN
        -- This is not the first tank score, but there are fewer than 5 not counting this one.
        -- Check the current scores + new one, order them. Keep the link between score and ID, somehow.
        -- Insert the score IDs into player_scores in their proper position.
        -- Know when to stop, because there could be between 2 and 4 values here.
        -- Or, maybe filling the rest of the data to insert with NULL values works just fine...
    ELSE
        -- There are already five tank results.
        -- Check if the new one beats at least one of them.
        -- If it doesn't, skip ahead.
        -- If it does, check the current scores + new one, order them. Keep the link between score and ID, somehow.
        -- Then remove the lowest value from the list.
        -- Once value has been removed, we are back to 5 values.
        -- Thus, we can insert them into the player_scores table in their proper order.
    END IF;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION compute_new_player_score_2025_cycle(
    is_out_of_region BOOLEAN DEFAULT FALSE,
    is_online BOOLEAN DEFAULT FALSE,
    player_id INT,
    event_id INT,
    result_id INT
)
RETURNS VOID AS $$
DECLARE
    current_oor INT;
    current_live_1 INT;
    current_live_2 INT;
    current_any_1 INT;
    current_any_2 INT;
BEGIN
    SELECT ps.out_of_region_live, ps.other_live_1, ps.other_live_2, ps.any_event_1, ps.any_event_2,
        INTO
            current_oor, current_live_1, current_live_2, current_any_1, current_any_2,
        FROM player_scores_2025_cycles ps
        WHERE ps.player_id = player_id;

    IF is_out_of_region THEN
        RAISE NOTICE 'oor';


    ELSIF NOT is_out_of_region AND NOT is_online THEN
        RAISE NOTICE 'live local';


    ELSIF is_online THEN
        RAISE NOTICE 'online';


    END IF;

    compute_tank_points_2025_cycle(player_id, event_id, result_id);

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_player_score_on_insert()
RETURNS TRIGGER AS $$
DECLARE
    player_region INT;
    event_region INT;
    event_player_count INT;
    event_is_online BOOLEAN;
    event_end_date DATE;
    event_is_valid BOOLEAN;
    event_is_out_of_region BOOLEAN;
BEGIN
    SELECT player_region
        INTO player_region
        FROM players
        WHERE id = NEW.player_id;

    SELECT event_region, event_end_date, is_online, number_of_players
        INTO event_region, event_end_date, event_is_online, event_player_count
        FROM events
        WHERE id = NEW.event_id;

    event_is_valid := event_is_valid_2025_cycle(event_end_date, event_player_count);
    event_is_out_of_region := event_is_out_of_region(player_region, event_region);

    IF event_is_valid THEN
        compute_new_player_score_2025_cycle(
            event_is_out_of_region,
            event_is_online,
            NEW.player_id,
            NEW.event_id,
            NEW.id
        );
    END IF;
END;
$$ LANGUAGE plpgsql;
-- endregion Player scores

CREATE OR REPLACE FUNCTION compute_event_scores()
RETURNS TRIGGER AS $$
    BEGIN
        PERFORM insert_event_score();
        PERFORM update_player_score_on_insert();
    END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER after_event_result_insert
    AFTER INSERT ON event_results
    FOR EACH ROW
    WHEN (NEW.player_id IS NOT NULL)
    EXECUTE FUNCTION compute_event_scores();

COMMIT;