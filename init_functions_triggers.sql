BEGIN;

--region Drop existing data
DROP TRIGGER IF EXISTS before_insert_event ON events;
DROP FUNCTION IF EXISTS generate_event_id;
DROP TRIGGER IF EXISTS after_event_result_insert ON event_results;
DROP FUNCTION IF EXISTS event_is_valid_2025_cycle;
DROP FUNCTION IF EXISTS event_is_out_of_region;
DROP FUNCTION IF EXISTS insert_event_score;
DROP FUNCTION IF EXISTS compute_tank_points_2025_cycle;
DROP FUNCTION IF EXISTS compute_new_player_score_2025_cycle;
DROP FUNCTION IF EXISTS update_player_score_on_insert;
DROP FUNCTION IF EXISTS update_player_score_total;
DROP FUNCTION IF EXISTS compute_event_scores;
DROP TYPE IF EXISTS result_score_pair;
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

CREATE OR REPLACE FUNCTION insert_event_score(new_result_id INT, new_event_id INT, placement INT)
RETURNS VOID AS $$
DECLARE
    num_of_players INT;
    main_points NUMERIC(6, 2);
    fsb NUMERIC(6, 2);
    q1s NUMERIC(6, 2);
    q2s NUMERIC(6, 2);
    qsize NUMERIC(6, 2);
    tank_points NUMERIC(5, 2);
BEGIN
    SELECT number_of_players INTO num_of_players FROM events WHERE id = new_event_id;

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
    VALUES (new_result_id, main_points, tank_points);
END;
$$ LANGUAGE plpgsql;
-- endregion Event scores

-- region Player scores
CREATE TYPE result_score_pair AS (
    result_id INT,
    score NUMERIC(6, 2)
);

CREATE OR REPLACE FUNCTION event_is_valid_2025_cycle(end_date DATE, num_of_players INT, new_event_id INT)
RETURNS BOOLEAN AS $$
DECLARE
    period_start_date DATE;
    period_end_date DATE;
    eventtype INT;
BEGIN
    period_start_date := '2022-01-01'::DATE;
    period_end_date := '2024-12-31'::DATE;

    eventtype := (SELECT event_type FROM events WHERE id = new_event_id);

    IF (end_date >= period_start_date
            AND end_date <= period_end_date
            AND (num_of_players >= 24 OR eventtype = 2)) THEN
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

CREATE OR REPLACE FUNCTION compute_tank_points_2025_cycle(new_player_id INT, event_id INT, new_tank_id INT)
RETURNS VOID AS $$
DECLARE
    current_tank_ids INT[];
    current_tank_scores result_score_pair[];
    new_tank_score NUMERIC(5, 2);
    i INT;
    temp_score NUMERIC(6, 2);
BEGIN
    -- Get current tank IDs
    SELECT ARRAY[ps.tank_1, ps.tank_2, ps.tank_3, ps.tank_4, ps.tank_5]
        INTO current_tank_ids
        FROM player_scores_2025_cycle ps
        WHERE ps.player_id = new_player_id;

    -- Remove NULL values
    current_tank_ids := array_remove(current_tank_ids, NULL);

    -- Get the current tank scores from the corresponding result IDs. If there are no results at all, skip this step
    IF current_tank_ids[1] IS NOT NULL THEN
        FOR i in 1..array_length(current_tank_ids, 1) LOOP
            temp_score := (SELECT es.tank_score
                FROM event_scores_2025_cycle es
                WHERE es.result_id = current_tank_ids[i]);

            current_tank_scores[i].result_id := current_tank_ids[i];
            current_tank_scores[i].score := temp_score;
        END LOOP;
    END IF;

    -- Get the new tank score
    SELECT es.tank_score
        INTO new_tank_score
        FROM event_scores_2025_cycle es
        WHERE result_id = new_tank_id;

    -- Append new result id + new tank score pair to array
    current_tank_scores := array_append(current_tank_scores, (new_tank_id, new_tank_score)::result_score_pair);

    -- Sort by scores, descending order
    current_tank_scores := ARRAY(
        SELECT t FROM unnest(current_tank_scores) AS t
        ORDER BY t.score DESC
    );

    -- If fewer than 5 rows, fill the rest with NULL
    WHILE array_length(current_tank_scores, 1) < 5 LOOP
        current_tank_scores := array_append(current_tank_scores, (NULL, NULL)::result_score_pair);
    END LOOP;

    -- If more than 5 rows, only keep the highest 5 scores
    IF array_length(current_tank_scores, 1) > 5 THEN
        current_tank_scores := ARRAY(
            SELECT t FROM unnest(current_tank_scores) AS t
            LIMIT 5
        );
    END IF;

    -- Put that sweet sweet data into the table
    UPDATE player_scores_2025_cycle
        SET
            tank_1 = current_tank_scores[1].result_id,
            tank_2 = current_tank_scores[2].result_id,
            tank_3 = current_tank_scores[3].result_id,
            tank_4 = current_tank_scores[4].result_id,
            tank_5 = current_tank_scores[5].result_id
        WHERE player_id = new_player_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION compute_global_points_2025_cycle(
    new_player_id INT,
    event_id INT,
    new_global_id INT
) RETURNS VOID AS $$
DECLARE
    current_global_ids INT[];
    current_global_scores result_score_pair[];
    new_global_score NUMERIC(6, 2);
    player_exists BOOLEAN;
    i INT;
    temp_score NUMERIC(6, 2);
