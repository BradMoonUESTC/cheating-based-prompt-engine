FROM python:3.9.6

ENV DEBIAN_FRONTEND=noninteractive

# 安装 PostgreSQL 客户端和其他必要的包
RUN apt-get update && apt-get install -y \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 复制应用程序文件
COPY src/ ./src/
COPY requirements.txt ./

# 安装 Python 依赖
RUN pip install --no-cache-dir -r requirements.txt

# 复制启动脚本
COPY start.sh /start.sh
RUN chmod +x /start.sh

# 设置环境变量
ENV PYTHONPATH=/app/src

# 使用启动脚本作为入口点
ENTRYPOINT ["/start.sh"]

# 默认命令
CMD ["python", "/app/src/main.py"]