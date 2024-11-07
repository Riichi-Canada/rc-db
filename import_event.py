import pandas as pd
from sqlalchemy import create_engine


def import_event_data(csv_path: str, db_path: str) -> None:
    """
    Import data for an event into the database.

    :param csv_path: Path to event CSV
    :param db_path: Database URL
    """

    event_df = pd.read_csv(csv_path)
    engine = create_engine(db_path)
    event_df.to_sql('events', engine, if_exists='append', index=False)
