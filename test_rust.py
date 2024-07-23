import os
import re
import json


def find_rust_functions(text, filename,hash):
    regex = r"((?:pub(?:\s*\([^)]*\))?\s+)?fn\s+\w+(?:<[^>]*>)?\s*\([^{]*\)(?:\s*->\s*[^{]*)?\s*\{)"
    matches = re.finditer(regex, text)

    # 函数列表
    functions = []

    # 将文本分割成行，用于更容易地计算行号
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
                visibility = 'public' if 'pub' in match.group(1) else 'private'
                functions.append({
                    'type': 'FunctionDefinition',
                    'name': 'special_'+re.search(r'\bfn\s+(\w+)', match.group(1)).group(1),  # Extract function name from match
                    'start_line': start_line_number + 1,
                    'end_line': end_line_number,
                    'offset_start': 0,
                    'offset_end': 0,
                    'content': function_body,
                    'contract_name': filename.replace('.rs','_rust'+str(hash)),
                    'contract_code': contract_code,
                    'modifiers': [],
                    'stateMutability': None,
                    'returnParameters': None,
                    'visibility': visibility,
                    'node_count': function_body_lines
                })
                break

    return functions
def process_rust_file(file_path, hash_value):
    with open(file_path, 'r', encoding='utf-8') as file:
        rust_code = file.read()
    
    filename = os.path.basename(file_path)
    functions = find_rust_functions(rust_code, filename, hash_value)
    
    return functions
def process_rust_folder(folder_path, hash_value):
    all_functions = []
    
    for root, dirs, files in os.walk(folder_path):
        for file in files:
            if file.endswith('.cairo'):
                file_path = os.path.join(root, file)
                print(f"处理文件：{file_path}")
                functions = process_rust_file(file_path, hash_value)
                all_functions.extend(functions)
                
                # 打印每个文件的结果
                print(f"\n{file_path} 的解析结果：")
                for func in functions:
                    print(json.dumps(func, indent=2))
                    print("-" * 50)
                
                print(f"在 {file_path} 中找到 {len(functions)} 个函数。")
    
    return all_functions

def test_find_rust_functions(folder_path, hash_value):
    if not os.path.isdir(folder_path):
        print(f"错误：'{folder_path}' 不是一个有效的文件夹路径。")
        return

    print(f"处理文件夹：{folder_path}")
    all_functions = process_rust_folder(folder_path, hash_value)

    # 打印统计信息
    print(f"\n总共找到 {len(all_functions)} 个函数。")

    # 返回所有找到的函数
    return all_functions

if __name__ == "__main__":
    # 在这里直接定义参数
    FOLDER_PATH = "src/dataset/agent-v1-c4/cairo_test"  # 替换为您的 Rust 项目文件夹路径
    HASH_VALUE = 12345  # 您可以根据需要更改这个值

    found_functions = test_find_rust_functions(FOLDER_PATH, HASH_VALUE)