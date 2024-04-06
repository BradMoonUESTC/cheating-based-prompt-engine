#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# mod by https://github.com/ConsenSys/python-solidity-parser
# derived from https://github.com/federicobond/solidity-parser-antlr/
#

from antlr4 import *

from .SolidityLexer import SolidityLexer
from .SolidityParser import SolidityParser
from .SolidityVisitor import SolidityVisitor


class Node(dict):
    """
    provide a dict interface and object attrib access
    """
    ENABLE_LOC = False
    NONCHILD_KEYS = ("type","name","loc")

    def __init__(self, ctx, **kwargs):
        for k, v in kwargs.items():
            self[k] = v

        if Node.ENABLE_LOC:
            self["loc"] = Node._get_loc(ctx)

    def __getattr__(self, item):
        return self[item]
     
    def __hasattr__(self, item):
        if item in self.keys():
            return True
        else:
            False        
            
    def __setattr__(self, name, value):
        self[name] = value

    @staticmethod
    def _get_loc(ctx):
        return {
            'start': {
                'line': ctx.start.line,
                'column': ctx.start.column
            },
            'end': {
                'line': ctx.stop.line,
                'column': ctx.stop.column
            }
        }
        
        
class AstVisitor(SolidityVisitor):
    
    def __init__(self, file_path):
        self.file_path = file_path
    
    
    def _mapCommasToNulls(self, children):
        if not children or len(children) == 0:
            return []

        values = []
        comma = True

        for el in children:
            if comma:
                if el.getText() == ',':
                    values.append(None)
                else:
                    values.append(el)
                    comma = False
            else:
                if el.getText() != ',':
                    raise Exception('expected comma')

                comma = True

        if comma:
            values.append(None)

        return values

    def _createNode(self, **kwargs):
        ## todo: add loc!
        return Node(**kwargs)
    
    def visit(self, tree):
        """
        override the default visit to optionally accept a range of children nodes

        :param tree:
        :return:
        """
        if tree is None:
            return None
        elif isinstance(tree, list):
            return self._visit_nodes(tree)
        else:
            return super().visit(tree)


    def _visit_nodes(self, nodes):
        """
        modified version of visitChildren() that returns an array of results

        :param nodes:
        :return:
        """
        allresults = []
        result = self.defaultResult()
        for c in nodes:
            childResult = c.accept(self)
            result = self.aggregateResult(result, childResult)
            allresults.append(result)
        return allresults


    #  ********************************************************
    #  sourceUnit
    #  : (pragmaDirective | importDirective | structDefinition | enumDefinition | contractDefinition)* EOF ;

    def visitSourceUnit(self, ctx: SolidityParser.SourceUnitContext):
        return Node(
            ctx=ctx,
            type="SourceUnit",
            children=self.visit(ctx.children[:-1])
        )  # skip EOF


    # ********************************************************
    #   pragmaDirective
    #   : 'pragma' pragmaName pragmaValue ';' ;
    
    def visitPragmaDirective(self, ctx: SolidityParser.PragmaDirectiveContext):
        return Node(
            ctx=ctx,
            type="PragmaDirective",
            name=ctx.pragmaName().getText(),
            value=ctx.pragmaValue().getText()
        )


    # ********************************************************
    #     importDirective
    #   : 'import' StringLiteralFragment ('as' identifier)? ';'
    #   | 'import' ('*' | identifier) ('as' identifier)? 'from' StringLiteralFragment ';'
    #   | 'import' '{' importDeclaration ( ',' importDeclaration )* '}' 'from' StringLiteralFragment ';' ;
    
    def visitImportDirective(self, ctx: SolidityParser.ImportDirectiveContext):
        symbol_aliases = {}
        unit_alias = None

        if len(ctx.importDeclaration()) > 0:
            path = path = ctx.children[-2].getText()
            for item in ctx.importDeclaration():

                try:
                    alias = item.identifier(1).getText()
                except:
                    alias = None
                symbol_aliases[item.identifier(0).getText()] = alias

        elif len(ctx.children) == 7:
            unit_alias = ctx.getChild(3).getText()
            path = ctx.children[5].getText()

        elif len(ctx.children) == 5:
            unit_alias = ctx.getChild(3).getText()
            path = ctx.children[1].getText()
            
        elif len(ctx.children) == 3:
            path = ctx.children[1].getText()
            
        return Node(
            ctx=ctx,
            type="ImportDirective",
            path=path,
            symbolAliases=symbol_aliases,
            unitAlias=unit_alias
        )


    # ********************************************************
    #    contractDefinition
    #   : 'abstract'? ( 'contract' | 'interface' | 'library' ) identifier
    #   ( 'is' inheritanceSpecifier (',' inheritanceSpecifier )* )?
    #   '{' contractPart* '}' ;
    
    def visitContractDefinition(self, ctx: SolidityParser.ContractDefinitionContext):
        self._currentContract = ctx.identifier().getText()
        return Node(
            ctx=ctx,
            type="ContractDefinition",
            name=ctx.identifier().getText(),
            baseContracts=self.visit(ctx.inheritanceSpecifier()),
            subNodes=self.visit(ctx.contractPart()),
            kind=ctx.getChild(0).getText()
        )

    #     contractPart
    #   : stateVariableDeclaration
    #   | usingForDeclaration
    #   | structDefinition
    #   | modifierDefinition
    #   | functionDefinition
    #   | eventDefinition
    #   | enumDefinition ;
    
    # ********************************************************
    #     stateVariableDeclaration
    #   : typeName
    #     ( PublicKeyword | InternalKeyword | PrivateKeyword | ConstantKeyword | ImmutableKeyword | overrideSpecifier )*
    #     identifier ('=' expression)? ';' ;
    
    def visitStateVariableDeclaration(self, ctx: SolidityParser.StateVariableDeclarationContext):
        type = self.visit(ctx.typeName())
        iden = ctx.identifier()
        name = iden.getText()

        expression = None

        if ctx.expression():
            expression = self.visit(ctx.expression())

        visibility = 'default'

        if ctx.InternalKeyword(0):
            visibility = 'internal'
        elif ctx.PublicKeyword(0):
            visibility = 'public'
        elif ctx.PrivateKeyword(0):
            visibility = 'private'

        isDeclaredConst = False
        if ctx.ConstantKeyword(0):
            isDeclaredConst = True

        decl = self._createNode(
            ctx=ctx,
            type='VariableDeclaration',
            typeName=type,
            name=name,
            expression=expression,
            visibility=visibility,
            isStateVar=True,
            isDeclaredConst=isDeclaredConst,
            isIndexed=False
        )

        return Node(
            ctx=ctx,
            type='StateVariableDeclaration',
            variables=[decl],
            initialValue=expression
        )


    # ********************************************************
    # usingForDeclaration
    #   : 'using' identifier 'for' ('*' | typeName) ';' ;
    
    def visitUsingForDeclaration(self, ctx: SolidityParser.UsingForDeclarationContext):
        typename = None
        if ctx.getChild(3) != '*':
            typename = self.visit(ctx.getChild(3))

        return Node(
            ctx=ctx,
            type="UsingForDeclaration",
            typeName=typename,
            libraryName=ctx.identifier().getText()
        )
        
        
    # ********************************************************
    #     structDefinition
    #   : 'struct' identifier
    #     '{' ( variableDeclaration ';' (variableDeclaration ';')* )? '}' ;
    
    def visitStructDefinition(self, ctx: SolidityParser.structDefinition):
        return Node(
            ctx=ctx,
            type='StructDefinition',
            name=ctx.identifier().getText(),
            members=self.visit(ctx.variableDeclaration())
        )
    
    
    # ********************************************************
    #     modifierDefinition
    #   : 'modifier' identifier parameterList? ( VirtualKeyword | overrideSpecifier )* ( ';' | block ) ;
    
    def visitModifierDefinition(self, ctx: SolidityParser.ModifierDefinitionContext):
        parameters = []

        if ctx.parameterList():
            parameters = self.visit(ctx.parameterList())

        return Node(
            ctx=ctx,
            type='ModifierDefinition',
            name=ctx.identifier().getText(),
            parameters=parameters,
            body=self.visit(ctx.block())
        )


    # ********************************************************
    #     functionDefinition
    # : functionDescriptor parameterList modifierList returnParameters? ( ';' | block ) ;
    
    def visitFunctionDefinition(self, ctx: SolidityParser.FunctionDefinitionContext):
        # name = ctx.identifier().getText() if ctx.identifier() else ""
        functionDescriptor = self.visit(ctx.functionDescriptor())
        if functionDescriptor:
            name = functionDescriptor.name
            function_type = "FunctionDefinition"
            isConstructor = False
        else:
            name = self._currentContract
            function_type = "ConstructorDefinition"
            isConstructor = True   
        parameters = self.visit(ctx.parameterList())
        returnParameters = self.visit(ctx.returnParameters()) if ctx.returnParameters() else []
        block = self.visit(ctx.block()) if ctx.block() else []
        modifiers = [self.visit(i) for i in ctx.modifierList().modifierInvocation()]

        if ctx.modifierList().ExternalKeyword(0):
            visibility = "external"
        elif ctx.modifierList().InternalKeyword(0):
            visibility = "internal"
        elif ctx.modifierList().PublicKeyword(0):
            visibility = "public"
        elif ctx.modifierList().PrivateKeyword(0):
            visibility = "private"
        else:
            visibility = 'default'

        if ctx.modifierList().stateMutability(0):
            stateMutability = ctx.modifierList().stateMutability(0).getText()
        else:
            stateMutability = None

        return Node(
            ctx=ctx,
            type=function_type,
            name=name,
            parameters=parameters,
            returnParameters=returnParameters,
            body=block,
            visibility=visibility,
            modifiers=modifiers,
            isConstructor=isConstructor,
            stateMutability=stateMutability
        )
    
    
    # ********************************************************
    #     functionDescriptor
    #   : 'function' ( identifier | ReceiveKeyword | FallbackKeyword )?
    #   | ConstructorKeyword
    #   | FallbackKeyword
    #   | ReceiveKeyword ;

    def visitfunctionDescriptor(self, ctx: SolidityParser.FunctionDescriptorContext):
        return Node(
            ctx=ctx,
            type="functionDescriptor",
            name=ctx.identifier().getText(),
        )
        
    
    
    # ********************************************************
    #     returnParameters
    #   : 'returns' parameterList ;
    
    def visitReturnParameters(self, ctx: SolidityParser.ReturnParametersContext):
        return self.visit(ctx.parameterList())
    
    
    # ********************************************************
    #     modifierInvocation
    #   : identifier ( '(' expressionList? ')' )? ;

    def visitModifierInvocation(self, ctx: SolidityParser.modifierInvocation):
        exprList = ctx.expressionList()

        if exprList is not None:
            args = self.visit(exprList.expression())
        else:
            args = []

        return Node(
            ctx=ctx,
            type='ModifierInvocation',
            name=ctx.identifier().getText(),
            arguments=args
        )
        
    
    # ********************************************************
    #     eventDefinition
    #   : 'event' identifier eventParameterList AnonymousKeyword? ';' ;
    
    def visitEventDefinition(self, ctx: SolidityParser.eventDefinition):
        return Node(
            ctx=ctx,
            type='EventDefinition',
            name=ctx.identifier().getText(),
            parameters=self.visit(ctx.eventParameterList()),
            isAnonymous=not not ctx.AnonymousKeyword()
        )
        
        
    # ********************************************************
    #     enumDefinition
    #   : 'enum' identifier '{' enumValue? (',' enumValue)* '}' ;
    
    def visitEnumDefinition(self, ctx: SolidityParser.enumDefinition):
        return Node(
            ctx=ctx,
            type="EnumDefinition",
            name=ctx.identifier().getText(),
            members=self.visit(ctx.enumValue())
        )
        
        
    # ********************************************************
    #     parameterList
    #   : '(' ( parameter (',' parameter)* )? ')' ;
    
    def visitParameterList(self, ctx: SolidityParser.ParameterListContext):
        parameters = [self.visit(p) for p in ctx.parameter()]
        return Node(
            ctx=ctx,
            type="ParameterList",
            parameters=parameters
        )
        

    # ********************************************************
    #     enumValue
    #   : identifier ;
    def visitEnumValue(self, ctx: SolidityParser.enumValue):
        return Node(
            ctx=ctx,
            type="EnumValue",
            name=ctx.identifier().getText()
        )
    
    
    # ********************************************************
    #     parameterList
    #   : '(' ( parameter (',' parameter)* )? ')' ;
    def visitParameterList(self, ctx: SolidityParser.ParameterListContext):
        parameters = [self.visit(p) for p in ctx.parameter()]
        return Node(
            ctx=ctx,
            type="ParameterList",
            parameters=parameters
        )
    
    # ********************************************************
    #     parameter
    #   : typeName storageLocation? identifier? ;
    def visitParameter(self, ctx: SolidityParser.ParameterContext):
    
        storageLocation = ctx.storageLocation().getText() if ctx.storageLocation() else None
        name = ctx.identifier().getText() if ctx.identifier() else None

        return Node(
            ctx=ctx,
            type="Parameter",
            typeName=self.visit(ctx.typeName()),
            name=name,
            storageLocation=storageLocation,
            isStateVar=False,
            isIndexed=False
        )
    
    
    # ********************************************************
    #     eventParameterList
    #   : '(' ( eventParameter (',' eventParameter)* )? ')' ;
    def visitEventParameterList(self, ctx: SolidityParser.eventParameterList):
        parameters = []
        for paramCtx in ctx.eventParameter():
            type = self.visit(paramCtx.typeName())
            name = None
            if paramCtx.identifier():
                name = paramCtx.identifier().getText()

            parameters.append(self._createNode(ctx=ctx,
                type='VariableDeclaration',
                typeName=type,
                name=name,
                isStateVar=False,
                isIndexed=not not paramCtx.IndexedKeyword()))

        return Node(
            ctx=ctx,
            type='EventParameterList',
            parameters=parameters
        )
    
    # ********************************************************
    #     eventParameter
    #   : typeName IndexedKeyword? identifier? ;
    def visitEventParameter(self, ctx: SolidityParser.eventParameter):
        storageLocation = None

        # TODO: fixme

        if (ctx.storageLocation(0)):
            storageLocation = ctx.storageLocation(0).getText()

        return Node(
            ctx=ctx,
            type='VariableDeclaration',
            typeName=self.visit(ctx.typeName()),
            name=ctx.identifier().getText(),
            storageLocation=storageLocation,
            isStateVar=False,
            isIndexed=not not ctx.IndexedKeyword()
        )
    
    # ********************************************************
    #     variableDeclaration
    #   : typeName storageLocation? identifier ;
    def visitVariableDeclaration(self, ctx: SolidityParser.variableDeclaration):
        storageLocation = None

        if ctx.storageLocation():
            storageLocation = ctx.storageLocation().getText()

        return Node(
            ctx=ctx,
            type='VariableDeclaration',
            typeName=self.visit(ctx.typeName()),
            name=ctx.identifier().getText(),
            storageLocation=storageLocation
        )
    
    
    # ********************************************************
    #     typeName
    #   : elementaryTypeName
    #   | userDefinedTypeName
    #   | mapping
    #   | typeName '[' expression? ']'
    #   | functionTypeName ;
    def visitTypeName(self, ctx: SolidityParser.typeName):
        if len(ctx.children) > 2:
            length = None
            if len(ctx.children) == 4:
                length = self.visit(ctx.getChild(2))

            return Node(
                ctx=ctx,
                type='ArrayTypeName',
                baseTypeName=self.visit(ctx.getChild(0)),
                length=length
            )

        if len(ctx.children) == 2:
            return Node(
                ctx=ctx,
                type='ElementaryTypeName',
                name=ctx.getChild(0).getText(),
                stateMutability=ctx.getChild(1).getText()
            )

        return self.visit(ctx.getChild(0))
    
    
    # ********************************************************
    #     userDefinedTypeName
    #   : identifier ( '.' identifier )* ;
    def visitUserDefinedTypeName(self, ctx: SolidityParser.userDefinedTypeName):
        return Node(
            ctx=ctx,
            type='UserDefinedTypeName',
            namePath=ctx.getText()
        )
    
    
    # ********************************************************
    #     mapping
    #   : 'mapping' '(' (elementaryTypeName | userDefinedTypeName) '=>' typeName ')' ;
    def visitMapping(self, ctx: SolidityParser.mapping):
        return Node(
            ctx=ctx,
            type='Mapping',
            keyType=self.visit(ctx.elementaryTypeName()),
            valueType=self.visit(ctx.typeName())
        )
        
        
    # ********************************************************
    #     functionTypeName
    #   : 'function' parameterList modifierList returnParameters? ;
    def visitFunctionTypeName(self, ctx: SolidityParser.functionTypeName):
        parameterTypes = [self.visit(p) for p in ctx.functionTypeParameterList(0).functionTypeParameter()]
        returnTypes = []

        if ctx.functionTypeParameterList(1):
            returnTypes = [self.visit(p) for p in ctx.functionTypeParameterList(1).functionTypeParameter()]

        visibility = 'default'
        if ctx.InternalKeyword(0):
            visibility = 'internal'
        elif ctx.ExternalKeyword(0):
            visibility = 'external'

        stateMutability = None
        if ctx.stateMutability(0):
            stateMutability = ctx.stateMutability(0).getText()

        return Node(
            ctx=ctx,
            type='FunctionTypeName',
            parameterTypes=parameterTypes,
            returnTypes=returnTypes,
            visibility=visibility,
            stateMutability=stateMutability
        )
    
    
    # ********************************************************
    #     block
    #   : '{' statement* '}' ;
    def visitBlock(self, ctx: SolidityParser.block):
        return Node(
            ctx=ctx,
            type='Block',
            statements=self.visit(ctx.statement())
        )
        
        
    # ********************************************************        
    #     statement
    #   : ifStatement
    #   | tryStatement
    #   | whileStatement
    #   | forStatement
    #   | block
    #   | inlineAssemblyStatement
    #   | doWhileStatement
    #   | continueStatement
    #   | breakStatement
    #   | returnStatement
    #   | throwStatement
    #   | emitStatement
    #   | simpleStatement ;
    def visitStatement(self, ctx: SolidityParser.statement):
        return self.visit(ctx.getChild(0))
        
            
    # ********************************************************  
    #     expressionStatement
    #   : expression ';' ;        
    def visitExpressionStatement(self, ctx: SolidityParser.expressionStatement):
        return Node(
            ctx=ctx,
            type='ExpressionStatement',
            expression=self.visit(ctx.expression())
        )        

    # ********************************************************  
    # ifStatement
    #   : 'if' '(' expression ')' statement ( 'else' statement )? ;
    def visitIfStatement(self, ctx: SolidityParser.ifStatement):
    
        TrueBody = self.visit(ctx.statement(0))

        FalseBody = None
        if len(ctx.statement()) > 1:
            FalseBody = self.visit(ctx.statement(1))

        return Node(
            ctx=ctx,
            type='IfStatement',
            condition=self.visit(ctx.expression()),
            TrueBody=TrueBody,
            FalseBody=FalseBody
        )
    
    
    # ******************************************************** 
    # tryStatement : 'try' expression returnParameters? block catchClause+ ;
    def visitTryStatement(self, ctx: SolidityParser.tryStatement):
        return Node(
            ctx=ctx,
            type='TryStatment',
            block=self.visit(ctx.block()),
            expression=self.visit(ctx.expression()),
            catchClause=self.visit(ctx.catchClause())
        )
        
    
    # ******************************************************** 
    # catchClause : 'catch' ( identifier? parameterList )? block ;
    def visitCatchClause(self, ctx: SolidityParser.catchClause):
        return Node(
            ctx=ctx,
            type="CatchClause",
            block=self.visit(ctx.block())
        )
    
    
    # ******************************************************** 
    #     whileStatement
    #   : 'while' '(' expression ')' statement ;
    def visitWhileStatement(self, ctx: SolidityParser.whileStatement):
        return Node(
            ctx=ctx,
            type='WhileStatement',
            condition=self.visit(ctx.expression()),
            body=self.visit(ctx.statement())
        )
    
    
    
    # ******************************************************** 
    #     forStatement
    #   : 'for' '(' ( simpleStatement | ';' ) ( expressionStatement | ';' ) expression? ')' statement ;
    def visitForStatement(self, ctx: SolidityParser.forStatement):
        conditionExpression = self.visit(ctx.expressionStatement()) if ctx.expressionStatement() else None

        if conditionExpression:
            conditionExpression = conditionExpression.expression

        return Node(
            ctx=ctx,
            type='ForStatement',
            initExpression=self.visit(ctx.simpleStatement()),
            conditionExpression=conditionExpression,
            loopExpression=Node(
                ctx=ctx,
                type='ExpressionStatement',
                expression=self.visit(ctx.expression())
            ),
            body=self.visit(ctx.statement())
        )
    
    
    # ******************************************************** 
    #     simpleStatement
    #   : ( variableDeclarationStatement | expressionStatement ) ;
    def visitSimpleStatement(self, ctx: SolidityParser.simpleStatement):
        return self.visit(ctx.getChild(0))
    
    
    # ******************************************************** 
    #     inlineAssemblyStatement
    #   : 'assembly' StringLiteralFragment? assemblyBlock ;
    def visitInLineAssemblyStatement(self, ctx: SolidityParser.inlineAssemblyStatement):
        language = None

        if ctx.StringLiteralFragment():
            language = ctx.StringLiteral().getText()
            language = language[1: len(language) - 1]

        return Node(
            ctx=ctx,
            type='InLineAssemblyStatement',
            language=language,
            body=self.visit(ctx.assemblyBlock())
        )
    
    
    # ******************************************************** 
    #     doWhileStatement
    #   : 'do' statement 'while' '(' expression ')' ';' ;
    def visitDoWhileStatement(self, ctx: SolidityParser.doWhileStatement):
        return Node(
            ctx=ctx,
            type='DoWhileStatement',
            condition=self.visit(ctx.expression()),
            body=self.visit(ctx.statement())
        )

    
    # ******************************************************** 
    # returnStatement
    #   : 'return' expression? ';' ;
    def visitReturnStatement(self, ctx: SolidityParser.returnStatement):
        return self.visit(ctx.expression())
    
    
    # ******************************************************** 
    #     throwStatement
    #   : 'throw' ';' ;
    def visieThrowStatement(self, ctx: SolidityParser.throwStatement):
        # TODO
        return self.visit(ctx.expression())
    
    
    # ********************************************************   
    #     emitStatement
    #   : 'emit' functionCall ';' ;
    def visitEmitStatement(self, ctx):
        return Node(
            ctx=ctx,
            type='EmitStatement',
            eventCall=self.visit(ctx.getChild(1))
        )
    
    
    # ********************************************************   
    #     variableDeclarationStatement
    #   : ( 'var' identifierList | variableDeclaration | '(' variableDeclarationList ')' ) ( '=' expression )? ';';
    def visitVariableDeclarationStatement(self, ctx):
    
        if ctx.variableDeclaration():
            variables = [self.visit(ctx.variableDeclaration())]
        elif ctx.identifierList():
            variables = self.visit(ctx.identifierList())
        elif ctx.variableDeclarationList():
            variables = self.visit(ctx.variableDeclarationList())

        initialValue = None

        if ctx.expression():
            initialValue = self.visit(ctx.expression())

        return Node(
            ctx=ctx,
            type='VariableDeclarationStatement',
            variables=variables,
            initialValue=initialValue
        )
    
    
    # ********************************************************   
    #     variableDeclarationList
    #   : variableDeclaration? (',' variableDeclaration? )* ;
    def visitVariableDeclarationList(self, ctx: SolidityParser.VariableDeclarationListContext):
        result = []
        for decl in self._mapCommasToNulls(ctx.children):
            if decl == None:
                return result

            result.append(
                self._createNode(
                    ctx=ctx,
                    type='VariableDeclaration',
                    name=decl.identifier().getText(),
                    typeName=self.visit(decl.typeName()),
                    isStateVar=False,
                    isIndexed=False,
                    decl=decl
                )
            )

        return result
    
    
    # ********************************************************   
    #     identifierList
    #   : '(' ( identifier? ',' )* identifier? ')' ;
    def visitIdentifierList(self, ctx: SolidityParser.IdentifierListContext):
        children = ctx.children[1:-1]

        result = []
        for iden in self._mapCommasToNulls(children):
            if iden == None:
                result.append(None)
            else:
                result.append(
                    self._createNode(
                        ctx=ctx,
                        type="VariableDeclaration",
                        name=iden.getText(),
                        isStateVar=False,
                        isIndexed=False,
                        iden=iden
                    )
                )
    
        return result
    
    
    # ******************************************************** 
    #     elementaryTypeName
    #   : 'address' PayableKeyword? | 'bool' | 'string' | 'var' | Int | Uint | 'byte' | Byte | Fixed | Ufixed ;
    def visitElementaryTypeName(self, ctx):
        return Node(
            ctx=ctx,
            type='ElementaryTypeName',
            name=ctx.getText()
        )
    
        
    # ********************************************************     
    #     primaryExpression
    #   : BooleanLiteral
    #   | numberLiteral
    #   | hexLiteral
    #   | stringLiteral
    #   | identifier ('[' ']')?
    #   | TypeKeyword
    #   | tupleExpression
    #   | typeNameExpression ('[' ']')? ;
    def visitPrimaryExpression(self, ctx):
        if ctx.BooleanLiteral():
            return Node(
                ctx=ctx,
                type='BooleanLiteral',
                value=ctx.BooleanLiteral().getText() == 'true'
            )

        if ctx.hexLiteral():
            return Node(
                ctx=ctx,
                type='HexLiteral',
                value=ctx.hexLiteral().getText()
            )

        if ctx.stringLiteral():
            text = ctx.getText()

            return Node(
                ctx=ctx,
                type='StringLiteral',
                value=text[1: len(text) - 1]
            )

        if ctx.children:
            if len(ctx.children) == 3 and ctx.getChild(1).getText() == '[' and ctx.getChild(2).getText() == ']':
                node = self.visit(ctx.getChild(0))
                if node.type == 'Identifier':
                    node = Node(
                        ctx=ctx,
                        type='UserDefinedTypeName',
                        namePath=node.name
                    )
                else:
                    node = Node(
                        ctx=ctx,
                        type='ElementaryTypeName',
                        name=ctx.getChild(0).getText()
                    )

                return Node(
                    ctx=ctx,
                    type='ArrayTypeName',
                    baseTypeName=node,
                    length=None
                )

        return self.visit(ctx.getChild(0))
    
    
    # ********************************************************  
    #     functionCall
    #   : expression '(' functionCallArguments ')' ;
    def visitFunctionCall(self, ctx):
        args = []
        names = []

        ctxArgs = ctx.functionCallArguments()

        if ctxArgs.expressionList():
            args = [self.visit(a) for a in ctxArgs.expressionList().expression()]

        elif ctxArgs.nameValueList():
            for nameValue in ctxArgs.nameValueList().nameValue():
                args.append(self.visit(nameValue.expression()))
                names.append(nameValue.identifier().getText())

        return Node(
            ctx=ctx,
            type='FunctionCall',
            expression=self.visit(ctx.expression()),
            arguments=args,
            names=names
        )
        
        
    # ******************************************************** 
    #     tupleExpression
    #   : '(' ( expression? ( ',' expression? )* ) ')'
    #   | '[' ( expression ( ',' expression )* )? ']' ;
    def visitTupleExpression(self, ctx):
        children = ctx.children[1:-1]
        components = [None if e is None else self.visit(e) for e in self._mapCommasToNulls(children)]

        return Node(
            ctx=ctx,
            type='TupleExpression',
            components=components,
            isArray=ctx.getChild(0).getText() == '['
        )
    
    # ******************************************************** 
    #     typeNameExpression
    #   : elementaryTypeName
    #   | userDefinedTypeName ;
    def visitTypeNameExpression(self, ctx: SolidityParser.typeNameExpression):
        return Node(
            ctx=ctx,
            type='TypeNameExpression',
            typeName=self.visit(ctx.elementaryTypeName())
        )
        

    # ********************************************************
    #     expression
    #   : expression ('++' | '--')
    #   | 'new' typeName
    #   | expression '[' expression? ']'
    #   | expression '[' expression? ':' expression? ']'
    #   | expression '.' identifier
    #   | expression '{' nameValueList '}'
    #   | expression '(' functionCallArguments ')'
    #   | PayableKeyword '(' expression ')'
    #   | '(' expression ')'
    #   | ('++' | '--') expression
    #   | ('+' | '-') expression
    #   | ('after' | 'delete') expression
    #   | '!' expression
    #   | '~' expression
    #   | expression '**' expression
    #   | expression ('*' | '/' | '%') expression
    #   | expression ('+' | '-') expression
    #   | expression ('<<' | '>>') expression
    #   | expression '&' expression
    #   | expression '^' expression
    #   | expression '|' expression
    #   | expression ('<' | '>' | '<=' | '>=') expression
    #   | expression ('==' | '!=') expression
    #   | expression '&&' expression
    #   | expression '||' expression
    #   | expression '?' expression ':' expression
    #   | expression ('=' | '|=' | '^=' | '&=' | '<<=' | '>>=' | '+=' | '-=' | '*=' | '/=' | '%=') expression
    #   | primaryExpression ;
    def visitExpression(self, ctx):
    
        children_length = len(ctx.children)
        if children_length == 1:
            return self.visit(ctx.getChild(0))

        elif children_length == 2:
            op = ctx.getChild(0).getText()
            if op == 'new':
                return Node(
                    ctx=ctx,
                    type='NewExpression',
                    typeName=self.visit(ctx.typeName())
                )

            if op in ['+', '-', '++', '--', '!', '~', 'after', 'delete']:
                return Node(
                    ctx=ctx,
                    type='UnaryOperation',
                    operator=op,
                    subExpression=self.visit(ctx.getChild(1)),
                    isPrefix=True
                )

            op = ctx.getChild(1).getText()
            if op in ['++', '--']:
                return Node(
                    ctx=ctx,
                    type='UnaryOperation',
                    operator=op,
                    subExpression=self.visit(ctx.getChild(0)),
                    isPrefix=False
                )
                
        elif children_length == 3:
            if ctx.getChild(0).getText() == '(' and ctx.getChild(2).getText() == ')':
                return Node(
                    ctx=ctx,
                    type='TupleExpression',
                    components=[self.visit(ctx.getChild(1))],
                    isArray=False
                )

            op = ctx.getChild(1).getText()

            if op == ',':
                return Node(
                    ctx=ctx,
                    type='TupleExpression',
                    components=[
                        self.visit(ctx.getChild(0)),
                        self.visit(ctx.getChild(2))
                    ],
                    isArray=False
                )


            elif op == '.':
                expression = self.visit(ctx.getChild(0))
                memberName = ctx.getChild(2).getText()
                return Node(
                    ctx=ctx,
                    type='MemberAccess',
                    expression=expression,
                    memberName=memberName
                )

            binOps = [
                '+',
                '-',
                '*',
                '/',
                '**',
                '%',
                '<<',
                '>>',
                '&&',
                '||',
                '&',
                '|',
                '^',
                '<',
                '>',
                '<=',
                '>=',
                '==',
                '!=',
                '=',
                '|=',
                '^=',
                '&=',
                '<<=',
                '>>=',
                '+=',
                '-=',
                '*=',
                '/=',
                '%='
            ]

            if op in binOps:
                return Node(
                    ctx=ctx,
                    type='BinaryOperation',
                    operator=op,
                    left=self.visit(ctx.getChild(0)),
                    right=self.visit(ctx.getChild(2))
                )

        elif children_length == 4:

            if ctx.getChild(1).getText() == '(' and ctx.getChild(3).getText() == ')':
                args = []
                names = []

                ctxArgs = ctx.functionCallArguments()
                if ctxArgs: # payable( )                                             
                    if ctxArgs.expressionList():
                        args = [self.visit(a) for a in ctxArgs.expressionList().expression()]
                    elif ctxArgs.nameValueList():
                        for nameValue in ctxArgs.nameValueList().nameValue():
                            args.append(self.visit(nameValue.expression()))
                            names.append(nameValue.identifier().getText())
                

                return Node(
                    ctx=ctx,
                    type='FunctionCall',
                    expression=self.visit(ctx.getChild(0)),
                    arguments=args,
                    names=names
                )

            if ctx.getChild(1).getText() == '[' and ctx.getChild(3).getText() == ']':
                return Node(
                    ctx=ctx,
                    type='IndexAccess',
                    base=self.visit(ctx.getChild(0)),
                    index=self.visit(ctx.getChild(2))
                )

        elif children_length == 5:
            # ternary
            if ctx.getChild(1).getText() == '?' and ctx.getChild(3).getText() == ':':
                return Node(
                    ctx=ctx,
                    type='Conditional',
                    condition=self.visit(ctx.getChild(0)),
                    TrueExpression=self.visit(ctx.getChild(2)),
                    FalseExpression=self.visit(ctx.getChild(4))
                )

        # raise Exception("unrecognized expression")    
        
        
    # ********************************************************     
    #     assemblyItem
    #   : identifier
    #   | assemblyBlock
    #   | assemblyExpression
    #   | assemblyLocalDefinition
    #   | assemblyAssignment
    #   | assemblyStackAssignment
    #   | labelDefinition
    #   | assemblySwitch
    #   | assemblyFunctionDefinition
    #   | assemblyFor
    #   | assemblyIf
    #   | BreakKeyword
    #   | ContinueKeyword
    #   | LeaveKeyword
    #   | subAssembly
    #   | numberLiteral
    #   | stringLiteral
    #   | hexLiteral ;

    
    # ********************************************************
    #     assemblyBlock
    #   : '{' assemblyItem* '}' ;
    def visitAssemblyBlock(self, ctx):
        operations = [self.visit(it) for it in ctx.assemblyItem()]
        return Node(
            ctx=ctx,
            type="AssemblyBlock",
            operations=operations
        )
    
    
    def visitAssemblyItem(self, ctx: SolidityParser.assemblyItem):
    
        if ctx.hexLiteral():
            return Node(
                ctx=ctx,
                type='HexLiteral',
                value=ctx.HexLiteral().getText()
            )

        if ctx.stringLiteral():
            text = ctx.StringLiteral().getText()
            return Node(
                ctx=ctx,
                type='StringLiteral',
                value=text[1: len(text) - 1]
            )

        if ctx.BreakKeyword():
            return Node(
                ctx=ctx,
                type='Break'
            )

        if ctx.ContinueKeyword():
            return Node(
                ctx=ctx,
                type='Continue'
            )

        return self.visit(ctx.getChild(0))
    
    
    # ********************************************************
    #     assemblyExpression
    #   : assemblyCall | assemblyLiteral ;
    def visitAssemblyExpression(self, ctx):
        return self.visit(ctx.getChild(0))
    
    
    # ********************************************************   
    #     assemblyCall
    #   : ( 'return' | 'address' | 'byte' | identifier ) ( '(' assemblyExpression? ( ',' assemblyExpression )* ')' )? ;
    def visitAssemblyCall(self, ctx):
        functionName = ctx.getChild(0).getText()
        args = [self.visit(arg) for arg in ctx.assemblyExpression()]

        return Node(
            ctx=ctx,
            type='AssemblyExpression',
            functionName=functionName,
            arguments=args
        )
        
        
    # ********************************************************       
    #     assemblyLocalDefinition
    #   : 'let' assemblyIdentifierList ( ':=' assemblyExpression )? ;
    def visitAssemblyFunctionDefinition(self, ctx):
        args = ctx.assemblyIdentifierList().identifier()
        returnArgs = ctx.assemblyFunctionReturns().assemblyIdentifierList().identifier()

        return Node(
            ctx=ctx,
            type='AssemblyFunctionDefinition',
            name=ctx.identifier().getText(),
            arguments=self.visit(args),
            returnArguments=self.visit(returnArgs),
            body=self.visit(ctx.assemblyBlock())
        )
    
    
    # ********************************************************   
    #     assemblyAssignment
    #   : assemblyIdentifierList ':=' assemblyExpression ;
    def visitAssemblyAssignment(self, ctx):
        names = ctx.assemblyIdentifierList()

        if names.identifier():
            names = [self.visit(names.identifier())]
        else:
            names = self.visit(names.assemblyIdentifierList().identifier())

        return Node(
            ctx=ctx,
            type='AssemblyAssignment',
            names=names,
            expression=self.visit(ctx.assemblyExpression())
        )    
    
    
    # ********************************************************      
    #     assemblyStackAssignment
    #   : '=:' identifier ;
    def visitAssemblyStackAssignment(self, ctx):
        return Node(
            ctx=ctx,
            type='AssemblyStackAssignment',
            name=ctx.identifier().getText()
        )
        
        
    # ********************************************************     
    #     labelDefinition
    #   : identifier ':' ;
    def visitLabelDefinition(self, ctx):
        return Node(
            ctx=ctx,
            type='LabelDefinition',
            name=ctx.identifier().getText()
        )
        
        
    # ******************************************************** 
    #     assemblyCase
    #   : 'case' assemblyLiteral assemblyType? assemblyBlock
    #   | 'default' assemblyBlock ;    
    def visitAssemblyCase(self, ctx):
        value = None

        if ctx.getChild(0).getText() == 'case':
            value = self.visit(ctx.assemblyLiteral())

        if value != None:
            node = Node(
                ctx=ctx,
                type="AssemblyCase",
                block=self.visit(ctx.assemblyBlock()),
                value=value
            )
        else:
            node = Node(
                ctx=ctx,
                type="AssemblyCase",
                block=self.visit(ctx.assemblyBlock()),
                default=True
            )

        return node    
        
          
    # ********************************************************   
    # assemblySwitch
    #   : 'switch' assemblyExpression assemblyCase* ;
    def visitAssemblySwitch(self, ctx):
        return Node(
            ctx=ctx,
            type='AssemblySwitch',
            expression=self.visit(ctx.assemblyExpression()),
            cases=[self.visit(c) for c in ctx.assemblyCase()]
        )

    # ********************************************************   
    #     assemblyFunctionDefinition
    # : 'function' identifier '(' assemblyTypedVariableList? ')'
    #     assemblyFunctionReturns? assemblyBlock ;
    def visitAssemblyFunctionDefinition(self, ctx):
        args = ctx.assemblyTypedVariableList().identifier()
        returnArgs = ctx.assemblyFunctionReturns().assemblyTypedVariableList().identifier()

        return Node(
            ctx=ctx,
            type='AssemblyFunctionDefinition',
            name=ctx.identifier().getText(),
            arguments=self.visit(args),
            returnArguments=self.visit(returnArgs),
            body=self.visit(ctx.assemblyBlock())
        )


    # ********************************************************  
    #     assemblyFor
    #   : 'for' assemblyBlock assemblyExpression assemblyBlock assemblyBlock ;
    def visitAssemblyFor(self, ctx):
        return Node(
            ctx=ctx,
            type='AssemblyFor',
            pre=self.visit(ctx.getChild(1)),
            condition=self.visit(ctx.getChild(2)),
            post=self.visit(ctx.getChild(3)),
            body=self.visit(ctx.getChild(4))
        )


    # ********************************************************
    #     assemblyIf
    #   : 'if' assemblyExpression assemblyBlock ;
    def visitAssemblyIf(self, ctx):
        return Node(
            ctx=ctx,
            type='AssemblyIf',
            condition=self.visit(ctx.assemblyExpression()),
            body=self.visit(ctx.assemblyBlock())
        )
        
        
    # ********************************************************
    #     assemblyLiteral
    #   : ( stringLiteral | DecimalNumber | HexNumber | hexLiteral | BooleanLiteral ) assemblyType? ;
    def visitAssemblyLiteral(self, ctx):
    
        if ctx.stringLiteral():
            text = ctx.getText()
            return Node(
                ctx=ctx,
                type='StringLiteral',
                value=text[1: len(text) - 1]
            )

        if ctx.DecimalNumber():
            return Node(
                ctx=ctx,
                type='DecimalNumber',
                value=ctx.getText()
            )

        if ctx.HexNumber():
            return Node(ctx=ctx,
                        type='HexNumber',
                        value=ctx.getText())

        if ctx.HexLiteral():
            return Node(
                ctx=ctx,
                type='HexLiteral',
                value=ctx.getText()
            )
            
            
    # ********************************************************
    #     assemblyTypedVariableList
    #   : identifier assemblyType? ( ',' assemblyTypedVariableList )? ;
    def visitAssemblyTypedVariableList(self, ctx: SolidityParser.AssemblyTypedVariableListContext):
        # TODO
        return Node(
            ctx=ctx,
            type="AssemblyTypedVariableList"
        )
    
    
    # ********************************************************   
    #     assemblyType
    #   : ':' identifier ;
    def visitAssemblyType(self, ctx: SolidityParser.AssemblyTypeContext):
        # TODO
        return Node(
            ctx=ctx,
            type="AssemblyType"
        )
    
    
    # ********************************************************     
    #     subAssembly
    #   : 'assembly' identifier assemblyBlock ;
    def visitSubAssembly(self, ctx: SolidityParser.SubAssemblyContext):
       # TODO
        return Node(
            ctx=ctx,
            type="SubAssembly"
        ) 
        
        
    # ******************************************************** 
    #     numberLiteral
    #   : (DecimalNumber | HexNumber) NumberUnit? ;
    def visitNumberLiteral(self, ctx):
        number = ctx.getChild(0).getText()
        subdenomination = None

        if len(ctx.children) == 2:
            subdenomination = ctx.getChild(1).getText()

        return Node(
            ctx=ctx,
            type='NumberLiteral',
            number=number,
            subdenomination=subdenomination
        )
    
    
    # ********************************************************     
    #     identifier
    #   : ('from' | 'calldata' | 'address' | Identifier) ;
    
    def visitIdentifier(self, ctx):
        return Node(
            ctx=ctx,
            type="Identifier",
            name=ctx.getText()
        )
    

