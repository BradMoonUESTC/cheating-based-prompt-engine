FROM ubuntu:22.04

COPY src /app
COPY requirements.txt /app/
WORKDIR /app

ARG DATABASE_URL
ARG PEZZO_API_KEY
ARG PEZZO_PROJECT_ID
ARG PEZZO_ENVIRONMENT
ARG SSH_PRIVATE_KEY

ENV DATABASE_URL=${DATABASE_URL:-postgresql://postgres:1234@localhost:5432/postgres} \
    PEZZO_API_KEY=${PEZZO_API_KEY:-test} \
    PEZZO_PROJECT_ID=${PEZZO_PROJECT_ID:-clmeshz6f007vwt0he19wbsy0} \
    PEZZO_ENVIRONMENT=${PEZZO_ENVIRONMENT:-Production}

RUN apt update && \
    apt install -y software-properties-common openssh-client git && \
    add-apt-repository ppa:deadsnakes/ppa -y && \
    apt install -y --no-install-recommends openjdk-17-jdk python3.10 python3-pip pkg-config vim libcairo2-dev && \
    mkdir -p /root/.ssh && \
    chmod 0700 /root/.ssh && \
    ssh-keyscan github.com >> /root/.ssh/known_hosts && \
    echo "${SSH_PRIVATE_KEY}" > /root/.ssh/id_rsa && \
    chmod 0600 /root/.ssh/id_rsa && \
    python3.10 -m pip install -r /app/requirements.txt && \
    python3.10 -c "import tiktoken; tiktoken.get_encoding('cl100k_base')" && \
    rm -rf /var/lib/apt/lists/* && \
    sed -i "s/BUILD_TIME/`date`/g" /app/buildTime.py

CMD ["tail", "-f", "/dev/null"]
