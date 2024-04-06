import subprocess
from . import parseString
import os, sys
import logging
import json
from typing import List, Dict, Tuple, Set
import re

logger = logging.getLogger(__name__)

current_path = os.path.abspath(os.path.dirname(__file__))
whitelist = json.load(open(os.path.join(current_path, "whitelist.json")))
modifier_whitelist = json.load(open(os.path.join(current_path, "modifier_whitelist.json")))

def is_in_whitelist(contract_name: str, function_name: str, content: str, visibility: str) -> bool:
    signatures = generate_signatures(contract_name, function_name, content)
    loc = get_loc(content)
    for signature in signatures:
        signature = re.sub(r"uint\d+", "uint", signature)
        signature = re.sub(r"int\d+", "int", signature)
        if signature in whitelist and whitelist[signature]["lines"] <= loc+2 and whitelist[signature]["lines"] >= loc-2:
            logger.info("In whitelist: {}".format(signature))
            return True
    return False


def generate_signatures(contract: dict, function_name: str, content: str) -> List[str]:
    signatures = []
    names = contract["inheritance"]
    names.append(contract["name"])
    for inherit in names:
        signature: str = inherit+"."+function_name+"("

        def_content = content.split("{")[0].strip()

        param_types = []
        params = content.split("(")[1].split(")")[0].split(",")
        for param in params:
            if param == "":
                continue
            param_type = param.strip().split(" ")[0]
            param_types.append(param_type)
        signature += ",".join(param_types)+") returns("

        if "returns" in def_content:
            return_types = def_content.split("returns")[1].split(
                "(")[1].split(")")[0].strip().split(",")
            signature += ",".join(map(lambda x: x.strip(), return_types))+")"
        elif "return" in def_content:
            return_type = def_content.split("return")[1].strip().split(" ")[0]
            signature += return_type+")"
        else:
            signature += ")"

        signatures.append(signature)
        if signature.startswith("I") and signature[1].isupper():
            signatures.append(signature[1:])
    # logger.info("Signatures: " + str(signatures))
    return signatures


def is_empty_function(content: str) -> bool:
    if "{" not in content:
        return True
    body = content[content.index("{")+1:content.rindex("}")].strip()
    empty_line_num = len(body.split("\n\n")) - 1
    if body == "":
        return True
    elif len(body.split(";")) + empty_line_num <= 3:
        return True
    return False


def get_loc(content: str) -> int:
    return len(list(filter(lambda x: x != "", content.splitlines())))


def is_in_modifier_whitelist(content: str) -> bool:
    if "{" not in content:
        def_content = content.strip()
    else:
        def_content = content.split("{")[0].strip()
    for modifier in modifier_whitelist:
        if modifier in def_content:
            return True
    return False

