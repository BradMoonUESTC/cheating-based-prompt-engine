from typing import Any, List, Optional, Tuple, Union
from typing_extensions import override

from antlr4.tree.Tree import ErrorNode
from antlr4 import ParserRuleContext
from antlr4.tree.Tree import ParseTree,ParseTreeVisitor
from antlr4.error.Errors import RecognitionException

from sgp.utilities.contract_extractor import extract_contract_with_name


from .parser.SolidityParser import SolidityParser as SP
from .parser.SolidityVisitor import SolidityVisitor


from .ast_node_types import *


class SGPVisitorOptions:
    def __init__(
        self,
        tokens: bool = False,
        tolerant: bool = True,
        range: bool = True,
        loc: bool = True,
    ):
        """
        Contains options for the SGPVisitor

        Parameters
        ----------
        tokens : bool, optional, default False - #TODO: sort it out
        tolerant : bool, optional, default True - suppress not critical [CST](https://en.wikipedia.org/wiki/Parse_tree) traversing errors
        range : bool, optional, default True - add range (start, end offset) information to AST nodes
        loc : bool, optional, default True - add line/column location information to AST nodes
        """
        self.range: bool = range
        self.loc: bool = loc
        self.tokens: bool = tokens  # TODO: sort it out
        self.errors_tolerant: bool = tolerant


