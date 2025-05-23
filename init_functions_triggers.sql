BEGIN;

--region Drop existing data
DROP TYPE IF EXISTS result_score_pair;

DROP TRIGGER IF EXISTS before_insert_event ON events;
DROP TRIGGER IF EXISTS placement_check ON event_results;
DROP TRIGGER IF EXISTS after_event_result_insert ON event_results;

DROP FUNCTION IF EXISTS generate_event_code;
DROP FUNCTION IF EXISTS check_placement;
DROP FUNCTION IF EXISTS event_is_valid;
DROP FUNCTION IF EXISTS event_is_valid_2025_cycle;
DROP FUNCTION IF EXISTS event_is_valid_2028_cycle;
DROP FUNCTION IF EXISTS event_is_out_of_region;
DROP FUNCTION IF EXISTS event_is_canadian;
DROP PROCEDURE IF EXISTS compute_tank_points_2025_cycle;
DROP PROCEDURE IF EXISTS compute_global_points_2025_cycle;
DROP PROCEDURE IF EXISTS compute_live_local_points_2025_cycle;
DROP PROCEDURE IF EXISTS compute_out_of_region_points_2025_cycle;
DROP PROCEDURE IF EXISTS compute_slot_1_2028_cycle;
DROP PROCEDURE IF EXISTS compute_slot_2_2028_cycle;
DROP PROCEDURE IF EXISTS compute_slots_3_4_2028_cycle;
DROP PROCEDURE IF EXISTS compute_slot_5_2028_cycle;
DROP PROCEDURE IF EXISTS compute_new_player_score;
DROP PROCEDURE IF EXISTS compute_new_player_score_2025_cycle;
DROP PROCEDURE IF EXISTS compute_new_player_score_2028_cycle;
DROP PROCEDURE IF EXISTS insert_event_scores;
DROP PROCEDURE IF EXISTS insert_event_scores_2025_cycle;
DROP PROCEDURE IF EXISTS insert_event_scores_2028_cycle;
DROP PROCEDURE IF EXISTS update_player_score_on_insert;
DROP PROCEDURE IF EXISTS update_player_score_total;
DROP PROCEDURE IF EXISTS update_player_score_total_2025_cycle;
DROP PROCEDURE IF EXISTS update_player_score_total_2028_cycle;
DROP FUNCTION IF EXISTS compute_event_scores;
--endregion Drop existing data

-- region Event codes

CREATE OR REPLACE FUNCTION generate_event_code()
RETURNS TRIGGER AS $$
DECLARE
    year_part TEXT;
    type_part TEXT;
    number_part TEXT;
BEGIN
    year_part := TO_CHAR(NEW.event_start_date, 'YYYY');
    type_part := LPAD(NEW.event_type::TEXT, 2, '0');

    UPDATE event_code_sequences
        SET current_number = current_number + 1
        WHERE year = EXTRACT(YEAR FROM NEW.event_start_date)::INT AND event_type = NEW.event_type;

    IF NOT FOUND THEN
        INSERT INTO event_code_sequences (year, event_type, current_number)
        VALUES (EXTRACT(YEAR FROM NEW.event_start_date)::INT, NEW.event_type, 1);
    END IF;

    SELECT LPAD(current_number::TEXT, 4, '0') INTO number_part
        FROM event_code_sequences
        WHERE year = EXTRACT(YEAR FROM NEW.event_start_date)::INT AND event_type = NEW.event_type;

    NEW.event_code := year_part || '-' || type_part || number_part;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- endregion Event codes

-- region Placement check

CREATE OR REPLACE FUNCTION check_placement()
RETURNS TRIGGER AS $$
DECLARE
    num_players INT;
BEGIN
    SELECT number_of_players INTO num_players FROM events WHERE id = NEW.event_id;

    IF NEW.placement > num_players THEN
        RAISE EXCEPTION 'Placement % cannot be greater than number of players %', NEW.placement, num_players;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- endregion Placement check

-- region Event scores

CREATE OR REPLACE PROCEDURE insert_event_scores_2025_cycle(new_result_id INT, new_event_id INT, placement INT)
AS $$
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

CREATE OR REPLACE PROCEDURE insert_event_scores_2028_cycle(new_result_id INT, new_event_id INT, placement INT)
AS $$
DECLARE
    num_of_players INT;
    min_number_of_players INT := 16;

    part_A_points NUMERIC(6, 2);
    size_scaling_multiplier NUMERIC(6, 5);
    maximum_multiplier NUMERIC := 1.25;

    part_B_points NUMERIC(5, 2);
    top_percentage NUMERIC(5, 2);
