import csv
import logging
import shutil
import os
import subprocess
import hashlib

from utilities.contract_extractor import extract_solc_version
from utilities.micelleneous import read_dataset

def execute_commands(i, name, description):
    cwd = os.getcwd()
    solc_version = extract_solc_version('other_tools/sGuard/contracts/sample.sol')
    os.chdir('other_tools/sGuard/')
    # logging.debug('npm run dev')
    if solc_version:
        subprocess.check_output('solc-select use ' + solc_version.replace('^', '') + ' --always-install',
                                stderr=subprocess.STDOUT, shell=True)
    result = ''
    try:
        p = subprocess.run(['npm', 'run', 'dev'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=300)
        result = p.stderr
    except:
        pass
    # print(p.stderr)
    os.chdir(cwd)
    res = 'n'
    if 'Error' not in str(result) and os.path.getmtime('/Users/lyuye/workspace/access-control-repair/other_tools/sGuard/contracts/sample.sol')<=os.path.getmtime('/Users/lyuye/workspace/access-control-repair/other_tools/sGuard/contracts/fixed.sol'):
        if os.path.getsize('/Users/lyuye/workspace/access-control-repair/other_tools/sGuard/contracts/sample.sol') != os.path.getsize('/Users/lyuye/workspace/access-control-repair/other_tools/sGuard/contracts/fixed.sol'):
            p = subprocess.run(['code', '--diff', '/Users/lyuye/workspace/access-control-repair/other_tools/sGuard/contracts/sample.sol', '/Users/lyuye/workspace/access-control-repair/other_tools/sGuard/contracts/fixed.sol'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            logging.info('Description: ' + description)
            res = input('Is the fix correct? [y/n]')
        with open('data/sGuard.csv', 'a') as f:
            csv.writer(f).writerow([i, name, res, 'compilable'])
    else:
        logging.error(result)
        with open('data/sGuard.csv', 'a') as f:
            csv.writer(f).writerow([i, name, res, 'uncompilable'])
def run_sGuard():
    dataset = read_dataset('data/data_set - all_data_set.csv')
    last_index = 0
    with open('data/sGuard.csv', 'r') as f:
        for l in csv.reader(f):
            last_index = int(l[0])



    for i, name in enumerate(dataset):
        if i <= last_index:
            continue
        function = dataset[name]['function']
        if function == '':
            continue
        file = dataset[name]['file']
        logging.info(str(i) + ' Name: ' + name + ', File: ' + file)
        description = dataset[name]['description']
        shutil.copy(file, 'other_tools/sGuard/contracts/sample.sol')

        execute_commands(i, name, description)

