import re
from antlr4 import *
from sgp.parser.SolidityLexer import SolidityLexer
from sgp.parser.SolidityParser import SolidityParser
from sgp.parser.SolidityListener import SolidityListener
from colorama import Fore, init


def extract_solc_version(filename):
    with open(filename, 'r') as file:
        content = file.read()
        match = re.search(r'pragma solidity ([^;]*);', content)
        if match:
            # print(match.group(1))
            if '>=0.8.0 <0.9.0' in match.group(1):
                return '0.8.0'
            if '>=0.4.21 <0.6.0' in match.group(1):
                return '0.8.0'
            return match.group(1).replace('=', '')

        else:
            return None


def extract_comments_from_function(file_path, function_name):

    with open(file_path, 'r') as file:
        lines = file.readlines()

    content = "".join(lines)

    # Regular expression pattern for matching the function declaration with preceding comments.
    # pattern = re.compile(r"(//.*?$|/\*.*?\*/)\s*(function\s*"+re.escape(function_name)+r"\s*\([^{]*\)\s*\{)", re.DOTALL | re.MULTILINE)
    pattern = re.compile(r"(/\*.*?\*/)\s*(?=function\s*"+re.escape(function_name)+r")", re.DOTALL | re.MULTILINE)

    matches = pattern.findall(content)
    if not matches:
        # print(f"[WARNING] No function named '{function_name}' with preceding comments was found.")
        return

    pattern = re.compile(r"/\*.*?\*/", re.DOTALL | re.MULTILINE)
    matches = pattern.findall(matches[0])
    if not matches:
        print(f"[WARNING] No function named '{function_name}' with preceding comments was found.")
        return

    comments = matches[-1]

    return comments

def extract_comments_from_contract(file_path, contract_name):
    with open(file_path, 'r') as file:
        lines = file.readlines()

    content = "".join(lines)

    # Regular expression pattern for matching the contract declaration with preceding comments.
    pattern = re.compile(r"(//.*?$|/\*.*?\*/)\s*(contract\s*"+re.escape(contract_name)+r"\s*)", re.DOTALL | re.MULTILINE)

    matches = pattern.findall(content)

    if not matches:
        print(f"No contract named '{contract_name}' with preceding comments was found.")
        return

    comments = [match[0].strip() for match in matches]

    return comments

def extract_state_variables(contract_name, solidity_file_path):
    with open(solidity_file_path, 'r') as file:
        solidity_code = file.read()
    # # Find the contract
    # contract_pattern = re.compile(f'contract\\s+{contract_name}\\s*{{(.+?)}}', re.DOTALL)
    # match = contract_pattern.search(solidity_code)

    # if match is None:
    #     raise ValueError(f"No contract found with name: {contract_name}")

    # contract_body = match.group(1)
    contract_body = extract_contract(contract_name, solidity_code)
    # state_variable_pattern = re.compile(r'(public|private|internal|external)?\s+(uint256|uint|bool|string|address)\s+\w+;')
    state_variable_pattern = re.compile(
        r'[public|private|internal|external]?\s+\w+;')

    state_variables = [each.split(' ')[-1].replace(';', '') for each in state_variable_pattern.findall(contract_body)]

    return state_variables
from collections import defaultdict
def group_functions_by_contract(functions_list):
    """
    Groups functions by their contract name and concatenates their content into a single contract code without comments.
    Returns a list of lists, where each sublist contains the contract's functions and the concatenated contract code without comments.
    """
    # Group functions by contract name
    contracts = defaultdict(list)
    for function in functions_list:
        contracts[function["contract_name"]].append(function)
    
    # Prepare the result list
    result = []

    # Process each contract
    for contract_name, functions in contracts.items():
        contract_code_without_comment = ""
        for function in functions:
            # Remove comments from the function content
            content_without_comments = re.sub(r'\/\/.*|\/\*[\s\S]*?\*\/', '', function["content"])
            contract_code_without_comment += content_without_comments + "\n"
        
        # Append the grouped functions and the cleaned contract code to the result
        result.append({
            "contract_name": contract_name,
            "functions": functions,
            "contract_code_without_comment": contract_code_without_comment.strip()
        })
    
    return result
