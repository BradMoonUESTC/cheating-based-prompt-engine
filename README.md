## cheat based Engine 使用说明

环境设置如下：

1. 使用 `src/db.sql` 创建数据库，需要提前安装 PostgreSQL。

2. 设置 `.env` 文件，通过创建 `.env` 文件并填写以下内容来配置你的环境：

```
# 数据库连接信息
DATABASE_URL=postgresql://postgres:1234@127.0.0.1:5432/postgres
OPENAI_API_BASE="apix.ai-gaochao.cn"
OPENAI_API_KEY=sk-hQfski4aO06WQD0jF442Da78D4Ef4f758c678aC095Dc0a9b
VUL_MODEL_ID=gpt-4-1106-preview
AZURE_API_KEY="xxxxxxx"
AZURE_API_BASE="https://web3-westus.openai.azure.com/"
AZURE_API_VERSION="2024-08-01-preview"
AZURE_DEPLOYMENT_NAME="gpt-4-turbo"
AZURE_OR_OPENAI=AZURE # OPENAI OR AZURE
BUSINESS_FLOW_COUNT=1
SWITCH_FUNCTION_CODE=False
SWITCH_BUSINESS_CODE=True
```

其中：
- `DATABASE_URL` 为数据库连接信息。
- `OPENAI_API_BASE` 为 GPT API 连接信息，一般情况下为 `api.openai.com`。
- `OPENAI_API_KEY` 设置为对应的 OpenAI API 密钥。
- `VUL_MODEL_ID` 为所使用的模型 ID，建议使用 `gpt-4-turbo`。
- `BUSINESS_FLOW_COUNT` 为利用幻觉造成随机性时设置的随机次数，一般为 7-20，常用 10。
- `SWITCH_FUNCTION_CODE` 和 `SWITCH_BUSINESS_CODE` 为扫描时的粒度，支持函数粒度和业务流粒度。
- 其余为与Azure OpenAI相关的配置，如果使用OpenAI，则不需要配置。可以通过 `AZURE_OR_OPENAI` 来选择。

6. 配置完成后，运行以下命令即可开始扫描过程。
```
python src/main.py -fpath ./shanxuan -id shanxuan11111222 -cmd detect -o ./output.xlsx
```
其中，`-fpath` 为项目路径，`-id` 为项目ID，`-cmd` 为命令，`-o` 为输出文件路径。
cmd的参数：
- detect 为扫描漏洞
- confirm 为确认已经扫描出的漏洞
- all 为扫描并确认漏洞
通常是运行完detect，然后运行confirm，或者直接运行all

1. 扫描时可能会因为网络原因或api原因中断，对于此已经整理成随时保存，不修改project_id的情况下可以重新运行上一个指令，可以继续扫描
2. 唯一建议gpt4-turbo，不要用3.5，不要用4o，4o和3.5的推理能力是一样的
3. 一般扫描时间为2-3小时，取决于项目大小和随机次数，中型项目+10次随机大约2个半小时
4. 中型项目+10次随机大约需要20美金左右成本
# 注意
1. gpt4效果会更好，gpt3尚未深入尝试
2. 这个tricky prompt理论上经过轻微变种，可以有效的扫描任何语言，但是尽量需要antlr相应语言的ast解析做支持，因为如果有code slicing，效果会更好
3. 目前支持solidity，rust，move，go，python，cairo，func，tact等语言