class SGPVisitor(SolidityVisitor):
    def __init__(self, options: SGPVisitorOptions):
        super().__init__()
        self._current_contract = None
        self._options = options

    @override
    def defaultResult(self):
        return {}

    @override
    def aggregateResult(self, aggregate, nextResult):
        return nextResult
    
    @override
    def visitErrorNode(self, node):
        return None
    
    @override
    def visitTerminal(self, node):
        return self.defaultResult()

    def visitSourceUnit(self, ctx: SP.SourceUnitContext) -> SourceUnit:
        children = [child for child in ctx.children if not isinstance(child, ErrorNode)]

        # node = SourceUnit(
        #     children=[self.visit(child) for child in children[:-1]]
        # )
        parsed_children = []
        for child in children[:-1]:
            try:
                n = self.visit(child)
                parsed_children.append(n)
            except Exception as e:
                raise RecognitionException(str(e), None, None, ctx)

        node = SourceUnit(children=parsed_children)

        return self._add_meta(node, ctx)

    def visitContractPart(self, ctx: SP.ContractPartContext):
        return self.visit(ctx.getChild(0))

    def visitContractDefinition(
        self, ctx: SP.ContractDefinitionContext
    ) -> ContractDefinition:
        name = self._to_text(ctx.identifier())
        kind = self._to_text(ctx.getChild(0))

        self._current_contract = name

        node = ContractDefinition(
            name=name,
            base_contracts=list(
                map(self.visitInheritanceSpecifier, ctx.inheritanceSpecifier())
            ),
            children=list(map(self.visit, ctx.contractPart())),
            kind=kind,
        )

        return self._add_meta(node, ctx)

    def visitStateVariableDeclaration(self, ctx: SP.StateVariableDeclarationContext):
        type = self.visitTypeName(ctx.typeName())
        iden = ctx.identifier()
        name = self._to_text(iden)

        expression = None
        ctxExpression = ctx.expression()
        if ctxExpression:
            expression = self.visitExpression(ctxExpression)

        visibility = "default"
        if len(ctx.InternalKeyword()) > 0:
            visibility = "internal"
        elif len(ctx.PublicKeyword()) > 0:
            visibility = "public"
        elif len(ctx.PrivateKeyword()) > 0:
            visibility = "private"

        isDeclaredConst = False
        if len(ctx.ConstantKeyword()) > 0:
            isDeclaredConst = True

        override = None
        overrideSpecifier = ctx.overrideSpecifier()
        if len(overrideSpecifier) == 0:
            override = None
        else:
            override = [
                self.visitUserDefinedTypeName(x)
                for x in overrideSpecifier[0].userDefinedTypeName()
            ]

        isImmutable = False
        if len(ctx.ImmutableKeyword()) > 0:
            isImmutable = True

        decl = StateVariableDeclarationVariable(
            type_name=type,
            name=name,
            identifier=self.visitIdentifier(iden),
            expression=expression,
            visibility=visibility,
            is_state_var=True,
            is_declared_const=isDeclaredConst,
            is_indexed=False,
            is_immutable=isImmutable,
            override=override,
            storage_location=None,
        )

        node = StateVariableDeclaration(
            variables=[self._add_meta(decl, ctx)], initial_value=expression
        )

        return self._add_meta(node, ctx)

    def visitVariableDeclaration(
        self, ctx: SP.VariableDeclarationContext
    ) -> VariableDeclaration:
        storageLocation = None
        ctxStorageLocation = ctx.storageLocation()
        if ctxStorageLocation:
            storageLocation = self._to_text(ctxStorageLocation)

        identifierCtx = ctx.identifier()

        node = VariableDeclaration(
            type_name=self.visitTypeName(ctx.typeName()),
            name=self._to_text(identifierCtx),
            identifier=self.visitIdentifier(identifierCtx),
            storage_location=storageLocation,
            is_state_var=False,
            is_indexed=False,
            expression=None,
        )

        return self._add_meta(node, ctx)

    def visitVariableDeclarationStatement(
        self, ctx: SP.VariableDeclarationStatementContext
    ) -> VariableDeclarationStatement:
        variables = []
        ctxVariableDeclaration = ctx.variableDeclaration()
        ctxIdentifierList = ctx.identifierList()
        ctxVariableDeclarationList = ctx.variableDeclarationList()

        if ctxVariableDeclaration is not None:
            variables = [self.visitVariableDeclaration(ctxVariableDeclaration)]
        elif ctxIdentifierList is not None:
            variables = self.buildIdentifierList(ctxIdentifierList)
        elif ctxVariableDeclarationList:
            variables = self.buildVariableDeclarationList(ctxVariableDeclarationList)

        initialValue = None
        ctxExpression = ctx.expression()
        if ctxExpression:
            initialValue = self.visitExpression(ctxExpression)

        node = VariableDeclarationStatement(
            variables=variables,
            initial_value=initialValue,
        )

        return self._add_meta(node, ctx)

    def visitStatement(self, ctx: SP.StatementContext) -> Statement:
        return self.visit(ctx.getChild(0))  # Assuming the child type is Statement

    def visitSimpleStatement(
        self, ctx: SP.SimpleStatementContext
    ) -> SimpleStatement:
        if ctx.children == None:
            return self.visitErrorNode(ctx.start)
        return self.visit(ctx.getChild(0))  # Assuming the child type is SimpleStatement

    def visitEventDefinition(
        self, ctx: SP.EventDefinitionContext
    ) -> EventDefinition:
        parameters = [
            self._add_meta(
                VariableDeclaration(
                    type_name=self.visitTypeName(paramCtx.typeName()),
                    name=self._to_text(paramCtx.identifier())
                    if paramCtx.identifier()
                    else None,
                    identifier=self.visitIdentifier(paramCtx.identifier())
                    if paramCtx.identifier()
                    else None,
                    is_state_var=False,
                    is_indexed=bool(paramCtx.IndexedKeyword() is not None),
                    storage_location=None,
                    expression=None,
                ),
                paramCtx,
            )
            for paramCtx in ctx.eventParameterList().eventParameter()
        ]

        node = EventDefinition(
            name=self._to_text(ctx.identifier()),
            parameters=parameters,
            is_anonymous=bool(ctx.AnonymousKeyword() is not None),
        )

        return self._add_meta(node, ctx)

    def visitBlock(self, ctx: SP.BlockContext) -> Block:
        statements = []
        for x in ctx.statement():
            s = self.visitStatement(x)
            if s:
                statements.append(s)
        node = Block(statements=statements)

        return self._add_meta(node, ctx)

    def visitParameter(self, ctx: SP.ParameterContext) -> VariableDeclaration:
        storageLocation = (
            self._to_text(ctx.storageLocation()) if ctx.storageLocation() else None
        )
        name = self._to_text(ctx.identifier()) if ctx.identifier() else None

        node = VariableDeclaration(
            type_name=self.visitTypeName(ctx.typeName()),
            name=name,
            identifier=self.visitIdentifier(ctx.identifier())
            if ctx.identifier()
            else None,
            storage_location=storageLocation,
            is_state_var=False,
            is_indexed=False,
            expression=None,
        )

        return self._add_meta(node, ctx)

    def visitFunctionDefinition(
        self, ctx: SP.FunctionDefinitionContext
    ) -> FunctionDefinition:
        isConstructor = False
        isFallback = False
        isReceiveEther = False
        isVirtual = False
        name = None
        parameters = []
        returnParameters = None
        visibility = "default"

        block = None
        ctxBlock = ctx.block()
        if ctxBlock is not None:
            block = self.visitBlock(ctxBlock)

        modifiers = [
            self.visitModifierInvocation(mod)
            for mod in ctx.modifierList().modifierInvocation()
        ]

        stateMutability = None
        if ctx.modifierList().stateMutability():
            stateMutability = self._stateMutabilityToText(
                ctx.modifierList().stateMutability(0)
            )

        # see what type of function we"re dealing with
        ctxReturnParameters = ctx.returnParameters()
        func_desc_child = self._to_text(ctx.functionDescriptor().getChild(0))
        if func_desc_child == "constructor":
            parameters = [self.visit(x) for x in ctx.parameterList().parameter()]
            # error out on incorrect function visibility
            if ctx.modifierList().InternalKeyword():
                visibility = "internal"
            elif ctx.modifierList().PublicKeyword():
                visibility = "public"
            else:
                visibility = "default"
            isConstructor = True
        elif func_desc_child == "fallback":
            parameters = [self.visit(x) for x in ctx.parameterList().parameter()]
            returnParameters = (
                self.visitReturnParameters(ctxReturnParameters)
                if ctxReturnParameters
                else None
            )
            visibility = "external"
            isFallback = True
        elif func_desc_child == "receive":
            visibility = "external"
            isReceiveEther = True
        elif func_desc_child == "function":
            identifier = ctx.functionDescriptor().identifier()
            name = self._to_text(identifier) if identifier is not None else ""
            parameters = [self.visit(x) for x in ctx.parameterList().parameter()]
            returnParameters = (
                self.visitReturnParameters(ctxReturnParameters)
                if ctxReturnParameters
                else None
            )
            # parse function visibility
            if ctx.modifierList().ExternalKeyword():
                visibility = "external"
            elif ctx.modifierList().InternalKeyword():
                visibility = "internal"
            elif ctx.modifierList().PublicKeyword():
                visibility = "public"
            elif ctx.modifierList().PrivateKeyword():
                visibility = "private"
            isConstructor = name == self._current_contract
            isFallback = name == ""

        # check if function is virtual
        if ctx.modifierList().VirtualKeyword():
            isVirtual = True

        override = None
        overrideSpecifier = ctx.modifierList().overrideSpecifier()
        if overrideSpecifier:
            override = [
                self.visitUserDefinedTypeName(x)
                for x in overrideSpecifier[0].userDefinedTypeName()
            ]

        node = FunctionDefinition(
            name=name,
            parameters=parameters,
            return_parameters=returnParameters,
            body=block,
            visibility=visibility,
            modifiers=modifiers,
            override=override,
            is_constructor=isConstructor,
            is_receive_ether=isReceiveEther,
            is_fallback=isFallback,
            is_virtual=isVirtual,
            state_mutability=stateMutability,
        )

        return self._add_meta(node, ctx)

    def visitEnumDefinition(self, ctx: SP.EnumDefinitionContext) -> EnumDefinition:
        node = EnumDefinition(
            name=self._to_text(ctx.identifier()),
            members=[self.visitEnumValue(x) for x in ctx.enumValue()],
        )

        return self._add_meta(node, ctx)

    def visitEnumValue(self, ctx: SP.EnumValueContext) -> EnumValue:
        node = EnumValue(name=self._to_text(ctx.identifier()))
        return self._add_meta(node, ctx)

    def visitElementaryTypeName(
        self, ctx: SP.ElementaryTypeNameContext
    ) -> ElementaryTypeName:
        node = ElementaryTypeName(name=self._to_text(ctx), state_mutability=None)

        return self._add_meta(node, ctx)

    def visitIdentifier(self, ctx: SP.IdentifierContext) -> Identifier:
        node = Identifier(name=self._to_text(ctx))
        return self._add_meta(node, ctx)

    def visitTypeName(
        self, ctx: SP.TypeNameContext
    ) -> Union[ArrayTypeName, ElementaryTypeName, UserDefinedTypeName]:
        if ctx.children and len(ctx.children) > 2:
            length = None
            if len(ctx.children) == 4:
                expression = ctx.expression()
                if expression is None:
                    raise Exception(
                        "Assertion error: a typeName with 4 children should have an expression"
                    )
                length = self.visitExpression(expression)

            ctxTypeName = ctx.typeName()

            node = ArrayTypeName(
                base_type_name=self.visitTypeName(ctxTypeName),
                length=length,
            )

            return self._add_meta(node, ctx)

        if ctx.children and len(ctx.children) == 2:
            node = ElementaryTypeName(
                name=self._to_text(ctx.getChild(0)),
                state_mutability=self._to_text(ctx.getChild(1)),
            )

            return self._add_meta(node, ctx)

        if ctx.elementaryTypeName() is not None:
            return self.visitElementaryTypeName(ctx.elementaryTypeName())
        if ctx.userDefinedTypeName() is not None:
            return self.visitUserDefinedTypeName(ctx.userDefinedTypeName())
        if ctx.mapping() is not None:
            return self.visitMapping(ctx.mapping())
        if ctx.functionTypeName() is not None:
            return self.visitFunctionTypeName(ctx.functionTypeName())

        raise Exception("Assertion error: unhandled type name case")

    def visitUserDefinedTypeName(
        self, ctx: SP.UserDefinedTypeNameContext
    ) -> UserDefinedTypeName:
        node = UserDefinedTypeName(
            name_path=self._to_text(ctx)
        )

        return self._add_meta(node, ctx)

    def visitUsingForDeclaration(
        self, ctx: SP.UsingForDeclarationContext
    ) -> UsingForDeclaration:
        typeName = None
        ctxTypeName = ctx.typeName()
        if ctxTypeName is not None:
            typeName = self.visitTypeName(ctxTypeName)

        isGlobal = ctx.GlobalKeyword() is not None

        usingForObjectCtx = ctx.usingForObject()

        userDefinedTypeNameCtx = usingForObjectCtx.userDefinedTypeName()

        if userDefinedTypeNameCtx is not None:
            # using Lib for ...
            node = UsingForDeclaration(
                is_global=isGlobal,
                type_name=typeName,
                library_name=self._to_text(userDefinedTypeNameCtx),
                functions=[],
                operators=[],
            )
        else:
            # using { } for ...
            usingForObjectDirectives = usingForObjectCtx.usingForObjectDirective()
            functions = [
                self._to_text(x.userDefinedTypeName()) for x in usingForObjectDirectives
            ]
            operators = [
                self._to_text(x.userDefinableOperators())
                if x.userDefinableOperators() is not None
                else None
                for x in usingForObjectDirectives
            ]

            node = UsingForDeclaration(
                is_global=isGlobal,
                type_name=typeName,
                library_name=None,
                functions=functions,
                operators=operators,
            )

        return self._add_meta(node, ctx)

    def visitPragmaDirective(
        self, ctx: SP.PragmaDirectiveContext
    ) -> PragmaDirective:
        # this converts something like >= 0.5.0  <0.7.0
        # in >=0.5.0 <0.7.0
        versionContext = ctx.pragmaValue().version()

        value = self._to_text(ctx.pragmaValue())
        if versionContext and versionContext.children is not None:
            value = " ".join([self._to_text(x) for x in versionContext.children])

        node = PragmaDirective(
            name=self._to_text(ctx.pragmaName()), value=value
        )

        return self._add_meta(node, ctx)

    def visitInheritanceSpecifier(
        self, ctx: SP.InheritanceSpecifierContext
    ) -> InheritanceSpecifier:
        exprList = ctx.expressionList()
        args = (
            [self.visitExpression(x) for x in exprList.expression()]
            if exprList is not None
            else []
        )

        node = InheritanceSpecifier(
            base_name=self.visitUserDefinedTypeName(ctx.userDefinedTypeName()),
            arguments=args,
        )

        return self._add_meta(node, ctx)

    def visitModifierInvocation(
        self, ctx: SP.ModifierInvocationContext
    ) -> ModifierInvocation:
        exprList = ctx.expressionList()

        args = (
            [self.visit(x) for x in exprList.expression()]
            if exprList is not None
            else []
        )

        if not args and ctx.children and len(ctx.children) > 1:
            args = None

        node = ModifierInvocation(
            name=self._to_text(ctx.identifier()),
            arguments=args,
        )
        return self._add_meta(node, ctx)

    def visitFunctionTypeName(
        self, ctx: SP.FunctionTypeNameContext
    ) -> FunctionTypeName:
        parameterTypes = [
            self.visitFunctionTypeParameter(typeCtx)
            for typeCtx in ctx.functionTypeParameterList(0).functionTypeParameter()
        ]

        returnTypes = []
        if len(ctx.functionTypeParameterList()) > 1:
            returnTypes = [
                self.visitFunctionTypeParameter(typeCtx)
                for typeCtx in ctx.functionTypeParameterList(1).functionTypeParameter()
            ]

        visibility = "default"
        if ctx.InternalKeyword():
            visibility = "internal"
        elif ctx.ExternalKeyword():
            visibility = "external"

        stateMutability = (
            self._to_text(ctx.stateMutability(0)) if ctx.stateMutability() else None
        )

        node = FunctionTypeName(
            parameter_types=parameterTypes,
            return_types=returnTypes,
            visibility=visibility,
            state_mutability=stateMutability,
        )

        return self._add_meta(node, ctx)

    def visitFunctionTypeParameter(
        self, ctx: SP.FunctionTypeParameterContext
    ) -> VariableDeclaration:
        storageLocation = (
            self._to_text(ctx.storageLocation()) if ctx.storageLocation() else None
        )

        node = VariableDeclaration(
            type_name=self.visitTypeName(ctx.typeName()),
            name=None,
            identifier=None,
            storage_location=storageLocation,
            is_state_var=False,
            is_indexed=False,
            expression=None,
        )

        return self._add_meta(node, ctx)

    def visitThrowStatement(self, ctx: SP.ThrowStatementContext) -> ThrowStatement:
        node = ThrowStatement(type="ThrowStatement")

        return self._add_meta(node, ctx)

    def visitReturnStatement(
        self, ctx: SP.ReturnStatementContext
    ) -> ReturnStatement:
        expression = (
            self.visitExpression(ctx.expression()) if ctx.expression() else None
        )

        node = ReturnStatement(expression=expression)

        return self._add_meta(node, ctx)

    def visitEmitStatement(self, ctx: SP.EmitStatementContext) -> EmitStatement:
        node = EmitStatement(
            event_call=self.visitFunctionCall(ctx.functionCall())
        )

        return self._add_meta(node, ctx)

    def visitCustomErrorDefinition(
        self, ctx: SP.CustomErrorDefinitionContext
    ) -> CustomErrorDefinition:
        node = CustomErrorDefinition(
            name=self._to_text(ctx.identifier()),
            parameters=self.visitParameterList(ctx.parameterList()),
        )

        return self._add_meta(node, ctx)

    def visitTypeDefinition(self, ctx: SP.TypeDefinitionContext) -> TypeDefinition:
        node = TypeDefinition(
            name=self._to_text(ctx.identifier()),
            definition=self.visitElementaryTypeName(ctx.elementaryTypeName()),
        )

        return self._add_meta(node, ctx)

    def visitRevertStatement(
        self, ctx: SP.RevertStatementContext
    ) -> RevertStatement:
        node = RevertStatement(
            revert_call=self.visitFunctionCall(ctx.functionCall()),
        )

        return self._add_meta(node, ctx)

    def visitFunctionCall(self, ctx: SP.FunctionCallContext) -> FunctionCall:
        args = []
        names = []
        identifiers = []

        ctxArgs = ctx.functionCallArguments()
        ctxArgsExpressionList = ctxArgs.expressionList()
        ctxArgsNameValueList = ctxArgs.nameValueList()
        if ctxArgsExpressionList:
            args = [
                self.visitExpression(exprCtx)
                for exprCtx in ctxArgsExpressionList.expression()
            ]
        elif ctxArgsNameValueList:
            for nameValue in ctxArgsNameValueList.nameValue():
                args.append(self.visitExpression(nameValue.expression()))
                names.append(self._to_text(nameValue.identifier()))
                identifiers.append(self.visitIdentifier(nameValue.identifier()))

        node = FunctionCall(
            expression=self.visitExpression(ctx.expression()),
            arguments=args,
            names=names,
            identifiers=identifiers,
        )

        return self._add_meta(node, ctx)

    def visitStructDefinition(
        self, ctx: SP.StructDefinitionContext
    ) -> StructDefinition:
        node = StructDefinition(
            name=self._to_text(ctx.identifier()),
            members=[
                self.visitVariableDeclaration(x) for x in ctx.variableDeclaration()
            ],
        )

        return self._add_meta(node, ctx)

    def visitWhileStatement(self, ctx: SP.WhileStatementContext) -> WhileStatement:
        node = WhileStatement(
            condition=self.visitExpression(ctx.expression()),
            body=self.visitStatement(ctx.statement()),
        )

        return self._add_meta(node, ctx)

    def visitDoWhileStatement(
        self, ctx: SP.DoWhileStatementContext
    ) -> DoWhileStatement:
        node = DoWhileStatement(
            condition=self.visitExpression(ctx.expression()),
            body=self.visitStatement(ctx.statement()),
        )

        return self._add_meta(node, ctx)

    def visitIfStatement(self, ctx: SP.IfStatementContext) -> IfStatement:
        trueBody = self.visitStatement(ctx.statement(0))

        falseBody = None
        if len(ctx.statement()) > 1:
            falseBody = self.visitStatement(ctx.statement(1))

        node = IfStatement(
            condition=self.visitExpression(ctx.expression()),
            true_body=trueBody,
            false_body=falseBody,
        )

        return self._add_meta(node, ctx)

    def visitTryStatement(self, ctx: SP.TryStatementContext) -> TryStatement:
        returnParameters = None
        ctxReturnParameters = ctx.returnParameters()
        if ctxReturnParameters is not None:
            returnParameters = self.visitReturnParameters(ctxReturnParameters)

        catchClauses = [self.visitCatchClause(exprCtx) for exprCtx in ctx.catchClause()]

        node = TryStatement(
            expression=self.visitExpression(ctx.expression()),
            return_parameters=returnParameters,
            body=self.visitBlock(ctx.block()),
            catch_clauses=catchClauses,
        )

        return self._add_meta(node, ctx)

    def visitCatchClause(self, ctx: SP.CatchClauseContext) -> CatchClause:
        parameters = None
        if ctx.parameterList():
            parameters = self.visitParameterList(ctx.parameterList())

        if ctx.identifier() and self._to_text(ctx.identifier()) not in [
            "Error",
            "Panic",
        ]:
            raise Exception("Expected 'Error' or 'Panic' identifier in catch clause")

        kind = self._to_text(ctx.identifier()) if ctx.identifier() else None

        node = CatchClause(
            is_reason_string_type=kind
            == "Error",  # deprecated, use the `kind` property instead,
            kind=kind,
            parameters=parameters,
            body=self.visitBlock(ctx.block()),
        )

        return self._add_meta(node, ctx)

    def visitExpressionStatement(
        self, ctx: SP.ExpressionStatementContext
    ) -> ExpressionStatement:
        if not ctx:
            return None
        node = ExpressionStatement(
            expression=self.visitExpression(ctx.expression()),
        )

        return self._add_meta(node, ctx)

    def visitNumberLiteral(self, ctx: SP.NumberLiteralContext) -> NumberLiteral:
        number = self._to_text(ctx.getChild(0))
        subdenomination = None

        if ctx.children and len(ctx.children) == 2:
            subdenomination = self._to_text(ctx.getChild(1))

        node = NumberLiteral(
            number=number, subdenomination=subdenomination
        )

        return self._add_meta(node, ctx)

    def visitMappingKey(
        self, ctx: SP.MappingKeyContext
    ) -> Union[ElementaryTypeName, UserDefinedTypeName]:
        if ctx.elementaryTypeName():
            return self.visitElementaryTypeName(ctx.elementaryTypeName())
        elif ctx.userDefinedTypeName():
            return self.visitUserDefinedTypeName(ctx.userDefinedTypeName())
        else:
            raise Exception(
                "Expected MappingKey to have either elementaryTypeName or userDefinedTypeName"
            )

    def visitMapping(self, ctx: SP.MappingContext) -> Mapping:
        mappingKeyNameCtx = ctx.mappingKeyName()
        mappingValueNameCtx = ctx.mappingValueName()

        node = Mapping(
            key_type=self.visitMappingKey(ctx.mappingKey()),
            key_name=self.visitIdentifier(mappingKeyNameCtx.identifier())
            if mappingKeyNameCtx
            else None,
            value_type=self.visitTypeName(ctx.typeName()),
            value_name=self.visitIdentifier(mappingValueNameCtx.identifier())
            if mappingValueNameCtx
            else None,
        )

        return self._add_meta(node, ctx)

    def visitModifierDefinition(
        self, ctx: SP.ModifierDefinitionContext
    ) -> ModifierDefinition:
        parameters = None
        if ctx.parameterList():
            parameters = self.visitParameterList(ctx.parameterList())

        isVirtual = len(ctx.VirtualKeyword()) > 0

        override = None
        overrideSpecifier = ctx.overrideSpecifier()
        if overrideSpecifier:
            override = [
                self.visitUserDefinedTypeName(x)
                for x in overrideSpecifier[0].userDefinedTypeName()
            ]

        body = None
        blockCtx = ctx.block()
        if blockCtx:
            body = self.visitBlock(blockCtx)

        node = ModifierDefinition(
            name=self._to_text(ctx.identifier()),
            parameters=parameters,
            body=body,
            is_virtual=isVirtual,
            override=override,
        )

        return self._add_meta(node, ctx)

    def visitUncheckedStatement(
        self, ctx: SP.UncheckedStatementContext
    ) -> UncheckedStatement:
        node = UncheckedStatement(
            block=self.visitBlock(ctx.block())
        )

        return self._add_meta(node, ctx)

    def visitExpression(self, ctx: SP.ExpressionContext) -> Expression:
        op = None

        if len(ctx.children) == 1:
            # primary expression
            primaryExpressionCtx = ctx.getTypedRuleContext(SP.PrimaryExpressionContext, 0)
            if primaryExpressionCtx is None:
                raise Exception(
                    "Assertion error: primary expression should exist when children length is 1"
                )
            return self.visitPrimaryExpression(primaryExpressionCtx)
        elif len(ctx.children) == 2:
            op = self._to_text(ctx.getChild(0))

            # new expression
            if op == "new":
                node = NewExpression(
                    type_name=self.visitTypeName(ctx.typeName())
                )
                return self._add_meta(node, ctx)

            # prefix operators
            if op in UNARY_OP_VALUES:
                node = UnaryOperation(
                    operator=op,
                    sub_expression=self.visitExpression(
                        ctx.getTypedRuleContext(SP.ExpressionContext, 0)
                    ),
                    is_prefix=True,
                )
                return self._add_meta(node, ctx)

            op = self._to_text(ctx.getChild(1))

            # postfix operators
            if op in ["++", "--"]:
                node = UnaryOperation(
                    operator=op,
                    sub_expression=self.visitExpression(
                        ctx.getTypedRuleContext(SP.ExpressionContext, 0)
                    ),
                    is_prefix=False,
                )
                return self._add_meta(node, ctx)
        elif len(ctx.children) == 3:
            # treat parenthesis as no-op
            if (
                self._to_text(ctx.getChild(0)) == "("
                and self._to_text(ctx.getChild(2)) == ")"
            ):
                node = TupleExpression(
                    components=[
                        self.visitExpression(
                            ctx.getTypedRuleContext(SP.ExpressionContext, 0)
                        )
                    ],
                    isArray=False,
                )
                return self._add_meta(node, ctx)

            op = self._to_text(ctx.getChild(1))

            # member access
            if op == ".":
                node = MemberAccess(
                    expression=self.visitExpression(ctx.expression(0)),
                    member_name=self._to_text(ctx.identifier()),
                )
                return self._add_meta(node, ctx)

            if op in BINARY_OP_VALUES:
                node = BinaryOperation(
                    operator=op,
                    left=self.visitExpression(ctx.expression(0)),
                    right=self.visitExpression(ctx.expression(1)),
                )
                return self._add_meta(node, ctx)
        elif len(ctx.children) == 4:
            # function call
            if (
                self._to_text(ctx.getChild(1)) == "("
                and self._to_text(ctx.getChild(3)) == ")"
            ):
                args = []
                names = []
                identifiers = []

                ctxArgs = ctx.functionCallArguments()
                if ctxArgs.expressionList():
                    args = [
                        self.visitExpression(exprCtx)
                        for exprCtx in ctxArgs.expressionList().expression()
                    ]
                elif ctxArgs.nameValueList():
                    for nameValue in ctxArgs.nameValueList().nameValue():
                        args.append(self.visitExpression(nameValue.expression()))
                        names.append(self._to_text(nameValue.identifier()))
                        identifiers.append(self.visitIdentifier(nameValue.identifier()))

                node = FunctionCall(
                    expression=self.visitExpression(ctx.expression(0)),
                    arguments=args,
                    names=names,
                    identifiers=identifiers,
                )

                return self._add_meta(node, ctx)

            # index access
            if (
                self._to_text(ctx.getChild(1)) == "["
                and self._to_text(ctx.getChild(3)) == "]"
            ):
                if ctx.getChild(2).getText() == ":":
                    node = IndexRangeAccess(
                        base=self.visitExpression(ctx.expression(0)),
                    )
                    return self._add_meta(node, ctx)

                node = IndexAccess(
                    base=self.visitExpression(ctx.expression(0)),
                    index=self.visitExpression(ctx.expression(1)),
                )

                return self._add_meta(node, ctx)

            # expression with nameValueList
            if (
                self._to_text(ctx.getChild(1)) == "{"
                and self._to_text(ctx.getChild(3)) == "}"
            ):
                node = NameValueExpression(
                    expression=self.visitExpression(ctx.expression(0)),
                    arguments=self.visitNameValueList(ctx.nameValueList()),
                )

                return self._add_meta(node, ctx)
        elif len(ctx.children) == 5:
            # ternary operator
            if (
                self._to_text(ctx.getChild(1)) == "?"
                and self._to_text(ctx.getChild(3)) == ":"
            ):
                node = Conditional(
                    condition=self.visitExpression(ctx.expression(0)),
                    true_expression=self.visitExpression(ctx.expression(1)),
                    false_expression=self.visitExpression(ctx.expression(2)),
                )

                return self._add_meta(node, ctx)

            # index range access
            if (
                self._to_text(ctx.getChild(1)) == "["
                and self._to_text(ctx.getChild(2)) == ":"
                and self._to_text(ctx.getChild(4)) == "]"
            ):
                node = IndexRangeAccess(
                    base=self.visitExpression(ctx.expression(0)),
                    index_end=self.visitExpression(ctx.expression(1)),
                )

                return self._add_meta(node, ctx)
            elif (
                self._to_text(ctx.getChild(1)) == "["
                and self._to_text(ctx.getChild(3)) == ":"
                and self._to_text(ctx.getChild(4)) == "]"
            ):
                node = IndexRangeAccess(
                    base=self.visitExpression(ctx.expression(0)),
                    index_start=self.visitExpression(ctx.expression(1)),
                )

                return self._add_meta(node, ctx)
        elif len(ctx.children) == 6:
            # index range access
            if (
                self._to_text(ctx.getChild(1)) == "["
                and self._to_text(ctx.getChild(3)) == ":"
                and self._to_text(ctx.getChild(5)) == "]"
            ):
                node = IndexRangeAccess(
                    base=self.visitExpression(ctx.expression(0)),
                    index_start=self.visitExpression(ctx.expression(1)),
                    index_end=self.visitExpression(ctx.expression(2)),
                )

                return self._add_meta(node, ctx)

        raise Exception("Unrecognized expression")

    def visitNameValueList(self, ctx: SP.NameValueListContext) -> NameValueList:
        names = []
        identifiers = []
        args = []

        for nameValue in ctx.nameValue():
            names.append(self._to_text(nameValue.identifier()))
            identifiers.append(self.visitIdentifier(nameValue.identifier()))
            args.append(self.visitExpression(nameValue.expression()))

        node = NameValueList(
            names=names, identifiers=identifiers, arguments=args
        )

        return self._add_meta(node, ctx)

    def visitFileLevelConstant(
        self, ctx: SP.FileLevelConstantContext
    ) -> FileLevelConstant:
        type = self.visitTypeName(ctx.typeName())
        iden = ctx.identifier()
        name = self._to_text(iden)

        expression = self.visitExpression(ctx.expression())

        node = FileLevelConstant(
            type_name=type,
            name=name,
            initial_value=expression,
            is_declared_const=True,
            is_immutable=False,
        )

        return self._add_meta(node, ctx)

    def visitForStatement(self, ctx: SP.ForStatementContext) -> ForStatement:
        conditionExpression = self.visitExpressionStatement(ctx.expressionStatement())
        if conditionExpression:
            conditionExpression = conditionExpression.expression
        node = ForStatement(
            init_expression=self.visitSimpleStatement(ctx.simpleStatement())
            if ctx.simpleStatement()
            else None,
            condition_expression=conditionExpression,
            loop_expression=ExpressionStatement(
                expression=self.visitExpression(ctx.expression())
                if ctx.expression()
                else None,
            ),
            body=self.visitStatement(ctx.statement()),
        )

        return self._add_meta(node, ctx)

    def visitHexLiteral(self, ctx: SP.HexLiteralContext) -> HexLiteral:
        parts = [self._to_text(x)[4:-1] for x in ctx.HexLiteralFragment()]
        node = HexLiteral(value="".join(parts), parts=parts)

        return self._add_meta(node, ctx)

    def visitPrimaryExpression(self, ctx: SP.PrimaryExpressionContext) -> Union[PrimaryExpression, Any]:
        if ctx.BooleanLiteral():
            node = BooleanLiteral(value=self._to_text(ctx.BooleanLiteral()) == "true")
            return self._add_meta(node, ctx)

        if ctx.hexLiteral():
            return self.visitHexLiteral(ctx.hexLiteral())

        if ctx.stringLiteral():
            fragments = ctx.stringLiteral().StringLiteralFragment()
            fragments_info = []

            for string_literal_fragment_ctx in fragments:
                text = self._to_text(string_literal_fragment_ctx)

                is_unicode = text[:7] == "unicode"
                if is_unicode:
                    text = text[7:]

                single_quotes = text[0] == """"""
                text_without_quotes = text[1:-1]
                if single_quotes:
                    value = text_without_quotes.replace(r"'", "")
                else:
                    value = text_without_quotes.replace(r'"', "")

                fragments_info.append({"value": value, "is_unicode": is_unicode})

            parts = [x["value"] for x in fragments_info]
            node = StringLiteral(value="".join(parts), parts=parts, is_unicode=[x["is_unicode"] for x in fragments_info])
            return self._add_meta(node, ctx)

        if ctx.numberLiteral():
            return self.visitNumberLiteral(ctx.numberLiteral())

        if ctx.TypeKeyword():
            node = Identifier(name="type")
            return self._add_meta(node, ctx)

        if ctx.typeName():
            return self.visitTypeName(ctx.typeName())

        if ctx.children == None:
            return self.visitErrorNode(ctx.start)

        return self.visit(ctx.getChild(0))

    def visitTupleExpression(
        self, ctx: SP.TupleExpressionContext
    ) -> TupleExpression:
        children = ctx.children[1:-1]  # remove parentheses
        components = [
            self.visit(expr) if expr is not None else None
            for expr in self._map_commas_to_nulls(children)
        ]

        node = TupleExpression(
            components=components,
            isArray=self._to_text(ctx.getChild(0)) == "[",
        )

        return self._add_meta(node, ctx)

    def buildIdentifierList(
        self, ctx: SP.IdentifierListContext
    ) -> List[Optional[VariableDeclaration]]:
        children = ctx.children[1:-1]  # remove parentheses
        identifiers = ctx.identifier()
        i = 0
        return [
            self.visitIdentifier(iden) if iden is not None else None
            for iden in self._map_commas_to_nulls(children)
        ]

    def buildVariableDeclarationList(
        self, ctx: SP.VariableDeclarationListContext
    ) -> List[Optional[VariableDeclaration]]:
        variableDeclarations = ctx.variableDeclaration()
        i = 0
        return [
            self.buildVariableDeclaration(decl) if decl is not None else None
            for decl in self._map_commas_to_nulls(ctx.children or [])
        ]

    def buildVariableDeclaration(
        self, ctx: SP.VariableDeclarationContext
    ) -> VariableDeclaration:
        storageLocation = (
            self._to_text(ctx.storageLocation()) if ctx.storageLocation() else None
        )
        identifierCtx = ctx.identifier()
        result = VariableDeclaration(
            name=self._to_text(identifierCtx),
            identifier=self.visitIdentifier(identifierCtx),
            type_name=self.visitTypeName(ctx.typeName()),
            storage_location=storageLocation,
            is_state_var=False,
            is_indexed=False,
            expression=None,
        )

        return self._add_meta(result, ctx)

    def visitImportDirective(
        self, ctx: SP.ImportDirectiveContext
    ) -> ImportDirective:
        pathString = self._to_text(ctx.importPath())
        unitAlias = None
        unitAliasIdentifier = None
        symbolAliases = None
        symbolAliasesIdentifiers = None

        if len(ctx.importDeclaration()) > 0:
            symbolAliases = [
                [self._to_text(decl.identifier(0)), self._to_text(decl.identifier(1))]
                if len(decl.identifier()) > 1
                else [self._to_text(decl.identifier(0)), None]
                for decl in ctx.importDeclaration()
            ]
            symbolAliasesIdentifiers = [
                [
                    self.visitIdentifier(decl.identifier(0)),
                    self.visitIdentifier(decl.identifier(1)),
                ]
                if len(decl.identifier()) > 1
                else [self.visitIdentifier(decl.identifier(0)), None]
                for decl in ctx.importDeclaration()
            ]
        else:
            identifierCtxList = ctx.identifier()
            if len(identifierCtxList) == 0:
                pass
            elif len(identifierCtxList) == 1:
                aliasIdentifierCtx = ctx.identifier(0)
                unitAlias = self._to_text(aliasIdentifierCtx)
                unitAliasIdentifier = self.visitIdentifier(aliasIdentifierCtx)
            elif len(identifierCtxList) == 2:
                aliasIdentifierCtx = ctx.identifier(1)
                unitAlias = self._to_text(aliasIdentifierCtx)
                unitAliasIdentifier = self.visitIdentifier(aliasIdentifierCtx)
            else:
                raise AssertionError("an import should have one or two identifiers")

        path = pathString[1:-1]

        pathLiteral = StringLiteral(
            value=path,
            parts=[path],
            is_unicode=[
                False
            ],  # paths in imports don"t seem to support unicode literals
        )

        node = ImportDirective(
            path=path,
            path_literal=self._add_meta(pathLiteral, ctx.importPath()),
            unit_alias=unitAlias,
            unit_alias_identifier=unitAliasIdentifier,
            symbol_aliases=symbolAliases,
            symbol_aliases_identifiers=symbolAliasesIdentifiers,
        )

        return self._add_meta(node, ctx)

    def buildEventParameterList(
        self, ctx: SP.EventParameterListContext
    ) -> List[VariableDeclaration]:
        return [
            VariableDeclaration(
                type="VariableDeclaration",
                type_name=self.visit(paramCtx.typeName()),
                name=self._to_text(paramCtx.identifier())
                if paramCtx.identifier()
                else None,
                is_state_var=False,
                is_indexed=bool(paramCtx.IndexedKeyword()),
            )
            for paramCtx in ctx.eventParameter()
        ]

    def visitReturnParameters(
        self, ctx: SP.ReturnParametersContext
    ) -> List[VariableDeclaration]:
        return self.visitParameterList(ctx.parameterList())

    def visitParameterList(
        self, ctx: SP.ParameterListContext
    ) -> List[VariableDeclaration]:
        return [self.visitParameter(paramCtx) for paramCtx in ctx.parameter()]

    def visitInlineAssemblyStatement(
        self, ctx: SP.InlineAssemblyStatementContext
    ) -> InlineAssemblyStatement:
        language = None
        if ctx.StringLiteralFragment():
            language = self._to_text(ctx.StringLiteralFragment())
            language = language[1:-1]

        flags = []
        flag = ctx.inlineAssemblyStatementFlag()
        if flag is not None:
            flagString = self._to_text(flag.stringLiteral())
            flags.append(flagString[1:-1])

        node = InlineAssemblyStatement(
            language=language,
            flags=flags,
            body=self.visitAssemblyBlock(ctx.assemblyBlock()),
        )

        return self._add_meta(node, ctx)

    def visitAssemblyBlock(self, ctx: SP.AssemblyBlockContext) -> AssemblyBlock:
        operations = [self.visitAssemblyItem(item) for item in ctx.assemblyItem()]

        node = AssemblyBlock(
            operations=operations,
        )

        return self._add_meta(node, ctx)

    def visitAssemblyItem(
        self, ctx: SP.AssemblyItemContext
    ) -> Union[
        HexLiteral, StringLiteral, Break, Continue, AssemblyItem
    ]:
        text = None

        if ctx.hexLiteral():
            return self.visitHexLiteral(ctx.hexLiteral())

        if ctx.stringLiteral():
            text = self._to_text(ctx.stringLiteral())
            value = text[1:-1]
            node = StringLiteral(
                value=value,
                parts=[value],
                is_unicode=[
                    False
                ],  # assembly doesn"t seem to support unicode literals right now
            )

            return self._add_meta(node, ctx)

        if ctx.BreakKeyword():
            node = Break()

            return self._add_meta(node, ctx)

        if ctx.ContinueKeyword():
            node = Continue()

            return self._add_meta(node, ctx)

        return self.visit(ctx.getChild(0))

    def visitAssemblyExpression(
        self, ctx: SP.AssemblyExpressionContext
    ) -> AssemblyExpression:
        return self.visit(ctx.getChild(0))

    def visitAssemblyCall(self, ctx: SP.AssemblyCallContext) -> AssemblyCall:
        functionName = self._to_text(ctx.getChild(0))
        args = [
            self.visitAssemblyExpression(assemblyExpr)
            for assemblyExpr in ctx.assemblyExpression()
        ]

        node = AssemblyCall(
            function_name=functionName,
            arguments=args,
        )

        return self._add_meta(node, ctx)

    def visitAssemblyLiteral(
        self, ctx: SP.AssemblyLiteralContext
    ) -> Union[
        StringLiteral,
        BooleanLiteral,
        DecimalNumber,
        HexNumber,
        HexLiteral,
    ]:
        text = None

        if ctx.stringLiteral():
            text = self._to_text(ctx)
            value = text[1:-1]
            node = StringLiteral(
                value=value,
                parts=[value],
                is_unicode=[
                    False
                ],  # assembly doesn"t seem to support unicode literals right now
            )

            return self._add_meta(node, ctx)

        if ctx.BooleanLiteral():
            node = BooleanLiteral(
                value=self._to_text(ctx.BooleanLiteral()) == "true",
            )

            return self._add_meta(node, ctx)

        if ctx.DecimalNumber():
            node = DecimalNumber(
                value=self._to_text(ctx),
            )

            return self._add_meta(node, ctx)

        if ctx.HexNumber():
            node = HexNumber(
                value=self._to_text(ctx),
            )

            return self._add_meta(node, ctx)

        if ctx.hexLiteral():
            return self.visitHexLiteral(ctx.hexLiteral())

        raise ValueError("Should never reach here")

    def visitAssemblySwitch(self, ctx: SP.AssemblySwitchContext) -> AssemblySwitch:
        node = AssemblySwitch(
            expression=self.visitAssemblyExpression(ctx.assemblyExpression()),
            cases=[self.visitAssemblyCase(c) for c in ctx.assemblyCase()],
        )

        return self._add_meta(node, ctx)

    def visitAssemblyCase(self, ctx: SP.AssemblyCaseContext) -> AssemblyCase:
        value = None
        if self._to_text(ctx.getChild(0)) == "case":
            value = self.visitAssemblyLiteral(ctx.assemblyLiteral())

        node = AssemblyCase(
            block=self.visitAssemblyBlock(ctx.assemblyBlock()),
            value=value,
            default=(value is None),
        )

        return self._add_meta(node, ctx)

    def visitAssemblyLocalDefinition(
        self, ctx: SP.AssemblyLocalDefinitionContext
    ) -> AssemblyLocalDefinition:
        ctxAssemblyIdentifierOrList = ctx.assemblyIdentifierOrList()
        if ctxAssemblyIdentifierOrList.identifier():
            names = [self.visitIdentifier(ctxAssemblyIdentifierOrList.identifier())]
        elif ctxAssemblyIdentifierOrList.assemblyMember():
            names = [
                self.visitAssemblyMember(ctxAssemblyIdentifierOrList.assemblyMember())
            ]
        else:
            names = [
                self.visitIdentifier(x)
                for x in ctxAssemblyIdentifierOrList.assemblyIdentifierList().identifier()
            ]

        expression = None
        if ctx.assemblyExpression() is not None:
            expression = self.visitAssemblyExpression(ctx.assemblyExpression())

        node = AssemblyLocalDefinition(
            names=names,
            expression=expression,
        )

        return self._add_meta(node, ctx)

    def visitAssemblyFunctionDefinition(
        self, ctx: SP.AssemblyFunctionDefinitionContext
    ):
        ctxAssemblyIdentifierList = ctx.assemblyIdentifierList()
        args = (
            [self.visitIdentifier(x) for x in ctxAssemblyIdentifierList.identifier()]
            if ctxAssemblyIdentifierList
            else []
        )

        ctxAssemblyFunctionReturns = ctx.assemblyFunctionReturns()
        returnArgs = (
            [
                self.visitIdentifier(x)
                for x in ctxAssemblyFunctionReturns.assemblyIdentifierList().identifier()
            ]
            if ctxAssemblyFunctionReturns
            else []
        )

        node = AssemblyFunctionDefinition(
            name=self._to_text(ctx.identifier()),
            arguments=args,
            return_arguments=returnArgs,
            body=self.visitAssemblyBlock(ctx.assemblyBlock()),
        )

        return self._add_meta(node, ctx)

    def visitAssemblyAssignment(self, ctx: SP.AssemblyAssignmentContext):
        ctxAssemblyIdentifierOrList = ctx.assemblyIdentifierOrList()
        if ctxAssemblyIdentifierOrList.identifier():
            names = [self.visitIdentifier(ctxAssemblyIdentifierOrList.identifier())]
        elif ctxAssemblyIdentifierOrList.assemblyMember():
            names = [
                self.visitAssemblyMember(ctxAssemblyIdentifierOrList.assemblyMember())
            ]
        else:
            names = [
                self.visitIdentifier(x)
                for x in ctxAssemblyIdentifierOrList.assemblyIdentifierList().identifier()
            ]

        node = AssemblyAssignment(
            names=names,
            expression=self.visitAssemblyExpression(ctx.assemblyExpression()),
        )

        return self._add_meta(node, ctx)

    def visitAssemblyMember(
        self, ctx: SP.AssemblyMemberContext
    ) -> AssemblyMemberAccess:
        accessed, member = ctx.identifier()
        node = AssemblyMemberAccess(
            expression=self.visitIdentifier(accessed),
            member_name=self.visitIdentifier(member),
        )

        return self._add_meta(node, ctx)

    def visitLabelDefinition(self, ctx: SP.LabelDefinitionContext):
        node = LabelDefinition(
            name=self._to_text(ctx.identifier()),
        )

        return self._add_meta(node, ctx)

    def visitAssemblyStackAssignment(self, ctx: SP.AssemblyStackAssignmentContext):
        node = AssemblyStackAssignment(
            name=self._to_text(ctx.identifier()),
            expression=self.visitAssemblyExpression(ctx.assemblyExpression()),
        )

        return self._add_meta(node, ctx)

    def visitAssemblyFor(self, ctx: SP.AssemblyForContext):
        node = AssemblyFor(
            pre=self.visit(ctx.getChild(1)),
            condition=self.visit(ctx.getChild(2)),
            post=self.visit(ctx.getChild(3)),
            body=self.visit(ctx.getChild(4)),
        )

        return self._add_meta(node, ctx)

    def visitAssemblyIf(self, ctx: SP.AssemblyIfContext):
        node = AssemblyIf(
            condition=self.visitAssemblyExpression(ctx.assemblyExpression()),
            body=self.visitAssemblyBlock(ctx.assemblyBlock()),
        )

        return self._add_meta(node, ctx)

    def visitContinueStatement(
        self, ctx: SP.ContinueStatementContext
    ) -> ContinueStatement:
        node = ContinueStatement()

        return self._add_meta(node, ctx)

    def visitBreakStatement(self, ctx: SP.BreakStatementContext) -> BreakStatement:
        node = BreakStatement()

        return self._add_meta(node, ctx)

    def _to_text(self, ctx: ParserRuleContext or ParseTree) -> str:
        text = ctx.getText()
        if text is None:
            raise ValueError("Assertion error: text should never be undefined")

        return text

    def _stateMutabilityToText(
        self, ctx: SP.StateMutabilityContext
    ) -> FunctionDefinition:
        if ctx.PureKeyword() is not None:
            return "pure"
        if ctx.ConstantKeyword() is not None:
            return "constant"
        if ctx.PayableKeyword() is not None:
            return "payable"
        if ctx.ViewKeyword() is not None:
            return "view"

        raise ValueError("Assertion error: non-exhaustive stateMutability check")

    def _loc(self, ctx) -> Location:
        start_line = ctx.start.line
        start_column = ctx.start.column
        end_line = ctx.stop.line if ctx.stop else start_line
        end_column = ctx.stop.column if ctx.stop else start_column

        source_location = Location(
            start=(start_line, start_column), end=(end_line, end_column)
        )

        return source_location

    def _range(self, ctx) -> Tuple[int, int]:
        return Range(ctx.start.start, ctx.stop.stop if ctx.stop else ctx.start.stop)

    def _add_meta(
        self, node: Union[BaseASTNode, NameValueList], ctx
    ) -> Union[BaseASTNode, NameValueList]:
        # node_with_meta = {"type": node.type}

        if self._options.loc:
            node.add_loc(self._loc(ctx))

        if self._options.range:
            node.add_range(self._range(ctx))

        return node

    def _map_commas_to_nulls(
        self, children: List[Optional[ParseTree]]
    ) -> List[Optional[ParseTree]]:
        if len(children) == 0:
            return []

        values = []
        comma = True

        for el in children:
            if comma:
                if self._to_text(el) == ",":
                    values.append(None)
                else:
                    values.append(el)
                    comma = False
            else:
                if self._to_text(el) != ",":
                    raise ValueError("expected comma")
                comma = True

        if comma:
            values.append(None)

        return values

