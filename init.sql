BEGIN;

--region Drop existing data
DROP TRIGGER IF EXISTS before_insert_event ON events;
DROP FUNCTION IF EXISTS generate_event_id;
DROP TABLE IF EXISTS event_id_sequences CASCADE;

DROP TABLE IF EXISTS event_types CASCADE;
DROP TABLE IF EXISTS regions CASCADE;
DROP TABLE IF EXISTS clubs CASCADE;
DROP TABLE IF EXISTS events CASCADE;
DROP TABLE IF EXISTS players CASCADE;
DROP TABLE IF EXISTS event_results CASCADE;
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
--endregion Events

--region Players
CREATE TABLE IF NOT EXISTS players (
    id SERIAL PRIMARY KEY,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    player_region INT NOT NULL REFERENCES regions(id),
    player_club INT REFERENCES clubs(id)
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

COMMIT;