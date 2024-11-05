BEGIN;

--region Drop existing data
DROP TABLE IF EXISTS event_types;
DROP TABLE IF EXISTS regions;
DROP TABLE IF EXISTS clubs;
DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS players;
DROP TABLE IF EXISTS event_results;
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
    ('Gatineau-Ottawa Riichi', 'GO Riichi'),
    ('University of British Columbia Mahjong Club', 'UBC Mahjong');
--endregion Clubs

--region Events
CREATE TABLE IF NOT EXISTS events (
    id SERIAL PRIMARY KEY,
    event_name TEXT UNIQUE NOT NULL,
    event_region INT REFERENCES regions(id),
    event_type INT REFERENCES event_types(id),
    event_start_date DATE NOT NULL,
    event_end_date DATE NOT NULL,
    event_city TEXT NOT NULL,
    event_country TEXT NOT NULL,
    number_of_players INT NOT NULL,
    is_online BOOLEAN NOT NULL
);
--endregion Events

--region Players
CREATE TABLE IF NOT EXISTS players (
    id SERIAL PRIMARY KEY,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    player_region INT NOT NULL REFERENCES regions(id),
    player_club INT NOT NULL REFERENCES clubs(id)
);
--endregion Players

--region Event results
CREATE TABLE IF NOT EXISTS event_results (
    event_id INT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    player_id INT REFERENCES players(id) ON DELETE CASCADE,
    player_first_name TEXT NOT NULL,
    player_last_name TEXT NOT NULL,
    placement INT NOT NULL,
    PRIMARY KEY (event_id, player_id)
);
--endregion Event results

COMMIT;