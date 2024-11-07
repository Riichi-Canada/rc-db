import os
from import_players import import_player_data
from import_event import import_event_data
from import_event_results import import_event_results_data
from db_config import DB_NAME, DB_HOST, DB_USER, DB_PASSWORD


def import_all_data() -> None:
    """
    Imports data for all players, events and event results from CSV files into the database.
    """

    DATABASE_PATH = f'postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}/{DB_NAME}'
    PLAYERS_CSV_PATH = './data/players/players.csv'
    EVENT_PATHS = [
        './data/events/montreal_riichi_open/mro_2023.csv',
        './data/events/montreal_riichi_open/mro_2024.csv',
        './data/events/cwl/2023/cwl_fall_2023.csv',
        './data/events/cwl/2024/cwl_spring_2024.csv',
        './data/events/cwl/2024/cwl_fall_2024.csv'
    ]
    EVENT_RESULTS_PATHS = [
        './data/events/montreal_riichi_open/mro_2023_results.csv',
        './data/events/montreal_riichi_open/mro_2024_results.csv',
        './data/events/cwl/2023/cwl_fall_2023_results.csv',
        './data/events/cwl/2024/cwl_spring_2024_results.csv',
    ]

    print("Importing players...")
    import_player_data(csv_path=PLAYERS_CSV_PATH, db_path=DATABASE_PATH)
    print("Done!\n")

    print("Importing events...")
    for event in EVENT_PATHS:
        import_event_data(csv_path=event, db_path=DATABASE_PATH)
    print("Done!\n")

    for event_results in EVENT_RESULTS_PATHS:
        print(f"Importing results for {os.path.splitext(os.path.basename(event_results))[0]}...")
        import_event_results_data(csv_path=event_results, db_path=DATABASE_PATH)
        print("Done! Moving to next event in queue.\n")
    print("\n\nAll done!")


if __name__ == '__main__':
    import_all_data()
