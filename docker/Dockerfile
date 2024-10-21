# base stage
FROM python:3.9.6
USER root

# 设置非交互模式，避免安装依赖时的交互提示  
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /prompt-engine

# 开发环境中修改容器中的 APT 配置，以保留下载的包文件，而不是在安装后删除它们。部署时请删除这两行
# RUN rm -f /etc/apt/apt.conf.d/docker-clean \
#     && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# 复制应用程序文件
COPY ../requirements.txt ./

# 安装 Python 依赖
RUN pip install --no-cache-dir -r requirements.txt
COPY ../src src
COPY ../projects projects

# 设置环境变量
ENV PYTHONPATH=/prompt-engine/src
