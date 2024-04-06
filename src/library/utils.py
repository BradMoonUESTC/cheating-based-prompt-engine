import hashlib

def strip_file_names(content):
    lines = content.split("\n")
    lines_sol = list(filter(lambda x : '.sol' in x , lines))
    
    return [x.split("\t")[0].rsplit('/', 1)[1].rsplit(' ')[0] for x in lines_sol]

def str_hash(str):
    md5_hash = hashlib.md5()
    md5_hash.update(str.encode('utf-8'))

    # 生成MD5哈希值
    md5_result = md5_hash.hexdigest()
    return md5_result
