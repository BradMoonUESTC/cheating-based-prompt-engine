import csv
import json


def read_dataset(path):
    ret = {}
    with open(path) as f:
        for line in csv.reader(f):
            if line[0]=='name':
                continue
            ret[line[0]] = {
                'file': line[1],
                'class': line[2],
                'function': line[3],
                'description': line[5]
            }
    return ret

def get_gpt_template():
    gpt = json.load(open('data/gpt_template.json'))
    gpt['evidence']['role_category'] = json.load(open('data/role/Pre-study - Roles&Permissions.json'))
    gpt['evidence']['templates'] = json.load(open('data/role/Pre-study - Templates.json'))
    return gpt