BEGIN
    -- Check if this is the first result for this player.
    -- If it is, create a new row and get out.
    SELECT EXISTS (
        SELECT 1
        FROM player_scores_2025_cycle
        WHERE player_id = new_player_id
    ) INTO player_exists;

    IF NOT player_exists THEN
        INSERT INTO player_scores_2025_cycle (player_id, any_event_1)
            VALUES (new_player_id, new_global_id);
        RETURN;
    END IF;

    -- Get current "any event" IDs
    SELECT ARRAY[ps.any_event_1, ps.any_event_2]
        INTO current_global_ids
        FROM player_scores_2025_cycle ps
        WHERE ps.player_id = new_player_id;

    -- Remove NULL values (only does something if the 2nd result is NULL)
    current_global_ids := array_remove(current_global_ids, NULL);

    -- Get the current "global" scores from the corresponding result IDs.
    IF array_length(current_global_ids, 1) IS NOT NULL THEN
        FOR i in 1..array_length(current_global_ids, 1) LOOP
            temp_score := (SELECT es.main_score
                           FROM event_scores_2025_cycle es
                           WHERE es.result_id = current_global_ids[i]);

            current_global_scores[i].result_id := current_global_ids[i];
            current_global_scores[i].score := temp_score;
        END LOOP;
    END IF;


    -- Get the new event's score
    SELECT es.main_score
        INTO new_global_score
        FROM event_scores_2025_cycle es
        WHERE result_id = new_global_id;

    -- Append new result id + new score pair to array
    current_global_scores := array_append(current_global_scores, (new_global_id, new_global_score)::result_score_pair);

    -- Sort by scores, descending order
    current_global_scores := ARRAY(
        SELECT t FROM unnest(current_global_scores) AS t
        ORDER BY t.score DESC
    );

    -- If fewer than 2 rows, fill the extra row with NULL
    IF array_length(current_global_scores, 1) < 2 THEN
        current_global_scores := array_append(current_global_scores, (NULL, NULL)::result_score_pair);
    END IF;

    -- If more than 2 rows, only keep the highest 2 scores
    IF array_length(current_global_scores, 1) > 2 THEN
        current_global_scores := ARRAY(
            SELECT t FROM unnest(current_global_scores) AS t
            LIMIT 2
        );
    END IF;

    -- Put that sweet sweet data into the table
    UPDATE player_scores_2025_cycle
        SET
            any_event_1 = current_global_scores[1].result_id,
            any_event_2 = current_global_scores[2].result_id
        WHERE player_id = new_player_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION compute_live_local_points_2025_cycle(
    new_player_id INT,
    event_id INT,
    new_live_id INT
) RETURNS VOID AS $$
DECLARE
    current_live_ids INT[];
    current_live_scores result_score_pair[];
    new_live_score NUMERIC(6, 2);
    third_best_live_id INT;
    player_exists BOOLEAN;
    i INT;
    temp_score NUMERIC(6, 2);
