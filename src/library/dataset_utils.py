import os
import json

def function_map_to_white_list(function_map):
    ws = []
    for k, v in function_map.items():
        for f in v:
            ws.append("%s.%s" % (k, f))
    return ws

def load_dataset(dataset_path, external_project_id=None, external_project_path=None):
    # Load projects from datasets.json
    if not external_project_id and not external_project_path:
        ds_json = os.path.join(dataset_path, "datasets.json")
        dj = json.load(open(ds_json, 'r', encoding='utf-8'))
        projects = {}
        for k, v in dj.items():
            if 'functions' in v and isinstance(v['functions'], dict):
                v['functions'] = function_map_to_white_list(v['functions'])

            v['base_path'] = dataset_path
            projects[k] = v

    # Handle external project input
    if external_project_id and external_project_path:
        projects = {}
        # Construct project data structure for the external project
        external_project = {
            'path': external_project_path,
            'files': [],  # You might want to populate this based on actual project files
            'functions': [],  # and functions if applicable
            'base_path': dataset_path
        }

        # Add the external project to the projects dictionary
        projects[external_project_id] = external_project

    return projects


class Project(object):
    def __init__(self, id, project) -> None:
        self.id = id
        self.path = os.path.join(project['base_path'], project['path'])
        self.white_files = project.get('files', [])
        self.white_functions = project.get('functions', [])


if __name__ == '__main__':
    dataset_base = "../../dataset/agent-v1-c4"
    projects = load_dataset(dataset_base)
    project = projects['whalefall']
    print(project)
