import os
import re
import json

def find_vyper_functions(text, filename, hash_value):
    # 更新后的正则表达式，使用非贪婪匹配和多行模式
    regex = r"def\s+(\w+)\s*\(([\s\S]*?)\)(?:\s*->\s*(\w+))?\s*:"
    matches = re.finditer(regex, text, re.MULTILINE)

    # 函数列表
    functions = []

    # 将文本分割成行，用于更容易地计算行号
    lines = text.split('\n')
    line_starts = {i: sum(len(line) + 1 for line in lines[:i]) for i in range(len(lines))}

    # 遍历匹配，创建函数定义
    if any(matches):  # 如果有匹配的函数定义
        for match in matches:
            start_line_number = next(i for i, pos in line_starts.items() if pos > match.start()) - 1
            indent_level = len(lines[start_line_number]) - len(lines[start_line_number].lstrip())

            # 查找函数体的结束
            end_line_number = start_line_number + 1
            while end_line_number < len(lines):
                line = lines[end_line_number]
                if line.strip() and (len(line) - len(line.lstrip()) <= indent_level):
                    break
                end_line_number += 1
            end_line_number -= 1  # Adjust to include last valid line of the function

            # 构建函数体
            function_body = '\n'.join(lines[start_line_number:end_line_number+1])
            function_body_lines = function_body.count('\n') + 1

            # 清理参数字符串
            params = match.group(2).replace('\n', '').replace(' ', '')

            functions.append({
                'type': 'FunctionDefinition',
                'name': "function" + match.group(1),  # 函数名
                'start_line': start_line_number + 1,
                'end_line': end_line_number + 1,
                'offset_start': 0,
                'offset_end': 0,
                'content': function_body,
                'contract_name': filename.replace('.vy', '_vyper'),
                'contract_code': text.strip(),  # 整个代码
                'modifiers': [],
                'stateMutability': None,
                'returnParameters': match.group(3),
                'visibility': 'public',
                'node_count': function_body_lines,
                'parameters': params
            })
    else:  # 如果没有找到函数定义
        function_body_lines = len(lines)
        functions.append({
            'type': 'FunctionDefinition',
            'name': "function" + filename.split('.')[0] + "all",  # 使用文件名作为函数名
            'start_line': 1,
            'end_line': function_body_lines,
            'offset_start': 0,
            'offset_end': 0,
            'content': text.strip(),
            'contract_name': filename.replace('.vy', '_vyper'),
            'contract_code': text.strip(),
            'modifiers': [],
            'stateMutability': None,
            'returnParameters': None,
            'visibility': 'public',
            'node_count': function_body_lines,
            'parameters': ''
        })

    return functions

# 其他函数保持不变
def process_vyper_file(file_path, hash_value):
    with open(file_path, 'r', encoding='utf-8') as file:
        vyper_code = file.read()
    
    filename = os.path.basename(file_path)
    functions = find_vyper_functions(vyper_code, filename, hash_value)
    
    return functions

def process_vyper_folder(folder_path, hash_value):
    all_functions = []
    
    for root, dirs, files in os.walk(folder_path):
        for file in files:
            if file.endswith('.vy'):
                file_path = os.path.join(root, file)
                print(f"处理文件：{file_path}")
                functions = process_vyper_file(file_path, hash_value)
                all_functions.extend(functions)
                
                # 打印每个文件的结果
                print(f"\n{file_path} 的解析结果：")
                for func in functions:
                    print(json.dumps(func, indent=2))
                    print("-" * 50)
                
                print(f"在 {file_path} 中找到 {len(functions)} 个函数。")
    
    return all_functions

def test_find_vyper_functions(folder_path, hash_value):
    if not os.path.isdir(folder_path):
        print(f"错误：'{folder_path}' 不是一个有效的文件夹路径。")
        return

    print(f"处理文件夹：{folder_path}")
    all_functions = process_vyper_folder(folder_path, hash_value)

    # 打印统计信息
    print(f"\n总共找到 {len(all_functions)} 个函数。")

    # 返回所有找到的函数
    return all_functions

if __name__ == "__main__":
    # 在这里直接定义参数
    FOLDER_PATH = "src/dataset/agent-v1-c4/vyper_test"  # 替换为您的 vyper 项目文件夹路径
    HASH_VALUE = 12345  # 您可以根据需要更改这个值

    found_functions = test_find_vyper_functions(FOLDER_PATH, HASH_VALUE)