BEGIN
    SELECT e.number_of_players INTO num_of_players FROM events e WHERE id = new_event_id;

    part_A_points := ROUND(1000 * (num_of_players - placement) / (num_of_players - 1), 2);
    IF num_of_players > min_number_of_players THEN
        size_scaling_multiplier := (num_of_players - min_number_of_players) * 0.00125 + 1;
        part_A_points := ROUND(part_A_points * LEAST(size_scaling_multiplier, maximum_multiplier), 2);
    END IF;

    -- TODO This formula does not account for ties (half-stars etc.), fix it
    top_percentage := placement::NUMERIC / num_of_players::NUMERIC;
    IF num_of_players >= 32 and top_percentage <= 1.0/32.0 THEN
        part_B_points := 200;
    ELSIF top_percentage <= 1.0/16.0 THEN
        part_B_points := 150;
    ELSIF top_percentage <= 1.0/8.0 THEN
        part_B_points := 100;
    ELSIF top_percentage <= 1.0/4.0 THEN
        part_B_points := 50;
    ELSE
        part_B_points := 0;
    END IF;

    INSERT INTO event_scores_2028_cycle (result_id, part_a, part_b)
    VALUES (new_result_id, part_A_points, part_B_points);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE insert_event_scores(new_result_id INT, new_event_id INT, placement INT)
AS $$
DECLARE
    end_date DATE;
BEGIN
    SELECT event_end_date INTO end_date FROM events WHERE id = new_event_id;

    IF end_date BETWEEN '2022-01-01'::DATE AND '2024-12-31'::DATE THEN
        CALL insert_event_scores_2025_cycle(new_result_id, new_event_id, placement);
    ELSIF end_date BETWEEN '2025-01-01'::DATE AND '2027-12-31'::DATE THEN
        CALL insert_event_scores_2028_cycle(new_result_id, new_event_id, placement);
    END IF;
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
    period_start_date CONSTANT DATE := '2022-01-01'::DATE;
    period_end_date CONSTANT DATE := '2024-12-31'::DATE;
    eventtype INT;
BEGIN
    eventtype := (SELECT event_type FROM events WHERE id = new_event_id);

    -- 24 player limit does not apply to league events (CWL)
    RETURN (end_date >= period_start_date
        AND end_date <= period_end_date
        AND (num_of_players >= 24 OR eventtype = 2));
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION event_is_valid_2028_cycle(end_date DATE, num_of_players INT)
    RETURNS BOOLEAN AS $$
DECLARE
    period_start_date CONSTANT DATE := '2025-01-01'::DATE;
    period_end_date CONSTANT DATE := '2027-12-31'::DATE;
    min_num_of_participants INT := 16;
BEGIN
    RETURN (end_date >= period_start_date
        AND end_date <= period_end_date
        AND num_of_players >= min_num_of_participants);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION event_is_valid(end_date DATE, num_of_players INT, new_event_id INT)
RETURNS BOOLEAN AS $$
BEGIN
    IF end_date BETWEEN '2022-01-01'::DATE AND '2024-12-31'::DATE THEN
        RETURN event_is_valid_2025_cycle(end_date, num_of_players, new_event_id);
    ELSIF end_date BETWEEN '2025-01-01'::DATE AND '2027-12-31'::DATE THEN
        RETURN event_is_valid_2028_cycle(end_date, num_of_players);
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION event_is_out_of_region(event_region INT, player_region INT)
RETURNS BOOLEAN AS $$
DECLARE
    quebec_regions INT[] := ARRAY[1, 2, 3, 4, 5, 6, 7, 8, 9];
    ontario_regions INT[] := ARRAY[10, 11, 12, 13];
BEGIN
    RETURN event_region <> player_region
        AND NOT event_region IS NULL
        AND NOT (  -- Québec and Ontario are considered to be in the same region for this purpose
            (event_region = ANY(quebec_regions) AND player_region = ANY(ontario_regions))
            OR (event_region = ANY(ontario_regions) AND player_region = ANY(quebec_regions))
        );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION event_is_canadian(result_id INT)
RETURNS BOOLEAN AS $$
DECLARE
    -- Regions 1 to this number are in Canada. Regions with a higher number are outside of Canada.
    num_of_canadian_regions INT := 26;
    new_event_region INT;
    is_canadian BOOLEAN;
BEGIN
    SELECT e.event_region INTO new_event_region FROM events e
    JOIN event_results er ON e.id = er.event_id
    WHERE er.id = result_id;

    is_canadian := new_event_region <= num_of_canadian_regions;

    RETURN is_canadian;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE compute_tank_points_2025_cycle(new_player_id INT, new_tank_id INT)
