# Generated from Solidity.g4 by ANTLR 4.13.1
from antlr4 import *
if "." in __name__:
    from .SolidityParser import SolidityParser
else:
    from SolidityParser import SolidityParser

# This class defines a complete generic visitor for a parse tree produced by SolidityParser.

class SolidityVisitor(ParseTreeVisitor):

    # Visit a parse tree produced by SolidityParser#sourceUnit.
    def visitSourceUnit(self, ctx:SolidityParser.SourceUnitContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#pragmaDirective.
    def visitPragmaDirective(self, ctx:SolidityParser.PragmaDirectiveContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#pragmaName.
    def visitPragmaName(self, ctx:SolidityParser.PragmaNameContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#pragmaValue.
    def visitPragmaValue(self, ctx:SolidityParser.PragmaValueContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#version.
    def visitVersion(self, ctx:SolidityParser.VersionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#versionOperator.
    def visitVersionOperator(self, ctx:SolidityParser.VersionOperatorContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#versionConstraint.
    def visitVersionConstraint(self, ctx:SolidityParser.VersionConstraintContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#importDeclaration.
    def visitImportDeclaration(self, ctx:SolidityParser.ImportDeclarationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#importDirective.
    def visitImportDirective(self, ctx:SolidityParser.ImportDirectiveContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#importPath.
    def visitImportPath(self, ctx:SolidityParser.ImportPathContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#contractDefinition.
    def visitContractDefinition(self, ctx:SolidityParser.ContractDefinitionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#inheritanceSpecifier.
    def visitInheritanceSpecifier(self, ctx:SolidityParser.InheritanceSpecifierContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#contractPart.
    def visitContractPart(self, ctx:SolidityParser.ContractPartContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#stateVariableDeclaration.
    def visitStateVariableDeclaration(self, ctx:SolidityParser.StateVariableDeclarationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#fileLevelConstant.
    def visitFileLevelConstant(self, ctx:SolidityParser.FileLevelConstantContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#customErrorDefinition.
    def visitCustomErrorDefinition(self, ctx:SolidityParser.CustomErrorDefinitionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#typeDefinition.
    def visitTypeDefinition(self, ctx:SolidityParser.TypeDefinitionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#usingForDeclaration.
    def visitUsingForDeclaration(self, ctx:SolidityParser.UsingForDeclarationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#usingForObject.
    def visitUsingForObject(self, ctx:SolidityParser.UsingForObjectContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#usingForObjectDirective.
    def visitUsingForObjectDirective(self, ctx:SolidityParser.UsingForObjectDirectiveContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#userDefinableOperators.
    def visitUserDefinableOperators(self, ctx:SolidityParser.UserDefinableOperatorsContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#structDefinition.
    def visitStructDefinition(self, ctx:SolidityParser.StructDefinitionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#modifierDefinition.
    def visitModifierDefinition(self, ctx:SolidityParser.ModifierDefinitionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#modifierInvocation.
    def visitModifierInvocation(self, ctx:SolidityParser.ModifierInvocationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#functionDefinition.
    def visitFunctionDefinition(self, ctx:SolidityParser.FunctionDefinitionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#functionDescriptor.
    def visitFunctionDescriptor(self, ctx:SolidityParser.FunctionDescriptorContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#returnParameters.
    def visitReturnParameters(self, ctx:SolidityParser.ReturnParametersContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#modifierList.
    def visitModifierList(self, ctx:SolidityParser.ModifierListContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#eventDefinition.
    def visitEventDefinition(self, ctx:SolidityParser.EventDefinitionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#enumValue.
    def visitEnumValue(self, ctx:SolidityParser.EnumValueContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#enumDefinition.
    def visitEnumDefinition(self, ctx:SolidityParser.EnumDefinitionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#parameterList.
    def visitParameterList(self, ctx:SolidityParser.ParameterListContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#parameter.
    def visitParameter(self, ctx:SolidityParser.ParameterContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#eventParameterList.
    def visitEventParameterList(self, ctx:SolidityParser.EventParameterListContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#eventParameter.
    def visitEventParameter(self, ctx:SolidityParser.EventParameterContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#functionTypeParameterList.
    def visitFunctionTypeParameterList(self, ctx:SolidityParser.FunctionTypeParameterListContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#functionTypeParameter.
    def visitFunctionTypeParameter(self, ctx:SolidityParser.FunctionTypeParameterContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#variableDeclaration.
    def visitVariableDeclaration(self, ctx:SolidityParser.VariableDeclarationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#typeName.
    def visitTypeName(self, ctx:SolidityParser.TypeNameContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#userDefinedTypeName.
    def visitUserDefinedTypeName(self, ctx:SolidityParser.UserDefinedTypeNameContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#mappingKey.
    def visitMappingKey(self, ctx:SolidityParser.MappingKeyContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#mapping.
    def visitMapping(self, ctx:SolidityParser.MappingContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#mappingKeyName.
    def visitMappingKeyName(self, ctx:SolidityParser.MappingKeyNameContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#mappingValueName.
    def visitMappingValueName(self, ctx:SolidityParser.MappingValueNameContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#functionTypeName.
    def visitFunctionTypeName(self, ctx:SolidityParser.FunctionTypeNameContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#storageLocation.
    def visitStorageLocation(self, ctx:SolidityParser.StorageLocationContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#stateMutability.
    def visitStateMutability(self, ctx:SolidityParser.StateMutabilityContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#block.
    def visitBlock(self, ctx:SolidityParser.BlockContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#statement.
    def visitStatement(self, ctx:SolidityParser.StatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#expressionStatement.
    def visitExpressionStatement(self, ctx:SolidityParser.ExpressionStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#ifStatement.
    def visitIfStatement(self, ctx:SolidityParser.IfStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#tryStatement.
    def visitTryStatement(self, ctx:SolidityParser.TryStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#catchClause.
    def visitCatchClause(self, ctx:SolidityParser.CatchClauseContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#whileStatement.
    def visitWhileStatement(self, ctx:SolidityParser.WhileStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#simpleStatement.
    def visitSimpleStatement(self, ctx:SolidityParser.SimpleStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#uncheckedStatement.
    def visitUncheckedStatement(self, ctx:SolidityParser.UncheckedStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#forStatement.
    def visitForStatement(self, ctx:SolidityParser.ForStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#inlineAssemblyStatement.
    def visitInlineAssemblyStatement(self, ctx:SolidityParser.InlineAssemblyStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#inlineAssemblyStatementFlag.
    def visitInlineAssemblyStatementFlag(self, ctx:SolidityParser.InlineAssemblyStatementFlagContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#doWhileStatement.
    def visitDoWhileStatement(self, ctx:SolidityParser.DoWhileStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#continueStatement.
    def visitContinueStatement(self, ctx:SolidityParser.ContinueStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#breakStatement.
    def visitBreakStatement(self, ctx:SolidityParser.BreakStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#returnStatement.
    def visitReturnStatement(self, ctx:SolidityParser.ReturnStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#throwStatement.
    def visitThrowStatement(self, ctx:SolidityParser.ThrowStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#emitStatement.
    def visitEmitStatement(self, ctx:SolidityParser.EmitStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#revertStatement.
    def visitRevertStatement(self, ctx:SolidityParser.RevertStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#variableDeclarationStatement.
    def visitVariableDeclarationStatement(self, ctx:SolidityParser.VariableDeclarationStatementContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#variableDeclarationList.
    def visitVariableDeclarationList(self, ctx:SolidityParser.VariableDeclarationListContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#identifierList.
    def visitIdentifierList(self, ctx:SolidityParser.IdentifierListContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#elementaryTypeName.
    def visitElementaryTypeName(self, ctx:SolidityParser.ElementaryTypeNameContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#expression.
    def visitExpression(self, ctx:SolidityParser.ExpressionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#primaryExpression.
    def visitPrimaryExpression(self, ctx:SolidityParser.PrimaryExpressionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#expressionList.
    def visitExpressionList(self, ctx:SolidityParser.ExpressionListContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#nameValueList.
    def visitNameValueList(self, ctx:SolidityParser.NameValueListContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#nameValue.
    def visitNameValue(self, ctx:SolidityParser.NameValueContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#functionCallArguments.
    def visitFunctionCallArguments(self, ctx:SolidityParser.FunctionCallArgumentsContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#functionCall.
    def visitFunctionCall(self, ctx:SolidityParser.FunctionCallContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#assemblyBlock.
    def visitAssemblyBlock(self, ctx:SolidityParser.AssemblyBlockContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#assemblyItem.
    def visitAssemblyItem(self, ctx:SolidityParser.AssemblyItemContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#assemblyExpression.
    def visitAssemblyExpression(self, ctx:SolidityParser.AssemblyExpressionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#assemblyMember.
    def visitAssemblyMember(self, ctx:SolidityParser.AssemblyMemberContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#assemblyCall.
    def visitAssemblyCall(self, ctx:SolidityParser.AssemblyCallContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#assemblyLocalDefinition.
    def visitAssemblyLocalDefinition(self, ctx:SolidityParser.AssemblyLocalDefinitionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#assemblyAssignment.
    def visitAssemblyAssignment(self, ctx:SolidityParser.AssemblyAssignmentContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#assemblyIdentifierOrList.
    def visitAssemblyIdentifierOrList(self, ctx:SolidityParser.AssemblyIdentifierOrListContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#assemblyIdentifierList.
    def visitAssemblyIdentifierList(self, ctx:SolidityParser.AssemblyIdentifierListContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#assemblyStackAssignment.
    def visitAssemblyStackAssignment(self, ctx:SolidityParser.AssemblyStackAssignmentContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#labelDefinition.
    def visitLabelDefinition(self, ctx:SolidityParser.LabelDefinitionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#assemblySwitch.
    def visitAssemblySwitch(self, ctx:SolidityParser.AssemblySwitchContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#assemblyCase.
    def visitAssemblyCase(self, ctx:SolidityParser.AssemblyCaseContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#assemblyFunctionDefinition.
    def visitAssemblyFunctionDefinition(self, ctx:SolidityParser.AssemblyFunctionDefinitionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#assemblyFunctionReturns.
    def visitAssemblyFunctionReturns(self, ctx:SolidityParser.AssemblyFunctionReturnsContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#assemblyFor.
    def visitAssemblyFor(self, ctx:SolidityParser.AssemblyForContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#assemblyIf.
    def visitAssemblyIf(self, ctx:SolidityParser.AssemblyIfContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#assemblyLiteral.
    def visitAssemblyLiteral(self, ctx:SolidityParser.AssemblyLiteralContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#tupleExpression.
    def visitTupleExpression(self, ctx:SolidityParser.TupleExpressionContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#numberLiteral.
    def visitNumberLiteral(self, ctx:SolidityParser.NumberLiteralContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#identifier.
    def visitIdentifier(self, ctx:SolidityParser.IdentifierContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#hexLiteral.
    def visitHexLiteral(self, ctx:SolidityParser.HexLiteralContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#overrideSpecifier.
    def visitOverrideSpecifier(self, ctx:SolidityParser.OverrideSpecifierContext):
        return self.visitChildren(ctx)


    # Visit a parse tree produced by SolidityParser#stringLiteral.
    def visitStringLiteral(self, ctx:SolidityParser.StringLiteralContext):
        return self.visitChildren(ctx)



del SolidityParser