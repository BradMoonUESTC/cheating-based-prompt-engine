import re

import antlr4
from collections import defaultdict
from parser.SolidityLexer import SolidityLexer
from parser.SolidityParser import SolidityParser
from parser.SolidityListener import SolidityListener

class FunctionListener(SolidityListener):
    def __init__(self):
        self.current_function = None
        self.functions = {}
        self.call_graph = defaultdict(set)
        self.callers_graph = defaultdict(set)
        self.state_variables = set()
        self.expression_dependencies = {}
        self.data_dependencies = {}
        self.control_stack = []
        self.control_dependencies = {}


    def enterStateVariableDeclaration(self, ctx: SolidityParser.StateVariableDeclarationContext):
        # Add the variable to the set of state variable names
        identifier = ctx.identifier()
        if identifier:
            self.state_variables.add(identifier.getText())

    def enterFunctionDefinition(self, ctx:SolidityParser.FunctionDefinitionContext):
        identifier = ctx.identifier()
        if identifier:
            # We are entering a function
            self.current_function = identifier.getText()
            self.functions[self.current_function] = {'calls': set(), 'state_variables': set(), 'source': ctx.getText()}
            if self.current_function not in self.call_graph:
                self.call_graph[self.current_function] = set()
            if self.current_function not in self.callers_graph:
                self.callers_graph[self.current_function] = set()

            # Parse function body for dependencies
            function_body = ctx.block()
            if function_body:
                self.parseFunctionBody(function_body)


    def parseFunctionBody(self, body: SolidityParser.BlockContext):
        # Traverse the body AST to identify function calls and state variable accesses
        for expr in body.statement():  # assuming 'expression' is the method to get all expressions within the body
            current_dependencies = self.extractDataDependencies(expr, self.data_dependencies)

            # Store these dependencies (assuming you have a method or structure to store them)
            self.storeDependencies(expr, current_dependencies)

            # Update data_dependencies with variables modified or defined in the current expression
            self.updateDependencies(expr, self.data_dependencies)

        for stmt in body.statement():
            self.checkControlDependencies(stmt)

            if self.isControlStatement(stmt):
                # Push to control stack and process its body
                self.control_stack.append(stmt)
                self.processControlStatementBody(stmt)
                self.control_stack.pop()

    def checkControlDependencies(self, stmt):
        """
        If there's a control statement at the top of the stack,
        then the current statement has a control dependency on it.
        """
        if self.control_stack:
            control_stmt = self.control_stack[-1]  # get the control statement at the top
            if stmt not in self.control_dependencies:
                self.control_dependencies[stmt] = []
            self.control_dependencies[stmt].append(control_stmt)

    def isControlStatement(self, stmt):
        """
        Check if the statement is a control statement (like if, for, while, etc.)
        """
        return isinstance(stmt, (SolidityParser.IfStatementContext, SolidityParser.WhileStatementContext,
                                 SolidityParser.ForStatementContext))


    def processControlStatementBody(self, control_stmt):
        """
        Process the body of the control statement to capture dependencies within it.
        This can be a recursive process if there are nested control statements.
        """
        if isinstance(control_stmt, SolidityParser.IfStatementContext):
            # Handle 'if' and optional 'else'
            self.parseFunctionBodyForControlDependencies(control_stmt.ifBody)
            if control_stmt.elseBody:
                self.parseFunctionBodyForControlDependencies(control_stmt.elseBody)


    def extractDataDependencies(self, expr, data_dependencies):
        """
        Check if the expression has variables that were previously defined or modified.
        """
        dependencies = set()
        variables_in_expr = self.extractVariables(expr)  # Extract all variables in the current expression

        for var in variables_in_expr:
            if var in data_dependencies:
                dependencies.add(data_dependencies[var])  # Add the expression or statement this variable depends on

        return dependencies


    def updateDependencies(self, expr, data_dependencies):
        """
        Update the data_dependencies dictionary with variables that are modified or defined in the current expression.
        """
        modified_variables = self.extractModifiedVariables(
            expr)  # Extract variables that are modified in the current expression

        for var in modified_variables:
            data_dependencies[var] = expr  # Update the variable's dependency to the current expression

    def extractVariables(self, expr):
        return [variable.getText() for variable in expr.getTokens(SolidityParser.Identifier)]

    def extractModifiedVariables(self, expr):
        modified_vars = []

        # Check for assignments in the expression
        simple_stmt = expr.simpleStatement()
        if simple_stmt:
            variable = simple_stmt.expressionStatement()  # Assuming assignment() is a method within SimpleStatementContext
            if variable:
                modified_vars.append(variable.getText())
        # assignments = expr.assignment()
        # for assignment in assignments:
        #     # Get the left-hand side of the assignment which is typically the variable being modified
        #     variable = assignment.identifier()
        #     if variable:
        #         modified_vars.append(variable.getText())

        return modified_vars

    def storeDependencies(self, expr, dependencies):
        if expr not in self.expression_dependencies:
            self.expression_dependencies[expr] = set()

        self.expression_dependencies[expr].update(dependencies)

    def exitFunctionDefinition(self, ctx:SolidityParser.FunctionDefinitionContext):
        identifier = ctx.identifier()
        if identifier and identifier.getText() == self.current_function:
            # We are exiting the current function
            self.current_function = None

    def enterFunctionCall(self, ctx:SolidityParser.FunctionCallContext):
        if self.current_function:
            # We are inside a function and we found a function call
            a = ctx.getText()
            called_function = re.sub('\(.*\)$', '', ctx.getText())  # get the name of the called function
            self.functions[self.current_function]['calls'].add(called_function)
            self.call_graph[self.current_function].add(called_function)
            self.callers_graph[called_function].add(self.current_function)

    def enterIdentifier(self, ctx:SolidityParser.Identifier):
        if self.current_function:
            identifier = ctx.getText()
            if identifier and identifier in self.state_variables:
                self.functions[self.current_function]['state_variables'].add(identifier)
    def get_function_src(self, func):
        return self.get_functions().get(func, {}).get('source', '')

    def get_function_callers(self, func):
        return self.callers_graph.get(func, set())

    def get_function_callees(self, func):
        return self.call_graph.get(func, set())

    def get_functions(self):
        return self.functions

    def get_call_graph(self):
        return self.call_graph

    def get_callers_graph(self):
        return self.callers_graph

    def get_state_variables(self):
        return self.state_variables

    def get_related_state_variables(self, func):
        related_functions = defaultdict(set)

        for state_var in self.functions.get(func, {}).get('state_variables', set()):
            for fu, values in self.functions.items():
                if fu == func:
                    continue
                if state_var in values['state_variables']:
                    related_functions[state_var].add(fu)
        return related_functions


