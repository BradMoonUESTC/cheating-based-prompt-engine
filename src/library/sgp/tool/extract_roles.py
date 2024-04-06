from collections import defaultdict
import os
import re
import csv
from tqdm import tqdm


# Regular expressions to extract the information
contract_pattern = re.compile(r'contract\s+(.*?)Role(\s+is\s+[\w,\s]*)?\s*\{')
func_pattern = re.compile(r"function\s+(\w+)\s*\((?:.*?)\)")

# Regular expressions to extract the information
modifier_pattern = re.compile(r"modifier\s+(.*?)\((.*?)\)\s*\{(.*?)\}", re.DOTALL)
require_pattern = re.compile(r"require\(msg.sender\s+==\s+(.*?)\)")
func_pattern = re.compile(r"function\s+(.*?)\((.*?)\)\s*(public|private|external|internal)?\s*(.*?)\s*\{(.*?)\}", re.DOTALL)

# Function to extract information from Solidity code
def extract_Role_contract(code, path):
    roles_permissions = []

    # Search for contract
    contract_match = contract_pattern.search(code)
    if contract_match:
        contract_start = contract_match.end() - 1
        contract_name = contract_match.group(1)
        role = contract_name  # Extract role from contract name
        
        # Finding the end of contract
        braces_count = 0
        contract_end = contract_start
        # print(code[contract_start:])
        while contract_end < len(code):
            if code[contract_end] == '{':
                braces_count += 1
            elif code[contract_end] == '}':
                braces_count -= 1
            if braces_count == 0:
                break
            contract_end += 1

        contract_content = code[contract_start:contract_end+1]
        # Search for functions inside the contract
        func_matches = func_pattern.findall(contract_content)
        funcs = []
        for func_name in func_matches:
            funcs.append(func_name[0])
        roles_permissions.append((path, 'Contract', funcs, role))
    return roles_permissions


def check_openzeppelin_import(filename):
    with open(filename, 'r') as f:
        content = f.readlines()

    openzeppelin_access_controls = [
        "import '@openzeppelin/contracts/access/Ownable.sol';",
        "import '@openzeppelin/contracts/access/AccessControl.sol';",
        "import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';",
        "import '@openzeppelin/contracts/access/RoleBasedAccessControl.sol';", # Include any other access control mechanisms if OpenZeppelin adds more in the future
    ]

    for line in content:
        for control in openzeppelin_access_controls:
            if control in line:
                return True

    return False


# Function to extract information from Solidity code
def extract_info(code, path):
    roles_permissions = []

    # Search for function
    func_matches = func_pattern.findall(code)

    # Search for modifier and require statement inside each function
    for func_match in func_matches:
        func_name, _, _, modifier, body = func_match

        # Check if function uses modifier
        mod_match = modifier_pattern.search(code)
        if mod_match and mod_match.group(1) in modifier:
            roles_permissions.append((path, 'Modifier', func_name.strip(), mod_match.group(1)))

        # Check if function contains require statement
        req_match = require_pattern.search(body)
        if req_match:
            roles_permissions.append((path, 'Require', func_name.strip(), req_match.group(1)))
    role_contracts = extract_Role_contract(code, path)
    roles_permissions = roles_permissions + role_contracts
    return roles_permissions


def extract_roles_from_eth():
    with open('data/role/roles_permissions.csv', 'w') as f:
        writer = csv.writer(f)
        writer.writerow(['Path', 'Type', 'Functions', 'Role', 'isOZ'])
    c = 0
    # Read Solidity code from file
    for r, d, files in os.walk('../smart_contract/smart-contract-sanctuary-ethereum/contracts/mainnet/'):
        for file in files:
            if file.endswith('.sol'):
                c +=1
                print(c, '\r', end='', flush=True)
                path = os.path.join(r, file)
                with open(path, 'r') as f:
                    code = f.read()
                info = extract_info(code,path)
                is_oz = check_openzeppelin_import(path)
                info.append(str(is_oz))
                # Write to csv
                with open('data/role/roles_permissions.csv', 'a') as f:
                    writer = csv.writer(f)
                    writer.writerows(info)

def is_alphanumeric(s):
    return s.isalnum()

def is_nonsense(s):
    return re.match('[o|O]nly\d+', s)
def clean_output_file():
    counts = defaultdict(int)
    with open('data/role/roles_permissions.csv', 'r') as f, open('data/role/roles_permissions_clean.csv', 'w') as fw:
        writere = csv.writer(fw)
        writere.writerow(['Role', 'Functions'])
        for line in csv.reader(f):
            if not is_alphanumeric(line[3]):
                continue
            if is_nonsense(line[3]):
                print(line)
            if 'only' not in line[3] and 'role' not in line[3]:
                continue
            # if line[3].split(',')[0]+line[2] in visited:
            #     continue
            counts[line[3].split(',')[0]+'[Placeholder]'+line[2]]+=1
        
        for key, count in counts.items():
            print(key)
            role, func = key.split('[Placeholder]')
            writere.writerow([role, func, count])

def process_output():
    roles = {}
    with open('data/role/roles_permissions_clean.csv', 'r') as f:
        for line in csv.reader(f):
            if line[0]=='Role':
                continue
            if line[0].startswith('only'):
                roles[line[0].replace('only', '').lower()] = line[1]
            else:
                roles[line[0].lower()] = line[1]
        roles.pop('')
        print(len(roles))
        with open('data/role/roles_permissions_processed.csv', 'w') as fw:
            writer = csv.writer(fw)
            writer.writerow(['role', 'functions'])
            for key, item in roles.items():
                writer.writerow([key, item])
        print(roles.keys())
        # for each in roles.keys():
        #     print(each)

    

