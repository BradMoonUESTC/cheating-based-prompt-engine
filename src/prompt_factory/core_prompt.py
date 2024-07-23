class CorePrompt:
    def core_prompt():
        return """
        We have already confirmed that the code contains only one exploitable, \
        code-error based and non-related to other code logical bug due to error logic in the code, \
        and your job is to identify it.
        """
    def assumation_prompt():
        return """
        Based on the vulnerability information, answer whether the establishment of the attack depends on the code of other unknown or unprovided contracts within the project, or whether the establishment of the vulnerability is affected by any external calls or contract states. 
        
        """
    def assumation_prompt_old():
        return """
        Based on the vulnerability information, answer whether the establishment of the attack depends on the code of other unknown or unprovided contracts within the project, or whether the establishment of the vulnerability is affected by any external calls or contract states. 
        
        Based on the results of the answer, add the JSON result: {'analaysis':'xxxxxxx','result':'need In-project other contract'} or {'analaysis':'xxxxxxx','result':'dont need In-project other contract'}.

        """
    def category_check():
        return """

        Based on the vulnerability information, analysis first step by step, then based on the analysis,Determine whether this vulnerability belongs to the access control type of vulnerability, the data validation type of vulnerability, or the data processing type of vulnerability.
        return as {'analaysis':'xxxxxxx','result':'xxxx vulnerability'}



        """