def extract_function_signature(function_code):
    """
    This function extracts the function signature from the provided Solidity function code.
    It also checks for the existence of specific keywords within the signature.
    """
    # Split the code at the first opening brace '{' to separate the signature
    parts = function_code.split('{', 1)
    if len(parts) < 2:
        return None, {"public": False, "view": False, "external": False, "pure": False}
    
    signature = parts[0].strip()
    keywords = ["public", "view", "external", "pure"]
    keyword_presence = {keyword.strip(): keyword in signature for keyword in keywords}
    
    return signature, keyword_presence
def check_function_if_public_or_external(function_code):
    signature, keyword_presence = extract_function_signature(function_code)
    return keyword_presence["public"] or keyword_presence["external"]
def check_function_if_view_or_pure(function_code):
    signature, keyword_presence = extract_function_signature(function_code)
    return keyword_presence["view"] or keyword_presence["pure"]
    
def extract_state_variables_from_code(contract_code):
    state_variable_pattern = re.compile(
        r'[public|private|internal|external]?\s+\w+;')

    state_variables = [each.split(' ')[-1].replace(';', '') for each in state_variable_pattern.findall(contract_code)]

    return state_variables
def extract_modifier_names_of_a_function(function_code):
    modifier_pattern = re.compile(r'(\w+)\s*\(')
    matches = modifier_pattern.findall(function_code)
    # The first match is the function name, so we remove it
    matches.pop(0)
    return matches


def extract_modifier_names(solidity_file_path, contract_name=None):
    with open(solidity_file_path, 'r') as file:
        solidity_code = file.read()
    # Find the contract
    # contract_pattern = re.compile(f'contract\\s+{contract_name}\\s*{{(.+?)}}', re.DOTALL)
    # match = contract_pattern.search(solidity_code)

    # if match is None:
    #     raise ValueError(f"No contract found with name: {contract_name}")

    # contract_body = match.group(1)
    if contract_name:
        contract_body = extract_contract(contract_name, solidity_code)
    else:
        contract_body = solidity_code
    modifier_pattern = re.compile(r'modifier\s+(\w+)', re.DOTALL)

    modifiers = modifier_pattern.findall(contract_body)
    if modifiers:
        return [each.replace('modifier ', '') for each in modifiers]
    else:
        return []


def extract_modifiers(solidity_file_path, contract_name=None):
    with open(solidity_file_path, 'r') as file:
        solidity_code = file.read()
    # Find the contract
    # contract_pattern = re.compile(f'contract\\s+{contract_name}\\s*{{(.+?)}}', re.DOTALL)
    # match = contract_pattern.search(solidity_code)

    # if match is None:
    #     raise ValueError(f"No contract found with name: {contract_name}")

    # contract_body = match.group(1)
    if contract_name:
        contract_body = extract_contract(contract_name, solidity_code)
    else:
        contract_body = solidity_code
    modifier_pattern = re.compile(r'modifier\s+\w+\s*\((.*?)\)\s*{(.*?)}', re.DOTALL)

    modifiers = modifier_pattern.findall(contract_body)

    return modifiers

def extract_inherited_contracts(contract_name, solidity_file_path):
    with open(solidity_file_path, 'r') as file:
        solidity_code = file.read()
    inherited_contracts = []

    # Pattern to match 'contract A is B, C, D { ... }'
    inheritance_pattern = re.compile(f'contract\\s+{contract_name}\\s+is\\s+([\\w\\s,]+)\\s*{{')

    # Find all inherited contracts
    match = inheritance_pattern.search(solidity_code)

    if match:
        # If there are inherited contracts, they are separated by commas
        # Split the string by comma and strip leading/trailing white space to get contract names
        inherited_contracts = [name.strip() for name in match.group(1).split(',')]

    return inherited_contracts

def extract_imported_contracts(solidity_file_path):
    with open(solidity_file_path, 'r') as file:
        solidity_code = file.read()
    imported_contracts = []

    # Pattern to match 'import "B.sol";' or 'import "./B.sol";'
    import_pattern = re.compile(r'import\s+"[^"]*\/(\w+)\.sol"\s*;')

    # Find all imported contracts
    imported_matches = import_pattern.findall(solidity_code)

    if imported_matches:
        imported_contracts.extend(imported_matches)

    return imported_contracts


