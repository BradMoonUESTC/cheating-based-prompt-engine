# GPT Engine

## Description


# V2 Usage
## Scan Vulnerability
```shell
python src/main.py -path ../../dataset/agent-v1-c4/Archive -id Archive_aaa -cmd detect_vul -o output.json
```
## False Positive Check
```shell
python src/main.py -path ../../dataset/agent-v1-c4/Archive -id Archive_aaa -cmd check_vul_if_positive -o output.json
```
***id为自定义，使用后需记录以便进行误报检查***
