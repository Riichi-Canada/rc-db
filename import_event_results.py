import pandas as pd
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from models import Event, Player


def get_event_id(e_code: str, session) -> int | None:
    """
    Maps the textual event ID in the CSV to the numeric event ID in the database and returns the numeric ID.

    :param e_code: Textual event ID
    :param session: DB session
    :return: Numeric event ID
    """

    event = session.query(Event).filter_by(event_code=e_code).first()
    return event.id if event else None


def get_player_id(rc_number: int, session) -> int | None:
    """
    Maps the Riichi Canada number in the CSV to the numeric player ID in the database and returns the numeric ID.

    :param rc_number: Player's Riichi Canada number
    :param session: DB session
    :return: Numeric player ID
    """

    player = session.query(Player).filter_by(player_rc_number=rc_number).first()
    return player.id if player else None


def import_event_results_data(csv_path: str, db_path: str, event_code: str) -> None:
    """
    Imports data for an event's results into the database.

    :param csv_path: Path to event results CSV
    :param db_path: Database URL
    :param event_code: event_code
    """

    event_df = pd.read_csv(csv_path)

    engine = create_engine(db_path)
    Session = sessionmaker(bind=engine)
    session = Session()

    event_df['player_id'] = event_df['player_id'].apply(
        lambda x: get_player_id(int(x), session) if len(str(x)) >= 8 else x
    )

    event_df['numeric_event_id'] = get_event_id(event_code, session)

    missing_events = event_df[event_df['numeric_event_id'].isna()]
    if not missing_events.empty:
        print("These event_ids were not found in the events table:")
        print(missing_events['event_code'])

    event_df.drop(columns=['event_code'], inplace=True)
    event_df.rename(columns={'numeric_event_id': 'event_id'}, inplace=True)

    event_df.to_sql('event_results', engine, if_exists='append', index=False)
