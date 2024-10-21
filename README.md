# cheat based Engine 使用说明

在 docker 文件夹下设置 `.env` 文件，通过创建 `.env` 文件并填写以下内容来配置你的环境：

TODO: 程序并没有从.env 读取环境变量，而是依靠事先 source

```
DATABASE_URL: "postgresql://${POSTGRES_USER_NAME}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB_NAME}"
# postgres
POSTGRES_DB_NAME=prompt-engine-db
POSTGRES_USER_NAME=prompt-engine
POSTGRES_PASSWORD=prompt-engine-password
POSTGRES_PORT=5433

# model setting
# openai
OPENAI_API_BASE="apix.ai-gaochao.cn"
OPENAI_API_KEY=xxxxxx
VUL_MODEL_ID=gpt-4-1106-preview

# Azure
AZURE_API_KEY="xxxxxxx"
AZURE_API_BASE="https://web3-westus.openai.azure.com/"
AZURE_API_VERSION="2024-08-01-preview"
AZURE_DEPLOYMENT_NAME="gpt-4-turbo"

AZURE_OR_OPENAI="AZURE" # OPENAI OR AZURE

# App setting
BUSINESS_FLOW_COUNT=10
SWITCH_FUNCTION_CODE=False
SWITCH_BUSINESS_CODE=True

```

其中：

- `VUL_MODEL_ID` 为所使用的模型 ID，建议使用 `gpt-4-turbo`。
- `BUSINESS_FLOW_COUNT` 为利用幻觉造成随机性时设置的随机次数，一般为 7-20，常用 10。
- `SWITCH_FUNCTION_CODE` 和 `SWITCH_BUSINESS_CODE` 为扫描时的粒度，支持函数粒度和业务流粒度。
- 其余为与 Azure OpenAI 相关的配置，如果使用 OpenAI，则不需要配置。可以通过 `AZURE_OR_OPENAI` 来选择。

> 如果从 docker 运行，那么不用更改 DATABASE_URL，如果是手动配置环境，注意修改主机名字为 localhost

## 基于 docker 运行

默认会把 projects 和 output 文件夹挂载在容器里，路径也是基于容器的，而不是 host。
在 docker 文件夹下，运行：

```
docker compose run --rm prompt-engine python src/main.py -fpath projects/shanxuan -id 1000shanxuan -cmd detect -o output/shanxuan.xlsx
```

## 配置本地环境

配置数据库，在 docker 文件夹下：

```
docker compose up -d
```

安装 python 依赖，建议 python 版本^3.9.0，3.10 及以上的版本可能在 MACOS 上遇到构建问题，需要手动解决。项目已经设置了基于 pyenv+poetry 的依赖方案，

```
   pyenv install 3.9.6
   poetry install
   poetry shell
```

如果手动配置环境，可以使用

```
pip install -r requirements.txt

```

6. 配置完成后，在根目录运行以下命令即可开始扫描过程。

```

python src/main.py -fpath ./shanxuan -id shanxuan11111222 -cmd detect -o ./output.xlsx

```

其中，`-fpath` 为项目路径，`-id` 为项目 ID，`-cmd` 为命令，`-o` 为输出漏洞文件路径。
cmd 的参数：

- detect 为扫描漏洞
- confirm 为确认已经扫描出的漏洞
- all 为扫描并确认漏洞
  通常是运行完 detect，然后运行 confirm，或者直接运行 all

## 注意事项

1. 扫描时可能会因为网络原因或 api 原因中断，对于此已经整理成随时保存，不修改 project_id 的情况下可以重新运行上一个指令，可以继续扫描
2. 唯一建议 gpt4-turbo，不要用 3.5，不要用 4o，4o 和 3.5 的推理能力是一样的
3. 一般扫描时间为 2-3 小时，取决于项目大小和随机次数，中型项目+10 次随机大约 2 个半小时
4. 中型项目+10 次随机大约需要 20 美金左右成本
5. 这个 tricky prompt 理论上经过轻微变种，可以有效的扫描任何语言，但是尽量需要 antlr 相应语言的 ast 解析做支持，因为如果有 code slicing，效果会更好
6. 目前支持 solidity，rust，move，go，python，cairo，func，tact 等语言
