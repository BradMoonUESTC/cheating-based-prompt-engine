class CorePrompt:
    def core_prompt():
        return """
        We have already confirmed that the code contains only one exploitable, \
        code-error based and non-related to other code logical bug due to error logic in the code, \
        and your job is to identify it.
        """