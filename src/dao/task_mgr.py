import csv

import sqlalchemy
from dao.entity import Project_Task
from sqlalchemy.orm import sessionmaker
import tqdm

class ProjectTaskMgr(object):

    def __init__(self, project_id, engine) -> None:
        self.project_id = project_id
        Project_Task.__table__.create(engine, checkfirst = True)
        self.Session = sessionmaker(bind=engine)

    def _operate_in_session(self, func, *args, **kwargs):
        with self.Session() as session:
            return func(session, *args, **kwargs)

    def add_tasks(self, tasks):
        for task in tasks:
            self._operate_in_session(self._add_task, task)
    def add_task_in_one(self, task):
        self._operate_in_session(self._add_task, task)
    def query_task_by_project_id(self, id):
        return self._operate_in_session(self._query_task_by_project_id, id)
    def _query_task_by_project_id(self, session, id):
        return session.query(Project_Task).filter_by(project_id=id).filter(Project_Task.result.like('%PATCH INFO%')).all()
    
    def add_task(self, name, content, keyword, business_type, sub_business_type, function_type, rule, result='', result_gpt4='', score='0.00', category='', contract_code='', risklevel='',similarity_with_rule='',description='',start_line='',end_line='',relative_file_path='',absolute_file_path='', recommendation='',title='',business_flow_code='',business_flow_lines='',business_flow_context='',if_business_flow_scan='', **kwargs):
        task = Project_Task(self.project_id, name, content, keyword, business_type, sub_business_type, function_type, rule, result, result_gpt4, score, category, contract_code, risklevel,similarity_with_rule,description,start_line,end_line,relative_file_path,absolute_file_path, recommendation,title,business_flow_code,business_flow_lines,business_flow_context,if_business_flow_scan)
        self._operate_in_session(self._add_task, task, **kwargs)

    def _add_task(self, session, task, commit=True):
        try:
            key = task.get_key()
            # ts = session.query(Project_Task).filter_by(project_id=self.project_id, key=key).all()
            # if len(ts) == 0:
            session.add(task)
            if commit:
                res=session.commit()
        except sqlalchemy.exc.IntegrityError as e:
            # 如果违反唯一性约束，则回滚事务
            session.rollback()

    def get_task_list(self):
        return self._operate_in_session(self._get_task_list)

    def _get_task_list(self, session):
        return list(session.query(Project_Task).filter_by(project_id=self.project_id).all())
    def get_task_list_by_id(self, id):
        return self._operate_in_session(self._get_task_list_by_id, id)
    def _get_task_list_by_id(self, session, id):
        return list(session.query(Project_Task).filter_by(project_id=id).all())
    def update_result(self, id, result, result_CN,result_assumation):
        self._operate_in_session(self._update_result, id, result, result_CN,result_assumation)

    def _update_result(self, session, id, result, result_CN,result_assumation):
        session.query(Project_Task).filter_by(id=id).update({Project_Task.result: result, Project_Task.result_gpt4: result_CN,Project_Task.category:result_assumation})
        session.commit()
    def update_similarity_generated_referenced_score(self, id, similarity_with_rule):
        self._operate_in_session(self._update_similarity_generated_referenced_score, id, similarity_with_rule)

    def _update_similarity_generated_referenced_score(self, session, id, similarity_with_rule):
        session.query(Project_Task).filter_by(id=id).update({Project_Task.similarity_with_rule: similarity_with_rule})
        session.commit()

    def update_description(self, id, description):
        self._operate_in_session(self._update_description, id, description)
    def _update_description(self, session, id, description):
        session.query(Project_Task).filter_by(id=id).update({Project_Task.description: description})
        session.commit()

    def update_recommendation(self, id, recommendation):
        self._operate_in_session(self._update_recommendation, id, recommendation)
    def _update_recommendation(self, session, id, recommendation):
        session.query(Project_Task).filter_by(id=id).update({Project_Task.recommendation: recommendation})
        session.commit()
    def update_title(self, id, title):
        self._operate_in_session(self._update_title, id, title)
    def _update_title(self, session, id, title):
        session.query(Project_Task).filter_by(id=id).update({Project_Task.title: title})
        session.commit()
        
    def import_file(self, filename):
        reader = csv.DictReader(open(filename, 'r', encoding='utf-8'))

        processed = 0
        for row in tqdm.tqdm(list(reader), "import tasks"):
            self.add_task(**row, commit=False)
            processed += 1
            if processed % 10 == 0:
                self._operate_in_session(lambda s: s.commit())
        self._operate_in_session(lambda s: s.commit())

    
    def dump_file(self, filename):
        writer = self.get_writer(filename)

        def write_rows(session):
            ts = session.query(Project_Task).filter_by(project_id=self.project_id).all()
            for row in ts:
                writer.writerow(row.as_dict())

        self._operate_in_session(write_rows)
        del writer
    def get_writer(self, filename):
        file = open(filename, 'w', newline='', encoding='utf-8')
        writer = csv.DictWriter(file, fieldnames=Project_Task.fieldNames)
        writer.writeheader()  # write header
        return writer

    def merge_results(self, function_rules):
        rule_map = {}
        for rule in function_rules:
            keys = [rule['name'], rule['content'], rule['BusinessType'], rule['Sub-BusinessType'], rule['FunctionType'], rule['KeySentence']]
            key = "/".join(keys)
            rule_map[key] = rule

        return rule_map.values() 

