# Recently Updated
2024.04.29:
1. Add function to basiclly support rust language.

2024.05.16:
1. Add support for cross-contract vulnerability confirmation, reduce the false positive rate approximately 50%.
2. upadte the structure of the db
3. add CN explaination

2024.05.18:
1. Add prompt for check if result of vulnerability has assumations, reduce the false positive rate approximately 20%.

2024.06.01:
1. Add support for python language, dont ask me why, so annoying.
   
2024.07.01
1. Update the license

2024.07.23
1. Add support for cairo, move

2024.08.01
1. Add support for func, tact
   
# TODO
1. Optimize code structure
2. Add more language support
3. Write usage documentation and code analysis
4. Add command line mode for easy use

   

审计赏金成果：截止2024年5月，此工具已获得$60000+
<img width="1258" alt="image" src="https://github.com/BradMoonUESTC/trickPrompt-engine/assets/63706549/b3812927-2aa9-47bf-a848-753c2fe05d98">


Audit bounty results: As of May 2024, this tool has received $60,000+


------
1. 优化代码结构
2. 增加更多语言支持
3. 编写使用文档和代码解析
4. 增加命令行模式，方便使用

## Introduction
This is a vulnerability mining engine purely based on GPT, requiring no prior knowledge base, no fine-tuning, yet its effectiveness can overwhelmingly surpass most of the current related research. 

The key lies in the design of prompts, which has shown excellent results. The core idea revolves around:

- Being task-driven, not question-driven.
- Driven by prompts, not by code.
- Focused on prompt design, not model design.

The essence is encapsulated in one word: "deception."

### Note:
- This is a type of code understanding logic vulnerability mining that fully stimulates the capabilities of gpt. The control flow type vulnerability detection ability is ineffective and is suitable for real actual projects.
- Therefore, don’t run tests on meaningless academic vulnerabilities
## GPT Engine Usage

### Vulnerability Scanning

Here's the translation into English:

**Test Environment Setup**

1. In the `src/main.py` file, set `switch_production_or_test` to `test` to configure the environment in test mode.
   
2. Place the project under the directory `src/dataset/agent-v1-c4`. This structure is crucial for proper tool positioning and interaction with data.

3. Refer to the configuration file `src/dataset/agent-v1-c4/datasets.json` to set up your project collection. For example:

```json
"StEverVault2":{
    "path":"StEverVault",
    "files":[
    ],
    "functions":[]
}
```

Where `StEverVault2` represents the custom name of the project, matching the `project_id` in `src/main.py`. `path` refers to the actual path of the project under `agent-v1-c4`. `files` specifies the contract files to be scanned; if not configured, it defaults to scanning all files. `functions` specifies the specific function names to be scanned; if not configured, it defaults to scanning all functions, in the format `[contract_name.function_name]`.

4. Use `src/db.sql` to create the database; PostgreSQL needs to be installed beforehand.

5. Set up the `.env` file by creating it and filling in the following details to configure your environment:

```
# Database connection information
DATABASE_URL=postgresql://postgres:1234@127.0.0.1:5432/postgres

# OpenAI API
OPENAI_API_BASE="apix.ai-gaochao.cn"
OPENAI_API_KEY=xxxxxx

# Model IDs
BUSINESS_FLOW_MODEL_ID=gpt-4-turbo
VUL_MODEL_ID=gpt-4-turbo

# Business flow scanning parameters
BUSINESS_FLOW_COUNT=10

SWITCH_FUNCTION_CODE=False
SWITCH_BUSINESS_CODE=True
```

Where:
- `DATABASE_URL` is the database connection information.
- `OPENAI_API_BASE` is the GPT API connection information, usually `api.openai.com`.
- `OPENAI_API_KEY` should be set to your actual OpenAI API key.
- `BUSINESS_FLOW_MODEL_ID` and `VUL_MODEL_ID` are the IDs of the models used, recommended to use `gpt-4-turbo`.
- `BUSINESS_FLOW_COUNT` is the number of randomizations used to create variability, typically 7-20, commonly 10.
- `SWITCH_FUNCTION_CODE` and `SWITCH_BUSINESS_CODE` are the granularity settings during scanning, supporting function-level and business flow-level granularity.

6. After configuring, run `main.py` to start the scanning process.
## 介绍
这是一个纯基于gpt的漏洞挖掘引擎，不需要任何前置知识库，不需要任何fine-tuning，但效果足可以碾压当前大部分相关研究的效果

