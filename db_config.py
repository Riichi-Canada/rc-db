from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from db_credentials import DB_USER, DB_PASSWORD, DB_HOST, DB_NAME


engine = create_engine(
    f'postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}/{DB_NAME}',
    pool_pre_ping=True,
    pool_recycle=300,
    pool_size=10,
    max_overflow=20
)

SessionLocal = sessionmaker(bind=engine)
