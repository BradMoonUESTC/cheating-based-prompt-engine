import random
import sqlalchemy
from sqlalchemy import create_engine, select, Column, String, Integer, MetaData, Table, inspect
from sqlalchemy.orm import sessionmaker
from sqlalchemy.ext.declarative import declarative_base
from library.utils import str_hash

Base = declarative_base()

class CacheEntry(Base):
    __tablename__ = 'prompt_cache2'
    index = Column(String, primary_key=True)
    key = Column(String)
    value = Column(String)

class Project_Task(Base):
    __tablename__ = 'project_tasks_amazing_prompt'
    id = Column(Integer, autoincrement=True, primary_key=True)
    key = Column(String, index=True)
    project_id = Column(String, index=True)
    name = Column(String)
    content = Column(String)
    keyword = Column(String)
    business_type = Column(String)
    sub_business_type = Column(String)
    function_type = Column(String)
    rule = Column(String)
    result = Column(String)
    result_gpt4 = Column(String)
    score=Column(String)
    category=Column(String)
    contract_code=Column(String)
    risklevel=Column(String)
    similarity_with_rule=Column(String)
    description = Column(String)
    start_line=Column(String)
    end_line=Column(String)
    relative_file_path=Column(String)
    absolute_file_path=Column(String)
    recommendation=Column(String)
    title=Column(String)
    business_flow_code=Column(String)
    business_flow_lines=Column(String)
    business_flow_context=Column(String)
    if_business_flow_scan=Column(String)

    fieldNames = ['name', 'content', 'keyword', 'business_type', 'sub_business_type', 'function_type', 'rule', 'result', 'result_gpt4','score','category','contract_code','risklevel','similarity_with_rule','description','start_line','end_line','relative_file_path','absolute_file_path','recommendation','title','business_flow_code','business_flow_lines','business_flow_context','if_business_flow_scan']

    def __init__(self, project_id, name, content, keyword, business_type, sub_business_type, function_type, rule, result='', result_gpt4='',score='0.00',category='',contract_code='',risklevel='',similarity_with_rule='0.00',description='',start_line='',end_line='',relative_file_path='',absolute_file_path='',recommendation='',title='',business_flow_code='',business_flow_lines='',business_flow_context='',if_business_flow_scan='0'):
        self.project_id = project_id
        self.name = name
        self.content = content
        self.keyword = keyword
        self.business_type = business_type
        self.sub_business_type = sub_business_type
        self.function_type = function_type
        self.rule = rule
        self.result = result
        self.result_gpt4 = result_gpt4
        self.key = self.get_key()
        self.score=score
        self.category=category
        self.contract_code=contract_code
        self.risklevel=risklevel
        self.similarity_with_rule=similarity_with_rule
        self.description = description
        self.start_line=start_line
        self.end_line=end_line
        self.relative_file_path=relative_file_path
        self.absolute_file_path=absolute_file_path
        self.recommendation=recommendation
        self.title=title
        self.business_flow_code=business_flow_code
        self.business_flow_lines=business_flow_lines
        self.business_flow_context=business_flow_context
        self.if_business_flow_scan=if_business_flow_scan



    def as_dict(self):
        return {
            'name': self.name,
            'content': self.content,
            'keyword': self.keyword,
            'business_type': self.business_type,
            'sub_business_type': self.sub_business_type,
            'function_type': self.function_type,
            'rule': self.rule,
            'result': self.result,
            'result_gpt4': self.result_gpt4,
            'score':self.score,
            'category':self.category,
            'contract_code':self.contract_code,
            'risklevel':self.risklevel,
            'similarity_with_rule':self.similarity_with_rule,
            'description': self.description,
            'start_line':self.start_line,
            'end_line':self.end_line,
            'relative_file_path':self.relative_file_path,
            'absolute_file_path':self.absolute_file_path,
            'recommendation':self.recommendation,
            'title':self.title,
            'business_flow_code':self.business_flow_code,
            'business_flow_lines':self.business_flow_lines,
            'business_flow_context':self.business_flow_context,
            'if_business_flow_scan':self.if_business_flow_scan
        }
    
    def set_result(self, result, is_gpt4 = False):
        if is_gpt4:
            self.result_gpt4 = result
        else:
            self.result = result

    def get_result(self, is_gpt4 = False):
        result = self.result
        return None if result == '' else result
    def get_result_CN(self):
        result = self.result_gpt4
        return None if result == '' else result
    def get_category(self):
        result = self.category
        return None if result == '' else result
    def get_key(self):
        key = "/".join([self.name, self.content,self.keyword])
        # key = str(random.random())
        return str_hash(key)
    def get_similarity_with_rule(self):
        result = self.similarity_with_rule
        return None if result == '' else result


