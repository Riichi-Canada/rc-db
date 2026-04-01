BEGIN;

--region Drop existing data
DROP TABLE IF EXISTS event_types CASCADE;
DROP TABLE IF EXISTS regions CASCADE;
DROP TABLE IF EXISTS player_region_changes CASCADE;
DROP TABLE IF EXISTS clubs CASCADE;
DROP TABLE IF EXISTS rulesets CASCADE;
DROP TABLE IF EXISTS events CASCADE;
DROP TABLE IF EXISTS event_code_sequences CASCADE;
DROP TABLE IF EXISTS players CASCADE;
DROP TABLE IF EXISTS event_results CASCADE;
DROP TABLE IF EXISTS event_scores_2025_cycle CASCADE;
DROP TABLE IF EXISTS event_scores_2028_cycle CASCADE;
DROP TABLE IF EXISTS player_scores_2025_cycle CASCADE;
DROP TABLE IF EXISTS player_scores_2028_cycle CASCADE;

DROP TABLE IF EXISTS event_types_log;
DROP TABLE IF EXISTS regions_log;
DROP TABLE IF EXISTS player_region_changes_log;
DROP TABLE IF EXISTS clubs_log;
DROP TABLE IF EXISTS events_log;
DROP TABLE IF EXISTS players_log;
DROP TABLE IF EXISTS event_results_log;
DROP TABLE IF EXISTS event_scores_2025_cycle_log;
DROP TABLE IF EXISTS event_scores_2028_cycle_log;
DROP TABLE IF EXISTS player_scores_2025_cycle_log;
DROP TABLE IF EXISTS player_scores_2028_cycle_log;
--endregion Drop existing data

--region Event types
CREATE TABLE IF NOT EXISTS event_types (
    id SERIAL PRIMARY KEY,
    event_type TEXT UNIQUE NOT NULL
);

INSERT INTO event_types (event_type)
VALUES ('Tournament'), ('League'), ('IORMC Qualifier');

CREATE TABLE IF NOT EXISTS event_types_log (
    id SERIAL PRIMARY KEY,
    operation_type CHAR(1) NOT NULL,
    timestamp TIMESTAMP,
    data jsonb
);
--endregion Event types

--region Regions
CREATE TABLE IF NOT EXISTS regions (
    id INT PRIMARY KEY,
    region TEXT UNIQUE NOT NULL
);

INSERT INTO regions (id, region)
VALUES
    (1, 'Québec (Greater Montreal)'),
    (2, 'Québec (Capitale-Nationale—Chaudière-Appalaches)'),
    (3, 'Québec (Outaouais)'),
    (4, 'Québec (Montérégie—Estrie—Centre-du-Québec)'),
    (5, 'Québec (Laurentides—Lanaudière—Mauricie)'),
    (6, 'Québec (Saguenay—Lac-Saint-Jean)'),
    (7, 'Québec (Bas-Saint-Laurent—Gaspésie)'),
    (8, 'Québec (Abitibi-Témiscamingue)'),
    (9, 'Québec (Côte-Nord—Nord-du-Québec)'),
    (10, 'Ontario (Central)'),
    (11,'Ontario (East)'),
    (12,'Ontario (Golden Horseshoe)'),
    (13,'Ontario (North East)'),
    (14,'Ontario (North West)'),
    (15,'Ontario (South West)'),
    (20,'British Columbia (South West—Vancouver Island)'),
    (21,'British Columbia (South Central—South East)'),
    (22,'British Columbia (North)'),
    (30,'Nova Scotia'),
    (31,'New Brunswick'),
    (32,'Prince Edward Island'),
    (33,'Newfoundland and Labrador'),
    (40,'Manitoba'),
    (41,'Saskatchewan'),
    (42,'Alberta'),
    (50,'Northwest Territories'),
    (51,'Yukon'),
    (52,'Nunavut'),
    (60,'United States'),
    (70,'Europe'),
    (80,'Japan'),
    (100,'Asia'),
    (110,'Oceania'),
    (120,'South America'),
    (0,'Canadian living abroad'),
    (200,'Other');

CREATE TABLE IF NOT EXISTS regions_log (
    id SERIAL PRIMARY KEY,
    operation_type CHAR(1) NOT NULL,
    timestamp TIMESTAMP,
    data jsonb
);
--endregion Regions

--region Clubs
CREATE TABLE IF NOT EXISTS clubs (
    id SERIAL PRIMARY KEY,
    club_name TEXT UNIQUE NOT NULL,
    club_short_name TEXT UNIQUE
);

INSERT INTO clubs (club_name, club_short_name)
VALUES
    ('Toronto Riichi Club', 'TORI'),
    ('Capital Riichi Club', 'CRIC'),
    ('Riichi Mahjong University of Waterloo', 'RMUW'),
    ('Club Riichi de Montréal', 'CRM'),
    ('University of British Columbia Mahjong Club', 'UBCMJC');

CREATE TABLE IF NOT EXISTS clubs_log (
    id SERIAL PRIMARY KEY,
    operation_type CHAR(1) NOT NULL,
    timestamp TIMESTAMP,
    data jsonb
);
--endregion Clubs

