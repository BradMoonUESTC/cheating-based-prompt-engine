from library.chatgpt_api2 import *
from .audit_rules import AuditRules
from dao.entity import Project_Task
import tqdm

class PlanningV1(object):
    def __init__(self, llm, project) -> None:
        self.llm = llm
        self.project = project
        self.audit_rules = AuditRules()

    def do_planning(self):
        # Step 4: 使用提取出的name和content，结合每一组单词，构造出提问内容
        self.llm.init_conversation()

        for function in tqdm.tqdm(self.project.functions_to_check, desc = "find_project_rules"):
            name = function['name']
            content = function['content']

            tasks = self.find_rule_for_function(name, content)
            yield tasks

    def check_function_vul(self, content, key_sentence, is_gpt4 = False):
        variables={
            "content": content,
            "keyconcept": key_sentence
        }
        return self.llm.completion("check_vul_from_knowledge", variables)
    

    def find_rule_for_function(self, name, content):
        tasks = []
        kws = self.audit_rules.get_keywords_list()
        for index in range(len(kws)):
            kw = kws[index]
            _tasks = self.find_rule_with_keywords(name, content, kw)

            print("find_rule_for_function ", index + 1, name, len(_tasks))
            tasks += _tasks

        return tasks

    def find_rule_with_keywords(self, name, content, keywords):

        ## todo cache 
        response = ''

        variables = {
            "name": name,
            "content": content,
            "keywords": keywords
        }
        response = self.llm.completion("function_type", variables)

        if response is None or "None of the" in response:
            return []
        
        keywords_list = response.replace("[", "").replace("]", "").split(",")
        keywords_list = [k.strip() for k in keywords_list]  # clean up any spaces
        keywords_list = list(filter(lambda x : len(x) > 0, keywords_list))
        
        # search for keywords in csv and store results
        tasks = []
        results = self.audit_rules.filter_rules(keywords_list)
        for keyword, key_sentence, business_type, sub_business_type, function_type in results:
            task = Project_Task(self.project.project_id, name, content, keyword, business_type, sub_business_type, function_type, key_sentence)
            tasks.append(task)
        
        return tasks
    

