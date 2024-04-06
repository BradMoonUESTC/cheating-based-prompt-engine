import csv
import logging
import re
import pyperclip
from time import time
from utilities.contract_extractor import extract_function_with_contract, extract_inherited_contracts, \
    extract_imported_contracts, extract_state_variables, extract_modifiers, \
    extract_comments_from_contract, extract_comments_from_function, extract_solc_version, extract_contract, \
    extract_modifier_names
from utilities.micelleneous import read_dataset, get_gpt_template
from utilities.call_graph_generator import get_callers_callees


def print_rbac_mechanisms(file, clazz, function, func_or_modi, gpt_template):
    prompt = ''
    did_print = False
    # print(
    #     '\n\n-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------')
    # print(
    #     '-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n\n')
    solc_version = extract_solc_version(file)
    if clazz != 'NONE' and clazz != '':
        # imported = extract_imported_contracts(file)
        inherited = extract_inherited_contracts(clazz, file)
        state_vairables = extract_state_variables(clazz, file)
        modifiers = extract_modifier_names(file, clazz)
        if inherited:
            print(f'{gpt_template["evidence"]["inherited"]} {inherited}.', end="")
            prompt += f'{gpt_template["evidence"]["inherited"]} {inherited}.'+'\n'
            did_print = True
        if state_vairables:
            print(f'{gpt_template["evidence"]["state variables"]} {state_vairables}.', end="")
            prompt += f'{gpt_template["evidence"]["state variables"]} {state_vairables}.'+'\n'
            did_print = True
        if modifiers:
            print(f'{gpt_template["evidence"]["modifier names"]} {modifiers}. ', end="")
            did_print = True
            prompt += f'{gpt_template["evidence"]["modifier names"]} {modifiers}. ' +'\n'
    else:
        modifiers = extract_modifier_names(file, clazz)
        if modifiers:
            print(f'{gpt_template["evidence"]["modifier names"]} {modifiers}. ', end="")
            prompt += f'{gpt_template["evidence"]["modifier names"]} {modifiers}. \n'
            did_print = True
    if func_or_modi == 'function':
        # Do not search callers for modifiers
        state_var_functions, callers, callees = get_callers_callees(file, function, solc_version)
        if callers:
            print("Callers for function", '`' + function + '`', "are:")
            prompt += "Callers for function"+ ' `' + function + '` '+ "are:\n"
            did_print = True
            # for caller, src in callers.items():
            #     # for caller, paths in callers.items():
            #     # print("Function", caller, ", call paths:", paths, '.')
            #     print("Function", caller, ", source code:", src, '.')
        else:
            print('This function has no callers.')
            prompt += 'This function has no callers.\n'
        if callees:
            print("Callees for function", '`' + function + '`', "are:")
            prompt += "Callees for function"+ ' `' + function + '` '+ "are:" + '\n'
            did_print = True
            # for callee, src in callees.items():
            #     # for callee, paths in callees.items():
            #     # print("Function", callee,  "call paths:", paths, '.')
            #     print("Function", callee, ", source code:", src, '.')
        else:
            print('This function has no callees.')
            prompt += 'This function has no callees.' + '\n'
        if state_var_functions:
            print(f"The functions that use the same state variables as function {function} are:")
            prompt += f"The functions that use the same state variables as function {function} are:" + '\n'
            for func, src in state_var_functions.items():
                did_print = True
                print(func)  # source code:", src, '.')
                prompt += func + '\n'

        return prompt, did_print, (state_var_functions, callers, callees)
    return prompt, did_print, ({}, {}, {})


def check_transitivity(file, clazz, function, gpt_template):
    print(
        '\n\n-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------')
    print(
        '-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n\n')

    callers, callees = get_callers_callees(file, function)

    # codes = []
    # for caller in callers:
    #     codes.append(extract_function_from_solidity(clazz, caller, file))
    # if not codes:
    #     print(f'{gpt_template["question"]["transitive"]}: ``` {" ".join(codes)} ```')


def ask_practice(gpt_template):
    # print(
    #     '\n\n-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------')
    # print(
    #     '-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n\n')

    print(gpt_template['question']['common practice'])





