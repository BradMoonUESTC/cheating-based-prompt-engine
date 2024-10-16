import os
import sys
from sqlalchemy import create_engine

base_path = os.path.join(os.path.dirname(__file__), "../")
sys.path.append(os.path.abspath(base_path))

import audit_config
from cache_manager import test_cache_mgr
from task_mgr import ProjectTaskMgr


if __name__ == "__main__":
    db_url_from = os.environ.get("DATABASE_URL")
    engine = create_engine(db_url_from)

    test_cache_mgr(engine)