AS $$
DECLARE
    current_tank_ids INT[];
    current_tank_scores result_score_pair[];
    new_tank_score NUMERIC(5, 2);
    i INT;
    temp_score NUMERIC(6, 2);
BEGIN
    SELECT ARRAY[ps.tank_1, ps.tank_2, ps.tank_3, ps.tank_4, ps.tank_5]
        INTO current_tank_ids
        FROM player_scores_2025_cycle ps
        WHERE ps.player_id = new_player_id;

    current_tank_ids := array_remove(current_tank_ids, NULL);

    IF current_tank_ids[1] IS NOT NULL THEN
        FOR i IN 1..array_length(current_tank_ids, 1) LOOP
            temp_score := (SELECT es.tank_score
                FROM event_scores_2025_cycle es
                WHERE es.result_id = current_tank_ids[i]);

            current_tank_scores[i].result_id := current_tank_ids[i];
            current_tank_scores[i].score := temp_score;
        END LOOP;
    END IF;

    SELECT es.tank_score
        INTO new_tank_score
        FROM event_scores_2025_cycle es
        WHERE result_id = new_tank_id;

    current_tank_scores := array_append(current_tank_scores, (new_tank_id, new_tank_score)::result_score_pair);
    current_tank_scores := ARRAY(
        SELECT t FROM unnest(current_tank_scores) AS t
        ORDER BY t.score DESC
    );

    WHILE array_length(current_tank_scores, 1) < 5 LOOP
        current_tank_scores := array_append(current_tank_scores, (NULL, NULL)::result_score_pair);
    END LOOP;

    IF array_length(current_tank_scores, 1) > 5 THEN
        current_tank_scores := ARRAY(
            SELECT t FROM unnest(current_tank_scores) AS t
            LIMIT 5
        );
    END IF;

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

CREATE OR REPLACE PROCEDURE compute_global_points_2025_cycle(new_player_id INT, new_global_id INT)
AS $$
DECLARE
    current_global_ids INT[];
    current_global_scores result_score_pair[];
    new_global_score NUMERIC(6, 2);
    player_exists BOOLEAN;
    i INT;
    temp_score NUMERIC(6, 2);
BEGIN
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

    SELECT ARRAY[ps.any_event_1, ps.any_event_2]
        INTO current_global_ids
        FROM player_scores_2025_cycle ps
        WHERE ps.player_id = new_player_id;

    current_global_ids := array_remove(current_global_ids, NULL);

    IF array_length(current_global_ids, 1) IS NOT NULL THEN
        FOR i in 1..array_length(current_global_ids, 1) LOOP
            temp_score := (SELECT es.main_score
                           FROM event_scores_2025_cycle es
                           WHERE es.result_id = current_global_ids[i]);

            current_global_scores[i].result_id := current_global_ids[i];
            current_global_scores[i].score := temp_score;
        END LOOP;
    END IF;

    SELECT es.main_score
        INTO new_global_score
        FROM event_scores_2025_cycle es
        WHERE result_id = new_global_id;

    current_global_scores := array_append(current_global_scores, (new_global_id, new_global_score)::result_score_pair);
    current_global_scores := ARRAY(
        SELECT t FROM unnest(current_global_scores) AS t
        ORDER BY t.score DESC
    );

    IF array_length(current_global_scores, 1) < 2 THEN
        current_global_scores := array_append(current_global_scores, (NULL, NULL)::result_score_pair);
    END IF;

    IF array_length(current_global_scores, 1) > 2 THEN
        current_global_scores := ARRAY(
            SELECT t FROM unnest(current_global_scores) AS t
            LIMIT 2
        );
    END IF;

    UPDATE player_scores_2025_cycle
        SET
            any_event_1 = current_global_scores[1].result_id,
            any_event_2 = current_global_scores[2].result_id
        WHERE player_id = new_player_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE compute_live_local_points_2025_cycle(new_player_id INT, new_live_id INT)
AS $$
DECLARE
    current_live_ids INT[];
    current_live_scores result_score_pair[];
    new_live_score NUMERIC(6, 2);
    third_best_live_id INT;
    player_exists BOOLEAN;
    i INT;
    temp_score NUMERIC(6, 2);
