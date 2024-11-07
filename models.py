from sqlalchemy import Column, Integer, Text, Date, ForeignKey, text
from sqlalchemy.orm import declarative_base, relationship

Base = declarative_base()


class EventType(Base):
    __tablename__ = 'event_types'

    id = Column(Integer, primary_key=True, server_default=text("nextval('event_types_id_seq'::regclass)"))
    event_type = Column(Text, nullable=False, unique=True)


class Region(Base):
    __tablename__ = 'regions'

    id = Column(Integer, primary_key=True, server_default=text("nextval('regions_id_seq'::regclass)"))
    region = Column(Text, nullable=False, unique=True)


class Event(Base):
    __tablename__ = 'events'

    id = Column(Integer, primary_key=True)  # Integer ID for foreign key reference
    event_id = Column(Text, unique=True, nullable=False)  # Human-readable event_id
    event_name = Column(Text, nullable=False)
    event_region = Column(Integer, ForeignKey('regions.id'))
    event_type = Column(Integer, ForeignKey('event_types.id'), nullable=False)
    event_start_date = Column(Date, nullable=False)
    event_end_date = Column(Date, nullable=False)
    event_city = Column(Text)
    event_country = Column(Text, nullable=False)
    number_of_players = Column(Integer, nullable=False)
    is_online = Column(Integer, nullable=False)

    region = relationship("Region")
    event_type_ref = relationship("EventType")


class EventResult(Base):
    __tablename__ = 'event_results'

    id = Column(Integer, primary_key=True)
    event_id = Column(Text, ForeignKey('events.event_id'), nullable=False)
    player_id = Column(Integer, nullable=False)
    placement = Column(Integer, nullable=False)
    score = Column(Integer)

    event = relationship("Event")