BEGIN
    -- Check if this is the first result for this player.
    -- If it is, create a new row and get out.
    SELECT EXISTS (
        SELECT 1
        FROM player_scores_2025_cycle
        WHERE player_id = new_player_id
    ) INTO player_exists;

    IF NOT player_exists THEN
        INSERT INTO player_scores_2025_cycle (player_id, other_live_1)
            VALUES (new_player_id, new_live_id);
        RETURN;
    END IF;

    -- Get current live event IDs
    SELECT ARRAY[ps.other_live_1, ps.other_live_2]
        INTO current_live_ids
        FROM player_scores_2025_cycle ps
        WHERE ps.player_id = new_player_id;

    -- Remove NULL values (only does something if the 2nd result is NULL)
    current_live_ids := array_remove(current_live_ids, NULL);

    -- Get the current live scores from the corresponding result IDs
    FOR i in 1..array_length(current_live_ids, 1) LOOP
        temp_score := (SELECT es.main_score
            FROM event_scores_2025_cycle es
            WHERE es.result_id = current_live_ids[i]);

        current_live_scores[i].result_id := current_live_ids[i];
        current_live_scores[i].score := temp_score;
    END LOOP;

    -- Get the new event's score
    SELECT es.main_score
        INTO new_live_score
        FROM event_scores_2025_cycle es
        WHERE result_id = new_live_id;

    -- Append new result id + new score pair to array
    current_live_scores := array_append(current_live_scores, (new_live_id, new_live_score)::result_score_pair);

    -- Sort by scores, descending order
    current_live_scores := ARRAY(
        SELECT t FROM unnest(current_live_scores) AS t
        ORDER BY t.score DESC
    );

    -- If fewer than 2 rows, fill the extra row with NULL
    IF array_length(current_live_scores, 1) < 2 THEN
        current_live_scores := array_append(current_live_scores, (NULL, NULL)::result_score_pair);
    END IF;

    -- If more than 2 rows, only keep the highest 2 scores
    IF array_length(current_live_scores, 1) > 2 THEN
        -- Check the "leftover" result in case it beats results in a lower tier
        third_best_live_id := current_live_scores[3].result_id;
        PERFORM compute_global_points_2025_cycle(
            new_player_id,
            event_id,
            third_best_live_id
        );

        current_live_scores := ARRAY(
            SELECT t FROM unnest(current_live_scores) AS t
            LIMIT 2
        );
    END IF;

    -- Put that sweet sweet data into the table
    UPDATE player_scores_2025_cycle
    SET
        other_live_1 = current_live_scores[1].result_id,
        other_live_2 = current_live_scores[2].result_id
    WHERE player_id = new_player_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION compute_out_of_region_points_2025_cycle(
    new_player_id INT,
    event_id INT,
    new_out_of_region_id INT
) RETURNS VOID AS $$
DECLARE
    current_out_of_region_id INT;
    current_out_of_region_scores result_score_pair[];
    new_out_of_region_score NUMERIC(6, 2);
    second_best_out_of_region_id INT;
    player_exists BOOLEAN;
    i INT;
    temp_score NUMERIC(6, 2);
BEGIN
    -- Check if this is the first result for this player.
    -- If it is, create a new row and get out.
    SELECT EXISTS (
        SELECT 1
        FROM player_scores_2025_cycle
        WHERE player_id = new_player_id
    ) INTO player_exists;

    -- Get current out of region ID
    SELECT ps.out_of_region_live
        INTO current_out_of_region_id
        FROM player_scores_2025_cycle ps
        WHERE ps.player_id = new_player_id;

    IF NOT player_exists OR current_out_of_region_id IS NULL THEN
        INSERT INTO player_scores_2025_cycle (player_id, out_of_region_live)
            VALUES (new_player_id, new_out_of_region_id);
        RETURN;
    END IF;

    -- Get the current out of region score from the corresponding result IDs
    temp_score := (SELECT es.main_score
        FROM event_scores_2025_cycle es
        WHERE es.result_id = current_out_of_region_id);

    current_out_of_region_scores[1].result_id := current_out_of_region_id;
    current_out_of_region_scores[1].score := temp_score;

    -- Get the new event's score
    SELECT es.main_score
        INTO new_out_of_region_score
        FROM event_scores_2025_cycle es
        WHERE result_id = new_out_of_region_id;

    -- Append new result id + new score pair to array
    current_out_of_region_scores := array_append(
            current_out_of_region_scores, (new_out_of_region_id, new_out_of_region_score)::result_score_pair
    );

    -- Sort by scores, descending order
    current_out_of_region_scores := ARRAY(
        SELECT t FROM unnest(current_out_of_region_scores) AS t
        ORDER BY t.score DESC
    );

    -- Check the 2nd best result in case it beats results in a lower tier
    second_best_out_of_region_id := current_out_of_region_scores[2].result_id;
    PERFORM compute_live_local_points_2025_cycle(
        new_player_id,
        event_id,
        second_best_out_of_region_id
    );

    -- Put that sweet sweet data into the table
    UPDATE player_scores_2025_cycle
        SET
            out_of_region_live = current_out_of_region_scores[1].result_id
        WHERE player_id = new_player_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION compute_new_player_score_2025_cycle(
    is_out_of_region BOOLEAN,
    is_online BOOLEAN,
    new_player_id INT,
    new_event_id INT,
    new_result_id INT
)
RETURNS VOID AS $$
BEGIN
    IF is_out_of_region THEN
        PERFORM compute_out_of_region_points_2025_cycle(
            new_player_id,
            new_event_id,
            new_result_id
        );
    ELSIF NOT is_out_of_region AND NOT is_online THEN
        PERFORM compute_live_local_points_2025_cycle(
            new_player_id,
            new_event_id,
            new_result_id
        );
    ELSIF is_online THEN
        PERFORM compute_global_points_2025_cycle(
            new_player_id,
            new_event_id,
            new_result_id
        );
    END IF;

    PERFORM compute_tank_points_2025_cycle(new_player_id, new_event_id, new_result_id);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_player_score_on_insert(new_result_id INT, new_player_id INT, new_event_id INT)
