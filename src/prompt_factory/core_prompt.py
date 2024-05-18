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
        
        Based on the results of the answer, add the JSON result: {'result':'need In-project other contract'} or {'result':'dont need In-project other contract'}.

        """