--region Rulesets
CREATE TABLE IF NOT EXISTS rulesets (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

INSERT INTO rulesets (name)
VALUES
    ('Unknown'),
    ('EMA 2008'),
    ('EMA 2012'),
    ('EMA 2016'),
    ('EMA 2025'),
    ('WRC 2014'),
    ('WRC 2017'),
    ('WRC 2022'),
    ('WRC 2025'),
    ('Saikouisen'),
    ('M.League');

CREATE TABLE IF NOT EXISTS rulesets_log (
    id SERIAL PRIMARY KEY,
    operation_type CHAR(1) NOT NULL,
    timestamp TIMESTAMP,
    data jsonb
);
--endregion Rulesets

--region Events
CREATE TABLE IF NOT EXISTS events (
    id SERIAL PRIMARY KEY,
    event_code TEXT UNIQUE,
    event_name TEXT UNIQUE NOT NULL,
    event_region INT REFERENCES regions(id),
    event_type INT NOT NULL REFERENCES event_types(id),
    event_start_date DATE NOT NULL,
    event_end_date DATE NOT NULL,
    event_city TEXT,
    event_country TEXT NOT NULL,
    number_of_players INT NOT NULL,
    is_online BOOLEAN NOT NULL,
    event_ruleset INT NOT NULL REFERENCES rulesets(id),
    rule_modifications TEXT,
    event_notes TEXT,
    valid_for_ranking BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS events_log (
    id SERIAL PRIMARY KEY,
    operation_type CHAR(1) NOT NULL,
    timestamp TIMESTAMP,
    data jsonb
);

CREATE TABLE IF NOT EXISTS event_code_sequences (
    year INT NOT NULL,
    event_type INT NOT NULL,
    current_number INT NOT NULL DEFAULT 0,
    PRIMARY KEY (year, event_type)
);
--endregion Events

--region Players
CREATE TABLE IF NOT EXISTS players (
    id SERIAL PRIMARY KEY,
    player_rc_number INT,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    player_region INT NOT NULL REFERENCES regions(id),
    player_club INT REFERENCES clubs(id),
    player_score_2025_cycle NUMERIC(6, 2),
    player_score_2028_cycle NUMERIC(6, 2)
);

CREATE TABLE IF NOT EXISTS players_log (
    id SERIAL PRIMARY KEY,
    operation_type CHAR(1) NOT NULL,
    timestamp TIMESTAMP,
    data jsonb
);

CREATE TABLE IF NOT EXISTS player_region_changes (
    id SERIAL PRIMARY KEY,
    player_id INT REFERENCES players(id),
    old_region INT REFERENCES regions(id),
    new_region INT REFERENCES regions(id),
    date_of_change DATE
);

CREATE TABLE IF NOT EXISTS player_region_changes_log (
    id SERIAL PRIMARY KEY,
    operation_type CHAR(1) NOT NULL,
    timestamp TIMESTAMP,
    data jsonb
);
--endregion Players

--region Event results
CREATE TABLE IF NOT EXISTS event_results (
    id SERIAL PRIMARY KEY,
    event_id INT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    player_id INT REFERENCES players(id),
    player_first_name TEXT NOT NULL,
    player_last_name TEXT NOT NULL,
    placement INT NOT NULL,
    score NUMERIC(10, 2),
    UNIQUE (event_id, player_id)
);

CREATE TABLE IF NOT EXISTS event_results_log (
    id SERIAL PRIMARY KEY,
    operation_type CHAR(1) NOT NULL,
    timestamp TIMESTAMP,
    data jsonb
);
--endregion Event results

-- region Event scores
CREATE TABLE IF NOT EXISTS event_scores_2025_cycle (
    id SERIAL PRIMARY KEY,
    result_id INT UNIQUE NOT NULL REFERENCES event_results(id) ON DELETE CASCADE,
    main_score NUMERIC(6, 2) NOT NULL,
    tank_score NUMERIC(5, 2) NOT NULL
);

CREATE TABLE IF NOT EXISTS event_scores_2025_cycle_log (
    id SERIAL PRIMARY KEY,
    operation_type CHAR(1) NOT NULL,
    timestamp TIMESTAMP,
    data jsonb
);

CREATE TABLE IF NOT EXISTS event_scores_2028_cycle (
    id SERIAL PRIMARY KEY,
    result_id INT UNIQUE NOT NULL REFERENCES event_results(id) ON DELETE CASCADE,
    part_A NUMERIC(6, 2) NOT NULL,
    part_B NUMERIC(5, 2) NOT NULL
);

CREATE TABLE IF NOT EXISTS event_scores_2028_cycle_log (
    id SERIAL PRIMARY KEY,
    operation_type CHAR(1) NOT NULL,
    timestamp TIMESTAMP,
    data jsonb
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

CREATE TABLE IF NOT EXISTS player_scores_2025_cycle_log (
    id SERIAL PRIMARY KEY,
    operation_type CHAR(1) NOT NULL,
    timestamp TIMESTAMP,
    data jsonb
);

CREATE TABLE IF NOT EXISTS player_scores_2028_cycle(
    id SERIAL PRIMARY KEY,
    player_id INT UNIQUE NOT NULL REFERENCES players(id),
    total_score NUMERIC(6, 2),
    slot_1 INT REFERENCES event_results(id),
    slot_2 INT REFERENCES event_results(id),
    slot_3 INT REFERENCES event_results(id),
    slot_4 INT REFERENCES event_results(id),
    slot_5 INT REFERENCES event_results(id)
);

CREATE TABLE IF NOT EXISTS player_scores_2028_cycle_log (
    id SERIAL PRIMARY KEY,
    operation_type CHAR(1) NOT NULL,
    timestamp TIMESTAMP,
    data jsonb
);
-- endregion Player scores

COMMIT;