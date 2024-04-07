## GPT Engine Usage

### Vulnerability Scanning

#### Setup for Testing
1. In `src/main.py`, set `switch_production_or_test` to `test` to configure the environment for testing purposes.

2. Place the project within the directory `src/dataset/agent-v1-c4`. This structure is critical for the tool to locate and interact with the data correctly.

3. Refer to the configuration file at `src/dataset/agent-v1-c4/datasets.json` for guidance on setting up your datasets. Once configured, you can execute `main.py` to begin the scanning process.

4. setup the database with the connection string provided in the `.env` file.

5. create db with sql `src/db.sql`

#### Environment Configuration
Configure your environment by creating a `.env` file with the following contents:

- `DATABASE_URL=postgresql://postgres:1234@127.0.0.1:5432/postgres`
    - This is your database connection string, which the tool will use to store and retrieve data. Ensure that the details match your PostgreSQL setup.

- `OPENAI_API_KEY=sk-xxxxx`
    - Replace `sk-xxxxx` with your actual OpenAI API key. This key enables the tool to interact with OpenAI services for various operations, such as data processing or analysis.



## GPT Engine 使用说明

### 漏洞扫描

#### 测试环境设置
1. 在 `src/main.py` 文件中，将 `switch_production_or_test` 设置为 `test`，以配置环境为测试模式。

2. 将项目放置于 `src/dataset/agent-v1-c4` 目录下。这一结构对于工具正确定位和与数据交互至关重要。

3. 参照 `src/dataset/agent-v1-c4/datasets.json` 配置文件来设置你的数据集。配置完成后，运行 `main.py` 即可开始扫描过程。

4. 设置.env

5. 使用`src/db.sql`创建数据库
#### 环境配置
通过创建 `.env` 文件并填写以下内容来配置你的环境：

- `DATABASE_URL=postgresql://postgres:1234@127.0.0.1:5432/postgres`
    - 这是你的数据库连接字符串，工具将使用它来存储和检索数据。确保详情与你的 PostgreSQL 设置相匹配。

- `OPENAI_API_KEY=sk-xxxxx`
    - 将 `sk-xxxxx` 替换为你的实际 OpenAI API 密钥。这个密钥使工具能够与 OpenAI 服务进行各种操作，如数据处理或分析。
