import logging

import pyperclip

from tool.main import print_code, fix
from utilities.contract_extractor import extract_function_with_contract
from utilities.micelleneous import get_gpt_template, read_dataset
from colorama import Fore, init

def formulate_template(code_lines, description, gpt_template):
    prompt = ''
    prompt += print_code(code_lines, gpt_template)
    if description:
        print(gpt_template["evidence"]["description"], description)
        prompt+=gpt_template["evidence"]["description"], description

    prompt += fix(gpt_template)
    pyperclip.copy(prompt)
    print(
        '\n-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------')
    print(
        '-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n')


def run_baseline():
    gpt_template = get_gpt_template()
    # dataset = read_dataset(working_dir+'data/data_set - cve_data_set.csv')
    # dataset = read_dataset(working_dir + 'data/data_set - self-collected.csv')
    dataset = read_dataset('data/data_set - all_data_set.csv')
    for i, name in enumerate(dataset):
        # To resume from breakpoint
        if i < 112:
            continue

        # read dataset
        file = dataset[name]['file']
        logging.info(str(i) + ' Name: ' + name + ', File: ' + file)
        description = dataset[name]['description']
        clazz = dataset[name]['class']
        function = dataset[name]['function']
        # Extract the corresponding code from files
        code_lines, func_or_modi = extract_function_with_contract(clazz, function, file)
        if code_lines is None:
            print(Fore.RED +f'No code found for {name}, skip...')
            init(autoreset=True)
            continue
        # Print the question for GPT
        formulate_template(code_lines, description, gpt_template)

        # Continue with y/Y
        next = input('Next one?')
        if next == 'y' or next == 'Y':
            continue
        else:
            print('The last index was', i+1)
            break
