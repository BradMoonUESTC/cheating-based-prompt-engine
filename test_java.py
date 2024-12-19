import re
import json
import sys

def find_java_functions(text, filename, hash):
    # 匹配Java方法定义的正则表达式
    regex = r"""
        # 注解部分（支持多行注解和嵌套括号）
        (?:@[\w.]+                     # 注解名称
            (?:\s*\(                   # 开始括号
                (?:[^()]|\([^()]*\))*  # 注解参数，支持嵌套括号
            \))?                       # 结束括号
        \s*)*
        
        # 所有可能的修饰符组合
        (?:(?:public|private|protected|
            static|final|native|
            synchronized|abstract|
            transient|volatile|strictfp|
            default)\s+)*
        
        # 泛型返回类型（支持嵌套泛型）
        (?:<(?:[^<>]|<[^<>]*>)*>\s*)?
        
        # 返回类型
        (?:(?:[\w.$][\w.$]*\s*(?:\[\s*\]\s*)*)|\s*void\s+)
        
        # 方法名（排除非法情况）
        (?<!new\s)
        (?<!return\s)
        (?<!throw\s)
        (?<!super\.)
        (?<!this\.)
        (?<!\.)  # 防止匹配方法调用
        ([\w$]+)\s*
        
        # 方法的泛型参数
        (?:<(?:[^<>]|<[^<>]*>)*>\s*)?
        
        # 参数列表（支持复杂参数）
        \(\s*
        (?:
            (?:
                (?:final\s+)?              # 可选的final修饰符
                (?:[\w.$][\w.$]*\s*       # 参数类型
                    (?:<(?:[^<>]|<[^<>]*>)*>\s*)?  # 参数的泛型部分
                    (?:\[\s*\]\s*)*        # 数组标记
                    \s+[\w$]+              # 参数名
                    (?:\s*,\s*)?           # 可能的逗号
                )*
            )?
        )\s*\)
        
        # throws声明（可选）
        (?:\s*throws\s+
            (?:[\w.$][\w.$]*
                (?:\s*,\s*[\w.$][\w.$]*)*
            )?
        )?
        
        # 方法体或分号
        \s*(?:\{|;)
        
        # 负向前瞻，确保不是在catch块或其他非方法上下文中
        (?!\s*catch\b)
    """
    
    functions = []
    matches = re.finditer(regex, text, re.VERBOSE | re.MULTILINE | re.DOTALL)
    
    # 用于计算行号
    lines = text.split('\n')
    line_starts = {i: sum(len(line) + 1 for line in lines[:i]) for i in range(len(lines))}

    # 用于记录找到的所有完整函数体，供后续处理
    all_function_bodies = []
    
    for match in matches:
        match_text = match.group()
        
        # 跳过常见的误匹配情况
        if any([
            'catch' in match_text,                    # catch块
            'super.' in match_text,                   # super调用
            'this.' in match_text,                    # this调用
            '.clone()' in match_text,                 # 方法调用
            match_text.strip().startswith('return'),  # return语句
            'new ' in text[max(0, match.start()-4):match.start()], # 构造器表达式
            '=>' in match_text,                       # lambda表达式
        ]):
            continue

        # 获取方法名
        method_name = match.group(1)
        
        # 处理方法体
        if match_text.strip().endswith(';'):
            # 对于没有方法体的方法，只保留接口方法和抽象方法
            if not ('abstract' in match_text.lower() or 'interface' in text[:match.start()].lower()):
                continue
            function_body = match_text
            start_pos = match.start()
            end_pos = match.end()
            function_body_lines = 1
        else:
            # 处理有方法体的方法
            brace_count = 1
            start_pos = match.start()
            i = match.end()
            
            # 寻找匹配的结束大括号
            while i < len(text) and brace_count > 0:
                if text[i] == '{':
                    brace_count += 1
                elif text[i] == '}':
                    brace_count -= 1
                i += 1
            
            if brace_count == 0:
                end_pos = i
                function_body = text[start_pos:end_pos]
                function_body_lines = function_body.count('\n') + 1
            else:
                continue

        # 计算行号
        start_line = sum(1 for _ in text[:start_pos].splitlines())
        end_line = sum(1 for _ in text[:end_pos].splitlines())
        
        # 确定可见性
        visibility = 'package'  # 默认包级别访问权限
        if 'public' in match_text:
            visibility = 'public'
        elif 'private' in match_text:
            visibility = 'private'
        elif 'protected' in match_text:
            visibility = 'protected'

        # 获取修饰符
        modifiers = []
        modifier_list = ['static', 'final', 'native', 'synchronized', 
                        'abstract', 'transient', 'volatile', 'strictfp']
        for modifier in modifier_list:
            if re.search(r'\b' + modifier + r'\b', match_text):
                modifiers.append(modifier)

        # 记录函数体用于后续处理
        all_function_bodies.append(function_body)
        
        # 创建函数信息对象
        function_info = {
            'type': 'FunctionDefinition',
            'name': 'special_' + method_name,
            'start_line': start_line + 1,
            'end_line': end_line,
            'offset_start': start_pos,
            'offset_end': end_pos,
            'content': function_body,
            'contract_name': filename.replace('.java', '_java' + str(hash)),
            'contract_code': '\n'.join(all_function_bodies),
            'modifiers': modifiers,
            'stateMutability': None,
            'returnParameters': None,
            'visibility': visibility,
            'node_count': function_body_lines
        }
        
        functions.append(function_info)

    return functions

def test_java_parser():
    def print_function_info(func):
        print(f"\nFunction: {func['name']}")
        print(f"Lines: {func['start_line']} - {func['end_line']}")
        print(f"Visibility: {func['visibility']}")
        print(f"Modifiers: {', '.join(func['modifiers']) if func['modifiers'] else 'None'}")
        print(f"Node Count: {func['node_count']}")
        print("Content:")
        print("---")
        print(func['content'])
        print("---")

    if len(sys.argv) != 2:
        print("Usage: python test_java_parser.py <java_file_path>")
        return

    file_path = sys.argv[1]
    try:
        with open(file_path, 'r', encoding='utf-8') as file:
            content = file.read()
    except Exception as e:
        print(f"Error reading file: {e}")
        return

    filename = file_path.split('/')[-1]
    hash_value = hash(content) & 0xffffffff  # 使用简单的hash值
    
    functions = find_java_functions(content, filename, hash_value)
    
    print(f"\nFound {len(functions)} functions in {filename}")
    print("=" * 50)
    
    for idx, func in enumerate(functions, 1):
        print(f"\nFunction #{idx}")
        print_function_info(func)
    
    # 保存详细结果到JSON文件
    output_filename = f"{filename}_analysis.json"
    with open(output_filename, 'w', encoding='utf-8') as f:
        json.dump(functions, f, indent=2)
    print(f"\nDetailed analysis saved to {output_filename}")

if __name__ == "__main__":
    test_java_parser()