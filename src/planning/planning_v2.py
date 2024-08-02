import random
import time
import requests
from library.chatgpt_api2 import *
from dao.entity import Project_Task
import os, sys
from tqdm import tqdm
import pickle
from library.vectorutils import get_top_k_similar, find_elbow_point, plot_elbow_curve
from library.embedding_api import get_embbedding
import re

'''
根据每个function 的 functionality embbeding 匹配结果 
'''
class PlanningV2(object):
    def __init__(self, llm, project,taskmgr) -> None:
        self.llm = llm
        self.project = project
        self.taskmgr=taskmgr
        self.scan_list_for_larget_context=[]


    def ask_openai_for_business_flow(self,function_name,contract_code_without_comment):
        prompt=f"""
        Based on the code above, analyze the business flows that start with the {function_name} function, consisting of multiple function calls. The analysis should adhere to the following requirements:
        1. only output the one sub-business flows, and must start from {function_name}.
        2. The output business flows should only involve the list of functions of the contract itself (ignoring calls to other contracts or interfaces, as well as events).
        3. After step-by-step analysis, output one result in JSON format, with the structure: {{"{function_name}":[function1,function2,function3....]}}
        4. The business flows must include all involved functions without any omissions

        """
        question=f"""

        {contract_code_without_comment}
        \n
        {prompt}

        """
        api_base= os.getenv('OPENAI_API_BASE', 'api.openai.com')  # Replace with your actual OpenAI API base URL
        api_key = os.getenv('OPENAI_API_KEY')  # Replace with your actual OpenAI API key
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}"
        }
        data = {
            "model": os.getenv('BUSINESS_FLOW_MODEL_ID'),
            "response_format": { "type": "json_object" },
            "messages": [
                {
                    "role": "system",
                    "content": "You are a helpful assistant designed to output JSON."
                },
                {
                    "role": "user",
                    "content": question
                }
            ]
        }
        response = requests.post(f'https://{api_base}/v1/chat/completions', headers=headers, json=data)

        response_josn = response.json()
        if 'choices' not in response_josn:
            return ''
        return response_josn['choices'][0]['message']['content']
    def extract_filtered_functions(self, json_string):
        """
        Extracts function names from a JSON string. For function names and keys containing a period,
        only the substring after the last period is included. The key is included as the first
        element in the returned list, processed in the same way as the functions.

        :param json_string: A string representation of a JSON object.
        :return: A list of the processed key followed by its corresponding filtered function names.
        """
        # Load the JSON data into a Python dictionary
        json_string=json_string.replace("```json",'"')
        data = json.loads(json_string)

        # Initialize the result list
        result_list = []

        # Process each key-value pair in the dictionary
        for key, functions in data.items():
            # Process the key in the same way as function names
            result_list.append(key)
            
            # Extend the list with filtered function names
            filtered_functions = [function for function in functions]
            result_list.extend(filtered_functions)

        # Remove duplicates by converting to a set and back to a list
        return list(set(result_list))
    def extract_and_concatenate_functions_content(self,function_lists, contract_info):
        """
        Extracts the content of functions based on a given function list and contract info,
        and concatenates them into a single string.
        
        :param function_lists: A list of function names.
        :param contract_info: A dictionary representing a single contract's information, including its functions.
        :return: A string that concatenates all the function contents from the function list.
        """
        concatenated_content = ""

        # Get the list of functions from the contract info
        functions = contract_info.get("functions", [])

        # Create a dictionary for quick access to functions by name
        function_dict = {str(function["name"]).split(".")[1]: function for function in functions}

        # Loop through each function name in the provided function list
        for function_name in function_lists:
            # Find the function content by name
            function_content = function_dict.get(function_name, {}).get("content")
            
            # If function content is found, append it to the concatenated_content string
            if function_content is not None:
                concatenated_content += function_content + "\n"

        return concatenated_content.strip()
    def extract_results(self,text):
        if text is None:
            return []
        # 定义一个正则表达式来匹配包含关键字 "result" 的JSON对象
        regex = r'\{.*?\}'

        # 使用正则表达式查找所有匹配项
        matches = re.findall(regex, text)

        # 解析找到的每个匹配项
        json_objects = []
        for match in matches:
            try:
                json_obj = json.loads(match)
                json_objects.append(json_obj)
            except json.JSONDecodeError:
                pass  # 在这里可以处理JSON解析错误

        return json_objects

    def get_vul_from_code(self,content,keyconcept):
        response=''
        varaibles = {
            "content": content,
            "keyconcept": keyconcept
        }
        response = self.llm.completion("getVulV41205", varaibles)
        return response
    # Function to merge two rulesets based on sim_score
    def merge_and_sort_rulesets(self,high, medium):
        # Combine the two rulesets
        # combined_ruleset = high # only high
        combined_ruleset = high + medium
        # Sort the combined ruleset based on sim_score in descending order
        combined_ruleset.sort(key=lambda x: x['sim_score'], reverse=True)
        return combined_ruleset
    def decode_business_flow_list_from_response(self, response):
        # 正则表达式用于匹配形如 {xxxx:[]} 的结果
        pattern = r'({\s*\"[a-zA-Z0-9_]+\"\s*:\s*\[[^\]]*\]\s*})'

        # 使用正则表达式找到所有匹配项
        matches = re.findall(pattern, response)

        # 初始化一个集合用于去重
        unique_functions = set()

        # 遍历所有匹配项
        for match in matches:
            # 尝试将匹配的字符串转换为JSON对象
            try:
                json_obj = json.loads(match)
                # 遍历JSON对象中的所有键（即函数名）
                for key in json_obj:
                    # 将键（函数名）添加到集合中去重
                    unique_functions.add(key)
                    # 遍历对应的值（即函数列表），并将它们也添加到集合中去重
                    for function in json_obj[key]:
                        unique_functions.add(function)
            except json.JSONDecodeError:
                # 如果匹配的字符串不是有效的JSON格式，则忽略错误
                pass

        # 将集合转换为列表并返回
        return list(unique_functions)
    def identify_contexts(self, functions_to_check):
        """
        Identify sub-calls and parent-calls for each function in functions_to_check,
        only including calls that are not in the same contract.
        Returns a dictionary with function names as keys and their sub-calls and parent-calls as values,
        including the content of the sub-calls and parent-calls.
        """
        contexts = {}
        calls = {function["name"]: {"sub_calls": set(), "parent_calls": set()} for function in functions_to_check}

        for function in functions_to_check:
            function_name = function["name"]
            function_content = function["content"]
            function_contract_name = function["contract_name"]

            for other_function in functions_to_check:
                other_function_name = other_function["name"]
                other_function_content = other_function["content"]
                other_function_contract_name = other_function["contract_name"]

                # Check if the other function is not in the same contract
                if function_contract_name != other_function_contract_name:
                    if function_name.split(".")[1] in other_function_content:
                        calls[function_name]["parent_calls"].add((other_function_name, other_function_content))

                    if other_function_name.split(".")[1] in function_content:
                        calls[function_name]["sub_calls"].add((other_function_name, other_function_content))
        
        for function_name, call_data in calls.items():
            contexts[function_name] = {
                "sub_calls": [{"name": name, "content": content} for name, content in call_data["sub_calls"]],
                "parent_calls": [{"name": name, "content": content} for name, content in call_data["parent_calls"]]
            }

        return contexts


    def get_all_business_flow(self,functions_to_check):
        """
        Extracts all business flows for a list of functions.
        :param functions_to_check: A list of function names to extract business flows for.
        :return: A dictionary containing all business flows for each contract.
        The keys of the dictionary are the contract names, and the values are dictionaries containing the business flows for each public/external function.
        """
        from library.sgp.utilities.contract_extractor import group_functions_by_contract
        from library.sgp.utilities.contract_extractor import check_function_if_public_or_external
        from library.sgp.utilities.contract_extractor import check_function_if_view_or_pure

        grouped_functions = group_functions_by_contract(functions_to_check)
        contexts = self.identify_contexts(functions_to_check)
        # 遍历grouped_functions，按每个合约代码进行业务流抽取
        all_business_flow = {}
        all_business_flow_line={}
        all_business_flow_context = {}
        print("grouped contract count:",len(grouped_functions))
        
        for contract_info in grouped_functions:
            print("———————————————————————processing contract_info:",contract_info['contract_name'],"—————————————————————————")
            contract_name = contract_info['contract_name']
            functions = contract_info['functions']
            contract_code_without_comments = contract_info['contract_code_without_comment']  # Assuming this is the correct key

            # 初始化合约名字典
            all_business_flow[contract_name] = {}
            all_business_flow_line[contract_name]={}
            all_business_flow_context[contract_name] = {}
            # 提取所有的public和external函数的name，且这些函数不能是view或pure函数
            if "_rust" in str(contract_name) or contract_name is None:
                all_public_external_function_names = [
                    function['name'].split(".")[1] for function in functions
                    # if function['visibility']=='public' #有些private函数也可能是业务流的起点，还是扫一下
                ]
            elif "_python" in str(contract_name) or contract_name is None:
                all_public_external_function_names = [
                    function['name'].split(".")[1] for function in functions
                ]
            elif "_move" in str(contract_name) or contract_name is None:
                all_public_external_function_names = [
                    function['name'].split(".")[1] for function in functions if function['visibility']=='public'
                ]
            elif "_cairo" in str(contract_name) or contract_name is None:
                all_public_external_function_names = [
                    function['name'].split(".")[1] for function in functions if function['visibility']=='public'
                ]
            elif "_tact" in str(contract_name) or contract_name is None:
                all_public_external_function_names = [
                    function['name'].split(".")[1] for function in functions if function['visibility']=='public'
                ]
            elif "_func" in str(contract_name) or contract_name is None:
                all_public_external_function_names = [
                    function['name'].split(".")[1] for function in functions if function['visibility']=='public'
                ]
            else:
                all_public_external_function_names = [
                    function['name'].split(".")[1] for function in functions
                    if check_function_if_public_or_external(function['content'])
                    # and not check_function_if_view_or_pure(function['content'])
                ]
            print("all_public_external_function_names count:",len(all_public_external_function_names))
            if len(self.scan_list_for_larget_context)>0 and contract_name not in self.scan_list_for_larget_context:
                continue
            # 有了函数名列表，有了contract_code_without_comments，可以进行业务流的GPT提问了
            print("-----------------asking openai for business flow-----------------")
            for public_external_function_name in all_public_external_function_names:
                print("***public_external_function_name***:",public_external_function_name)
                if "_python" in str(contract_name) and len(all_public_external_function_names)==1:
                    key = all_public_external_function_names[0]
                    data = {key: all_public_external_function_names}
                    business_flow_list = json.dumps(data)
                else:
                    try:
                        business_flow_list = self.ask_openai_for_business_flow(public_external_function_name, contract_code_without_comments)
                    except Exception as e:
                        business_flow_list=[]
                if len(business_flow_list)==0:
                    continue
                # 返回一个list，这个list中包含着多条从public_external_function_name开始的业务流函数名
                try:
                    function_lists = self.extract_filtered_functions(business_flow_list)
                except Exception as e:
                    print(e)  
                print("business_flow_list:",function_lists)
                # 从functions_to_check中提取start_line和end_line行数
                # 然后将start_line和end_line行数对应的代码提取出来，放入all_business_flow_line
                
                def get_function_structure(functions, function_name):
                    for func in functions:
                        if func['name'] == function_name:
                            return func
                    return None
                line_info_list = []
                for function in function_lists:
                    if str(function)=="-1":
                        continue
                    function_name_to_search=contract_name+"."+function
                    function_structure=get_function_structure(functions, function_name_to_search)
                    if function_structure is not None:
                        start_line=function_structure['start_line']
                        end_line=function_structure['end_line']
                        line_info_list.append((start_line, end_line))

                # 获取拼接后的业务流代码
                ask_business_flow_code = self.extract_and_concatenate_functions_content(function_lists, contract_info)

                # 在 contexts 中获取扩展后的业务流内容
                extended_flow_code = ""
                for function in function_lists:
                    context = contexts.get(contract_name + "." + function, {})
                    parent_calls = context.get("parent_calls", [])
                    sub_calls = context.get("sub_calls", [])
                    for call in parent_calls + sub_calls:
                        extended_flow_code += call["content"] + "\n"
                all_business_flow_context[contract_name][public_external_function_name] = extended_flow_code.strip()
                # 将结果存储为键值对，其中键是函数名，值是对应的业务流代码
                all_business_flow[contract_name][public_external_function_name] = ask_business_flow_code
                all_business_flow_line[contract_name][public_external_function_name] = line_info_list
        return all_business_flow,all_business_flow_line,all_business_flow_context    
        # 此时 all_business_flow 为一个字典，包含了每个合约及其对应的业务流
    
    def search_business_flow(self,all_business_flow, all_business_flow_line,all_business_flow_context, function_name, contract_name):
        """
        Search for the business flow code based on a function name and contract name.

        :param all_business_flow: The dictionary containing all business flows.
        :param function_name: The name of the function to search for.
        :param contract_name: The name of the contract where the function is located.
        :return: The business flow code if found, or a message indicating it doesn't exist.
        """
        # Check if the contract_name exists in the all_business_flow dictionary
        if contract_name in all_business_flow:
            # Check if the function_name exists within the nested dictionary for the contract
            contract_flows = all_business_flow[contract_name]
            contract_flows_line=all_business_flow_line[contract_name]
            contract_flows_context=all_business_flow_context[contract_name]
            if function_name in contract_flows:
                # Return the business flow code for the function
                return contract_flows[function_name],contract_flows_line[function_name],contract_flows_context[function_name]
            else:
                # Function name not found within the contract's business flows
                return "not found","",""
        else:
            # Contract name not found in the all_business_flow dictionary
            return "not found","",""
    def do_planning(self):
        tasks = []
        print("Begin do planning...")
        switch_function_code=eval(os.getenv('SWITCH_FUNCTION_CODE','False'))
        switch_business_code=eval(os.getenv('SWITCH_BUSINESS_CODE','True'))
        tasks = self.taskmgr.get_task_list_by_id(self.project.project_id)
        if len(tasks) > 0:
            return 
        # filter all "test" function
        for function in self.project.functions_to_check:
            name=function['name']
            if "test" in name:
                self.project.functions_to_check.remove(function)

        if switch_business_code:
            all_business_flow,all_business_flow_line,all_business_flow_context=self.get_all_business_flow(self.project.functions_to_check)                    
        
        # Process each function with optimized threshold
        for function in tqdm(self.project.functions_to_check, desc="Finding project rules"):
            
            
            name = function['name']
            content = function['content']
            contract_code=function['contract_code']
            contract_name=function['contract_name']
            # if len(self.scan_list_for_larget_context)>0 and contract_name not in self.scan_list_for_larget_context:
            #     continue
            task_count = 0
            print(f"————————Processing function: {name}————————")
            # business_task_item_id = 
            if switch_business_code:
                business_flow_code,line_info_list,other_contract_context=self.search_business_flow(all_business_flow, all_business_flow_line,all_business_flow_context, name.split(".")[1], contract_name)
                if business_flow_code != "not found":
                    for i in range(int(os.getenv('BUSINESS_FLOW_COUNT', 1))):
                        task = Project_Task(
                            project_id=self.project.project_id,
                            name=name,
                            content=content,
                            keyword=str(random.random()),
                            business_type='',
                            sub_business_type='',
                            function_type='',
                            rule='',
                            result='',
                            result_gpt4='',
                            score='',
                            category='',
                            contract_code=contract_code,
                            risklevel='',
                            similarity_with_rule='',
                            description='',
                            start_line=function['start_line'],
                            end_line=function['end_line'],
                            relative_file_path=function['relative_file_path'],
                            absolute_file_path=function['absolute_file_path'],
                            recommendation='',
                            title='',
                            business_flow_code=str(business_flow_code)+"\n"+str(content),
                            business_flow_lines=line_info_list,
                            business_flow_context=other_contract_context,
                            if_business_flow_scan=1  # Indicating scanned using business flow code
                        )
                        self.taskmgr.add_task_in_one(task)
                        task_count += 1
            
            if switch_function_code:
                for i in range(int(os.getenv('BUSINESS_FLOW_COUNT', 1))):
                    task = Project_Task(
                        project_id=self.project.project_id,
                        name=name,
                        content=content,
                        keyword=str(random.random()),
                        business_type='',
                        sub_business_type='',
                        function_type='',
                        rule='',
                        result='',
                        result_gpt4='',
                        score='',
                        category='',
                        contract_code=contract_code,
                        risklevel='',
                        similarity_with_rule='',
                        description='',
                        start_line=function['start_line'],
                        end_line=function['end_line'],
                        relative_file_path=function['relative_file_path'],
                        absolute_file_path=function['absolute_file_path'],
                        recommendation='',
                        title='',
                        business_flow_code='',
                        business_flow_lines='',
                        business_flow_context='',
                        if_business_flow_scan=0  # Indicating scanned using function code
                    )
                    self.taskmgr.add_task_in_one(task)
                    task_count += 1

            
        # return tasks    