BEGIN
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

    SELECT ARRAY[ps.other_live_1, ps.other_live_2]
        INTO current_live_ids
        FROM player_scores_2025_cycle ps
        WHERE ps.player_id = new_player_id;

    current_live_ids := array_remove(current_live_ids, NULL);

    IF array_length(current_live_ids, 1) IS NOT NULL THEN
        FOR i in 1..array_length(current_live_ids, 1) LOOP
            temp_score := (SELECT es.main_score
                FROM event_scores_2025_cycle es
                WHERE es.result_id = current_live_ids[i]);

            current_live_scores[i].result_id := current_live_ids[i];
            current_live_scores[i].score := temp_score;
        END LOOP;
    END IF;

    SELECT es.main_score
        INTO new_live_score
        FROM event_scores_2025_cycle es
        WHERE result_id = new_live_id;

    current_live_scores := array_append(current_live_scores, (new_live_id, new_live_score)::result_score_pair);
    current_live_scores := ARRAY(
        SELECT t FROM unnest(current_live_scores) AS t
        ORDER BY t.score DESC
    );

    IF array_length(current_live_scores, 1) < 2 THEN
        current_live_scores := array_append(current_live_scores, (NULL, NULL)::result_score_pair);
    END IF;

    IF array_length(current_live_scores, 1) > 2 THEN
        -- Check the "leftover" result in case it beats results in a lower tier
        third_best_live_id := current_live_scores[3].result_id;
        CALL compute_global_points_2025_cycle(
            new_player_id,
            third_best_live_id
        );

        current_live_scores := ARRAY(
            SELECT t FROM unnest(current_live_scores) AS t
            LIMIT 2
        );
    END IF;

    UPDATE player_scores_2025_cycle
        SET
            other_live_1 = current_live_scores[1].result_id,
            other_live_2 = current_live_scores[2].result_id
        WHERE player_id = new_player_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE compute_out_of_region_points_2025_cycle(new_player_id INT, new_out_of_region_id INT)
AS $$
DECLARE
    current_out_of_region_id INT;
    current_out_of_region_scores result_score_pair[];
    new_out_of_region_score NUMERIC(6, 2);
    second_best_out_of_region_id INT;
    player_exists BOOLEAN;
    temp_score NUMERIC(6, 2);
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM player_scores_2025_cycle
        WHERE player_id = new_player_id
    ) INTO player_exists;

    IF NOT player_exists THEN
        INSERT INTO player_scores_2025_cycle (player_id, out_of_region_live)
            VALUES (new_player_id, new_out_of_region_id);
        RETURN;
    END IF;

    SELECT ps.out_of_region_live
        INTO current_out_of_region_id
        FROM player_scores_2025_cycle ps
        WHERE ps.player_id = new_player_id;

    temp_score := (SELECT es.main_score
        FROM event_scores_2025_cycle es
        WHERE es.result_id = current_out_of_region_id);

    current_out_of_region_scores := array_append(
        current_out_of_region_scores, (current_out_of_region_id, temp_score)::result_score_pair
    );

    SELECT es.main_score
        INTO new_out_of_region_score
        FROM event_scores_2025_cycle es
        WHERE result_id = new_out_of_region_id;

    current_out_of_region_scores := array_append(
        current_out_of_region_scores, (new_out_of_region_id, new_out_of_region_score)::result_score_pair
    );

    current_out_of_region_scores := ARRAY(
        SELECT t FROM unnest(current_out_of_region_scores) AS t
        ORDER BY t.score DESC
    );

    -- Check the 2nd best result in case it beats results in a lower tier
    second_best_out_of_region_id := current_out_of_region_scores[2].result_id;
    CALL compute_live_local_points_2025_cycle(
        new_player_id,
        second_best_out_of_region_id
    );

    UPDATE player_scores_2025_cycle
        SET out_of_region_live = current_out_of_region_scores[1].result_id
        WHERE player_id = new_player_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE compute_slot_5_2028_cycle(new_player_id INT, new_global_result_id INT)
