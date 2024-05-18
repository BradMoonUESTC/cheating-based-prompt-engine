import os
import pandas as pd
import requests
from tqdm import tqdm  # 引入tqdm

def ask_openai_common(prompt):
    api_base = "api.openai.com"
    api_key = "xxx"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}"
    }
    data = {
        "model": "gpt-4-turbo",
        "messages": [{"role": "user", "content": prompt}]
    }
    response = requests.post(f'https://{api_base}/v1/chat/completions', headers=headers, json=data)
    try:
        response_json = response.json()
    except Exception as e:
        return ''
    if 'choices' not in response_json or not response_json['choices']:
        return ''
    return response_json['choices'][0]['message']['content']

def process_xlsx(file_path):
    # 读取Excel文件
    df = pd.read_excel(file_path)
    # 使用tqdm显示处理进度
    results = []
    for _, row in tqdm(df.iterrows(), total=df.shape[0], desc="Processing Rows"):
        prompt = f"""{row['英文结果']} {row['代码']} Based on the vulnerability information, answer whether the establishment of the attack depends on the code of other unknown or unprovided contracts within the project, or whether the establishment of the vulnerability is affected by any external calls or contract states. 
        
        Based on the results of the answer, add the JSON result: {{'result':'need In-project other contract'}} or {{'result':'dont need In-project other contract'}}
        """
        answer = ask_openai_common(prompt)
        print(f"Answer: {answer}\n")
        results.append(answer)
    # 将结果添加到新的列中
    df['OpenAI Response'] = results
    # 写回新的Excel文件
    df.to_excel('output_with_responses.xlsx', index=False)  # 注意文件扩展名改为.xlsx以支持新版Excel

# 处理指定的Excel文件
process_xlsx('src/Paper/project_tasks_amazing_prompt.xls')  # 确保路径和文件名正确