def antlr_listener(f):
    with open(f, 'r') as file:
        code = file.read()

    input_stream = antlr4.InputStream(code)
    lexer = SolidityLexer(input_stream)
    lexer.removeErrorListeners()
    token_stream = antlr4.CommonTokenStream(lexer)
    parser = SolidityParser(token_stream)
    parser.removeErrorListeners()
    tree = parser.sourceUnit()

    listener = FunctionListener()
    walker = antlr4.ParseTreeWalker()
    walker.walk(listener, tree)

    return listener


def get_antlr_parsing(f):
    # Read the Solidity source code from a file
    with open(f, 'r') as file:
        code = file.read()

    # Create a stream of tokens from the source code
    input_stream = antlr4.InputStream(code)
    lexer = SolidityLexer(input_stream)
    token_stream = antlr4.CommonTokenStream(lexer)

    # Use the token stream to create an AST
    parser = SolidityParser(token_stream)
    tree = parser.sourceUnit()

    # Print the AST to the console
    # print(tree.toStringTree(recog=parser))

    for child in tree.getChildren():
        if type(child) is SolidityParser.ContractDefinitionContext:
            print(child)
            for c in child.getChildren():
                if type(c) is SolidityParser.ContractPartContext:
                    print(c)




# file_path = 'G:/bbb/codingfy/FinetuneGPTCode/test.sol'

# get_antlr_parsing(file_path)
