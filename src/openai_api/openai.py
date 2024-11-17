import json
import os
import numpy as np
import requests


def azure_openai(prompt):
    # Azure OpenAI配置
    api_key = os.environ.get('AZURE_API_KEY')
    api_base = os.environ.get('AZURE_API_BASE')
    api_version = os.environ.get('AZURE_API_VERSION')
    deployment_name = os.environ.get('AZURE_DEPLOYMENT_NAME')
    # 构建URL
    url = f"{api_base}openai/deployments/{deployment_name}/chat/completions?api-version={api_version}"
    # 设置请求头
    headers = {
        "Content-Type": "application/json",
        "api-key": api_key
    }
    # 设置请求体
    data = {
        "messages": [
            {"role": "system", "content": "你是一个熟悉智能合约与区块链安全的安全专家。"},
            {"role": "user", "content": prompt}
        ],
        # "max_tokens": 150
    }
    try:
        # 发送POST请求
        response = requests.post(url, headers=headers, json=data)
        # 检查响应状态
        response.raise_for_status()
        # 解析JSON响应
        result = response.json()
        # 打印响应
        return result['choices'][0]['message']['content']
    except requests.exceptions.RequestException as e:
        print("Azure OpenAI测试失败。错误:", str(e))
        return None
    

def azure_openai_json(prompt):
    # Azure OpenAI配置
    api_key = os.environ.get('AZURE_API_KEY')
    api_base = os.environ.get('AZURE_API_BASE')
    api_version = os.environ.get('AZURE_API_VERSION')
    deployment_name = os.environ.get('AZURE_DEPLOYMENT_NAME')
    # 构建URL
    url = f"{api_base}openai/deployments/{deployment_name}/chat/completions?api-version={api_version}"
    # 设置请求头
    headers = {
        "Content-Type": "application/json",
        "api-key": api_key
    }
    # 设置请求体
    data = {
        "response_format": { "type": "json_object" },
        "messages": [
            {
                "role": "system",
                "content": "You are a helpful assistant designed to output JSON."
            },
            {
                "role": "user",
                "content": prompt
            }
        ]
    }
    try:
        # 发送POST请求
        response = requests.post(url, headers=headers, json=data)
        # 检查响应状态
        response.raise_for_status()
        # 解析JSON响应
        result = response.json()
        # 打印响应
        return result['choices'][0]['message']['content']
    except requests.exceptions.RequestException as e:
        print("Azure OpenAI测试失败。错误:", str(e))
        return None
def ask_claude(prompt):
    api_key = os.environ.get('CLAUDE_API_KEY')
    api_url = os.environ.get('CLAUDE_API_URL')
    headers = {
        'Content-Type': 'application/json',
        'Authorization': f'Bearer {api_key}'
    }

    data = {
        'model': 'claude-3-sonnet-20240229',#模型
        'max_tokens': 1000,
        'messages': [

            {
                'role': 'user',
                'content': prompt
            }
        ]
    }

    response = requests.post(api_url, headers=headers, data=json.dumps(data))

    if response.status_code == 200:
        response_data = response.json()
        if 'choices' in response_data and len(response_data['choices']) > 0:
            return response_data['choices'][0]['message']['content']
        else:
            return "Error: Unexpected response structure"
    else:
        return f"Error: {response.status_code}, {response.text}"
    
def ask_openai_common(prompt):
        api_base = os.environ.get('OPENAI_API_BASE', 'api.openai.com')  # Replace with your actual OpenAI API base URL
        api_key = os.environ.get('OPENAI_API_KEY')  # Replace with your actual OpenAI API key
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}"
        }
        data = {
            "model": os.environ.get('VUL_MODEL_ID'),  # Replace with your actual OpenAI model
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
def ask_openai_for_json(prompt):
    api_base = os.environ.get('OPENAI_API_BASE', 'api.openai.com')  # Replace with your actual OpenAI API base URL
    api_key = os.environ.get('OPENAI_API_KEY')  # Replace with your actual OpenAI API key
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}"
    }
    data = {
        "model": os.environ.get('VUL_MODEL_ID'),
        "response_format": { "type": "json_object" },
        "messages": [
            {
                "role": "system",
                "content": "You are a helpful assistant designed to output JSON."
            },
            {
                "role": "user",
                "content": prompt
            }
        ]
    }
    response = requests.post(f'https://{api_base}/v1/chat/completions', headers=headers, json=data)

    response_josn = response.json()
    if 'choices' not in response_josn:
        return ''
    return response_josn['choices'][0]['message']['content']

def common_ask_for_json(prompt):
    if os.environ.get('AZURE_OR_OPENAI') == 'AZURE':
        return azure_openai_json(prompt)
    else:
        return ask_openai_for_json(prompt)

def common_ask(prompt):
    if os.environ.get('AZURE_OR_OPENAI') == 'AZURE':
        return azure_openai(prompt)
    else:
        return ask_openai_common(prompt)

def clean_text(text: str) -> str:
    return str(text).replace(" ", "").replace("\n", "").replace("\r", "")

def common_get_embedding(text: str):
    api_key = os.getenv('OPENAI_API_KEY')
    if not api_key:
        raise ValueError("OPENAI_API_KEY environment variable is not set")

    api_base = os.getenv('OPENAI_API_BASE', 'api.openai.com')
    model = os.getenv("PRE_TRAIN_MODEL", "text-embedding-3-large")
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }

    cleaned_text = clean_text(text)
    
    data = {
        "input": cleaned_text,
        "model": model,
        "encoding_format": "float"
    }

    try:
        response = requests.post(f'https://{api_base}/v1/embeddings', json=data, headers=headers)
        response.raise_for_status()
        embedding_data = response.json()
        return embedding_data['data'][0]['embedding']
    except requests.exceptions.RequestException as e:
        print(f"Error: {e}")
        return list(np.zeros(3072))  # 返回长度为3072的全0数组
