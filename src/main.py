import argparse
import ast
import os
import time
import audit_config
from ai_engine import *
from project import ProjectAudit
from library.dataset_utils import load_dataset, Project
from planning import PlanningV2
from prompts import prompts
from sqlalchemy import create_engine
from dao import CacheManager, ProjectTaskMgr

def scan_project(project, db_engine):
    # 1. parsing projects  
    project_audit = ProjectAudit(project.id, project.path, db_engine)
    project_audit.parse(project.white_files, project.white_functions)

    # 2. planning & scanning
    project_taskmgr = ProjectTaskMgr(project.id, db_engine) 
    
    planning = PlanningV2(project_audit, project_taskmgr)
    # 
    engine = AiEngine(planning, project_taskmgr)
    # 1. 扫描 
    engine.do_planning()
    engine.do_scan()
    
    # 2. gpt4 对结果做rescan 
    # rescan_project_with_gpt4(project.id, db_engine)

def check_function_vul(engine):
    project_taskmgr = ProjectTaskMgr(project.id, engine)
    engine = AiEngine(None, project_taskmgr)
    engine.check_function_vul()
    # print(result)
def generate_json(output_path,project_id):
    project_taskmgr = ProjectTaskMgr(project_id, engine)
    entities=project_taskmgr.query_task_by_project_id(project.id)
    json_results = {
        "version": "1.0.0",
        "success": True,
        "message": None,
        "results": [],
        "fileMapping": {}
    }

    for entity in entities:
        if float(entity.similarity_with_rule) < 0.82:
            continue
        if '"result": "no"' in str(entity.description):
            continue
        line_info_list = entity.business_flow_lines  # 每个元素是一个(start_line, end_line)元组
                # 移除字符串两端的单引号或双引号（如果有的话）
        line_info_str = line_info_list.strip('"\'') 
        line_info_set = ast.literal_eval(line_info_str)
        line_info_list = list(line_info_set)
        line_info_tuples = [ast.literal_eval(item) for item in line_info_list]
        # 根据line_info_list创建多个affectedFiles条目
        affected_files_list = []
        for start_line, end_line in line_info_tuples:
            affected_file = {
                "filePath": entity.relative_file_path,  # Assuming entity has a relative_file_path attribute
                "range": {
                    "start": {"line": int(start_line)},
                    "end": {"line": int(end_line)}
                },
                "highlights": []
            }
            affected_files_list.append(affected_file)

        result_obj = {
            "code": "logic-error",
            "severity": "HIGH",
            "title": entity.title,  # Assuming entity has a title attribute
            "description": entity.description,  # Assuming entity has a description attribute
            "recommendation": entity.recommendation,
            "affectedFiles": affected_files_list
        }
        json_results["results"].append(result_obj)

    # Convert the constructed structure to JSON format
    json_string = json.dumps(json_results, indent=4)

    # Save the JSON to a file
    file_name = output_path  # You can change the file name as needed
    with open(file_name, 'w') as file:
        file.write(json_string)
if __name__ == '__main__':

    switch_production_or_test = 'test' # prod / test

    if switch_production_or_test == 'test':
        start_time=time.time()
        db_url_from = os.getenv("DATABASE_URL")
        engine = create_engine(db_url_from)
        
        dataset_base = "./src/dataset/agent-v1-c4"
        projects = load_dataset(dataset_base)

        project_id = 'shanxuan1212'
        project_path = ''
        project = Project(project_id, projects[project_id])
        
        cmd = 'detect_vul'
        if cmd == 'detect_vul':
            scan_project(project, engine) # scan
            check_function_vul(engine) # confirm
        elif cmd == 'check_vul_if_positive':
            check_function_vul(engine) # confirm

        end_time=time.time()
        print("Total time:",end_time-start_time)
        generate_json("output.json",project_id)
        
        
    if switch_production_or_test == 'prod':
        # Set up command line argument parsing
        parser = argparse.ArgumentParser(description='Process input parameters for vulnerability scanning.')
        parser.add_argument('-path', type=str, required=True, help='Combined base path for the dataset and folder')
        parser.add_argument('-id', type=str, required=True, help='Project ID')
        parser.add_argument('-cmd', type=str, choices=['detect_vul', 'check_vul_if_positive'], required=True, help='Command to execute')
        parser.add_argument('-o', type=str, required=True, help='Output file path')
        # usage:
        # python main.py 
        # --path ../../dataset/agent-v1-c4/Archive 
        # --id Archive_aaa 
        # --cmd detect_vul

        # Parse arguments
        args = parser.parse_args()

        # Split dataset_folder into dataset and folder
        dataset_base, folder_name = os.path.split(args.path)

        # Start time
        start_time = time.time()

        # Database setup
        db_url_from = os.getenv("DATABASE_URL")
        engine = create_engine(db_url_from)

        # Load projects
        projects = load_dataset(dataset_base, args.id, folder_name)
        project = Project(args.id, projects[args.id])

        # Execute command
        if args.cmd == 'detect_vul':
            scan_project(project, engine, True)  # scan
            content = ''' '''
            rule = ''' '''
            check_function_vul(content, engine, True)  # confirm
        elif args.cmd == 'check_vul_if_positive':
            content = ''' '''
            rule = ''' '''
            check_function_vul(content, engine, True)  # confirm

        project_taskmgr = ProjectTaskMgr(project.id, engine)
        print(project_taskmgr.query_task_by_project_id(project.id))
        # End time and print total time
        end_time = time.time()
        print("Total time:", end_time -start_time)
        generate_json(args.o,project.id)




