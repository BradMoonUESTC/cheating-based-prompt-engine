class VulCheckPrompt:
    def vul_check_prompt():
        return """
        Please re-analyze the original code step by step without drawing conclusions initially. Based on the analysis results, provide a conclusion at the end: determine whether this vulnerability truly exists or likely exists
        """
    def vul_check_prompt_old():
        return """
        Please re-analyze the original code step by step without drawing conclusions initially. Based on the analysis results, provide a conclusion at the end: determine whether this vulnerability truly exists or not extist or not sure.
        return result in json as {"analysis":"xxxxxx(detailed analyasis of the code)","result":"yes"} or {"analysis":"xxxxxx(detailed analyasis of the code)","result":"no"} or {"analysis":"xxxxxx(detailed analyasis of the code)","result":"not sure"}
        you must output the analysis first, and then provide a conclusion based on the analysis at the end.
        """
    def vul_check_prompt_claude():
        return """
        First analyze this vulnerability, and then determine if it really exists, beaware, the contract version is larger then 0.8.0, so overflow is not possible.
        """