RETURNS VOID AS $$
DECLARE
    result_player_region INT;
    result_event_region INT;
    event_player_count INT;
    event_is_online BOOLEAN;
    result_event_end_date DATE;
    event_is_valid BOOLEAN;
    event_is_out_of_region BOOLEAN;
BEGIN
    IF new_player_id IS NULL THEN
        RETURN;
    END IF;

    SELECT player_region
        INTO result_player_region
        FROM players
        WHERE id = new_player_id;

    SELECT event_region, event_end_date, is_online, number_of_players
        INTO result_event_region, result_event_end_date, event_is_online, event_player_count
        FROM events
        WHERE id = new_event_id;

    event_is_valid := event_is_valid_2025_cycle(result_event_end_date, event_player_count, new_event_id);
    event_is_out_of_region := event_is_out_of_region(result_player_region, result_event_region);

    IF event_is_valid THEN
        PERFORM compute_new_player_score_2025_cycle(
            event_is_out_of_region,
            event_is_online,
            new_player_id,
            new_event_id,
            new_result_id
        );
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_player_score_total(new_player_id INT)
RETURNS VOID AS $$
DECLARE
    score_sum NUMERIC(10, 2) := 0;
    temp_score NUMERIC(10, 2);
    result_ids RECORD;
BEGIN
    SELECT ps.out_of_region_live, ps.other_live_1, ps.other_live_2, ps.any_event_1, ps.any_event_2,
           ps.tank_1, ps.tank_2, ps.tank_3, ps.tank_4, ps.tank_5
        INTO result_ids
        FROM player_scores_2025_cycle ps
        WHERE player_id = new_player_id;

    FOR temp_score IN
        SELECT COALESCE(es.main_score, 0)
        FROM event_scores_2025_cycle es
        WHERE es.result_id = ANY(ARRAY[
            result_ids.out_of_region_live,
            result_ids.other_live_1,
            result_ids.other_live_2,
            result_ids.any_event_1,
            result_ids.any_event_2
        ])
    LOOP
        score_sum := score_sum + temp_score;
    END LOOP;

    FOR temp_score IN
        SELECT COALESCE(es.tank_score, 0)
        FROM event_scores_2025_cycle es
        WHERE es.result_id = ANY(ARRAY[
            result_ids.tank_1,
            result_ids.tank_2,
            result_ids.tank_3,
            result_ids.tank_4,
            result_ids.tank_5
        ])
    LOOP
        score_sum := score_sum + temp_score;
    END LOOP;

    UPDATE player_scores_2025_cycle
        SET total_score = score_sum
        WHERE player_id = new_player_id;
END;
$$ LANGUAGE plpgsql;
-- endregion Player scores

CREATE OR REPLACE FUNCTION compute_event_scores()
RETURNS TRIGGER AS $$
    BEGIN
        PERFORM insert_event_score(NEW.id, NEW.event_id, NEW.placement);
        PERFORM update_player_score_on_insert(NEW.id, NEW.player_id, NEW.event_id);
        PERFORM update_player_score_total(NEW.player_id);
        RETURN NEW;
    END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER after_event_result_insert
    AFTER INSERT ON event_results
    FOR EACH ROW
    EXECUTE FUNCTION compute_event_scores();

COMMIT;