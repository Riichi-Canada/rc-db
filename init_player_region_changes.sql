INSERT INTO player_region_changes (player_id, old_region, new_region, date_of_change)
VALUES
    (
        (SELECT id FROM players WHERE first_name = 'Edward' AND last_name = 'Zeng'),
        14,
        33,
        '2025-01-01'::DATE
    );