def ask_user_role_permission(gpt_template):
    print(gpt_template['question']['role'])
    print(gpt_template['evidence']['role_category'])
    return gpt_template['question']['role']+ '\n'+ str(gpt_template['evidence']['role_category'])
    # if description != 'N.A.':
    #     print(
    #         '\n\n-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------')
    #     print(
    #         '-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n\n')
    #
    #     print(f'{gpt_template["evidence"]["description"]} ``` {description} ```. {gpt_template["question"]["users"]}')


def fix(gpt_template, has_rbac=False):
    # Based on the principle of least privilege,
    # print(
    #     '\n\n-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------')
    # print(
    #     '-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n\n')
    if has_rbac:
        print(gpt_template['question']['fix has rbac'])
        return gpt_template['question']['fix has rbac']
    else:

        print(gpt_template['question']['fix'])
        return gpt_template['question']['fix']


def print_context_for_role(file, clazz, function, func_or_modi, rbac_names, context, gpt_template):
    prompt = ''
    #TODO: TO implement extraction: Call_chain Deps

    # print(
    #     '\n\n-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------')
    # print(
    #     '-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n\n')
    solc_version = extract_solc_version(file)
    comments = extract_comments_from_function(file, function)
    if comments:
        print(f'{gpt_template["evidence"]["comments"]} {comments}.')
        prompt += f'{gpt_template["evidence"]["comments"]} {comments}.' + '\n'
    if clazz != 'NONE' and clazz != '':
        modifiers = extract_modifiers(file, clazz)
        if func_or_modi == 'function':
            # Do not search callers for modifiers
            state_var_functions, callers, callees = context
            if callers:
                print("Callers for function", '`'+function+'`', "are:")
                prompt += "Callers for function"+ ' `'+function+'` '+ "are:" + '\n'
                for caller, src in callers.items():
                # for caller, paths in callers.items():
                    # print("Function", caller, ", call paths:", paths, '.')
                    print("Function", caller, ", source code:", src, '.')
                    prompt += "Function "+ caller+ " , source code: "+ src+ '.' + '\n'
            # else:
                # print('This function has no callers.')
                # prompt += 'This function has no callers.' + '\n'
            if callees:
                print("Callees for function", '`'+function+'`', "are:")
                prompt += "Callees for function"+ ' `'+function+'` ' + "are:" + '\n'
                for callee, src in callees.items():
                # for callee, paths in callees.items():
                    # print("Function", callee,  "call paths:", paths, '.')
                    with open(file, 'r') as f:
                        lines = f.readlines()
                        if 'emit '+callee in "".join(lines):
                            print("Event", callee, '.')
                            prompt += "Event " + callee + '.' + '\n'
                        else:
                            print("Function", callee, ", source code:", src, '.')
                            prompt += "Function " + callee + " , source code: " + src + '.' + '\n'
            # else:
            #     print('This function has no callees.')
            #     prompt += 'This function has no callees.' + '\n'
            if state_var_functions:
                template = ''
                # print(f"The functions that use the same state variables as function {function} are:")
                for func, src in state_var_functions.items():
                    if func in rbac_names:
                        if not template:
                            template+=f"The functions that use the same state variables as function {function} are:"
                        template+= func
                        template+=", source code:"
                        template+= src
                print(template)
                prompt += template + '\n'

        if modifiers:
            print(f'{gpt_template["evidence"]["modifier"]} {modifiers}. ', end="")
            prompt += f'{gpt_template["evidence"]["modifier"]} {modifiers}. ' + '\n'

    return prompt


def check_existing_ac(file, clazz, function, gpt_template):
    print(
        '\n\n-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------')
    print(
        '-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n\n')

    comments = extract_comments_from_function(file, function)
    if clazz!='':
        imported = extract_imported_contracts(file)
        inherited = extract_inherited_contracts(clazz, file)
        state_vairables = extract_state_variables(clazz, file)
        modifiers = extract_modifiers(clazz, file)
        # contract_comments = extract_comments_from_contract(file, clazz)
        if inherited:
            print(f'{gpt_template["evidence"]["imported and inherited"]} {imported}, {inherited}.', end="")
        if state_vairables:
            print(f'{gpt_template["evidence"]["state variables"]} {state_vairables}.', end="")
        if modifiers:
            print(f'{gpt_template["evidence"]["modifier"]} {modifiers}. ', end="")
        if comments:
            print(f'{gpt_template["evidence"]["comments"]} {comments} ', end="")
        print(f'{gpt_template["question"]["existing"]}', end="")

