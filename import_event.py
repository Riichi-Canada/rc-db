import pandas as pd
from sqlalchemy import text
from db_config import engine


def import_event_data(csv_path: str) -> str:
    """
    Imports data for an event into the database and returns the event_code of the newly created event.

    :param csv_path: Path to event CSV
    :return: event_code of the newly created event
    """

    event_df = pd.read_csv(csv_path)

    with engine.begin() as conn:
        event_df.to_sql('events', conn, if_exists='append', index=False, method='multi')

        result = conn.execute(text('SELECT event_code FROM events ORDER BY id DESC LIMIT 1'))
        event_code = result.scalar()

    return event_code
