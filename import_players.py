import pandas as pd
from db_config import engine


def import_player_data(csv_path: str, db_path: str) -> None:
    """
    Imports data for all players into the database.

    :param csv_path: Path to players CSV
    :param db_path: Database URL
    """

    players_df = pd.read_csv(csv_path)

    with engine.begin() as conn:
        players_df.to_sql('players', conn, if_exists='append', index=False, method='multi')