def print_code(code_lines, gpt_template):
    # print(
    #     '\n\n-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------')
    # print(
    #     '-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n\n')
    print('----'*5)
    print(gpt_template["evidence"]["Role playing"])
    print(gpt_template["evidence"]["code"], "```\n"+code_lines+"\n```")
    return gpt_template["evidence"]["Role playing"]+'\n'+gpt_template["evidence"]["code"]+" ```\n"+code_lines+"\n```\n"

def print_description(description, gpt_template):
    if description:
        print(gpt_template["evidence"]["description"], description)
        return gpt_template["evidence"]["description"]+' '+description+'\n'
    return ''

def read_role_permission(gpt_template):
    print(
        '\n-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------')
    print(
        '-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n')
    role_permission = input('Pleas key in the role and permission:\n')
    if role_permission == '':
        role_permission = input('Pleas key in the role and permission:\n')
    if role_permission:
        role = re.search('Role: (.*),', role_permission)
        if role:
            role = role.group(1)
        permission = re.search('Permission: (.*)', role_permission)
        if permission:
            permission = permission.group(1)
    else:
        role = input('Role:\n').strip().strip('.').replace('.', '')
        permission = input('Permission:\n').strip().replace('.', '')
    # role = role.replace('Role:', '').strip().replace('\'', '')
    # permission = permission.replace('Permission:', '').strip().replace('\'', '')
    print(
        '\n\n-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------')
    print(
        '-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n\n')

    print("The common practices of code patch for this vulnerability are", gpt_template['evidence']['templates'][role][permission])
    return "The common practices of code patch for this vulnerability are "+ str(gpt_template['evidence']['templates'][role][permission])

def ask_rbac(gpt_template):
    print(gpt_template['question']['RBAC'])
    print(
        '\n\n-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------')
    print(
        '-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n\n')
    names = input('Key in names:')

    print(
        '\n\n-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------')
    print(
        '-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n\n')
    if names == 'n':
        return []
    return names.replace(' ', '').split(',')

def main():
    gpt_template = get_gpt_template()
    # dataset = read_dataset(working_dir+'data/data_set - cve_data_set.csv')
    # dataset = read_dataset(working_dir + 'data/data_set - self-collected.csv')
    dataset = read_dataset('data/Dataset - Benchmark.csv')
    last_index = 15


    for i, name in enumerate(dataset):
        if i < last_index:
            continue
        function = dataset[name]['function']
        if function == '':
            continue
        timer = time()
        file = dataset[name]['file']
        logging.info(str(i)+' Name: ' + name+', File: '+file)
        clazz = dataset[name]['class']
        description = dataset[name]['description']
        code_lines, func_or_modi = extract_function_with_contract(clazz, function, file)
        # print ('-----')
        # print(code_lines)
        # print(func_or_modi)

        # #print(f'\n\n{gpt_template["question"]["type"]}: ``` {code_lines} ```')
        # print ('-----')
        first_prompt = ''
        first_prompt += print_code(code_lines, gpt_template)
        first_prompt += print_description(description, gpt_template)

        # RBAC inquiry
        prompt, did_print, context = print_rbac_mechanisms(file, clazz, function, func_or_modi, gpt_template)
        first_prompt += prompt
        
        names = []
        second_prompt = ''
        if did_print:
            first_prompt += gpt_template['question']['RBAC']
            pyperclip.copy(first_prompt)
            names = ask_rbac(gpt_template)
        else:
            second_prompt += first_prompt
        timer = time()



        # Print all relevant code and ask for the role/permission
        second_prompt += print_context_for_role(file, clazz, function, func_or_modi, names, context, gpt_template)
        second_prompt += ask_user_role_permission(gpt_template)
        pyperclip.copy(second_prompt)
        # ask_practice(gpt_template)



        # check_existing_ac(file, clazz, function, gpt_template)

        # check_transitivity(file, clazz, function, gpt_template)
        third_prompt = ''
        third_prompt += read_role_permission(gpt_template)


        third_prompt += fix(gpt_template, did_print)
        pyperclip.copy(third_prompt)
        print(
            '\n\n-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------')
        print(
            '-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n\n')
        next = input('Next one?')
        if next== 'y' or next == 'Y':
            with open('data/time.csv', 'a') as f:
                csv.writer(f).writerow([i, name, time() - timer])
            continue
        else:
            print('The last index was', i, 'Next is', i+1)
            break
