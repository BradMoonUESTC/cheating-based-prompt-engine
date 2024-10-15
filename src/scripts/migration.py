import os, sys
library_path = os.path.join(os.path.dirname(__file__), "../")
sys.path.append(os.path.abspath(library_path))
import audit_config
from sqlalchemy import create_engine, select, Column, String, MetaData, Table, inspect
from sqlalchemy.orm import sessionmaker
from library.utils import str_hash
import tqdm
import os

from dao.cache_manager import Base, CacheEntry

def object_as_dict(obj):
    return {c.key: getattr(obj, c.key)
            for c in inspect(obj).mapper.column_attrs}

def migrate_db(engine_from, engine_to):
    tables = ['prompt_cache']

    metadata_from = MetaData()
    metadata_to = MetaData()
    
    for table in tables:
        from_table = Table(table, metadata_from, autoload_with=engine_from)
        to_table = Table(table, metadata_to, autoload_with=engine_to)

        conn_from = engine_from.connect()
        result = conn_from.execute(select(from_table))

        # d1 = [row for row in result]
        data_to_insert = []
        for row in result:
            data = CacheEntry(index=str_hash(row[0]), key=row[0], value=row[1])
            data_to_insert.append(data)
        
        # data_to_insert = [row._asdict() for row in result]
        # for i in range(len(data_to_insert)):
        #     data_to_insert[i]['index'] = str_hash(data_to_insert[i]['key'])

        conn_to = engine_to.connect()
        DBSession = sessionmaker(bind=engine_to)
        session = DBSession()
        
        rs = 0
        for data in tqdm.tqdm(data_to_insert):
            session.add(data)
            rs += 1

            if rs % 10 == 0:
                session.commit()
            
        session.commit()
        # segment_size = 5
        # segments = [ data_to_insert[i : i + segment_size] for i in range(0, len(data_to_insert), segment_size) ]
        # for seg in tqdm.tqdm(segments, desc = "insert to db"):
        #     try:
        #         conn_to.execute(to_table.insert(), data_to_insert)
        #     except Exception as e:
        #         print ("failed ", e)
        #         raise


def do_migration():
    db_url_from = os.environ.get("DATABASE_SQLITE")
    db_url_to = os.environ.get("DATABASE_URL")

    db_from = create_engine(db_url_from)
    db_to = create_engine(db_url_to)

    migrate_db(db_from, db_to)


if __name__ == "__main__":
    # test()
    do_migration()