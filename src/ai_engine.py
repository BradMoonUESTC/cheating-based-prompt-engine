from concurrent.futures import ThreadPoolExecutor
import re
import threading
import time
import requests
import tqdm
from library.chatgpt_api2 import *
from sklearn.metrics.pairwise import cosine_similarity
from library.embedding_api import get_embbedding
from concurrent.futures import ThreadPoolExecutor, as_completed
from tqdm import tqdm

from prompt_factory.prompt_assembler import PromptAssembler
from prompt_factory.core_prompt import CorePrompt
class AiEngine(object):

    def __init__(self, llm, planning, taskmgr):
        # Step 1: 获取results
        self.llm = llm
        self.planning = planning
        self.project_taskmgr = taskmgr

    def do_planning(self):
        self.planning.do_planning()
        # self.project_taskmgr.add_tasks(tasks)
        # for task in self.planning.do_planning():
        #     self.project_taskmgr.add_tasks(task)    
    def ask_openai_common(self,prompt):
        api_base = os.getenv('OPENAI_API_BASE', 'api.openai.com')  # Replace with your actual OpenAI API base URL
        api_key = os.getenv('OPENAI_API_KEY')  # Replace with your actual OpenAI API key
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}"
        }
        data = {
            "model": os.getenv('VUL_MODEL_ID'),  # Replace with your actual OpenAI model
            "messages": [
                {
                    "role": "user",
                    "content": prompt
                }
            ]
        }
        response = requests.post(f'https://{api_base}/v1/chat/completions', headers=headers, json=data)
        try:
            response_josn = response.json()
        except Exception as e:
            return ''
        if 'choices' not in response_josn:
            return ''
        return response_josn['choices'][0]['message']['content']
    def calculate_similarity(self,input_text1, input_text2):
        embedding1 = get_embbedding(input_text1)
        embedding2 = get_embbedding(input_text2)
        return cosine_similarity([embedding1], [embedding2])[0][0]
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
                response_vul=self.ask_openai_common(prompt)
                print(response_vul)
                response_vul = response_vul if response_vul is not None else "no"                
                self.project_taskmgr.update_result(task.id, response_vul, "","")
    def do_scan(self, is_gpt4=False, filter_func=None):
        self.llm.init_conversation()

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
        if result_CN is not None and len(result_CN) > 0:
            print("\t skipped (scanned)")
        else:
            print("\t to confirm")
            function_code=task.content
            if_business_flow_scan = task.if_business_flow_scan
            business_flow_code = task.business_flow_code
            business_flow_context=task.business_flow_context
            # business_flow_context=''
            # 要进行检查的代码粒度
            code_to_be_tested=business_flow_code+"\n"+business_flow_context if if_business_flow_scan=="1" else function_code
            prompt=PromptAssembler.assemble_vul_check_prompt(code_to_be_tested,result)
            response_final=str(self.ask_openai_common(prompt))+"\n"+str(result)
            prompt_CN=response_final+"用中文解释一下这个漏洞"
            response_final_CN=str(self.ask_openai_common(prompt_CN))

            # 结果打标记，标记处那些会进行假设的vul，通常他们都不是vul
            prompt_filter_with_assumation=business_flow_code+"\n"+result+"\n\n"+CorePrompt.assumation_prompt()
            response_if_assumation=str(self.ask_openai_common(prompt_filter_with_assumation))
            self.project_taskmgr.update_result(task.id, response_final, response_final_CN,response_if_assumation)
            endtime=time.time()
            print("time cost of one task:",endtime-starttime)
        
    def check_function_vul(self):
        self.llm.init_conversation()
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

    def rescan_with_gpt4(self):

        def to_scan_gpt4(task):
            result = task.result
            result_gpt4 = task.result_gpt4
            #print(result)
            return result is not None and len(result) > 0 and result.lower().startswith("yes") and len(result_gpt4) == 0

        self.do_scan(True, to_scan_gpt4)

    def check_function_vul_in_short_return(self, content, key_sentence, is_gpt4 = False):
        variables={
            "content": content,
            "keyconcept": key_sentence
        }
        return self.llm.completion("getVulVersionV2", variables)
    def generate_description(self, response_vul, content):
        variables={
            "response_vul": response_vul,
            "content": content
        }
        return self.llm.completion("generateDescription", variables)
    def generate_recommendation(self, response_vul, content):
        variables={
            "response_vul": response_vul,
            "content": content
        }
        return self.llm.completion("generateRecommendation", variables)
    def generate_title(self, response_vul, content):
        variables={
            "response_vul": response_vul,
            "content": content
        }
        return self.llm.completion("generateTitle", variables)
    # def generate_severity(self, response_vul, content):
    #     variables={
    #         "response_vul": response_vul,
    #         "content": content
    #     }
    #     return self.llm.completion("generateSeverity", variables)
    def check_vul_if_false_positive(self,response,content,origin_rule):
        variables={
            "code":content,
            "vulresult":response
        }
        return self.llm.completion("checkFalsePositiveVersion1",variables)
    def check_vul_if_false_positive_by_patch(self,response,content,origin_rule):
        variables={
            "code":content,
            "vulresult":response
        }
        return self.llm.completion("checkFalsePositiveByPatchVersion1",variables)
    def check_vul_if_false_positive_by_context(self,contract_code,response,content):
        variables={
            "contract_code":contract_code,
            "code":content,
            "vulresult":response
        }
        return self.llm.completion("checkFalsePositiveByContext",variables)
    def check_vul_if_false_positive_by_context_v2(self,contract_code,response):
        variables={
            "contract_code":contract_code,
            "vulresult":response
        }
        return self.llm.completion("checkVulBasedContext",variables)


if __name__ == "__main__":
    pass