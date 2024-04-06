
prompts = {
    'hello': 'hello',

    'check_vul_from_knowledge': 
        (
            "Given the content:"
            "{content}"
            "Does this contain this vulnerability as described in this knowledge: '{keysentence}'? "
            "Please ignore any specific function or variable names and treat the knowledge in a generalized manner "
            "if contains such vulnerability I gave to you, response 'YES', and describe it "
            "if not contains such vulnerability I gave to you, response 'NO'"
        ),
    
    'function_type': '''In the function '{name}' with content:
        {content}
        Which of the following keywords are relevant or addressed? 
        {keywords}
        please output the keywords like "[a,b,c...]" without '\\n'
        if None of the keywords listed above are relevant or addressed, please type 'None of the above'.
        '''

}
