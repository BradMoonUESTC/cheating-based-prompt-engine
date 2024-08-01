import os
import re
import json

def find_func_functions(text, filename, hash):
    regex = r"((?:\w+|\(\))\s+\w+\s*\([^)]*\)(?:\s+\w+)*\s*\{)"
    matches = re.finditer(regex, text)

    functions = []
    lines = text.split('\n')
    line_starts = {i: sum(len(line) + 1 for line in lines[:i]) for i in range(len(lines))}

    for match in matches:
        start_line_number = next(i for i, pos in line_starts.items() if pos > match.start()) - 1
        function_header = match.group(1)
        
        # Extract function name
        func_name = re.search(r'\s(\w+)\s*\(', function_header).group(1)
        
        # Extract initial modifier (if any)
        initial_modifier = re.search(r'^(\w+|\(\))', function_header).group(1)
        
        # Extract additional modifiers after the parentheses
        additional_modifiers = re.findall(r'\)\s+(\w+)', function_header)
        
        all_modifiers = [initial_modifier] if initial_modifier != '()' else []
        all_modifiers.extend(additional_modifiers)
        
        functions.append({
            'type': 'FunctionDefinition',
            'name': 'special_' + func_name,
            'start_line': start_line_number + 1,
            'end_line': start_line_number + 1,  # We only process the function header
            'offset_start': 0,
            'offset_end': 0,
            'content': "",
            'contract_name': filename.replace('.fc', '_func' + str(hash)),
            'contract_code': "",
            'modifiers': all_modifiers,
            'stateMutability': None,
            'returnParameters': None,
            'visibility': 'public',  # Assuming all functions are public in FunC
            'node_count': 1  # Only counting the header as one line
        })

    return functions

# 其余函数保持不变
def process_func_file(file_path, hash_value):
    with open(file_path, 'r', encoding='utf-8') as file:
        func_code = file.read()
    
    filename = os.path.basename(file_path)
    functions = find_func_functions(func_code, filename, hash_value)
    
    return functions

def process_func_folder(folder_path, hash_value):
    all_functions = []
    
    for root, dirs, files in os.walk(folder_path):
        for file in files:
            if file.endswith('.fc'):
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

def test_find_func_functions(folder_path, hash_value):
    if not os.path.isdir(folder_path):
        print(f"Error: '{folder_path}' is not a valid folder path.")
        return

    print(f"Processing folder: {folder_path}")
    all_functions = process_func_folder(folder_path, hash_value)

    print(f"\nTotal functions found: {len(all_functions)}.")

    return all_functions

if __name__ == "__main__":
    FOLDER_PATH = "src/dataset/agent-v1-c4/func_test"  # Replace with your FunC project folder path
    HASH_VALUE = 12345  # You can change this value as needed

    found_functions = test_find_func_functions(FOLDER_PATH, HASH_VALUE)