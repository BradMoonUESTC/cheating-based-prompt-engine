from concurrent.futures import ThreadPoolExecutor
import json
import re
import threading
import time
import requests
import tqdm
from sklearn.metrics.pairwise import cosine_similarity
from concurrent.futures import ThreadPoolExecutor, as_completed
from tqdm import tqdm

from prompt_factory.prompt_assembler import PromptAssembler
from prompt_factory.core_prompt import CorePrompt
from openai_api.openai import *
class AiEngine(object):

    def __init__(self, planning, taskmgr):
        # Step 1: 获取results
        self.planning = planning
        self.project_taskmgr = taskmgr

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
        max_threads = 3

        with ThreadPoolExecutor(max_workers=max_threads) as executor:
            futures = [executor.submit(self.process_task_do_scan, task, filter_func, is_gpt4) for task in tasks]
            
            with tqdm(total=len(tasks), desc="Processing tasks") as pbar:
                for future in as_completed(futures):
                    future.result()  # 等待每个任务完成
                    pbar.update(1)  # 更新进度条

        return tasks
    def process_task_check_vul(self,task):
        response_final=""
        starttime=time.time()
        result = task.get_result(False)
        result_CN=task.get_result_CN()
        category_mark=task.get_category()
        if result_CN is not None and len(result_CN) > 0:
            if category_mark is not None and len(category_mark)>0:
                print("\t skipped (scanned)")
            else:
                print("\t to mark in assumation")
                prompt=PromptAssembler.assemble_vul_check_prompt(task.content,result_CN)
                function_code=task.content
                if_business_flow_scan = task.if_business_flow_scan
                business_flow_code = task.business_flow_code
                business_flow_context=task.business_flow_context
                # 结果打标记，标记处那些会进行假设的vul，通常他们都不是vul
                prompt_filter_with_assumation=business_flow_code+"\n"+result+"\n\n"+CorePrompt.assumation_prompt()
                response_if_assumation=str(common_ask(prompt_filter_with_assumation))
                self.project_taskmgr.update_result(task.id, result, result_CN,response_if_assumation)
            
        else:
            print("\t to confirm")
            function_code=task.content
            if_business_flow_scan = task.if_business_flow_scan
            business_flow_code = task.business_flow_code
            business_flow_context=task.business_flow_context
            # business_flow_context=''
            # 要进行检查的代码粒度
            code_to_be_tested=business_flow_code+"\n"+business_flow_context if if_business_flow_scan=="1" else function_code
            for attempt in range(3):  # 最多尝试3次
                prompt = PromptAssembler.assemble_vul_check_prompt(code_to_be_tested, result)
                response_final = str(common_ask_for_json(prompt))
                print(response_final)
                def parse_result(json_string):
                    try:
                        data = json.loads(json_string)
                        return data.get("result", None)
                    except json.JSONDecodeError:
                        print("Invalid JSON string")
                        return None
                
                result_yes_or_no = parse_result(response_final)
                
                if result_yes_or_no is not None and "no" in result_yes_or_no.lower():
                    print(f"\t confirmed no vulnerability on attempt {attempt + 1}")
                    break  # 如果包含"no"，结束循环
                elif attempt == 2:  # 如果是最后一次尝试，3次都是yes
                    print("\t confirmed potential vulnerability after 5 attempts")
                else:
                    print(f"\t potential vulnerability found, attempting confirmation {attempt + 2}")
            # prompt_CN=response_final+"用中文详细的翻译一下这个漏洞确认结果，不要有任何遗漏，记得给出最后的结论，看看是result-yes还是result-no"
            # response_final_CN=str(self.ask_openai_common(prompt_CN))

            # 结果打标记，标记处那些会进行假设的vul，通常他们都不是vul
            prompt_filter_with_assumation=business_flow_code+"\n"+result+"\n\n"+CorePrompt.category_check()
            response_if_assumation=str(common_ask_for_json(prompt_filter_with_assumation))
            self.project_taskmgr.update_result(task.id, result, response_final,response_if_assumation)
            endtime=time.time()
            print("time cost of one task:",endtime-starttime)
        
    def check_function_vul(self):
        # self.llm.init_conversation()
        tasks = self.project_taskmgr.get_task_list()
        if len(tasks) == 0:
            return

        # 定义线程池中的线程数量
        max_threads = 10

        with ThreadPoolExecutor(max_workers=max_threads) as executor:
            futures = [executor.submit(self.process_task_check_vul, task) for task in tasks]

            with tqdm(total=len(tasks), desc="Checking vulnerabilities") as pbar:
                for future in as_completed(futures):
                    future.result()  # 等待每个任务完成
                    pbar.update(1)  # 更新进度条

        return tasks


if __name__ == "__main__":
    pass