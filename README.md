# GPT Engine

## Description


# 用法
## 漏洞扫描
1. 在src/main.py中设置switch_production_or_test为test

2. 将项目放入到src/dataset/agent-v1-c4下

3. 参考src/dataset/agent-v1-c4/datasets.json配置后，运行main.py即可

.env配置：
DATABASE_URL=postgresql://postgres:1234@127.0.0.1:5432/postgres
OPENAI_API_KEY=sk-xxxxx(你的openai api key)