核心关键在于prompt的设计，效果非常好

核心思路：
- task driven, not question driven
- 关键一个字在于“骗”
- 利用幻觉，喜欢幻觉
### 注
- 这是一种充分激发gpt能力的代码理解型的逻辑漏洞挖掘，控制流类型的漏洞检测能力效果差，适用于真正的实际项目
- 因此，不要拿那些无意义的学术型漏洞来跑测试

## GPT Engine 使用说明

测试环境设置如下：

1. 在 `src/main.py` 文件中，将 `switch_production_or_test` 设置为 `test`，以配置环境为测试模式。

```python
if __name__ == '__main__':
    switch_production_or_test = 'test' # prod / test
    if switch_production_or_test == 'test':
        # Your code for test environment
```

2. 将项目放置于 `src/dataset/agent-v1-c4` 目录下，这一结构对于工具正确定位和与数据交互至关重要。

3. 参照 `src/dataset/agent-v1-c4/datasets.json` 配置文件来设置你的项目集。例如：

```json
"StEverVault2":{
    "path":"StEverVault",
    "files":[
    ],
    "functions":[]
}
```

其中，`StEverVault2` 代表项目自定义名，它的名字与 `src/main.py` 中的 `project_id` 相同。`path` 指代的是 `agent-v1-c4` 下项目的具体实际路径。`files` 指代的是要具体扫描的合约文件，如果不配置，则默认扫描全部。`functions` 指代的是要具体扫描的函数名，如果不配置，则默认扫描全部函数，形式为【合约名.函数名】。

4. 使用 `src/db.sql` 创建数据库，需要提前安装 PostgreSQL。

5. 设置 `.env` 文件，通过创建 `.env` 文件并填写以下内容来配置你的环境：

```
# 数据库连接信息
DATABASE_URL=postgresql://postgres:1234@127.0.0.1:5432/postgres

# OpenAI API
OPENAI_API_BASE="apix.ai-gaochao.cn"
OPENAI_API_KEY=xxxxxx

# 模型ID
BUSINESS_FLOW_MODEL_ID=gpt-4-turbo
VUL_MODEL_ID=gpt-4-turbo

# 业务流扫描参数
BUSINESS_FLOW_COUNT=10

SWITCH_FUNCTION_CODE=False
SWITCH_BUSINESS_CODE=True
```

其中：
- `DATABASE_URL` 为数据库连接信息。
- `OPENAI_API_BASE` 为 GPT API 连接信息，一般情况下为 `api.openai.com`。
- `OPENAI_API_KEY` 设置为对应的 OpenAI API 密钥。
- `BUSINESS_FLOW_MODEL_ID` 和 `VUL_MODEL_ID` 为所使用的模型 ID，建议使用 `gpt-4-turbo`。
- `BUSINESS_FLOW_COUNT` 为利用幻觉造成随机性时设置的随机次数，一般为 7-20，常用 10。
- `SWITCH_FUNCTION_CODE` 和 `SWITCH_BUSINESS_CODE` 为扫描时的粒度，支持函数粒度和业务流粒度。

6. 配置完成后，运行 `main.py` 即可开始扫描过程。

1. 扫描时可能会因为网络原因或api原因中断，对于此已经整理成随时保存，不修改project_id的情况下可以重新运行main.py，可以继续扫描
2. 唯一建议gpt4-turbo，不要用3.5，不要用4o，4o和3.5的推理能力是一样的，拉的一批
3. 一般扫描时间为2-3小时，取决于项目大小和随机次数，中型项目+10次随机大约2个半小时
4. 中型项目+10次随机大约需要20-30美金成本
5. 当前还是有误报，按项目大小，大约30-65%，小项目误报会少一些，且还有很多自定义的东西，后续会继续优化
6. 结果做了很多标记和中文解释
  1. 优先看result列中有【"result":"yes"】的（有时候是"result": "yes"，带个空格）
  2. category列优先筛选出【dont need In-project other contract】 的
  3. 具体的代码看business_flow_code列
  4. 代码位置看name列
# 注意
1. gpt4效果会更好，gpt3尚未深入尝试
2. 这个tricky prompt理论上经过轻微变种，可以有效的扫描任何语言，但是尽量需要antlr相应语言的ast解析做支持，因为如果有code slicing，效果会更好
3. 目前只支持solidity，后续会支持更多语言

# TODO
刚刚release，还没写完，后续再补充