AS $$
DECLARE
    current_global_scores result_score_pair[];
    current_global_result_id INT;
    current_global_result_score NUMERIC(6, 2);
    new_global_result_score NUMERIC(6, 2);
    player_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM player_scores_2028_cycle
        WHERE player_id = new_player_id
    ) INTO player_exists;

    -- Player has not played in other events before, so this new result is their best.
    -- Write it into the data immediately and exit the function.
    IF NOT player_exists THEN
        INSERT INTO player_scores_2028_cycle (player_id, slot_5)
        VALUES (new_player_id, new_global_result_id);
        RETURN;
    END IF;

    -- Get current slot 5 data
    SELECT ps.slot_5
    INTO current_global_result_id
    FROM player_scores_2028_cycle ps
    WHERE ps.player_id = new_player_id;

    current_global_result_score := (
        SELECT SUM(es.part_a + es.part_b) AS score
        FROM event_scores_2028_cycle es
        WHERE es.result_id = current_global_result_id
    );

    current_global_scores := array_append(
            current_global_scores, (current_global_result_id, current_global_result_score)::result_score_pair
                             );

    -- Get new result data
    SELECT SUM(es.part_a + es.part_b) AS score
    INTO new_global_result_score
    FROM event_scores_2028_cycle es
    WHERE result_id = new_global_result_id;

    current_global_scores := array_append(
            current_global_scores, (new_global_result_id, new_global_result_score)::result_score_pair
                             );

    -- Order new result and old result by score, save the highest
    current_global_scores := ARRAY(
            SELECT t FROM unnest(current_global_scores) AS t
            ORDER BY t.score DESC
                             );

    UPDATE player_scores_2028_cycle
    SET slot_5 = current_global_scores[1].result_id
    WHERE player_id = new_player_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE compute_slots_3_4_2028_cycle(new_player_id INT, new_live_result_id INT)
AS $$
DECLARE
    current_live_ids INT[];
    current_live_scores result_score_pair[];
    new_live_score NUMERIC(6, 2);
    third_best_live_id INT;
    i INT;
    temp_score NUMERIC(6, 2);
BEGIN
    -- Get current slot 3-4 data
    SELECT ARRAY[ps.slot_3, ps.slot_4]
    INTO current_live_ids
    FROM player_scores_2028_cycle ps
    WHERE ps.player_id = new_player_id;

    current_live_ids := array_remove(current_live_ids, NULL);

    IF array_length(current_live_ids, 1) IS NOT NULL THEN
        FOR i in 1..array_length(current_live_ids, 1) LOOP
                temp_score := (SELECT SUM(es.part_a + es.part_b) AS score
                               FROM event_scores_2028_cycle es
                               WHERE es.result_id = current_live_ids[i]);

                current_live_scores[i].result_id := current_live_ids[i];
                current_live_scores[i].score := temp_score;
            END LOOP;
    END IF;

    -- Get new result data
    SELECT SUM(es.part_a + es.part_b) AS score
    INTO new_live_score
    FROM event_scores_2028_cycle es
    WHERE result_id = new_live_result_id;

    current_live_scores := array_append(current_live_scores, (new_live_result_id, new_live_score)::result_score_pair);

    -- Order new result and old results by score, save the highest two and bump the new lowest to slot 5
    current_live_scores := ARRAY(
            SELECT t FROM unnest(current_live_scores) AS t
            ORDER BY t.score DESC
                           );

    IF array_length(current_live_scores, 1) < 2 THEN
        current_live_scores := array_append(current_live_scores, (NULL, NULL)::result_score_pair);
    END IF;

    IF array_length(current_live_scores, 1) > 2 THEN
        -- Check the "leftover" result in case it beats results in a lower tier
        third_best_live_id := current_live_scores[3].result_id;
        CALL compute_slot_5_2028_cycle(
                new_player_id,
                third_best_live_id
             );

        current_live_scores := ARRAY(
                SELECT t FROM unnest(current_live_scores) AS t
                LIMIT 2
                               );
    END IF;

    UPDATE player_scores_2028_cycle
    SET
        slot_3 = current_live_scores[1].result_id,
        slot_4 = current_live_scores[2].result_id
    WHERE player_id = new_player_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE compute_slot_2_2028_cycle(new_player_id INT, new_canadian_result_id INT)
AS $$
DECLARE
    current_canadian_scores result_score_pair[];
    current_canadian_result_id INT;
    current_canadian_result_score NUMERIC(6, 2);
    new_canadian_result_score NUMERIC(6, 2);
    player_exists BOOLEAN;
    second_best_canadian_result_id INT;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM player_scores_2028_cycle
        WHERE player_id = new_player_id
    ) INTO player_exists;

    -- Player has not played in other events before, so this new result is their best.
    -- Write it into the data immediately and exit the function.
    IF NOT player_exists THEN
        INSERT INTO player_scores_2028_cycle (player_id, slot_2)
        VALUES (new_player_id, new_canadian_result_id);
        RETURN;
    END IF;

    -- Get current slot 2 data
    SELECT ps.slot_2
    INTO current_canadian_result_id
    FROM player_scores_2028_cycle ps
    WHERE ps.player_id = new_player_id;

    current_canadian_result_score := (
        SELECT SUM(es.part_a + es.part_b) AS score
        FROM event_scores_2028_cycle es
        WHERE es.result_id = current_canadian_result_id
    );

    current_canadian_scores := array_append(
            current_canadian_scores, (current_canadian_result_id, current_canadian_result_score)::result_score_pair
                               );

    -- Get new result data
    SELECT SUM(es.part_a + es.part_b) AS score
    INTO new_canadian_result_score
    FROM event_scores_2028_cycle es
    WHERE result_id = new_canadian_result_id;

    current_canadian_scores := array_append(
            current_canadian_scores, (new_canadian_result_id, new_canadian_result_score)::result_score_pair
                               );

    -- Order new result and old result by score, save the highest
    current_canadian_scores := ARRAY(
            SELECT t FROM unnest(current_canadian_scores) AS t
            ORDER BY t.score DESC
                               );

    second_best_canadian_result_id = current_canadian_scores[2].result_id;

    CALL compute_slots_3_4_2028_cycle(new_player_id, second_best_canadian_result_id);

    UPDATE player_scores_2028_cycle
    SET slot_2 = current_canadian_scores[1].result_id
    WHERE player_id = new_player_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE compute_slot_1_2028_cycle(new_player_id INT, new_canadian_result_id INT)
