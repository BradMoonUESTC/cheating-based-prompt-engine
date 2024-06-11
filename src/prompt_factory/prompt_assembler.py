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
                +VulCheckPrompt.vul_check_prompt()+"\n"
        return ret_prompt  
