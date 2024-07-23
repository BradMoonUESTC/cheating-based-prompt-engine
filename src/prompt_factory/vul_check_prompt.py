class VulCheckPrompt:
    def vul_check_prompt():
        return """
        Please re-analyze the original code step by step without drawing conclusions initially. Based on the analysis results, provide a conclusion at the end: determine whether this vulnerability truly exists or likely exists
        """
    def vul_check_prompt_old():
        return """
        Please re-analyze the original code step by step without drawing conclusions initially. Based on the analysis results, provide a conclusion at the end: determine whether this vulnerability truly exists or likely exists
        return result in json as {"analysis":"xxxxxx(detailed analyasis of the code)","result":"yes"} or {"analysis":"xxxxxx(detailed analyasis of the code)","result":"no"}
        you must output the analysis first, and then provide a conclusion based on the analysis at the end.
        """