AS $$
DECLARE
    current_out_of_region_scores result_score_pair[];
    current_out_of_region_result_id INT;
    current_out_of_region_result_score NUMERIC(6, 2);
    new_out_of_region_result_score NUMERIC(6, 2);
    player_exists BOOLEAN;
    second_best_out_of_region_result_id INT;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM player_scores_2028_cycle
        WHERE player_id = new_player_id
    ) INTO player_exists;

    -- Player has not played in other events before, so this new result is their best.
    -- Write it into the data immediately and exit the function.
    IF NOT player_exists THEN
        INSERT INTO player_scores_2028_cycle (player_id, slot_1)
        VALUES (new_player_id, new_canadian_result_id);
        RETURN;
    END IF;

    -- Get current slot 1 data
    SELECT ps.slot_1
        INTO current_out_of_region_result_id
        FROM player_scores_2028_cycle ps
        WHERE ps.player_id = new_player_id;

    current_out_of_region_result_score := (
        SELECT SUM(es.part_a + es.part_b) AS score
        FROM event_scores_2028_cycle es
        WHERE es.result_id = current_out_of_region_result_id
    );

    current_out_of_region_scores := array_append(
        current_out_of_region_scores, (current_out_of_region_result_id, current_out_of_region_result_score)::result_score_pair
    );

    -- Get new result data
    SELECT SUM(es.part_a + es.part_b) AS score
        INTO new_out_of_region_result_score
        FROM event_scores_2028_cycle es
        WHERE result_id = new_canadian_result_id;

    current_out_of_region_scores := array_append(
        current_out_of_region_scores, (new_canadian_result_id, new_out_of_region_result_score)::result_score_pair
    );

    -- Order new result and old result by score, save the highest
    current_out_of_region_scores := ARRAY(
        SELECT t FROM unnest(current_out_of_region_scores) AS t
        ORDER BY t.score DESC
    );

    second_best_out_of_region_result_id = current_out_of_region_scores[2].result_id;

    IF event_is_canadian(second_best_out_of_region_result_id) THEN
        CALL compute_slot_2_2028_cycle(new_player_id, second_best_out_of_region_result_id);
    ELSE
        CALL compute_slots_3_4_2028_cycle(new_player_id, second_best_out_of_region_result_id);
    END IF;

    UPDATE player_scores_2028_cycle
        SET slot_1 = current_out_of_region_scores[1].result_id
        WHERE player_id = new_player_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE compute_new_player_score_2025_cycle(
    is_out_of_region BOOLEAN,
    is_online BOOLEAN,
    new_player_id INT,
    new_result_id INT
)
AS $$
BEGIN
    IF is_out_of_region THEN
        CALL compute_out_of_region_points_2025_cycle(
            new_player_id,
            new_result_id
        );
    ELSIF NOT is_out_of_region AND NOT is_online THEN
        CALL compute_live_local_points_2025_cycle(
            new_player_id,
            new_result_id
        );
    ELSIF is_online THEN
        CALL compute_global_points_2025_cycle(
            new_player_id,
            new_result_id
        );
    END IF;

    CALL compute_tank_points_2025_cycle(new_player_id, new_result_id);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE compute_new_player_score_2028_cycle(
    is_out_of_region BOOLEAN,
    is_canadian BOOLEAN,
    is_online BOOLEAN,
    new_player_id INT,
    new_result_id INT
)
AS $$
DECLARE

