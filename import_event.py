import pandas as pd
from sqlalchemy import create_engine, text


def import_event_data(csv_path: str, db_path: str) -> str:
    """
    Imports data for an event into the database and returns the event_code of the newly created event.

    :param csv_path: Path to event CSV
    :param db_path: Database URL
    :return: event_code of the newly created event
    """

    event_df = pd.read_csv(csv_path)
    engine = create_engine(db_path)
    event_df.to_sql('events', engine, if_exists='append', index=False)

    with engine.connect() as connection:
        result = connection.execute(text('SELECT event_code FROM events ORDER BY id DESC LIMIT 1'))
        event_code = result.scalar()

    return event_code
