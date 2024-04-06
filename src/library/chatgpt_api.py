import openai
import openai.error
from typing import List, Dict
import logging
import time
import traceback
import tiktoken
from .config import OPENAI_APIS, GPT4_API
from multiprocessing import Value
logger = logging.getLogger(__name__)


openai.api_key = OPENAI_APIS[0]

SYSTEM_MESSAGE = "You are a smart contract auditor. You will be asked questions related to code properties. You can mimic answering them in the background five times and provide me with the most frequently appearing answer. Furthermore, please strictly adhere to the output format specified in the question; there is no need to explain your answer."

encoder = tiktoken.get_encoding("cl100k_base")
encoder = tiktoken.encoding_for_model("gpt-3.5-turbo")

tokens_sent = Value("d", 0)
tokens_received = Value("d", 0)
tokens_sent_gpt4 = Value("d", 0)
tokens_received_gpt4 = Value("d", 0)


class Chat:
    def __init__(self) -> None:
        self.currentSession:List[Dict[str,str]] = []
    
    def newSession(self) -> None:
        self.currentSession = []
    
    def sendMessages(self, message:str, GPT4=False, GPT35_16K=False) -> str:

        logger.info(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>")
        logger.info(f"Sending message: \n{message}")
        logger.info(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>")
        key_id = 0
        
        self.currentSession.append({"role": "system", "content": SYSTEM_MESSAGE})
        self.currentSession.append({"role": "user", "content": message})
        while True:
            try:
                if GPT4:
                    openai.api_key = GPT4_API
                    response = openai.ChatCompletion.create(
                        # model="gpt-3.5-turbo-0301",
                        # model="gpt-3.5-turbo-0613",
                        # model="gpt-3.5-turbo",
                        model="gpt-4",
                        messages = self.currentSession,
                        temperature = 0,
                        top_p = 1.0
                    )
                elif GPT35_16K:
                    openai.api_key = GPT4_API
                    response = openai.ChatCompletion.create(
                        # model="gpt-3.5-turbo-0301",
                        # model="gpt-3.5-turbo-0613",
                        # model="gpt-3.5-turbo",
                        model="gpt-3.5-turbo-16k",
                        messages = self.currentSession,
                        temperature = 0,
                        top_p = 1.0
                    )
                else:
                    openai.api_key = OPENAI_APIS[key_id]
                    response = openai.ChatCompletion.create(
                        model="gpt-3.5-turbo-0301",
                        # model="gpt-3.5-turbo-0613",
                        # model="gpt-3.5-turbo",
                        # model="gpt-4",
                        messages = self.currentSession,
                        temperature = 0,
                        top_p = 1.0
                    )
                break
            except openai.error.RateLimitError as e1:
                if key_id == len(OPENAI_APIS) - 1:
                    key_id = 0
                    logger.warning("Trigger rate limit error for 2 times, skip")
                    return "KeySentence: "
                    # time.sleep(30)
                else:
                    key_id += 1
                    logger.warning("Trigger rate limit error, change key")
                    time.sleep(30)
            except openai.InvalidRequestError as e2:
                if e2.code == 'context_length_exceeded':
                    logger.error("Too long context, skip")
                    return "KeySentence: "
                else:
                    logger.warning("Retry")
            except openai.error.APIConnectionError as e3:
                logger.warning("API Connection Error, Retry")
            except openai.error.Timeout as e4:
                logger.warning("Timeout, Retry")
            except openai.error.APIError as e5:
                if "502" in e5._message:
                    logger.warning("502 Bad Gateway, Retry")
                    logger.warning(traceback.format_exc())
        # response = openai.Completion.create(
        #     # model="gpt-3.5-turbo",
        #     model="text-davinci-003",
        #     messages = self.currentSession,
        #     # temperature = 0.3
        # )

        if GPT4:
            global tokens_sent_gpt4
            global tokens_received_gpt4

            tokens_sent_gpt4.value += len(encoder.encode(SYSTEM_MESSAGE))
            tokens_sent_gpt4.value += len(encoder.encode(message))
            tokens_received_gpt4.value += len(encoder.encode(response['choices'][0]['message']['content']))
        else:
            global tokens_sent
            global tokens_received

            tokens_sent.value += len(encoder.encode(SYSTEM_MESSAGE))
            tokens_sent.value += len(encoder.encode(message))
            tokens_received.value += len(encoder.encode(response['choices'][0]['message']['content']))

        self.currentSession.append(response['choices'][0]['message'])


        logger.info("<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<")
        logger.info(f"Received message: \n{response['choices'][0]['message']['content']}")
        logger.info("<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<")

        return response['choices'][0]['message']['content']
    
    def makeYesOrNoQuestion(self, question:str)->str:
        prompt = f"{question}. Please answer in one word, yes or no."
        return prompt
    
    def makeCodeQuestion(self, question:str, code:str):
        prompt = f'Please analyze the following code, and answer the question "{question}"\n{code}'
        return prompt
