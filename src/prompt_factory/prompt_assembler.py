from prompt_factory.core_prompt import CorePrompt
from prompt_factory.periphery_prompt import PeripheryPrompt
from prompt_factory.vul_check_prompt import VulCheckPrompt
class PromptAssembler:
    def assemble_prompt(code):
        ret_prompt=code+"\n"\
                    +PeripheryPrompt.role_set_rust_common()+"\n"\
                    +PeripheryPrompt.task_set_blockchain_common()+"\n"\
                    +CorePrompt.core_prompt()+"\n"\
                    +PeripheryPrompt.guidelines()
                    # +PeripheryPrompt.impact_list()
        return ret_prompt
    
    def assemble_vul_check_prompt(code,vul):
        ret_prompt=code+"\n"\
                +str(vul)+"\n"\
                +VulCheckPrompt.vul_check_prompt_claude()+"\n"
        return ret_prompt

    def brief_of_response():
        return "based on the analysis response, please translate the response to json format, the json format is as follows: {'brief of response':'xxx','result':'yes'} or {'brief of response':'xxx','result':'no'} or {'brief of response':'xxx','result':'not sure'}"