class SolidityInfoVisitor(ParseTreeVisitor):

    def __init__(self, source_code):
        self.source_code = source_code
        self.results = []
        self.current_contract_name = None


    def visitContractDefinition(self, ctx: SP.ContractDefinitionContext):
        contract_name = ctx.identifier().getText()
        start_line = ctx.start.line
        end_line = ctx.stop.line
        offset_start = ctx.start.start
        offset_end = ctx.stop.stop
        
        source_content = self.extractSourceContent(offset_start, offset_end + 1)

        self.current_contract_name = contract_name


        self.results.append({
            "type": "ContractDefinition",
            "name": contract_name,
            "start_line": start_line,
            "end_line": end_line,
            "offset_start": offset_start,
            "offset_end": offset_end,
            "content": source_content
        })
        
        return self.visitChildren(ctx)
    def visitFunctionDefinition(self, ctx: SP.FunctionDefinitionContext):
        function_name = ctx.functionDescriptor().getText()
        start_line = ctx.start.line
        end_line = ctx.stop.line
        offset_start = ctx.start.start
        offset_end = ctx.stop.stop
        node_line = len(list(ctx.getChildren()))


        source_content = self.extractSourceContent(offset_start, offset_end + 1)

        if self.current_contract_name is None:
            current_contract_name = '' #todo

        isConstructor = isFallback =isReceive = False

        fd = ctx.functionDescriptor()
        if fd.ConstructorKeyword():
            name = fd.ConstructorKeyword().getText()
            isConstructor = True
        elif fd.FallbackKeyword():
            name = fd.FallbackKeyword().getText()
            isFallback = True
        elif fd.ReceiveKeyword():
            name = fd.ReceiveKeyword().getText()
            isReceive = True
        elif fd.identifier():
            name = fd.identifier().getText()
        else:
            name = ctx.getText()

        #modifiers: 这通常是函数名称前面的标识符，例如onlyOwner、payable等。
        #stateMutability: 这通常是pure、view、payable或constant中的一个。
        #visibility: 这是public、private、internal或external中的一个。
        #returnParameters: 这是函数返回类型的列表
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
        contract_code=self.source_code
        contract_code=extract_contract_with_name(self.current_contract_name,contract_code)

        self.results.append({
            "type": "FunctionDefinition",
            "name": function_name,
            "start_line": start_line,
            "end_line": end_line,
            "offset_start": offset_start,
            "offset_end": offset_end,
            "content": source_content,
            "contract_name": self.current_contract_name,
            "contract_code":contract_code,
            "modifiers": modifiers,
            "stateMutability": stateMutability,
            "returnParameters": returnParameters,
            "visibility":visibility,
            "node_count":node_line
        })

        return self.visitChildren(ctx)

    def extractSourceContent(self, start, end):
        return self.source_code[start:end]