BEGIN
    -- Out of region + any(foreign, Canadian): check slot 1, check bumped for slot 2 compatibility, check slot 3-4, check slot 5
    -- Local + Canadian: check slot 2, bump to slot 3-4, bump to slot 5
    -- Online: Check slot 5
    IF is_out_of_region THEN
        CALL compute_slot_1_2028_cycle(
            new_player_id,
            new_result_id
        );
    ELSIF is_canadian THEN
        CALL compute_slot_2_2028_cycle(
            new_player_id,
            new_result_id
        );
    ELSIF is_online THEN
        CALL compute_slot_5_2028_cycle(
            new_player_id,
            new_result_id
        );
    END IF;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE compute_new_player_score(
    is_out_of_region BOOLEAN,
    is_online BOOLEAN,
    new_player_id INT,
    new_result_id INT
)
AS $$
DECLARE
    event_end_date DATE;
    current_cycle INT;
BEGIN
    SELECT e.event_end_date INTO event_end_date FROM events e
        JOIN event_results er ON e.id = er.event_id
        WHERE er.id = new_result_id;

    IF event_end_date BETWEEN '2022-01-01'::DATE AND '2024-12-31'::DATE THEN
        current_cycle = 2025;
        CALL compute_new_player_score_2025_cycle(
           is_out_of_region,
           is_online,
           new_player_id,
           new_result_id
        );
    ELSIF event_end_date BETWEEN '2025-01-01'::DATE AND '2027-12-31'::DATE THEN
        current_cycle = 2028;
        CALL compute_new_player_score_2028_cycle(
           is_out_of_region,
           event_is_canadian(new_result_id),
           is_online,
           new_player_id,
           new_result_id
        );
    END IF;

    CALL update_player_score_total(new_player_id, current_cycle);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE update_player_score_on_insert(new_result_id INT, new_player_id INT, new_event_id INT)
AS $$
DECLARE
    result_player_region INT;
    result_event_region INT;
    event_player_count INT;
    event_is_online BOOLEAN;
    result_event_end_date DATE;
    event_is_valid BOOLEAN;
    event_is_out_of_region BOOLEAN;
BEGIN
    -- Not a registered canadian player (no ID)
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

    event_is_valid := event_is_valid(result_event_end_date, event_player_count, new_event_id);
    IF event_is_online THEN
        event_is_out_of_region := FALSE;
    ELSE
        event_is_out_of_region := event_is_out_of_region(result_player_region, result_event_region);
    END IF;

    IF event_is_valid THEN
        CALL compute_new_player_score(
            event_is_out_of_region,
            event_is_online,
            new_player_id,
            new_result_id
        );
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE update_player_score_total_2025_cycle(new_player_id INT)
AS $$
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

CREATE OR REPLACE PROCEDURE update_player_score_total_2028_cycle(new_player_id INT)
AS $$
DECLARE
    score_sum NUMERIC(10, 2) := 0;
    temp_score NUMERIC(10, 2);
    result_ids RECORD;
BEGIN
    SELECT ps.slot_1, ps.slot_2, ps.slot_3, ps.slot_4, ps.slot_5
        INTO result_ids
        FROM player_scores_2028_cycle ps
        WHERE player_id = new_player_id;

    FOR temp_score IN
        SELECT COALESCE(es.part_a, 0)
        FROM event_scores_2028_cycle es
        WHERE es.result_id = ANY(ARRAY[
            result_ids.slot_1,
            result_ids.slot_2,
            result_ids.slot_3,
            result_ids.slot_4,
            result_ids.slot_5
            ])
        LOOP
            score_sum := score_sum + temp_score;
        END LOOP;

    FOR temp_score IN
        SELECT COALESCE(es.part_b, 0)
        FROM event_scores_2028_cycle es
        WHERE es.result_id = ANY(ARRAY[
            result_ids.slot_1,
            result_ids.slot_2,
            result_ids.slot_3,
            result_ids.slot_4,
            result_ids.slot_5
            ])
        LOOP
            score_sum := score_sum + temp_score;
        END LOOP;

    UPDATE player_scores_2028_cycle
    SET total_score = score_sum
    WHERE player_id = new_player_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE update_player_score_total(new_player_id INT, current_cycle INT)
AS $$
BEGIN
    IF current_cycle = 2025 THEN
        CALL update_player_score_total_2025_cycle(new_player_id);
    ELSIF current_cycle = 2028 THEN
        CALL update_player_score_total_2028_cycle(new_player_id);
    END IF;
END;
$$ LANGUAGE plpgsql;
-- endregion Player scores

