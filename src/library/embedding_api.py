import sys
import time
import openai
from openai.error import AuthenticationError

PRETRAIN_MODEL_OPENAI = "text-embedding-ada-002"


def get_embbedding(text):
    max_retries = 5
    attempt, auth_error = 0, False
    while attempt < max_retries:
        try:
            response = openai.Embedding.create(
                model=PRETRAIN_MODEL_OPENAI,
                input=text
            )
            return response['data'][0]['embedding']
        except Exception as e:
            print(f"Attempt {attempt + 1} get embedding failed with error: {e}")
            attempt += 1
            time.sleep(1)  # 稍等一秒再重试
            if isinstance(e, AuthenticationError):
                auth_error = True

    if auth_error:
        sys.exit(-1)
    return [0] * 1536  # 所有尝试失败后返回一个长度为1536，元素全为0的数组