def visit(node, callback_object):
    """

    Walks the AST produced by parse/parse_file and calls callback_object.visit<Node.type>

    :param node: ASTNode returned from parse()
    :param callback: an object implementing the visitor pattern
    :return:
    """

    if node is None or not isinstance(node, Node):
        return node

    # call callback if it is available
    if hasattr(callback_object, "visit"+node.type):
        getattr(callback_object, "visit"+node.type)(node)

    for k,v in node.items():
        if k in node.NONCHILD_KEYS:
            # skip non child items
            continue

        # item is array?
        if isinstance(v, list):
            [visit(child, callback_object) for child in v]
        else:
            visit(v, callback_object)


def objectify(start_node, file_name=None):
    """
    Create an OOP like structure from the tree for easy access of most common information

    sourceUnit
       .pragmas []
       .imports []
       .contracts { name: contract}
           .statevars
           .enums
           .structs
           .functions
           .modifiers
           .

    :param tree:
    :return:
    """

    current_contract = None
    current_function = None

    class ObjectifyContractVisitor(object):

        def __init__(self, node):
            self.node = node
            self.name = node.name
            self.kind = node.kind
                
            self.dependencies = []
            self.stateVars = {}
            self.names = {}
            self.enums = {}
            self.structs = {}
            self.mappings = {}
            self.events = {}
            self.modifiers = {}
            self.functions = {}
            self.constructor = None
            self.inherited_names = {}


        def visitEnumDefinition(self, _node):
            self.enums[_node.name]=_node
            self.names[_node.name]=_node

        def visitStructDefinition(self, _node):
            self.structs[_node.name]=_node
            self.names[_node.name]=_node

        def visitConstructorDefinition(self, _node):
            class ConstructorObject(object):
    
                def __init__(self, node):
                    self.node = node
                    if(node.type=="ConstructorDefinition"):
                        self.visibility = node.visibility
                        self.stateMutability = node.stateMutability
                    self.arguments = {}
                    self.returns = {}
                    self.declarations = {}
                    self.identifiers = {}
                    self.assemblys = {}
            
            class ConstructorArgumentVisitor(object):
    
                def __init__(self):
                    self.parameters = {}

                def visitParameter(self, __node):
                    self.parameters[__node.name] = __node
            
            class VarDecVisitor(object):
    
                def __init__(self):
                    self.variable_declarations = {}

                def visitVariableDeclaration(self, __node):
                    self.variable_declarations[__node.name] = __node
                    
            class IdentifierDecVisitor(object):
    
                def __init__(self):
                    self.idents = {}

                def visitIdentifier(self, __node):
                    self.idents[__node.name] = __node

                def visitAssemblyCall(self, __node):
                    self.assemblys[__node.name] = __node

            current_Constructor = ConstructorObject(_node)
            self.constructor = current_Constructor
            
            constructorargvisitor = ConstructorArgumentVisitor()
            visit(_node.parameters, constructorargvisitor)
            current_Constructor.arguments = constructorargvisitor.parameters
            current_Constructor.declarations.update(current_Constructor.arguments)
            
            vardecs = VarDecVisitor()
            visit(_node.body, vardecs)
            current_Constructor.declarations.update(vardecs.variable_declarations)
            
            idents = IdentifierDecVisitor()
            visit(_node, idents)
            current_Constructor.identifiers.update(idents.idents)



        def visitStateVariableDeclaration(self, _node):

            class VarDecVisitor(object):

                def __init__(self, current_contract):
                    self._current_contract = current_contract

                def visitVariableDeclaration(self, __node):
                    self._current_contract.stateVars[__node.name] = __node
                    self._current_contract.names[__node.name] = __node

            visit(_node, VarDecVisitor(self))

        def visitEventDefinition(self, _node):

            class EventFunctionVisitor(object):
                def __init__(self, node):
                    self.arguments = {}
                    self.declarations = {}
                    self.node = node

                def visitVariableDeclaration(self, __node):                                                 
                    self.arguments[__node.name] = __node
                    self.declarations[__node.name] = __node

            current_function = EventFunctionVisitor(_node)
            visit(_node, current_function)
            self.names[_node.name] = current_function
            self.events[_node.name] = current_function


        def visitFunctionDefinition(self, _node, _definition_type=None):

            class FunctionObject(object):

                def __init__(self, node):
                    self.node = node
                    if(node.type=="FunctionDefinition"):
                        self.visibility = node.visibility
                        self.stateMutability = node.stateMutability
                    self.arguments = {}
                    self.returns = {}
                    self.declarations = {}
                    self.identifiers = {}
                    self.assemblys = {}

            class FunctionArgumentVisitor(object):

                def __init__(self):
                    self.parameters = {}

                def visitParameter(self, __node):
                    self.parameters[__node.name] = __node

            class VarDecVisitor(object):

                def __init__(self):
                    self.variable_declarations = {}

                def visitVariableDeclaration(self, __node):
                    self.variable_declarations[__node.name] = __node

            class IdentifierDecVisitor(object):

                def __init__(self):
                    self.idents = {}
                    self.assemblycalls = {}

                def visitIdentifier(self, __node):
                    self.idents[__node.name] = __node

                def visitAssemblyCall(self, __node):
                    self.assemblycalls[__node.name] = __node

            class InLineAssemblyStatementVisitor(object):
                
                def __init__(self):
                    self.assemStatements = []
                    
                def visitAssemblyBlock(self, __node):
                    self.assemStatements.append(__node)
            
            current_function = FunctionObject(_node)
            self.names[_node.name] = current_function
            if _definition_type=="ModifierDefinition":
                self.modifiers[_node.name] = current_function
            else:
                self.functions[_node.name] = current_function

            ## get parameters
            funcargvisitor = FunctionArgumentVisitor()
            visit(_node.parameters, funcargvisitor)
            current_function.arguments = funcargvisitor.parameters
            current_function.declarations.update(current_function.arguments)


            ## get returnParams
            if _node.get("returnParameters"):
                # because modifiers dont
                funcargvisitor = FunctionArgumentVisitor()
                visit(_node.returnParameters, funcargvisitor)
                current_function.returns = funcargvisitor.parameters
                current_function.declarations.update(current_function.returns)


            ## get vardecs in body
            vardecs = VarDecVisitor()
            visit(_node.body, vardecs)
            current_function.declarations.update(vardecs.variable_declarations)

            ## get all identifiers
            idents = IdentifierDecVisitor()
            visit(_node, idents)
            current_function.identifiers.update(idents.idents)

            ## get assem body in body
            assemblyStatement = InLineAssemblyStatementVisitor()
            visit(_node.body, assemblyStatement)
            current_function.assemblys = assemblyStatement.assemStatements
            
        def visitModifierDefinition(self, _node):
            return self.visitFunctionDefinition(_node, "ModifierDefinition")


    class ObjectifySourceUnitVisitor(object):

        TRUST_CONTRACTS = ["SafeMath"]
        
        def __init__(self, node):
            self.node = node
            self.fileName = file_name
            self.imports = []
            self.pragmas = []
            self.contracts = {}
            self.interfaces = {}

            self._current_contract = None

        def visitPragmaDirective(self, node):
            self.pragmas.append(node)

        def visitImportDirective(self, node):
            self.imports.append(node)

        def visitContractDefinition(self, node):
            if node.kind in ["contract", "interface"]:
                self.contracts[node.name] = ObjectifyContractVisitor(node)
                self._current_contract = self.contracts[node.name]

                # subparse the contracts //slightly inefficient but more readable :)
                visit(node, self.contracts[node.name])
                
    objectified_source_unit = ObjectifySourceUnitVisitor(start_node)
    visit(start_node, objectified_source_unit)
    return objectified_source_unit


def parse_file(path, start="sourceUnit", loc=False, strict=False):
    with open(path, 'r', encoding="utf-8") as f:
        return parse(f.read(), start=start, loc=loc, strict=strict, path=path)
    
    
def parse(text, start="sourceUnit", loc=False, strict=False, path=None):
    from antlr4.InputStream import InputStream
    from antlr4 import FileStream, CommonTokenStream

    input_stream = InputStream(text)

    lexer = SolidityLexer(input_stream)
    lexer.removeErrorListeners()
    token_stream = CommonTokenStream(lexer)
    parser = SolidityParser(token_stream)
    parser.removeErrorListeners()
    ast = AstVisitor(file_path=path)

    Node.ENABLE_LOC = loc

    return ast.visit(getattr(parser, start)())