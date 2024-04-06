from sqlalchemy.orm import sessionmaker
from library.utils import str_hash
from dao.entity import CacheEntry

# 缓存管理类
class CacheManager:
    def __init__(self, engine):
        CacheEntry.__table__.create(engine, checkfirst=True)
        self.Session = sessionmaker(bind=engine)

    def _operate_in_session(self, func, *args, **kwargs):
        with self.Session() as session:
            return func(session, *args, **kwargs)

    def set_cache(self, key, value):
        def do_set_cache(session):
            entry = CacheEntry(index=str_hash(key), key=key, value=value)
            session.merge(entry)
            session.commit()

        self._operate_in_session(do_set_cache)

    def get_cache(self, key):
        def do_get_cache(session):
            index = str_hash(key)
            entry = session.query(CacheEntry).get(index)
            return entry.value if entry else None

        return self._operate_in_session(do_get_cache)

    def clear_cache(self):
        def do_clear_cache(session):
            session.query(CacheEntry).delete()
            session.commit()

        self._operate_in_session(do_clear_cache)


def test_cache_mgr(engine):
    cache_manager = CacheManager(engine)

    # cache_manager.set_cache("key1", "value1")
    # cache_manager.set_cache("key2", "value2")

    cached_value = cache_manager.get_cache("key1")
    print(cached_value) 

    cache_manager.set_cache("key1", "value1 - 22")
    cached_value = cache_manager.get_cache("key1")
    print(cached_value) 

    # cache_manager.clear_cache()


if __name__ == "__main__":
    test_cache_mgr()
