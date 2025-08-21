import os
from import_players import import_player_data
from import_event import import_event_data
from import_event_results import import_event_results_data
from db_config import DB_NAME, DB_HOST, DB_USER, DB_PASSWORD

DATABASE_PATH = f'postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}/{DB_NAME}'


def get_event_paths(data_dir_path: str) -> list[str]:
    paths = []

    for root, dirs, files in os.walk(data_dir_path):
        for file in files:
            if file.endswith('.csv') and not file.endswith('_results.csv'):
                paths.append(os.path.join(root, file))

    paths.sort()
    return paths


def import_all_data() -> None:
    """
    Imports data for all players, events and event results from CSV files into the database.
    """

    PLAYERS_CSV_PATH = './data/players/players.csv'
    EVENT_PATHS = get_event_paths(data_dir_path='./data/events')

    print("Importing players...")
    import_player_data(csv_path=PLAYERS_CSV_PATH, db_path=DATABASE_PATH)
    print("Player import done! Moving on to events.\n---------------------------------------------------------------\n")

    print("Importing events and their results...")
    for event in EVENT_PATHS:
        print(f'Importing data for {os.path.splitext(os.path.basename(event))[0]}...')
        event_code = import_event_data(csv_path=event, db_path=DATABASE_PATH)
        print(f'Importing data for {os.path.splitext(os.path.basename(event))[0]}_results...')
        import_event_results_data(
            csv_path=event.rstrip('.csv') + '_results.csv',
            db_path=DATABASE_PATH,
            event_code=event_code
        )
        print("Done! Moving to next event in queue.\n-----------------------------------------------------------------")
    print("Event import done!\n")


if __name__ == '__main__':
    import_all_data()
