from library.sgp.sgp_parser import get_antlr_parsing
from library.parsing.callgraph import CallGraph
import os
import re

from library.sgp.utilities.contract_extractor import extract_state_variables_from_code
from .project_settings import FILE_PARTIAL_WHITE_LIST, PATH_PARTIAL_WHITE_LIST, PATH_WHITE_LIST, OPENZEPPELIN_CONTRACTS,OPENZEPPELIN_FUNCTIONS

class Function(dict):
    def __init__(self, file, contract, func):
        self.file = file
        self.contract = contract
        self.update(func)


def parse_project_cg(project_path):
    cg = CallGraph(project_path)
    
    function_list = []
    for file, contract, func in cg.functions_iterator():
        func_text = cg.get_function_src(file, func)
        # print(file, contract['name'], func['name'], func_text)

        f = Function(file, contract, func)
        f['name'] = contract['name'] + '.' + func['name']
        f['content'] = func_text
        function_list.append(f)

    function_list = [result for result in function_list if result['kind'] == 'function']

    return function_list

def is_path_in_white_list(haystack, white_list, partial):
    if partial:
        for item in white_list:
            if item in haystack:
                return True
    else:
        for p in haystack.split("/"):
            ds = filter(lambda x: x == p, white_list)
            if len(list(ds)) > 0:
                return True
    return False
            

class BaseProjectFilter(object):

    def __init__(self, white_files = [], white_functions = []):
        self.white_files = white_files
        self.white_functions = white_functions
        pass

    def filter_file(self, path, filename):
        # 检查文件后缀
        valid_extensions = ('.sol', '.rs', '.py', '.move', '.cairo', '.tact', '.fc', '.fr','.java')
        if not any(filename.endswith(ext) for ext in valid_extensions) or filename.endswith('.t.sol'):
            return True

        # 如果白名单不为空，检查文件是否在白名单中
        if len(self.white_files) > 0:
            return not any(os.path.basename(filename) in white_file for white_file in self.white_files)
            # return os.path.(filename) not in self.white_files

        # # 黑名单规则检查
        # if is_path_in_white_list(path, PATH_PARTIAL_WHITE_LIST, True) \
        #         or is_path_in_white_list(path, PATH_WHITE_LIST, False) \
        #         or is_path_in_white_list(filename, FILE_PARTIAL_WHITE_LIST, True):
        #     return True

        # 如果白名单不为空，检查文件是否在白名单中
        if len(self.white_files) > 0:
            return os.path.basename(filename) not in self.white_files

        return False
        #self.files[os.path.abspath(os.path.join(path, file))] = parseString(open(os.path.join(path, file), "r", encoding="utf-8", errors="ignore").read())

    def check_function_code_if_statevar_assign(self, function_code,contract_code):
        state_vars=extract_state_variables_from_code(contract_code)
        nodes = function_code.split(';')
        # 判断每个操作是否是对状态变量的赋值
        for node in nodes:
            if '=' in node:
                # 获取等号左边的内容
                left_side = node.split('=')[0].strip()
                # 检查是否有状态变量
                for var in state_vars:
                    if re.search(r'\b' + re.escape(var) + r'\b', left_side):
                        return True
        return False
    def filter_contract(self, function):
        # rust情况下，不进行筛选
        if '_rust' in function["name"]:
            return False
        if '_python' in function["name"]:
            return False
        if '_move' in function["name"]:
            return False
        if '_cairo' in function["name"]:
            return False
        if '_tact' in function["name"]:
            return False
        if '_func' in function["name"]:
            return False
        if '_fa' in function["name"]:
            return False
        # solidity情况下，进行筛选
        if str(function["contract_name"]).startswith("I") and function["contract_name"][1].isupper():
            print("function ", function['name'], " skipped for interface contract")
            return True
        if "test" in str(function["name"]).lower():
            print("function ", function['name'], " skipped for test function")
            return True
        # if str(function["name"].split('.')[1]) in OPENZEPPELIN_FUNCTIONS:
        #     print("function ", function['name'], " skipped for OZ functions")
        #     return True


        # if "interface " in function['contract_code']:
        #     print("function ", function['name'], " skipped for interface contract")
        # if str(function["contract_name"]).startswith("I"):
        #     print("function ", function['name'], " skipped for interface contract")
        if "function init" in str(function["content"]).lower() or "function initialize" in str(function["content"]).lower() or "constructor(" in str(function["content"]).lower() or "receive()" in str(function["content"]).lower() or "fallback()" in str(function["content"]).lower():
            print("function ", function['name'], " skipped for constructor")
            return True
        # if str(function["content"]).count(';')*1<=2:
        #     print("function ", function['name'], " skipped for node count")
        #     return True
        # if str(function['contract_name']) in OPENZEPPELIN_CONTRACTS:
        #     print("function ", function['name'], " skipped for contract filter")
        #     return True

        # if not self.check_function_code_if_statevar_assign(function['content'],function['contract_code']):
        #     print("function ", function['name'], " skipped for statevar assign")
        #     return True
        # if ("require(msg.sender" in str(function["content"]).lower() and "tx.origin" not in str(function["content"])) or "== msg.sender" in str(function["content"]).lower() or "==msg.sender" in str(function["content"]).lower():
        #     print("function ", function['name'], " skipped for onlyowner")
        #     return True
        # if "onlyOwner" in str(function["content"]):
        #     print("function ", function['name'], " skipped for onlyowner")
        #     return True
        # if re.search(r'.*?(set|get)\s*[A-Z]', function['name']):
        #     print("function ", function['name'], " skipped for set/get pattern")
        #     return True
        # if any(re.search(r'.*?(only)\s*[A-Z]', mod) for mod in str(function['content'])):
        #     print("function ", function['name'], " skipped for onlyXXX pattern in modifiers")
        #     return True
        

        return False
    
    def filter_functions(self, function):
        # Step 3: function 筛选 ( 白名单检查 )
        if len(self.white_functions) == 0:
            return False
        return function['name'] not in self.white_functions


