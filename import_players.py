import pandas as pd
from sqlalchemy import create_engine


def import_player_data(csv_path: str, db_path: str) -> None:
    """
    Imports data for all players into the database.

    :param csv_path: Path to players CSV
    :param db_path: Database URL
    """

    players_df = pd.read_csv(csv_path)
    engine = create_engine(db_path)
    players_df.to_sql('players', engine, if_exists='append', index=False)
