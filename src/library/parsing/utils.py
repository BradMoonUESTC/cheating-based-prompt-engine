import hashlib
from copy import deepcopy
import re
import traceback


# calculate hash
def hashString(content):
    return hashlib.md5(content.encode('utf-8')).hexdigest()

def hashFile(file_path):
    f = open(file_path, 'r', encoding='utf-8')
    return hashString(f.read())

# parse file
def stringClean(string:str):
    return string.replace("'","").replace('"','').replace(' ','').replace('\n','')