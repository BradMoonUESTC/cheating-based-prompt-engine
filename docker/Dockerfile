# base stage
FROM python:3.9.6
USER root

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /prompt-engine

# 复制应用程序文件
COPY ../requirements.txt ./

# 安装 Python 依赖
RUN pip install --no-cache-dir -r requirements.txt
COPY ../src src
COPY ../projects projects

# 设置环境变量
ENV PYTHONPATH=/prompt-engine/src
