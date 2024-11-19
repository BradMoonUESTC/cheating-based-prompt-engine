from concurrent.futures import ThreadPoolExecutor
import json
import re
import threading
import time
from typing import List
import requests
import tqdm
from sklearn.metrics.pairwise import cosine_similarity
from concurrent.futures import ThreadPoolExecutor, as_completed
from tqdm import tqdm
import warnings
import urllib3
warnings.filterwarnings('ignore', category=urllib3.exceptions.NotOpenSSLWarning)
from dao.entity import Project_Task
from prompt_factory.prompt_assembler import PromptAssembler
from prompt_factory.core_prompt import CorePrompt
from openai_api.openai import *
class AiEngine(object):

    def __init__(self, planning, taskmgr,lancedb,lance_table_name,project_audit):
        # Step 1: 获取results
        self.planning = planning
        self.project_taskmgr = taskmgr
        self.lancedb=lancedb
        self.lance_table_name=lance_table_name
        self.project_audit=project_audit
    def do_planning(self):
        self.planning.do_planning()
    def extract_title_from_text(self,input_text):
        try:
            # Regular expression pattern to capture the value of the title field
            pattern = r'"title"\s*:\s*"([^"]+)"'
            
            # Searching for the pattern in the input text
            match = re.search(pattern, input_text)

            # Extracting the value if the pattern is found
            if match:
                return match.group(1)
            else:
                return "Logic Error"
        except Exception as e:
            # Handling any exception that occurs and returning a message
            return f"Logic Error"

    def process_task_do_scan(self,task, filter_func = None, is_gpt4 = False):
        
        response_final = ""
        response_vul = ""

        # print("query vul %s - %s" % (task.name, task.rule))

        result = task.get_result(is_gpt4)
        business_flow_code = task.business_flow_code
        if_business_flow_scan = task.if_business_flow_scan
        function_code=task.content
        
        # 要进行检测的代码粒度
        code_to_be_tested=business_flow_code if if_business_flow_scan=="1" else function_code
        if result is not None and len(result) > 0 and str(result).strip() != "NOT A VUL IN RES no":
            print("\t skipped (scanned)")
        else:
            to_scan = filter_func is None or filter_func(task)
            if not to_scan:
                print("\t skipped (filtered)")
            else:
                print("\t to scan")
                prompt=PromptAssembler.assemble_prompt(code_to_be_tested)
                response_vul=common_ask(prompt)
                print(response_vul)
                response_vul = response_vul if response_vul is not None else "no"                
                self.project_taskmgr.update_result(task.id, response_vul, "","")
    def do_scan(self, is_gpt4=False, filter_func=None):
        # self.llm.init_conversation()

        tasks = self.project_taskmgr.get_task_list()
        if len(tasks) == 0:
            return

        # 定义线程池中的线程数量
        max_threads = 5

        with ThreadPoolExecutor(max_workers=max_threads) as executor:
            futures = [executor.submit(self.process_task_do_scan, task, filter_func, is_gpt4) for task in tasks]
            
            with tqdm(total=len(tasks), desc="Processing tasks") as pbar:
                for future in as_completed(futures):
                    future.result()  # 等待每个任务完成
                    pbar.update(1)  # 更新进度条

        return tasks
    def process_task_check_vul(self,task:Project_Task):
        response_final=""
        starttime=time.time()
        result = task.get_result(False)
        result_CN=task.get_result_CN()
        category_mark=task.get_category()
        if result_CN is not None and len(result_CN) > 0 and result_CN !="None":
            if category_mark is not None and len(category_mark)>0:
                print("\t skipped (scanned)")
            else:
                # print("\t to mark in assumation")
                prompt=PromptAssembler.assemble_vul_check_prompt(task.content,result_CN)
                function_code=task.content
                if_business_flow_scan = task.if_business_flow_scan
                business_flow_code = task.business_flow_code
                business_flow_context=task.business_flow_context
                # 结果打标记，标记处那些会进行假设的vul，通常他们都不是vul
                # prompt_filter_with_assumation=business_flow_code+"\n"+result+"\n\n"+CorePrompt.assumation_prompt()
                # response_if_assumation=str(common_ask(prompt_filter_with_assumation))
                response_if_assumation=""
                self.project_taskmgr.update_result(task.id, result, result_CN,response_if_assumation)
            
        else:
            print("\t to confirm")
            function_code=task.content
            if_business_flow_scan = task.if_business_flow_scan
            business_flow_code = task.business_flow_code
            business_flow_context=task.business_flow_context
            
            code_to_be_tested=business_flow_code+"\n"+business_flow_context if if_business_flow_scan=="1" else function_code
            
            yes_count = 0
            not_sure_count = 0
            all_responses = []  # Store all responses
            
            for attempt in range(3):
                prompt = PromptAssembler.assemble_vul_check_prompt(code_to_be_tested, result)
                response_from_claude=ask_claude(prompt)
                print(response_from_claude)
                # 用claude去问，结果更solid，然后再用gpt去进行json转换
                prompt_translate_claude_response_to_json="based on the analysis response, please translate the response to json format, the json format is as follows: {'brief of response':'xxx','result':'yes'} or {'brief of response':'xxx','result':'no'} or {'brief of response':'xxx','result':'not sure'}"
                response = str(common_ask_for_json(response_from_claude+"\n"+prompt_translate_claude_response_to_json))
                all_responses.append(response_from_claude+response)  # Add response to list
                print(response)
                
                def parse_result(json_string):
                    try:
                        data = json.loads(json_string)
                        return data.get("result", None)
                    except json.JSONDecodeError:
                        print("Invalid JSON string")
                        return None
                
                result_status = parse_result(response)
                
                if result_status is not None:
                    result_status = result_status.lower()
                    if "not sure" in result_status:  # 先判断not sure
                        not_sure_count += 1
                        print(f"\t got not sure on attempt {attempt + 1}")
                    elif "no" in result_status:  # 再判断no
                        print(f"\t confirmed no vulnerability on attempt {attempt + 1}")
                        response_final = "no"
                        break  # 有no直接结束
                    elif "yes" in result_status:  # 最后判断yes
                        yes_count += 1
                        print(f"\t got yes on attempt {attempt + 1}")
                
                # 最后一次循环结束后判断结果
                if attempt == 2:
                    if yes_count >= 2:  # 2-3次yes
                        response_final = "yes"
                        print("\t confirmed potential vulnerability with majority yes")
                    elif yes_count == 1 and not_sure_count == 2:  # 1次yes，2次not sure
                        response_final = "not sure"
                        print("\t result inconclusive with more not sure responses")
                    else:  # 其他情况(3次not sure)
                        response_final = "not sure"
                        print("\t result inconclusive")

            # Combine all responses
            response_if_assumation = "\n".join([f"Attempt {i+1}: {resp}" for i, resp in enumerate(all_responses)])
            
            self.project_taskmgr.update_result(task.id, result, response_final, response_if_assumation)
            endtime=time.time()
            print("time cost of one task:",endtime-starttime)
    def get_related_functions(self,query,k=3):
        query_embedding = common_get_embedding(query)
        table = self.lancedb.open_table(self.lance_table_name)
        return table.search(query_embedding).limit(k).to_list()
    
    def extract_related_functions_by_level(self, function_names: List[str], level: int) -> str:
        """
        从call_trees中提取指定函数相关的上下游函数信息并扁平化处理
        
        Args:
            function_names: 要分析的函数名列表
            level: 要分析的层级深度
            
        Returns:
            str: 所有相关函数内容的拼接文本
        """
        def get_functions_from_tree(tree, current_level=0, max_level=level, collected_funcs=None, level_stats=None):
            """递归获取树中指定层级内的所有函数信息"""
            if collected_funcs is None:
                collected_funcs = []
            if level_stats is None:
                level_stats = {}
                
            if not tree or current_level > max_level:
                return collected_funcs, level_stats
                    
            # 添加当前节点的函数信息
            if tree['function_data']:
                collected_funcs.append(tree['function_data'])
                # 更新层级统计
                level_stats[current_level] = level_stats.get(current_level, 0) + 1
                    
            # 递归处理子节点
            if current_level < max_level:
                for child in tree['children']:
                    get_functions_from_tree(child, current_level + 1, max_level, collected_funcs, level_stats)
                        
            return collected_funcs, level_stats

        all_related_functions = []
        statistics = {
            'total_layers': level,
            'upstream_stats': {},
            'downstream_stats': {}
        }
        
        # 遍历每个指定的函数名
        for func_name in function_names:
            # 在call_trees中查找对应的树
            for tree_data in self.project_audit.call_trees:
                if tree_data['function'] == func_name:
                    # 处理上游调用树
                    if tree_data['upstream_tree']:
                        upstream_funcs, upstream_stats = get_functions_from_tree(tree_data['upstream_tree'])
                        all_related_functions.extend(upstream_funcs)
                        # 合并上游统计信息
                        for level, count in upstream_stats.items():
                            statistics['upstream_stats'][level] = (
                                statistics['upstream_stats'].get(level, 0) + count
                            )
                            
                    # 处理下游调用树
                    if tree_data['downstream_tree']:
                        downstream_funcs, downstream_stats = get_functions_from_tree(tree_data['downstream_tree'])
                        all_related_functions.extend(downstream_funcs)
                        # 合并下游统计信息
                        for level, count in downstream_stats.items():
                            statistics['downstream_stats'][level] = (
                                statistics['downstream_stats'].get(level, 0) + count
                            )
                        
                    # 添加原始函数本身
                    for func in self.project_audit.functions_to_check:
                        if func['name'].split('.')[-1] == func_name:
                            all_related_functions.append(func)
                            break
                                
                    break
            
        # 去重处理
        seen_functions = set()
        unique_functions = []
        for func in all_related_functions:
            func_name = func['name']
            if func_name not in seen_functions:
                seen_functions.add(func_name)
                unique_functions.append(func)
        
        # 拼接所有函数内容
        combined_text = '\n'.join(func['content'] for func in unique_functions)
        
        # 打印统计信息
        print(f"\nFunction Call Tree Statistics:")
        print(f"Total Layers Analyzed: {level}")
        print("\nUpstream Statistics:")
        for layer, count in statistics['upstream_stats'].items():
            print(f"Layer {layer}: {count} functions")
        print("\nDownstream Statistics:")
        for layer, count in statistics['downstream_stats'].items():
            print(f"Layer {layer}: {count} functions")
        print(f"\nTotal Unique Functions: {len(unique_functions)}")
        
        return combined_text


    def check_function_vul(self):
        # self.llm.init_conversation()
        tasks = self.project_taskmgr.get_task_list()
        # 用codebaseQA的形式进行，首先通过rag和task中的vul获取相应的核心三个最相关的函数
        for task in tqdm(tasks,desc="Processing tasks for update business_flow_context"):
            if task.if_business_flow_scan=="1":
                # 获取business_flow_context
                code_to_be_tested=task.business_flow_code
            else:
                code_to_be_tested=task.content
            related_functions=self.get_related_functions(code_to_be_tested,5)
            related_functions_names=[func['name'].split('.')[-1] for func in related_functions]
            combined_text=self.extract_related_functions_by_level(related_functions_names,6)
            # 更新task对应的business_flow_context
            self.project_taskmgr.update_business_flow_context(task.id,combined_text)
            self.project_

        if len(tasks) == 0:
            return

        # 定义线程池中的线程数量
        max_threads = 5

        with ThreadPoolExecutor(max_workers=max_threads) as executor:
            futures = [executor.submit(self.process_task_check_vul, task) for task in tasks]

            with tqdm(total=len(tasks), desc="Checking vulnerabilities") as pbar:
                for future in as_completed(futures):
                    future.result()  # 等待每个任务完成
                    pbar.update(1)  # 更新进度条

        return tasks


if __name__ == "__main__":
    pass