import pandas as pd
from sqlalchemy import create_engine


def import_player_data(csv_path: str, db_path: str) -> None:
    players_df = pd.read_csv(csv_path)
    engine = create_engine(db_path)
    players_df.to_sql('players', engine, if_exists='append', index=False)