def parse_project(project_path, project_filter = None):

    if project_filter is None:
        project_filter = BaseProjectFilter([], [])

    ignore_folders = set()
    if os.environ.get('IGNORE_FOLDERS'):
        ignore_folders = set(os.environ.get('IGNORE_FOLDERS').split(','))
    ignore_folders.add('.git')
    all_results = []
    for dirpath, dirs, files in os.walk(project_path):
        dirs[:] = [d for d in dirs if d not in ignore_folders]
        for file in files:
            to_scan = not project_filter.filter_file(dirpath, file)
            sol_file = os.path.join(dirpath, file) # relative path
            absolute_path = os.path.abspath(sol_file)  # absolute path
            print("parsing file: ", sol_file, " " if to_scan else "[skipped]")
            
            if to_scan:
                results = get_antlr_parsing(sol_file)
                for result in results:
                    result['relative_file_path'] = sol_file
                    result['absolute_file_path'] = absolute_path
                all_results.extend(results)
    
    functions = [result for result in all_results if result['type'] == 'FunctionDefinition']
    # fix func name 
    fs = []
    for func in functions:
        name = func['name'][8:] # remove special_前缀，具体为啥我也忘了，似乎是为了考虑特定的function name
        func['name'] = "%s.%s" % (func['contract_name'], name)
        fs.append(func)

    fs_filtered = fs[:]
    # 2. filter contract 
    fs_filtered = [func for func in fs_filtered if not project_filter.filter_contract(func)]

    # 3. filter functions 
    fs_filtered = [func for func in fs_filtered if not project_filter.filter_functions(func)]

    return fs, fs_filtered 


if __name__ == '__main__':
    from library.dataset_utils import load_dataset
    dataset_base = "../../dataset/agent-v1-c4"
    projects = load_dataset(dataset_base)
    project = projects['whalefall']

    project_path = os.path.join(project['base_path'], project['path'])
    white_files, white_functions = project.get('files', []), project.get('functions', [])

    parser_filter = BaseProjectFilter(white_files, white_functions)
    functions, functions_to_check = parse_project(project_path, parser_filter)

    print(functions_to_check)