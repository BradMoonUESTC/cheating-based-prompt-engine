from ast import operator


class Scanner(object):
    """
        A class to scanning solidity unit object.
    """
    
    def __init__(self, sourceUnitObject):
        self.sourceUnitObject = sourceUnitObject
        #self.fileName = self.sourceUnitObject.fileName
        self.contracts = []
        self.interfaces = []
        self.functions = []
        self.operators = []
        
        self.filter_contracts()
        self.get_functions()
        self.get_operators()
        
    def filter_contracts(self):
        for contractObject in self.sourceUnitObject.contracts.values():
            if contractObject.kind == "interface":
                self.interfaces.append(contractObject)

            elif contractObject.kind == "contract":
                self.contracts.append(Contract(contractObject))
    
    def get_functions(self):
        for contract in self.contracts:
            self.functions += contract.functions
    
    def get_operators(self):
        for function in self.functions:
            self.operators += function.operators
        
        

class Contract(object):
    
    def __init__(self, contractObject):
        self.contractObject = contractObject
        self.functions = []
        self.get_functions()
                    
    def get_functions(self):
        if self.contractObject.functions:
            for functionObject in self.contractObject.functions.values():
                self.functions.append(Function(functionObject))
        

class Function(object):
    
    def __init__(self, functionObject):
        self.functionObject = functionObject
        self.modifiers = []
        self.statements = []
        self.expressions = []
        self.functionCalls = []
        self.variables = []
        self.numberLiteral = []
        self.variableDeclaration = []
        self.operators = []
        
        self.get_modifier()
        self.get_statements()
        self.get_expressions()
        self.get_variables()
        self.get_number_literals()
        self.get_variable_declarations() 
        self.get_operators()
        self.get_function_calls()
    
    def get_modifier(self):
        self.modifiers = [mod.name for mod in self.functionObject.node.modifiers]
        
        
    def get_statements(self):
        if self.functionObject.node.body:
            for statement in self.functionObject.node.body.statements:
                self.visit_statement(statement)
    
    def visit_statement(self, statement):
        if statement:
            self.statements.append(statement)
            if statement.type == "IfStatement":
                self.visit_statement(statement.condition)
                self.visit_statement(statement.TrueBody)
                self.visit_statement(statement.FalseBody)
            
            elif statement.type == "WhileStatement":
                self.visit_statement(statement.condition)
                
            elif statement.type == "ForStatement":
                self.visit_statement(statement.initExpression)
                self.visit_statement(statement.conditionExpression)
                self.visit_statement(statement.loopExpression)
                if statement.body.type == "Block":
                    if statement.body.statements:
                        for state in statement.body.statements:
                            self.visit_statement(state)
                else:
                    self.visit_statement(statement.body)

            elif statement.type == "Block":
                for block_statement in statement.statements:
                    self.visit_statement(block_statement)

            elif statement.type == "TryStatment":
                self.visit_statement(statement.block)
                self.visit_statement(statement.expression)
                for catchClause in statement.catchClause:
                    self.visit_statement(catchClause)

            elif statement.type == "CatchClause":
                self.visit_statement(statement.block)

            else:
                pass
               
    def get_expressions(self):
        if self.statements:
            for statement in self.statements:
                self.get_expression(statement)           
               
    def get_expression(self, expressionObject):
        
        class Expression(dict):
            
            def __getattr__(self, key):
                return self.get(key)
            
            def __setattr__(self, key, value):
                self[key] = value           

        
        if expressionObject.type == "Identifier":
            self.expressions.append(
                Expression(
                    {
                        "name": expressionObject.name,
                        "loc": expressionObject.loc,
                        "type": expressionObject.type
                    }
                )
            )

        elif expressionObject.type == "VariableDeclarationStatement":
            if expressionObject.variables:
                for variable_declaration in expressionObject.variables:
                    self.expressions.append(
                        Expression(
                            {
                                "name": variable_declaration.name,
                                "loc": variable_declaration.loc,
                                "type": variable_declaration.type,
                                "type_name": variable_declaration.typeName
                            }
                        )
                    )
            if expressionObject.initialValue:
                self.get_expression(expressionObject.initialValue)

        elif expressionObject.type == "MemberAccess":
            self.expressions.append(
                Expression(
                    {
                        "name": expressionObject.memberName,
                        "loc": expressionObject.loc,
                        "type": expressionObject.type,
                        "expression": expressionObject.expression
                    }
                )
            )
            self.get_expression(expressionObject.expression)

        elif expressionObject.type == "IndexAccess":
            if expressionObject.base.type == "MemberAccess":
                name = expressionObject.base.memberName
            elif expressionObject.base.type == "Identifier":
                name = expressionObject.base.name
            else:
                name = expressionObject.base.type
            self.expressions.append(
                Expression(
                    {
                        "name": name,
                        "loc": expressionObject.loc,
                        "type": expressionObject.type,
                        "base": expressionObject.base,
                        "index": expressionObject.index
                    }
                )
            )
            self.get_expression(expressionObject.base)
            self.get_expression(expressionObject.index)

        elif expressionObject.type == "BinaryOperation":
            self.expressions.append(
                Expression(
                    {
                        "name": expressionObject.operator,
                        "loc": expressionObject.loc,
                        "type": expressionObject.type,
                        "operator": expressionObject.operator
                    }
                )
            )
            self.get_expression(expressionObject.left)
            self.get_expression(expressionObject.right)

        elif expressionObject.type == "NumberLiteral":
            self.expressions.append(
                Expression(
                    {
                        "name": expressionObject.number,
                        "loc": expressionObject.loc,
                        "type": expressionObject.type
                    }
                )
            )

        elif expressionObject.type == "FunctionCall":
            if expressionObject.expression:
                if expressionObject.expression.type == "MemberAccess":
                    self.expressions.append(
                        Expression(
                            {
                                "name": expressionObject.expression.memberName,
                                "loc": expressionObject.loc,
                                "type": expressionObject.type,
                                "arguments": expressionObject.arguments,
                                "expression": expressionObject.expression.expression
                            }
                        )
                    )
                    self.get_expression(expressionObject.expression.expression)
                    for argument in expressionObject.arguments:
                        self.get_expression(argument)

                elif expressionObject.expression.type == "Identifier":
                    self.expressions.append(
                        Expression(
                            {
                                "name": expressionObject.expression.name,
                                "loc": expressionObject.loc,
                                "type": expressionObject.type,
                                "arguments": expressionObject.arguments,
                            }
                        )
                    )
                    for argument in expressionObject.arguments:
                        self.get_expression(argument)
                
                else:
                    self.get_expression(expressionObject.expression)

        elif expressionObject.type == "ExpressionStatement":
            self.get_expression(expressionObject.expression)

        elif expressionObject.type == "UnaryOperation":
            self.get_expression(expressionObject.subExpression)
            
    def get_variables(self):
        if self.expressions:
            for expression in self.expressions:
                if expression["type"] == "Identifier":
                    self.variables.append(expression)
                    
    def get_number_literals(self):
        if self.expressions:
            for expression in self.expressions:
                if expression["type"] == "NumberLiteral":
                    self.numberLiteral.append(expression)
    
    def get_variable_declarations(self):
        if self.expressions:
            for expression in self.expressions:
                if expression["type"] == "VariableDeclaration":
                    self.variableDeclaration.append(expression)
        
        for declaration in self.functionObject.declarations.values():
            if declaration.type == "VariableDeclaration":
                self.variableDeclaration.append(declaration)
                
    def get_operators(self):
        if self.expressions:
            for expression in self.expressions:
                if expression["type"] == "BinaryOperation":
                    self.operators.append(expression)
                    
    def get_function_calls(self):
        if self.expressions:
            for expression in self.expressions:
                if expression["type"] == "FunctionCall":
                    self.functionCalls.append(expression)
                        
    def get_below_statements(self, node):
        below_statements = list()
        if not hasattr(node, "loc"):
            return below_statements
        nodeStartLine = node.loc["start"]["line"]
        for statement in self.statements:
            if statement.loc["start"]["line"] >= nodeStartLine:
                below_statements.append(statement)
        return below_statements 


