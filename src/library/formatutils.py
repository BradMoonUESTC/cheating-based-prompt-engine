import csv
import json
import os

def convert_csv_to_json(csv_file, output_path):
    if not os.path.exists(output_path):
        os.makedirs(output_path)

    with open(csv_file, mode='r', encoding='utf-8') as csv_file:
        csv_reader = csv.DictReader(csv_file)
        data = []
        for row in csv_reader:
            data.append(row)
    
    for i in range(len(data)):
        out_file = os.path.join(output_path, "%03d.json" % (i + 1))
        with open(out_file, mode='w', encoding='utf-8') as json_file :
            json.dump(data[i], json_file, ensure_ascii=False, indent=2)


def dump_dictlist_to_csv(data, csv_file):
    if (len(data) == 0):
        return
    
    f = open(csv_file, "w", newline="", encoding='utf-8-sig')
    writer = csv.writer(f)
    writer.writerow(data[0].keys())
    [writer.writerow(x.values()) for x in data]



if __name__ == '__main__':
    convert_csv_to_json("../dataset/gap-16.csv", "../out/gap-16")
