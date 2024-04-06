
import os
import csv
import pathlib

class AuditRules(object):
    def __init__(self):
        self.rule_type = "v1"
        current_path = pathlib.Path(__file__).parent.parent.resolve()
        rules_path = os.path.join(current_path, "db/v1")
        self.keywords_path = os.path.join(rules_path, "keywords.txt")
        self.sentences_file = os.path.join(rules_path, "keysentences.csv")

        # Step 3: 读取txt文件，并将其内容分为六组
        # script_directory = pathlib.Path(__file__).parent.resolve()
        # keywords_path = script_directory / "keywords.txt"

        with open(self.keywords_path, 'r') as f:
            words = f.readlines()
        
        group_size = len(words) // 6
        self.word_groups = [words[i:i + group_size] for i in range(0, len(words), group_size)]

        ## 2. csv 
        self.rules = []
        with open(self.sentences_file, mode='r') as file:
            reader = csv.reader(file)
            next(reader)  # skip header row
            for row in reader:
                self.rules.append(row)


    def filter_rules(self, keywords_list):
        if len(keywords_list) == 0:
            return []
        
        keyword_sentences = []
        for row in self.rules:
            for keyword in keywords_list:
                if keyword in row[0:3]:  # search in BusinessType, Sub-BusinessType, FunctionType
                    keyword_sentences.append((keyword, row[3], row[0], row[1], row[2]))
    
        print("\tsearch_keywords_in_csv ", len(keyword_sentences), "/".join(keywords_list))
        return keyword_sentences
    
    
    def get_keywords_list(self):
        kws = []
        for group_id in range(len(self.word_groups)):
            group = self.word_groups[group_id]
            keywords = "\n".join([word.strip() for word in group])
            kws.append(keywords)
        
        return kws
    

def test():
    base_path = pathlib.Path(__file__).parent.resolve()
    audit_rules = AuditRules(base_path)
    audit_rules.filter_rules(["Token Vesting"])

    
if __name__ == '__main__':
    test()