def extract_contract(contract_name, solidity_code):
    # Find the contract
    contract_pattern = re.compile(f'[contract|interface|library]\\s+{contract_name}\\s*((is\\s*[\\w,\\s]+)*)?\\s*{{')
    match = contract_pattern.search(solidity_code)

    if match is None:
        return solidity_code

    start = match.end() - 1
    open_braces = 0

    # Go through the solidity code from the start of the contract until we've closed all braces
    for end in range(start, len(solidity_code)):
        if solidity_code[end] == '{':
            open_braces += 1
        elif solidity_code[end] == '}':
            open_braces -= 1

        # If all braces are closed, we've found the end of the contract
        if open_braces == 0:
            break

    contract_body = solidity_code[start:end + 1]
    return contract_body

def extract_function_from_solidity(function_name, solidity_file_path):
    # Read the Solidity code from the file
    func_or_modi = 'function'
    with open(solidity_file_path, 'r') as file:
        contract_body = file.read()
        # Find the function
        if function_name == 'constructor':
            # If the function is a constructor
            function_pattern = re.compile(f'{function_name}\\s*\\((.*?)\\)', re.DOTALL)
            match = function_pattern.search(contract_body)
        else:
            function_pattern = re.compile(f'function\\s+{function_name}\\s*\\((.*?)\\)', re.DOTALL)

            match = function_pattern.search(contract_body)
        if match is None:
            raise ValueError(f"No function found with name: {function_name} in contract: {contract_name}")
        start = match.start()
        open_braces = 0

        first_bracket = False

        # Go through the contract body from the start of the function until we've closed all braces
        for end in range(start, len(contract_body)):
            if contract_body[end] == '{':
                open_braces += 1
                first_bracket = True
            elif contract_body[end] == '}':
                open_braces -= 1

            # If all braces are closed, we've found the end of the function
            if open_braces == 0 and first_bracket:
                break

        function_body = contract_body[start:end + 1]

        return function_body

def extract_contract_with_name(contract_name,solidity_code):
   
    if contract_name!="":
        contract_body = extract_contract(contract_name, solidity_code)
    else:
        contract_body = solidity_code
    return contract_body
def extract_function_with_contract(contract_name, function_name, solidity_file_path):
    # Read the Solidity code from the file
    func_or_modi = 'function'
    if solidity_file_path == "":
        print(Fore.RED +"No solidity file path")
        init(autoreset=True)
        return None, None
    
    with open(solidity_file_path, 'r') as file:
        solidity_code = file.read()
        if contract_name!="":
            contract_body = extract_contract(contract_name, solidity_code)
        else:
            contract_body = solidity_code
        # Find the function
        if function_name == contract_name or function_name == 'constructor':
            # If the function is a constructor
            function_pattern = re.compile(f'{function_name}\\s*\\((.*?)\\)', re.DOTALL)
            match = function_pattern.search(contract_body)
        else:
            function_pattern = re.compile(f'function\\s+{function_name}\\s*\\((.*?)\\)', re.DOTALL)

            match = function_pattern.search(contract_body)
            if match is None:
                function_pattern = re.compile(f'modifier\\s+{function_name}\\s*\\((.*?)\\)', re.DOTALL)

                match = function_pattern.search(contract_body)
                if match:
                    func_or_modi = 'modifier'
        if match is None:
            raise ValueError(f"No function found with name: {function_name} in contract: {contract_name}")
        start = match.start()
        open_braces = 0

        first_bracket = False

        # Go through the contract body from the start of the function until we've closed all braces
        for end in range(start, len(contract_body)):
            if contract_body[end] == '{':
                open_braces += 1
                first_bracket = True
            elif contract_body[end] == '}':
                open_braces -= 1

            # If all braces are closed, we've found the end of the function
            if open_braces == 0 and first_bracket:
                break

        function_body = contract_body[start:end + 1]

        return function_body, func_or_modi


# use the function like this
# extract_function_from_solidity('contract.sol', 'myFunction')