class Tools(object):
    
    @staticmethod
    def scope_check(ctx0, ctx1) -> bool:
        loc0 = ctx0.loc
        loc1 = ctx1.loc
        if loc0["start"]["line"] == loc1["start"]["line"] \
            and loc0["end"]["line"] == loc1["end"]["line"] \
                and loc0["start"]["line"] == loc0["end"]["line"]:
                    if loc0["start"].column <= loc1["start"].column \
                        and loc0["start"].column <= loc1["start"].column:
                            return True
                    else:
                        return False
        elif loc0["start"]["line"] < loc1["start"]["line"] \
            and loc0["end"]["line"] > loc1["end"]["line"]:
                return True
        else:
            return False
    
    @staticmethod
    def check_modifier(function_object, modifier: list):
        """Checking if a function declaration contains certain modifiers"""
        mod_list = list()
        function_modifier_list = [mod["name"] for mod in function_object.node["modifiers"]]
        if hasattr(function_object, "stateMutability") and function_object.stateMutability:
            function_modifier_list.append(function_object.stateMutability)

        if hasattr(function_object, "visibility") and function_object.visibility:
            function_modifier_list.append(function_object.visibility)

        for mod in function_modifier_list:
            for modif in modifier:
                if modif in mod:
                    mod_list.append(mod)

        return list(set(mod_list))