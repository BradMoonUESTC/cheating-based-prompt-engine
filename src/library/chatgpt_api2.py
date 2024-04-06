import openai
from pezzo.client import pezzo
from pezzo.openai import openai as pezzo_openai
import json
from datetime import datetime
from ChatgptToken import ChatgptToken
import os

MODEL_GPT3 = 'gpt-3.5-turbo-16k-0613'
MODEL_GPT4 = 'gpt-4-0314'


def createGptApi(gpt_config, type, prompts_mgr, cache_mgr=None, model=MODEL_GPT3, temperature=1):
    if type == 'chatgpt':
        return ChatGptApi(gpt_config, model, prompts_mgr, cache_mgr, temperature=temperature)
    elif type == 'pezzo':
        return PezzoGptApi(gpt_config, model, prompts_mgr, cache_mgr, temperature=temperature)
    elif type == 'fake_chatgpt':
        return FakeChatGptApi(gpt_config, model, prompts_mgr, cache_mgr, temperature=temperature)
    else:
        raise Exception("unkown gptapi type")
        return None


class BaseGptApi(object):
    def __init__(self, gpt_config, model, prompts_mgr, cache_mgr=None, **kwargs):
        self.gpt_config = gpt_config
        self.prompts_mgr = prompts_mgr
        self.cache_manager = cache_mgr
        self.prompt_config = kwargs.copy()
        self.prompt_config['model'] = model
        self.prompt_config['use_cache'] = cache_mgr is not None
        if 'temperature' not in self.prompt_config:
            self.prompt_config['temperature'] = 1.2 if self.is_gpt4() else 1.0
        assert (len(model) > 0)

    def get_prompt(self, prompt_name):
        return self.prompts_mgr.get(prompt_name)

    def is_gpt4(self):
        return self.prompt_config.get('model', '').startswith("gpt-4")

    def init_conversation(self, initialal_prompt='You are a auditing expert for solidity smart contracts'):
        pass

    def get_prompt_config(self, kwargs):
        config = self.prompt_config.copy()
        config.update(kwargs)
        return config


'''
gpt-4-0314 | gpt-3.5-turbo-16k-0613
'''


class ChatGptApi(BaseGptApi):

    def completion(self, prompt_name, variables, **kwargs):
        prompt = self.get_prompt(prompt_name)
        formatted_text = prompt.format(**variables)

        prompt_config = self.get_prompt_config(kwargs)
        response = self.make_request(formatted_text, prompt_config)
        if self.is_gpt4() and response is None:
            prompt_config['model'] = 'gpt-3.5-turbo-16k-0613'
            prompt_config['temperature'] = 1
            response = self.make_request(formatted_text, prompt_config)

        return response

    def make_request(self, prompt, prompt_config):

        openai.api_key = self.gpt_config.GPT4_API if self.is_gpt4() else self.gpt_config.GPT3_API
        openai.api_base = "https://api.openai.com/v1"

        print("make_request ", prompt_config['model'])

        try:
            message = [
                {
                    "role": "user",
                    "content": prompt
                }
            ]
            completion = openai.ChatCompletion.create(
                model=prompt_config['model'],
                messages=message,
                temperature=prompt_config['temperature']
            )
            return completion.choices[0].message.content
        except Exception as e:
            print("failed to make chatgpt request", e)
            return None


class PezzoGptApi(BaseGptApi):

    # 并发可能会导致key错乱 
    def completion(self, prompt_name, variables, **kwargs):
        prompt_config = self.get_prompt_config(kwargs)
        # print(prompt_config)

        if prompt_config['model'] == MODEL_GPT3:
            key = prompt_name + "__" + json.dumps(variables)
        else:
            key = prompt_config['model'] + "__" + prompt_name + "__" + json.dumps(variables)
        content = self.cache_manager.get_cache(key)
        if content is not None:
            # print("from cache ", prompt_name)
            return content

        try:
            prompt = pezzo.get_prompt(prompt_name)

            pezzo_openai.openai.api_key = self.gpt_config.GPT4_API if self.is_gpt4() else self.gpt_config.GPT3_API
            response = pezzo_openai.ChatCompletion.create(
                pezzo_prompt=prompt,
                pezzo_options={
                    "variables": variables,
                    "cache": True,
                },
                model=prompt_config['model'],
                temperature=prompt_config['temperature']
            )

            content = response['choices'][0]['message']['content']
            self.cache_manager.set_cache(key, content)
            return content
        except Exception as e:
            print("get_response_pezzo %s failed " % prompt_name, e)

        return None


class FakeChatGptApi(BaseGptApi):

    def init_conversation(self, initialal_prompt='You are a auditing expert for solidity smart contracts'):
        if self.conversation_id is not None:
            return

        # token = os.environ.get("chatgpttoken")
        token = self.gpt_config.fake_gpt_token
        self.chatgpt = ChatgptToken(token, self.prompt_config['model'])

        self.conversation_id, result = self.chatgpt.init_conversation(initialal_prompt)

        current_time = datetime.now()
        formatted_time = current_time.strftime("%Y-%m-%d-%H-%M")
        self.chatgpt.change_title(self.conversation_id, formatted_time)

    def completion(self, prompt_name, variables, **kwargs):
        prompt = self.get_prompt(prompt_name)
        formatted_text = prompt.format(**variables)

        prompt_config = self.get_prompt_config(kwargs)
        return self.chatgpt.continue_conversation(self.conversation_id, formatted_text, prompt_config)


def get_response_pezzo2(prompt):
    response = pezzo_openai.ChatCompletion.create(
        model="gpt-3.5-turbo-16k-0613",
        temperature=1,
        messages=[
            {
                "role": "user",
                "content": prompt,
            }
        ],
        pezzo_options={
            "cache": True,
        }
    )
    return response['choices'][0]['message']['content']


def test():
    # engines = ['pezzo', 'chatgpt', 'fake_chatgpt']
    engines = ['fake_chatgpt']
    for engine in engines:
        gpt_api = createGptApi(engine)
        gpt_api.init_conversation()
        response = gpt_api.completion('hello', {})
        print(engine, response)

    # content = get_response_pezzo("function_type", {})
    # print(content)


def test_pezzo_switch_34():
    gpt_api = createGptApi('pezzo')
    gpt_api.init_conversation()
    response = gpt_api.completion('hello', {}, model=MODEL_GPT3)
    response4 = gpt_api.completion('hello2', {}, model=MODEL_GPT4)

    print("gpt3.5", response)
    print("gpt4", response4)


if __name__ == "__main__":
    # test()
    test_pezzo_switch_34()