class CallGraph:
    def __init__(self, root:str) -> None:
        self.root = root
        self.files = {}
        self.call_data = {}

        self.__parse_all_files()
        self.__run_jar()

        self.__clean()
    
    def get_rel_path(self, path:str)->str:
        return os.path.relpath(path, self.root)

    def __parse_all_files(self):
        for root, dirs, files in os.walk(self.root):
            for file in files:
                if "node_modules" in file or "node_modules" in root:
                    continue
                if "test" in root.lower() or "tests" in root.lower() or "testing" in root.lower() or "unittest" in root.lower() or "unit_test" in root.lower() or "unit tests" in root.lower() or "unit_testing" in root.lower():
                    continue
                if "external" in root.lower():
                    continue
                if "openzeppelin" in root.lower():
                    continue
                if "uniswap" in root.lower():
                    continue
                if "pancakeswap" in root.lower():
                    continue
                if "legacy" in root.lower():
                    continue
                if "@" in root.lower():
                    continue
                # 61 needs 'mocks' for FirstDeposit
                #if "mocks" in root.lower(): # 23-2021-08-notional
                #    continue
                if "mock" in root.lower() and "mocks" not in root.lower():
                    continue
                continue_flag = False
                for folder in root.split("/"):
                    if folder == "lib":
                        continue_flag = True
                        break
                if continue_flag:
                    continue
                if file.endswith(".sol"):
                    if re.search("ERC\\d{2,}.*\\.sol", file):
                        continue
                    if re.search("BEP\\d{2,}.*\\.sol", file):
                        continue
                    self.files[os.path.abspath(os.path.join(root, file))] = parseString(open(os.path.join(root, file), "r", encoding="utf-8", errors="ignore").read())

    def __run_jar(self):
        dir_name = os.path.abspath(os.path.dirname(__file__))
        jar_file = os.path.join(dir_name, "jars/SolidityCallgraph-1.0-SNAPSHOT-standalone.jar")
        subprocess.run(["java", "-jar", jar_file, self.root, "callgraph.json"], stdout=subprocess.DEVNULL)
        self.call_data = json.load(open("callgraph.json", "r"))


    def __clean(self):
        # clean parse result first
        self_file_to_remove_functions = {}
        for file, file_data in self.files.items():
            self_file_to_remove_functions[file] = {}
            for contract_data in file_data["subcontracts"]:
                self_file_to_remove_functions[file][contract_data["name"]] = []
                for function_data in contract_data["functions"]:
                    function_content = "\n".join(open(file, errors="ignore").read().splitlines()[int(function_data["loc"]["start"].split(":")[0])-1:int(function_data["loc"]["end"].split(":")[0])])
                    if function_data["kind"] != "function":
                        self_file_to_remove_functions[file][contract_data["name"]].append(function_data)
                        continue
                    if is_empty_function(function_content):
                        self_file_to_remove_functions[file][contract_data["name"]].append(function_data)
                        continue
                    if is_in_whitelist(contract_data, function_data["name"], function_content, function_data["visibility"]):
                        self_file_to_remove_functions[file][contract_data["name"]].append(function_data)
                        continue
                    if is_in_modifier_whitelist(function_content):
                        self_file_to_remove_functions[file][contract_data["name"]].append(function_data)
                        continue
        
        for file, file_data in self.files.items():
            for contract_data in file_data["subcontracts"]:
                for function_data in contract_data["functions"].copy():
                    if function_data in self_file_to_remove_functions[file][contract_data["name"]]:
                        contract_data["functions"].remove(function_data)

        # clean call data
        for file in self.call_data.copy():
            if file not in self.files:
                self.call_data.pop(file)
                continue
            for contract in self.call_data[file].copy():
                match_contract_flag = False
                matched_contract = None
                for contract_ in self.files[file]["subcontracts"]:
                    if contract_["name"] == contract:
                        match_flag = True
                        matched_contract = contract_
                        break
                if match_flag == False:
                    self.call_data[file].pop(contract)
                    continue
                for function in self.call_data[file][contract].copy():
                    match_function_flag = False
                    for function_ in matched_contract["functions"]:
                        if function_["name"] == function:
                            match_function_flag = True
                            break
                    if match_function_flag == False:
                        self.call_data[file][contract].pop(function)
                        continue

    def get_callers(self, function:str)->List[Tuple[str, str, str]]:
        result = []
        for file in self.call_data:
            for contract in self.call_data[file]:
                for function_ in self.call_data[file][contract]:
                    if function not in self.call_data[file][contract][function_]:
                        continue
                    for callee in self.call_data[file][contract][function_]:
                        if callee == function:
                            result.append((file, contract, function_))
        return result
    

    def get_callees(self, file:str, contract:str, function:str)->List[Tuple[str, str, str]]:
        functions = []
        for file_ in self.call_data:
            if self.get_rel_path(file) == self.get_rel_path(file_):
                if contract not in self.call_data[file_]:
                    continue
                if function not in self.call_data[file_][contract]:
                    continue
                functions.extend(self.call_data[file_][contract][function])
        # find functions in files
        result = []
        for file_ in self.files:
            for contract_ in self.files[file_]["subcontracts"]:
                for func in contract_["functions"]:
                    if func["name"] in functions:
                        result.append((file_, contract_["name"], func["name"]))
        return result


    def get_function_detail(self, file:str, contract:str, function:str):
        for file_ in self.files:
            if self.get_rel_path(file) == self.get_rel_path(file_):
                data = self.files[file_]
                for contract_ in data["subcontracts"]:
                    if contract_["name"] == contract:
                        for func in contract_["functions"]:
                            if func["name"] == function:
                                return func
                            
    
    def functions_iterator(self):
        for file in self.files:
            for contract in self.files[file]["subcontracts"]:
                for func in contract["functions"]:
                    yield file, contract, func 
            #         file_func_question_map[file][contract["name"]][func["name"]] = []
            #         func_text = "\n".join(open(file, errors='ignore').read().splitlines()[int(
            #             func["loc"]["start"].split(":")[0])-1:int(func["loc"]["end"].split(":")[0])])
            #         file_func_source_map[file][contract["name"]][func["name"]] = func_text
            
            # file_func_question_map[file] = {}
            # file_func_source_map[file] = {}

    def get_function_src(self, file, func):
        func_loc = func["loc"]
        return "\n".join(open(file, errors='ignore').read().splitlines()[int(
            func_loc["start"].split(":")[0])-1:int(func_loc["end"].split(":")[0])])
    