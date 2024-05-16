class VulCheckPrompt:
    def vul_check_prompt():
        return """
        Please re-analyze the original code step by step without drawing conclusions initially. Based on the analysis results, provide a conclusion at the end: determine whether this vulnerability truly exists or likely exists
        return result in json as {"result":"yes"} or {"result":"no"} or {"result":"high possibility"} or {"result":"low possibility"}
        if the vulnerability consider corner case or extreme senario, like attacker must have access of the owner, in addition to returning {"result":"xxxx"}, a additional return {"info":"corner case"} will be added.
        """