import os, sys
library_path = os.path.join(os.path.dirname(__file__), "../")
sys.path.append(os.path.abspath(library_path))
import audit_config
from sqlalchemy import create_engine
from dao.task_mgr import ProjectTaskMgr

def import_task(project_id, engine, file):
    tm = ProjectTaskMgr(project_id, engine)
    tm.import_file(file)

if __name__ == "__main__":
    db_url_from = os.environ.get("DATABASE_URL")
    engine = create_engine(db_url_from)

    # test_cache_mgr(engine)

    project_id = 'od-contracts'
    file = '../outputs/output_od-contracts_contracts_with_responses.csv'

    import_task(project_id, engine, file)


