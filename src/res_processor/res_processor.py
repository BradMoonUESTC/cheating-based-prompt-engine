import pandas as pd
from tqdm import tqdm
import json
from openai_api.openai import ask_claude, common_ask_for_json
import concurrent.futures
from threading import Lock

class ResProcessor:
    def __init__(self, df):
        self.df = df
        self.lock = Lock()

    def process(self):
        self.df['flow_code_len'] = self.df['业务流程代码'].str.len()
        grouped = list(self.df.groupby('业务流程代码'))
        
        processed_results = []
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            future_to_group = {executor.submit(self._process_group, flow_code, group): flow_code 
                             for flow_code, group in grouped}
            
            with tqdm(total=len(grouped), desc="处理漏洞归集") as pbar:
                for future in concurrent.futures.as_completed(future_to_group):
                    result = future.result()
                    with self.lock:
                        if isinstance(result, list):
                            processed_results.extend(result)
                        else:
                            processed_results.append(result)
                        pbar.update(1)
        
        new_df = pd.DataFrame(processed_results)
        
        if 'flow_code_len' in new_df.columns:
            new_df = new_df.drop('flow_code_len', axis=1)
            
        original_columns = [col for col in self.df.columns if col != 'flow_code_len']
        new_df = new_df[original_columns]
        
        return new_df

    def _process_group(self, flow_code, group):
        if len(group) <= 1:
            return self._process_single_vulnerability(group.iloc[0])
        return self._merge_vulnerabilities(group)

    def _process_single_vulnerability(self, row):
        translate_prompt = f"""请对以下漏洞描述翻译，用中文输出
原漏洞描述：
{row['漏洞结果']}
"""
        
        translated_description = ask_claude(translate_prompt)
        
        return {
            '漏洞结果': translated_description,
            'ID': row['ID'],
            '项目名称': row['项目名称'],
            '合同编号': row['合同编号'],
            'UUID': row['UUID'],
            '函数名称': row['函数名称'],
            '函数代码': row['函数代码'],
            '开始行': row['开始行'],
            '结束行': row['结束行'],
            '相对路径': row['相对路径'],
            '绝对路径': row['绝对路径'],
            '业务流程代码': row['业务流程代码'],
            '业务流程行': row['业务流程行'],
            '业务流程上下文': row['业务流程上下文'],
            '确认结果': row['确认结果'],
            '确认细节': row['确认细节']
        }

    def _merge_vulnerabilities(self, group):
        base_info = group.iloc[0].copy()
        
        merge_prompt = """
        合并一下这几个漏洞，将相同或本质相似漏洞合并到一起，用中文输出，如果存在多个不同漏洞，则分开描述，
        但要保证如下:1. 合并的结果相比于原来的漏洞结果不能有任何信息或漏洞缺失，且合并的相同或本质相似的漏洞描述要全面不能有遗漏；
        2. 每个合并后的漏洞描述必须非常详细,不能少于600个字用原来的原文翻译来描述漏洞,不能有任何表述遗漏，否则你会受到惩罚，
        输出格式如下，必须严格遵循格式输出
        {
            "merged_vulnerabilities": [
                {"description": "合并后的漏洞1描述"},
                {"description": "合并后的漏洞2描述"},
                ...
            ]
        }
        """
        for _, row in group.iterrows():
            merge_prompt += f"漏洞结果：{row['漏洞结果']}\n"
            merge_prompt += "---\n"
        
        merged_result = common_ask_for_json(merge_prompt)
        
        try:
            merged_data = json.loads(merged_result)
            vulnerabilities = merged_data.get('merged_vulnerabilities', [])
            
            if not vulnerabilities:
                return {
                    '漏洞结果': merged_result,
                    'ID': base_info['ID'],
                    '项目名称': base_info['项目名称'],
                    '合同编号': base_info['合同编号'],
                    'UUID': base_info['UUID'],
                    '函数名称': base_info['函数名称'],
                    '函数代码': base_info['函数代码'],
                    '开始行': min(group['开始行']),
                    '结束行': max(group['结束行']),
                    '相对路径': base_info['相对路径'],
                    '绝对路径': base_info['绝对路径'],
                    '业务流程代码': base_info['业务流程代码'],
                    '业务流程行': base_info['业务流程行'],
                    '业务流程上下文': base_info['业务流程上下文'],
                    '确认结果': base_info['确认结果'],
                    '确认细节': base_info['确认细节']
                }
            
            results = []
            for vuln in vulnerabilities:
                results.append({
                    '漏洞结果': vuln['description'],
                    'ID': base_info['ID'],
                    '项目名称': base_info['项目名称'],
                    '合同编号': base_info['合同编号'],
                    'UUID': base_info['UUID'],
                    '函数名称': base_info['函数名称'],
                    '函数代码': base_info['函数代码'],
                    '开始行': min(group['开始行']),
                    '结束行': max(group['结束行']),
                    '相对路径': base_info['相对路径'],
                    '绝对路径': base_info['绝对路径'],
                    '业务流程代码': base_info['业务流程代码'],
                    '业务流程行': base_info['业务流程行'],
                    '业务流程上下文': base_info['业务流程上下文'],
                    '确认结果': base_info['确认结果'],
                    '确认细节': base_info['确认细节']
                })
            
            return results
            
        except json.JSONDecodeError:
            # Fallback in case of JSON parsing error
            return {
                '漏洞结果': merged_result,
                'ID': base_info['ID'],
                '项目名称': base_info['项目名称'],
                '合同编号': base_info['合同编号'],
                'UUID': base_info['UUID'],
                '函数名称': base_info['函数名称'],
                '函数代码': base_info['函数代码'],
                '开始行': min(group['开始行']),
                '结束行': max(group['结束行']),
                '相对路径': base_info['相对路径'],
                '绝对路径': base_info['绝对路径'],
                '业务流程代码': base_info['业务流程代码'],
                '业务流程行': base_info['业务流程行'],
                '业务流程上下文': base_info['业务流程上下文'],
                '确认结果': base_info['确认结果'],
                '确认细节': base_info['确认细节']
            }

    def _clean_text(self, text):
        if pd.isna(text):
            return ''
        return str(text).strip()