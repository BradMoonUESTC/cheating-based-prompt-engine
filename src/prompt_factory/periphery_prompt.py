class PeripheryPrompt:
    def role_set_blockchain_common():
        return """You are the best blockchain auditor in the world"""
    def role_set_solidity_common():
        return """You are the best solidity auditor in the world"""
    def role_set_rust_common():
        return """You are the best rust and rust contract in solana auditor in the world"""
    def role_set_go_common():
        return """You are the best go auditor in the world"""
    def role_set_python_common():
        return """You are the best python auditor in the world"""
    def role_set_ai_common():
        return """You are the best neural netowrk and machine learning and transformer auditor in the world"""
    

    def task_set_blockchain_common():
        return """Your task is to pinpoint and correct any complex logical vulnerabilities present in the code. """
    

    def guidelines_v1():
        return """Follow the guidelines below for your response: 
        1. Describe this practical, exploitable code vulnerability in detail. It should be logical and an error or logic missing in the code, not based on technical errors or just security advice or best practices.
        2. Show step-by-step how to exploit this vulnerability. The exploit should be beneficial for an auditor and could invalidate the code.
        3. Keep your description clear and concise. Avoid vague terms.
        4. Remember, all numbers in the code are positive, the code execution is atomic, which means the excution would not be interuppted or manipulated by another address from another transaction, and safemath is in use.
        5. dont response in "attaker use some way" the exploit method must be clear and useable
        6. Remember, attacker only can use some exploit way like interact with blockchain, not invoke the function directly
        Ensure your response is as detailed as possible, and strictly adheres to all the above requirements
        """
    def guidelines():
        return """Follow the guidelines below for your response: 
        1. Describe this practical, exploitable code vulnerability in detail. It should be logical and an error or logic missing in the code, not based on technical errors or just security advice or best practices.
        2. Show step-by-step how to exploit this vulnerability. The exploit should be beneficial for an auditor and could invalidate the code.
        3. Keep your description clear and concise. Avoid vague terms.
        4. Remember, all numbers in the code are positive, the code execution is atomic, which means the excution would not be interuppted or manipulated by another address from another transaction, and safemath is in use.
        5. dont response in "attaker use some way" the exploit method must be clear and useable
        6. Dont consider any corner case or extreme scenario, the vulnerability must be practical and exploitable.
        7. Assume that the attack can not have the role of the owner of the contract
        Ensure your response is as detailed as possible, and strictly adheres to all the above requirements
        """
    def impact_list():
        return """
        The vulnerability must satisfy one of the following conditions:
            a. Manipulation of governance voting results.
            b. Direct theft of any user funds, at-rest or in-motion, excluding unclaimed yield.
            c. Permanent or temporary freezing of funds or unclaimed yield.
            d. Extraction of miner-extractable value (MEV).
            e. Protocol insolvency.
            f. Theft or freezing of unclaimed yield.
            g. A smart contract is unable to operate due to lack of token funds.
            h. Block stuffing for profit.
            i. Griefing (an attacker causing damage to the users or the protocol without any profit motive).
            j. A contract failing to deliver promised returns, but not losing value. 
                   
        """