import requests
import uuid
import json
import os

class ChatgptToken:
    ##ref
    ##https://platform.openai.com/docs/api-reference/making-requests
    ##https://github.com/zhile-io/pandora/
    def __init__(self, token, model, username = None, password = None): #todo 使用username/password refresh
        self.username = username
        self.password = password
        self.access_token = None
        self.refresh_token = None
        self.login_url = "https://ai.fakeopen.com"
        self.headers = {
            'Content-Type': 'application/json',
            'referer': 'https://ai.fakeopen.com/',
            'Authorization': "Bearer " + token
        }
        self.model = model
        #self.authenticate()

    def get_models(self):
        response = requests.get(
            f"{self.login_url}/api/models",
            headers=self.headers
        )
        return response.json()

    def init_conversation(self, content_parts):
        input_json = {
            "action": "next",
            "messages": [
                {
                    "id": str(uuid.uuid4()),
                    "author": {"role": "user"},
                    "content": {"content_type": "text", "parts": [content_parts]},
                    "metadata": {}
                }
            ],
            "parent_message_id": str(uuid.uuid4()),
            "model": self.model, #gpt-4
            "plugin_ids": [],
            "timezone_offset_min": -480,
            "suggestions": [],
            "history_and_training_disabled": False,
            "arkose_token": None,
            "force_paragen": False
        }

        response = requests.post(
            f"{self.login_url}/api/conversation",
            data=json.dumps(input_json),
            headers=self.headers
        )


        response_content = response.text
        data_parts = response_content.split('data: ')[1:]
        for part in data_parts:
            try:
                if part.strip():
                    json_obj = json.loads(part)
                    message = json_obj.get('message', {})
                    metadata = message.get('metadata', {})
                    if message.get('end_turn', False) or metadata.get('is_complete', False):
                        return json_obj['conversation_id'], message['content']['parts'][0]
            except json.JSONDecodeError:
                continue
        return None, None

    def change_title(self, conversation_id, new_title):
        input_json = {"title": new_title}
        response = requests.patch(
            f"{self.login_url}/api/conversation/{conversation_id}",
            data=json.dumps(input_json),
            headers=self.headers
        )
        return response.json()

    def continue_conversation(self, conversation_id, content_parts, prompt_config):
        input_json = {
            "action": "next",
            "messages": [
                {
                    "id": str(uuid.uuid4()),
                    "author": {"role": "user"},
                    "content": {"content_type": "text", "parts": [content_parts]},
                    "metadata": {}
                }
            ],
            "conversation_id": conversation_id,
            #"parent_message_id":parent_message_id,
            "model": prompt_config['model'], #gpt-4
            #"plugin_ids": [],
            "timezone_offset_min": -480,
            "suggestions": [],
            "history_and_training_disabled": False,
            'arkose_token': '24017913a8873e2d2.0008443302|r=us-west-2|meta=3|metabgclr=transparent|metaiconclr=%23757575|guitextcolor=%23000000|pk=35536E1E-65B4-4D96-9D97-6ADB7EFF8147|at=40|sup=1|rid=79|ag=101|cdn_url=https%3A%2F%2Fclient-api.arkoselabs.com%2Fcdn%2Ffc|lurl=https%3A%2F%2Faudio-us-west-2.arkoselabs.com|surl=https%3A%2F%2Fclient-api.arkoselabs.com|smurl=https%3A%2F%2Fclient-api.arkoselabs.com%2Fcdn%2Ffc%2Fassets%2Fstyle-manager',
            "force_paragen": False
        }

        response = requests.post(
            f"{self.login_url}/api/conversation",
            data=json.dumps(input_json),
            headers=self.headers
        )

        response_content = response.text
        data_parts = response_content.split('data: ')[1:]

        for part in data_parts:
            try:
                if part.strip():
                    json_obj = json.loads(part)
                    if 'message' in json_obj and json_obj['message'] is None and 'error' in json_obj:
                        print("error ", part, json_obj['error'])
                        return None
                    elif json_obj.get('message', {}).get('metadata', {}).get('is_complete') == True:
                        return json_obj['message']['content']['parts'][0]
            except json.JSONDecodeError:
                continue
        return ''