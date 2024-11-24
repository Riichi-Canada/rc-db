BEGIN;

--region Drop existing data
DROP TABLE IF EXISTS event_types CASCADE;
DROP TABLE IF EXISTS regions CASCADE;
DROP TABLE IF EXISTS clubs CASCADE;
DROP TABLE IF EXISTS events CASCADE;
DROP TABLE IF EXISTS event_id_sequences CASCADE;
DROP TABLE IF EXISTS players CASCADE;
DROP TABLE IF EXISTS event_results CASCADE;
DROP TABLE IF EXISTS event_scores_2025_cycle CASCADE;
DROP TABLE IF EXISTS player_scores_2025_cycle CASCADE;
--endregion Drop existing data

--region Event types
CREATE TABLE IF NOT EXISTS event_types (
    id SERIAL PRIMARY KEY,
    event_type TEXT UNIQUE NOT NULL
);

INSERT INTO event_types (event_type)
VALUES ('Tournament'), ('League');
--endregion Event types

--region Regions
CREATE TABLE IF NOT EXISTS regions (
    id SERIAL PRIMARY KEY,
    region TEXT UNIQUE NOT NULL
);

INSERT INTO regions (region)
VALUES
    ('Québec'),
    ('Ontario'),
    ('British Columbia'),
    ('Nova Scotia'),
    ('New Brunswick'),
    ('Prince Edward Island'),
    ('Newfoundland and Labrador'),
    ('Manitoba'),
    ('Saskatchewan'),
    ('Alberta'),
    ('Northwest Territories'),
    ('Yukon'),
    ('Nunavut'),
    ('United States'),
    ('Europe'),
    ('Asia'),
    ('Oceania'),
    ('South America'),
    ('Other');
--endregion Regions

--region Clubs
CREATE TABLE IF NOT EXISTS clubs (
    id SERIAL PRIMARY KEY,
    club_name TEXT UNIQUE NOT NULL,
    club_short_name TEXT UNIQUE
);

INSERT INTO clubs (club_name, club_short_name)
VALUES
    ('Club Riichi de Montréal', 'CRM'),
    ('Toronto Riichi Club', 'TORI'),
    ('University of British Columbia Mahjong Club', 'UBC Mahjong'),
    ('Gatineau-Ottawa Riichi', 'GO Riichi');
--endregion Clubs

--region Events
CREATE TABLE IF NOT EXISTS events (
    id SERIAL PRIMARY KEY,
    event_id TEXT UNIQUE NOT NULL,
    event_name TEXT UNIQUE NOT NULL,
    event_region INT REFERENCES regions(id),
    event_type INT NOT NULL REFERENCES event_types(id),
    event_start_date DATE NOT NULL,
    event_end_date DATE NOT NULL,
    event_city TEXT,
    event_country TEXT NOT NULL,
    number_of_players INT NOT NULL,
    is_online BOOLEAN NOT NULL
);

CREATE TABLE IF NOT EXISTS event_id_sequences (
    year INT NOT NULL,
    event_type INT NOT NULL,
    current_number INT NOT NULL DEFAULT 0,
    PRIMARY KEY (year, event_type)
);
--endregion Events

--region Players
CREATE TABLE IF NOT EXISTS players (
    id SERIAL PRIMARY KEY,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    player_region INT NOT NULL REFERENCES regions(id),
    player_club INT REFERENCES clubs(id),
    player_score_2025_cycle NUMERIC(6, 2)
);
--endregion Players

--region Event results
CREATE TABLE IF NOT EXISTS event_results (
    id SERIAL PRIMARY KEY,
    event_id INT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    player_id INT REFERENCES players(id) ON DELETE CASCADE,
    player_first_name TEXT NOT NULL,
    player_last_name TEXT NOT NULL,
    placement INT NOT NULL,
    score NUMERIC(10, 2),
    UNIQUE (event_id, player_id)
);
--endregion Event results

-- region Event scores
CREATE TABLE IF NOT EXISTS event_scores_2025_cycle (
    id SERIAL PRIMARY KEY,
    result_id INT UNIQUE NOT NULL REFERENCES event_results(id) ON DELETE CASCADE,
    main_score NUMERIC(6, 2) NOT NULL,
    tank_score NUMERIC(5, 2) NOT NULL
);
-- endregion Event scores

-- region Player scores
CREATE TABLE IF NOT EXISTS player_scores_2025_cycle(
    id SERIAL PRIMARY KEY,
    player_id INT UNIQUE NOT NULL REFERENCES players(id),
    total_score NUMERIC(6, 2),
    out_of_region_live INT REFERENCES event_results(id),
    other_live_1 INT REFERENCES event_results(id),
    other_live_2 INT REFERENCES event_results(id),
    any_event_1 INT REFERENCES event_results(id),
    any_event_2 INT REFERENCES event_results(id),
    tank_1 INT REFERENCES event_results(id),
    tank_2 INT REFERENCES event_results(id),
    tank_3 INT REFERENCES event_results(id),
    tank_4 INT REFERENCES event_results(id),
    tank_5 INT REFERENCES event_results(id)
);
-- endregion Player scores

COMMIT;