CREATE OR REPLACE FUNCTION compute_event_scores()
RETURNS TRIGGER AS $$
    BEGIN
        CALL insert_event_scores(NEW.id, NEW.event_id, NEW.placement);
        CALL update_player_score_on_insert(NEW.id, NEW.player_id, NEW.event_id);
        RETURN NEW;
    END;
$$ LANGUAGE plpgsql;

-- region Triggers

CREATE TRIGGER before_insert_event
    BEFORE INSERT ON events
    FOR EACH ROW
    EXECUTE FUNCTION generate_event_code();

CREATE TRIGGER placement_check
    BEFORE INSERT OR UPDATE ON event_results
    FOR EACH ROW
    EXECUTE FUNCTION check_placement();

CREATE TRIGGER after_event_result_insert
    AFTER INSERT ON event_results
    FOR EACH ROW
    EXECUTE FUNCTION compute_event_scores();
-- endregion Triggers

-- region Documentation comments
COMMENT ON TYPE result_score_pair IS
    $s$Dict-like object type to make data manipulation simpler in certain procedures.$s$;

COMMENT ON FUNCTION generate_event_code() IS
    $s$Generates a textual event ID of format YYYY-XXNNNN, where YYYY is the year the event took place, XX is the type
    (ex. 01 for tournament, 02 for league) and NNNN is a serial number.$s$;

COMMENT ON FUNCTION check_placement() IS
    $s$Checks that a player's placement in a new event result is not greater than the event's number of participants$s$;

COMMENT ON FUNCTION compute_event_scores IS
    'Calls the necessary functions to compute and update event scores for each new result.';

COMMENT ON PROCEDURE insert_event_scores IS
    $s$Computes an event's scores (for player rankings) and inserts them into the relevant event_scores table.$s$;

COMMENT ON PROCEDURE insert_event_scores_2025_cycle IS
    $s$Computes an event's scores (for player rankings) and inserts them into the event_scores_2025_cycle table.$s$;

COMMENT ON PROCEDURE update_player_score_on_insert IS
    $s$Check if the event is valid to be used in the ranking. If yes, compute the new score and insert it into that
    player's scores list if it beats any current ones.$s$;

COMMENT ON FUNCTION event_is_valid
    IS $s$Returns a boolean indicating if an event is valid to be used in the ranking.$s$;

COMMENT ON FUNCTION event_is_valid_2025_cycle
    IS $s$Returns a boolean indicating if an event is valid to be used in the ranking for the 2025 cycle.$s$;

COMMENT ON FUNCTION event_is_out_of_region
    IS $s$Returns a boolean indicating if an event is out of the given player's region.$s$;

COMMENT ON PROCEDURE compute_new_player_score
    IS $s$Checks if the player's new score beats any of their old scores. If yes, update the player's scores list.$s$;

COMMENT ON PROCEDURE compute_new_player_score_2025_cycle IS
    $s$Checks if the player's new score beats any of their old scores for the 2025 cycle.
    If yes, update the player's scores list.$s$;

COMMENT ON PROCEDURE compute_out_of_region_points_2025_cycle IS
    $s$Checks if the new score beats the player's current best out of region score for the 2025 cycle.
    If yes, update the player's scores list accordingly.$s$;

COMMENT ON PROCEDURE compute_live_local_points_2025_cycle IS
    $s$Checks if the new score beats one of the player's current best live, non-out of region scores for the 2025 cycle.
    If yes, update the player's scores list accordingly.$s$;

COMMENT ON PROCEDURE compute_global_points_2025_cycle IS
    $s$Checks if the new score beats one of the player's current best "any event" scores for the 2025 cycle.
    If yes, update the player's scores list accordingly.$s$;

COMMENT ON PROCEDURE compute_tank_points_2025_cycle IS
    $s$Checks if the new score beats one of the player's current best tank scores for the 2025 cycle.
    If yes, update the player's scores list accordingly.$s$;

COMMENT ON PROCEDURE update_player_score_total
    IS $s$Updates the specified player's score total.$s$;

COMMENT ON PROCEDURE update_player_score_total_2025_cycle
    IS $s$Updates the specified player's score total for the 2025 cycle.$s$;

COMMENT ON TRIGGER after_event_result_insert ON event_results IS
    $s$Calls the functions to calculate an event's scores for each placement,
    and to add these scores to player rankings.$s$;

COMMENT ON TRIGGER placement_check ON event_results IS
    $s$Calls a function to check if the placement in the result is greater than the event's number of participants.$s$;

COMMENT ON TRIGGER before_insert_event ON events IS
    'Calls the function to generate the textual event ID every time a new event is added to the data.';
-- endregion Documentation comments

COMMIT;