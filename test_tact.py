import os
import re
import json
import csv
def find_tact_functions(text, filename, hash):
    regex = r"((?:init|receive|fun\s+\w+)\s*\([^)]*\)(?:\s*:\s*\w+)?\s*\{)"
    matches = re.finditer(regex, text)

    functions = []
    lines = text.split('\n')
    line_starts = {i: sum(len(line) + 1 for line in lines[:i]) for i in range(len(lines))}

    # 先收集所有函数体，构建完整的函数代码
    function_bodies = []
    for match in matches:
        brace_count = 1
        function_body_start = match.start()
        inside_braces = True

        for i in range(match.end(), len(text)):
            if text[i] == '{':
                brace_count += 1
            elif text[i] == '}':
                brace_count -= 1

            if inside_braces and brace_count == 0:
                function_body_end = i + 1
                function_bodies.append(text[function_body_start:function_body_end])
                break

    # 完整的函数代码字符串
    contract_code = "\n".join(function_bodies).strip()

    # 再次遍历匹配，创建函数定义
    for match in re.finditer(regex, text):
        start_line_number = next(i for i, pos in line_starts.items() if pos > match.start()) - 1
        function_header = match.group(1)
        
        brace_count = 1
        function_body_start = match.start()
        inside_braces = True

        for i in range(match.end(), len(text)):
            if text[i] == '{':
                brace_count += 1
            elif text[i] == '}':
                brace_count -= 1

            if inside_braces and brace_count == 0:
                function_body_end = i + 1
                end_line_number = next(i for i, pos in line_starts.items() if pos > function_body_end) - 1
                function_body = text[function_body_start:function_body_end]
                function_body_lines = function_body.count('\n') + 1
                break

        # Extract function name
        if function_header.startswith('init') or function_header.startswith('receive'):
            func_name = function_header.split('(')[0]
        else:
            func_name = re.search(r'fun\s+(\w+)', function_header).group(1)
        
        # Extract modifiers (in this case, only 'init', 'receive', or 'fun')
        modifier = function_header.split('(')[0].strip().split()[0]
        
        # Extract return type if present
        return_type = None
        if ':' in function_header:
            return_type = re.search(r':\s*(\w+)', function_header).group(1)
        if func_name=="receive":
            func_name=func_name+"_"+str(start_line_number)+str(end_line_number)
        functions.append({
            'type': 'FunctionDefinition',
            'name': func_name,
            'start_line': start_line_number + 1,
            'end_line': end_line_number,
            'offset_start': 0,
            'offset_end': 0,
            'content': function_body,
            'contract_name': filename.replace('.tact', '_tact' + str(hash)),
            'contract_code': contract_code,
            'modifiers': [modifier],
            'stateMutability': None,
            'returnParameters': return_type,
            'visibility': 'public',  # Assuming all functions are public in FunC
            'node_count': function_body_lines
        })

    return functions

# 其余函数保持不变
def process_func_file(file_path, hash_value):
    with open(file_path, 'r', encoding='utf-8') as file:
        func_code = file.read()
    
    filename = os.path.basename(file_path)
    functions = find_tact_functions(func_code, filename, hash_value)
    
    return functions
def process_func_folder(folder_path, hash_value):
    all_functions = []
    
    for root, dirs, files in os.walk(folder_path):
        for file in files:
            if file.endswith('.tact'):
                file_path = os.path.join(root, file)
                print(f"Processing file: {file_path}")
                functions = process_func_file(file_path, hash_value)
                all_functions.extend(functions)
                
                print(f"\nParsing results for {file_path}:")
                for func in functions:
                    print(json.dumps(func, indent=2))
                    print("-" * 50)
                
                print(f"Found {len(functions)} functions in {file_path}.")
    
    return all_functions

def test_find_func_functions(folder_path, hash_value, output_csv):
    if not os.path.isdir(folder_path):
        print(f"Error: '{folder_path}' is not a valid folder path.")
        return

    print(f"Processing folder: {folder_path}")
    all_functions = process_func_folder(folder_path, hash_value)

    print(f"\nTotal functions found: {len(all_functions)}.")

    # 将结果写入CSV文件
    with open(output_csv, 'w', newline='', encoding='utf-8') as csvfile:
        fieldnames = ['type', 'name', 'start_line', 'end_line', 'offset_start', 'offset_end', 
                      'content', 'contract_name', 'contract_code', 'modifiers', 'stateMutability', 
                      'returnParameters', 'visibility', 'node_count']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)

        writer.writeheader()
        for func in all_functions:
            # 将列表类型的字段转换为字符串
            func['modifiers'] = ', '.join(func['modifiers'])
            writer.writerow(func)

    print(f"Results have been written to {output_csv}")

    return all_functions

if __name__ == "__main__":
    FOLDER_PATH = "src/dataset/agent-v1-c4/tact_test"  # Replace with your Tact project folder path
    HASH_VALUE = 12345  # You can change this value as needed
    OUTPUT_CSV = "tact_functions_output.csv"  # 输出CSV文件的名称

    found_functions = test_find_func_functions(FOLDER_PATH, HASH_VALUE, OUTPUT_CSV)