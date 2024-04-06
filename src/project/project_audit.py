import csv
from .project_parser import parse_project, BaseProjectFilter

class ProjectAudit(object):

    def __init__(self, project_id, project_path, db_engine):
        self.project_id = project_id
        self.project_path = project_path
        self.functions = []
        self.tasks = []
        self.taskkeys = set()
    
    def parse(self, white_files, white_functions):
        # Step 2 : parsing solidity fles 
        parser_filter = BaseProjectFilter(white_files, white_functions)
        functions, functions_to_check = parse_project(self.project_path, parser_filter)
        
        for function in functions:
            print(function['name'])

        self.functions = functions
        self.functions_to_check = functions_to_check

    def get_function_names(self):
        return set([function['name'] for function in self.functions])


