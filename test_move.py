import re
import os

def find_move_functions(text, filename, hash):
    # regex = r"((?:public\s+)?(?:entry\s+)?(?:native\s+)?(?:inline\s+)?fun\s+(?:<[^>]+>\s*)?(\w+)\s*(?:<[^>]+>)?\s*\([^)]*\)(?:\s*:\s*[^{]+)?(?:\s+acquires\s+[^{]+)?\s*\{)"
    regex = r"((?:public\s+)?(?:entry\s+)?(?:native\s+)?(?:inline\s+)?fun\s+(?:<[^>]+>\s*)?(\w+)\s*(?:<[^>]+>)?\s*\([^)]*\)(?:\s*:\s*[^{]+)?(?:\s+acquires\s+[^{]+)?\s*(?:\{|;))"
    matches = re.finditer(regex, text)

    functions = []
    lines = text.split('\n')
    line_starts = {i: sum(len(line) + 1 for line in lines[:i]) for i in range(len(lines))}

    function_bodies = []
    for match in matches:
        if match.group(1).strip().endswith(';'):  # native function
            function_bodies.append(match.group(1))
        else:
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

    contract_code = "\n".join(function_bodies).strip()

    for match in re.finditer(regex, text):
        start_line_number = next(i for i, pos in line_starts.items() if pos > match.start()) - 1
        
        if match.group(1).strip().endswith(';'):  # native function
            function_body = match.group(1)
            end_line_number = start_line_number
            function_body_lines = 1
        else:
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

        visibility = 'public' if 'public' in match.group(1) else 'private'
        is_native = 'native' in match.group(1)
        
        functions.append({
            'type': 'FunctionDefinition',
            'name':  'special_' + match.group(2),
            'start_line': start_line_number + 1,
            'end_line': end_line_number,
            'offset_start': 0,
            'offset_end': 0,
            'content': function_body,
            'header': match.group(1).strip(),  # 新增：函数头部
            'contract_name': filename.replace('.move', '_move' + str(hash)),
            'contract_code': contract_code,
            'modifiers': ['native'] if is_native else [],
            'stateMutability': None,
            'returnParameters': None,
            'visibility': visibility,
            'node_count': function_body_lines
        })

    return functions

test_cases = [
    {
        'name': 'Basic function',
        'code': '''
fun basic_function() {
    // Function body
}
''',
        'expected_count': 1,
        'expected_names': ['special_basic_function'],
        'expected_visibilities': ['private']
    },
    {
        'name': 'Public function with parameters and return type',
        'code': '''
public fun complex_function(param1: u64, param2: address): bool {
    // Function body
    true
}
''',
        'expected_count': 1,
        'expected_names': ['special_complex_function'],
        'expected_visibilities': ['public']
    },
    {
        'name': 'Generic function',
        'code': '''
fun generic_function<T>(value: T): T {
    // Function body
    value
}
''',
        'expected_count': 1,
        'expected_names': ['special_generic_function'],
        'expected_visibilities': ['private']
    },
    {
        'name': 'Native function',
        'code': '''
native fun native_function(x: u64): u64;
''',
        'expected_count': 1,
        'expected_names': ['special_native_function'],
        'expected_visibilities': ['private']
    },
    {
        'name': 'Multiple functions',
        'code': '''
fun function1() {
    // Function body
}

public fun function2<T>(param: T): T {
    // Function body
    param
}

native fun function3();
''',
        'expected_count': 3,
        'expected_names': ['special_function1', 'special_function2', 'special_function3'],
        'expected_visibilities': ['private', 'public', 'private']
    },
    {
        'name': 'Function with complex generic constraints',
        'code': '''
public fun complex_generic<T: copy + drop, U: store>(x: T, y: U): (T, U) {
    // Function body
    (x, y)
}
''',
        'expected_count': 1,
        'expected_names': ['special_complex_generic'],
        'expected_visibilities': ['public']
    },
    {
        'name': 'Public native function',
        'code': '''
public native fun public_native_function(): bool;
''',
        'expected_count': 1,
        'expected_names': ['special_public_native_function'],
        'expected_visibilities': ['public']
    },
    {
        'name': 'Function with no parameters and return type',
        'code': '''
fun no_params_no_return() {
    // Function body
}
''',
        'expected_count': 1,
        'expected_names': ['special_no_params_no_return'],
        'expected_visibilities': ['private']
    }
]

def run_individual_tests():
    total_tests = len(test_cases)
    passed_tests = 0
    failed_tests = 0

    for i, test_case in enumerate(test_cases):
        print(f"\nRunning test case {i + 1}: {test_case['name']}")
        result = find_move_functions(test_case['code'], 'test.move', 123)
        
        test_passed = True
        if len(result) != test_case['expected_count']:
            print(f"FAIL: Expected {test_case['expected_count']} functions, but found {len(result)}")
            test_passed = False
        
        for j, func in enumerate(result):
            if j < len(test_case['expected_names']):
                if func['name'] != test_case['expected_names'][j]:
                    print(f"FAIL: Expected function name {test_case['expected_names'][j]}, but found {func['name']}")
                    test_passed = False
                if func['visibility'] != test_case['expected_visibilities'][j]:
                    print(f"FAIL: Expected visibility {test_case['expected_visibilities'][j]} for {func['name']}, but found {func['visibility']}")
                    test_passed = False
            else:
                print(f"FAIL: Unexpected extra function found: {func['name']}")
                test_passed = False
        
        print("Found functions:")
        for func in result:
            print(f"  - {func['name']} (visibility: {func['visibility']})")
            print(f"    Header: {func['header']}")  # 新增：输出函数头部
        
        if test_passed:
            print("PASS")
            passed_tests += 1
        else:
            failed_tests += 1

    print(f"\nIndividual Test Summary:")
    print(f"Total tests: {total_tests}")
    print(f"Passed: {passed_tests}")
    print(f"Failed: {failed_tests}")

def test_move_file(file_path):
    print(f"\nTesting .move file: {file_path}")
    with open(file_path, 'r') as file:
        content = file.read()
    
    result = find_move_functions(content, os.path.basename(file_path), 123)
    
    print(f"Found {len(result)} functions in the file:")
    for func in result:
        print(f"  - {func['name']} (visibility: {func['visibility']}, lines: {func['start_line']}-{func['end_line']})")
        print(f"    Header: {func['header']}")  # 新增：输出函数头部
    
    return result

def run_file_tests(directory):
    move_files = [f for f in os.listdir(directory) if f.endswith('.move')]
    total_files = len(move_files)
    total_functions = 0

    print(f"\nTesting {total_files} .move files in directory: {directory}")

    for file in move_files:
        file_path = os.path.join(directory, file)
        functions = test_move_file(file_path)
        total_functions += len(functions)

    print(f"\nFile Test Summary:")
    print(f"Total .move files processed: {total_files}")
    print(f"Total functions found: {total_functions}")

if __name__ == "__main__":
    print("Running individual test cases:")
    run_individual_tests()

    print("\nTesting .move files:")
    move_directory = "move_test"  # 替换为实际的 .move 文件目录
    run_file_tests(move_directory)