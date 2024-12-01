import pandas as pd
from tqdm import tqdm
from openai_api.openai import ask_claude

class ResProcessor:
    def __init__(self,df):
        self.df=df

    def process(self):
        # 1. 按业务流程代码分组并按长度排序
        self.df['flow_code_len'] = self.df['业务流程代码'].str.len()
        grouped = self.df.groupby('业务流程代码')
        
        processed_results = []
        
        for flow_code, group in tqdm(grouped,desc="处理漏洞归集"):
            if len(group) <= 1:
                # 对单条记录也进行处理
                processed_result = self._process_single_vulnerability(group.iloc[0])
                processed_results.append(processed_result)
                continue
                
            # 对多条记录进行合并处理
            merged_result = self._merge_vulnerabilities(group)
            if isinstance(merged_result, dict):
                processed_results.append(merged_result)
            else:
                processed_results.extend(merged_result)
        
        # 创建新的DataFrame并确保列顺序正确
        new_df = pd.DataFrame(processed_results)
        
        # 删除flow_code_len列（如果存在）
        if 'flow_code_len' in new_df.columns:
            new_df = new_df.drop('flow_code_len', axis=1)
            
        # 确保列顺序与原始DataFrame相同
        original_columns = [col for col in self.df.columns if col != 'flow_code_len']
        new_df = new_df[original_columns]
        
        return new_df

    def _process_single_vulnerability(self, row):
        # 构建单条漏洞的翻译提示
        translate_prompt = f"""请对以下漏洞描述进行优化和完善，使其更加清晰详细，用中文输出。要求：
1. 保留原有的技术细节
2. 使描述更加通俗易懂
3. 确保不丢失任何重要信息

原漏洞描述：
{row['漏洞结果']}
"""
        
        # 调用LLM进行翻译
        translated_description = ask_claude(translate_prompt)
        
        # 返回处理后的结果
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
        
        # 构建合并提示
        merge_prompt = "合并一下这几个漏洞，使其形成一个完整的漏洞描述，用中文输出，如果存在多个不同漏洞，则分开解释，但要保证如下：1. 合并的结果相比于原来的漏洞结果不能有任何信息或漏洞缺失；2. 漏洞描述必须详细，与原来的漏洞描述方式相同\n\n"
        for _, row in group.iterrows():
            merge_prompt += f"漏洞结果：{row['漏洞结果']}\n"
            merge_prompt += "---\n"
        
        # 调用LLM进行合并
        merged_description = ask_claude(merge_prompt)
        
        # 创建合并后的结果
        return {
            '漏洞结果': merged_description,
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