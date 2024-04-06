# Generated from Solidity.g4 by ANTLR 4.13.1
from antlr4 import *
if "." in __name__:
    from .SolidityParser import SolidityParser
else:
    from SolidityParser import SolidityParser

# This class defines a complete listener for a parse tree produced by SolidityParser.
class SolidityListener(ParseTreeListener):

    # Enter a parse tree produced by SolidityParser#sourceUnit.
    def enterSourceUnit(self, ctx:SolidityParser.SourceUnitContext):
        pass

    # Exit a parse tree produced by SolidityParser#sourceUnit.
    def exitSourceUnit(self, ctx:SolidityParser.SourceUnitContext):
        pass


    # Enter a parse tree produced by SolidityParser#pragmaDirective.
    def enterPragmaDirective(self, ctx:SolidityParser.PragmaDirectiveContext):
        pass

    # Exit a parse tree produced by SolidityParser#pragmaDirective.
    def exitPragmaDirective(self, ctx:SolidityParser.PragmaDirectiveContext):
        pass


    # Enter a parse tree produced by SolidityParser#pragmaName.
    def enterPragmaName(self, ctx:SolidityParser.PragmaNameContext):
        pass

    # Exit a parse tree produced by SolidityParser#pragmaName.
    def exitPragmaName(self, ctx:SolidityParser.PragmaNameContext):
        pass


    # Enter a parse tree produced by SolidityParser#pragmaValue.
    def enterPragmaValue(self, ctx:SolidityParser.PragmaValueContext):
        pass

    # Exit a parse tree produced by SolidityParser#pragmaValue.
    def exitPragmaValue(self, ctx:SolidityParser.PragmaValueContext):
        pass


    # Enter a parse tree produced by SolidityParser#version.
    def enterVersion(self, ctx:SolidityParser.VersionContext):
        pass

    # Exit a parse tree produced by SolidityParser#version.
    def exitVersion(self, ctx:SolidityParser.VersionContext):
        pass


    # Enter a parse tree produced by SolidityParser#versionOperator.
    def enterVersionOperator(self, ctx:SolidityParser.VersionOperatorContext):
        pass

    # Exit a parse tree produced by SolidityParser#versionOperator.
    def exitVersionOperator(self, ctx:SolidityParser.VersionOperatorContext):
        pass


    # Enter a parse tree produced by SolidityParser#versionConstraint.
    def enterVersionConstraint(self, ctx:SolidityParser.VersionConstraintContext):
        pass

    # Exit a parse tree produced by SolidityParser#versionConstraint.
    def exitVersionConstraint(self, ctx:SolidityParser.VersionConstraintContext):
        pass


    # Enter a parse tree produced by SolidityParser#importDeclaration.
    def enterImportDeclaration(self, ctx:SolidityParser.ImportDeclarationContext):
        pass

    # Exit a parse tree produced by SolidityParser#importDeclaration.
    def exitImportDeclaration(self, ctx:SolidityParser.ImportDeclarationContext):
        pass


    # Enter a parse tree produced by SolidityParser#importDirective.
    def enterImportDirective(self, ctx:SolidityParser.ImportDirectiveContext):
        pass

    # Exit a parse tree produced by SolidityParser#importDirective.
    def exitImportDirective(self, ctx:SolidityParser.ImportDirectiveContext):
        pass


    # Enter a parse tree produced by SolidityParser#importPath.
    def enterImportPath(self, ctx:SolidityParser.ImportPathContext):
        pass

    # Exit a parse tree produced by SolidityParser#importPath.
    def exitImportPath(self, ctx:SolidityParser.ImportPathContext):
        pass


    # Enter a parse tree produced by SolidityParser#contractDefinition.
    def enterContractDefinition(self, ctx:SolidityParser.ContractDefinitionContext):
        pass

    # Exit a parse tree produced by SolidityParser#contractDefinition.
    def exitContractDefinition(self, ctx:SolidityParser.ContractDefinitionContext):
        pass


    # Enter a parse tree produced by SolidityParser#inheritanceSpecifier.
    def enterInheritanceSpecifier(self, ctx:SolidityParser.InheritanceSpecifierContext):
        pass

    # Exit a parse tree produced by SolidityParser#inheritanceSpecifier.
    def exitInheritanceSpecifier(self, ctx:SolidityParser.InheritanceSpecifierContext):
        pass


    # Enter a parse tree produced by SolidityParser#contractPart.
    def enterContractPart(self, ctx:SolidityParser.ContractPartContext):
        pass

    # Exit a parse tree produced by SolidityParser#contractPart.
    def exitContractPart(self, ctx:SolidityParser.ContractPartContext):
        pass


    # Enter a parse tree produced by SolidityParser#stateVariableDeclaration.
    def enterStateVariableDeclaration(self, ctx:SolidityParser.StateVariableDeclarationContext):
        pass

    # Exit a parse tree produced by SolidityParser#stateVariableDeclaration.
    def exitStateVariableDeclaration(self, ctx:SolidityParser.StateVariableDeclarationContext):
        pass


    # Enter a parse tree produced by SolidityParser#fileLevelConstant.
    def enterFileLevelConstant(self, ctx:SolidityParser.FileLevelConstantContext):
        pass

    # Exit a parse tree produced by SolidityParser#fileLevelConstant.
    def exitFileLevelConstant(self, ctx:SolidityParser.FileLevelConstantContext):
        pass


    # Enter a parse tree produced by SolidityParser#customErrorDefinition.
    def enterCustomErrorDefinition(self, ctx:SolidityParser.CustomErrorDefinitionContext):
        pass

    # Exit a parse tree produced by SolidityParser#customErrorDefinition.
    def exitCustomErrorDefinition(self, ctx:SolidityParser.CustomErrorDefinitionContext):
        pass


    # Enter a parse tree produced by SolidityParser#typeDefinition.
    def enterTypeDefinition(self, ctx:SolidityParser.TypeDefinitionContext):
        pass

    # Exit a parse tree produced by SolidityParser#typeDefinition.
    def exitTypeDefinition(self, ctx:SolidityParser.TypeDefinitionContext):
        pass


    # Enter a parse tree produced by SolidityParser#usingForDeclaration.
    def enterUsingForDeclaration(self, ctx:SolidityParser.UsingForDeclarationContext):
        pass

    # Exit a parse tree produced by SolidityParser#usingForDeclaration.
    def exitUsingForDeclaration(self, ctx:SolidityParser.UsingForDeclarationContext):
        pass


    # Enter a parse tree produced by SolidityParser#usingForObject.
    def enterUsingForObject(self, ctx:SolidityParser.UsingForObjectContext):
        pass

    # Exit a parse tree produced by SolidityParser#usingForObject.
    def exitUsingForObject(self, ctx:SolidityParser.UsingForObjectContext):
        pass


    # Enter a parse tree produced by SolidityParser#usingForObjectDirective.
    def enterUsingForObjectDirective(self, ctx:SolidityParser.UsingForObjectDirectiveContext):
        pass

    # Exit a parse tree produced by SolidityParser#usingForObjectDirective.
    def exitUsingForObjectDirective(self, ctx:SolidityParser.UsingForObjectDirectiveContext):
        pass


    # Enter a parse tree produced by SolidityParser#userDefinableOperators.
    def enterUserDefinableOperators(self, ctx:SolidityParser.UserDefinableOperatorsContext):
        pass

    # Exit a parse tree produced by SolidityParser#userDefinableOperators.
    def exitUserDefinableOperators(self, ctx:SolidityParser.UserDefinableOperatorsContext):
        pass


    # Enter a parse tree produced by SolidityParser#structDefinition.
    def enterStructDefinition(self, ctx:SolidityParser.StructDefinitionContext):
        pass

    # Exit a parse tree produced by SolidityParser#structDefinition.
    def exitStructDefinition(self, ctx:SolidityParser.StructDefinitionContext):
        pass


    # Enter a parse tree produced by SolidityParser#modifierDefinition.
    def enterModifierDefinition(self, ctx:SolidityParser.ModifierDefinitionContext):
        pass

    # Exit a parse tree produced by SolidityParser#modifierDefinition.
    def exitModifierDefinition(self, ctx:SolidityParser.ModifierDefinitionContext):
        pass


    # Enter a parse tree produced by SolidityParser#modifierInvocation.
    def enterModifierInvocation(self, ctx:SolidityParser.ModifierInvocationContext):
        pass

    # Exit a parse tree produced by SolidityParser#modifierInvocation.
    def exitModifierInvocation(self, ctx:SolidityParser.ModifierInvocationContext):
        pass


    # Enter a parse tree produced by SolidityParser#functionDefinition.
    def enterFunctionDefinition(self, ctx:SolidityParser.FunctionDefinitionContext):
        pass

    # Exit a parse tree produced by SolidityParser#functionDefinition.
    def exitFunctionDefinition(self, ctx:SolidityParser.FunctionDefinitionContext):
        pass


    # Enter a parse tree produced by SolidityParser#functionDescriptor.
    def enterFunctionDescriptor(self, ctx:SolidityParser.FunctionDescriptorContext):
        pass

    # Exit a parse tree produced by SolidityParser#functionDescriptor.
    def exitFunctionDescriptor(self, ctx:SolidityParser.FunctionDescriptorContext):
        pass


    # Enter a parse tree produced by SolidityParser#returnParameters.
    def enterReturnParameters(self, ctx:SolidityParser.ReturnParametersContext):
        pass

    # Exit a parse tree produced by SolidityParser#returnParameters.
    def exitReturnParameters(self, ctx:SolidityParser.ReturnParametersContext):
        pass


    # Enter a parse tree produced by SolidityParser#modifierList.
    def enterModifierList(self, ctx:SolidityParser.ModifierListContext):
        pass

    # Exit a parse tree produced by SolidityParser#modifierList.
    def exitModifierList(self, ctx:SolidityParser.ModifierListContext):
        pass


    # Enter a parse tree produced by SolidityParser#eventDefinition.
    def enterEventDefinition(self, ctx:SolidityParser.EventDefinitionContext):
        pass

    # Exit a parse tree produced by SolidityParser#eventDefinition.
    def exitEventDefinition(self, ctx:SolidityParser.EventDefinitionContext):
        pass


    # Enter a parse tree produced by SolidityParser#enumValue.
    def enterEnumValue(self, ctx:SolidityParser.EnumValueContext):
        pass

    # Exit a parse tree produced by SolidityParser#enumValue.
    def exitEnumValue(self, ctx:SolidityParser.EnumValueContext):
        pass


    # Enter a parse tree produced by SolidityParser#enumDefinition.
    def enterEnumDefinition(self, ctx:SolidityParser.EnumDefinitionContext):
        pass

    # Exit a parse tree produced by SolidityParser#enumDefinition.
    def exitEnumDefinition(self, ctx:SolidityParser.EnumDefinitionContext):
        pass


    # Enter a parse tree produced by SolidityParser#parameterList.
    def enterParameterList(self, ctx:SolidityParser.ParameterListContext):
        pass

    # Exit a parse tree produced by SolidityParser#parameterList.
    def exitParameterList(self, ctx:SolidityParser.ParameterListContext):
        pass


    # Enter a parse tree produced by SolidityParser#parameter.
    def enterParameter(self, ctx:SolidityParser.ParameterContext):
        pass

    # Exit a parse tree produced by SolidityParser#parameter.
    def exitParameter(self, ctx:SolidityParser.ParameterContext):
        pass


    # Enter a parse tree produced by SolidityParser#eventParameterList.
    def enterEventParameterList(self, ctx:SolidityParser.EventParameterListContext):
        pass

    # Exit a parse tree produced by SolidityParser#eventParameterList.
    def exitEventParameterList(self, ctx:SolidityParser.EventParameterListContext):
        pass


    # Enter a parse tree produced by SolidityParser#eventParameter.
    def enterEventParameter(self, ctx:SolidityParser.EventParameterContext):
        pass

    # Exit a parse tree produced by SolidityParser#eventParameter.
    def exitEventParameter(self, ctx:SolidityParser.EventParameterContext):
        pass


    # Enter a parse tree produced by SolidityParser#functionTypeParameterList.
    def enterFunctionTypeParameterList(self, ctx:SolidityParser.FunctionTypeParameterListContext):
        pass

    # Exit a parse tree produced by SolidityParser#functionTypeParameterList.
    def exitFunctionTypeParameterList(self, ctx:SolidityParser.FunctionTypeParameterListContext):
        pass


    # Enter a parse tree produced by SolidityParser#functionTypeParameter.
    def enterFunctionTypeParameter(self, ctx:SolidityParser.FunctionTypeParameterContext):
        pass

    # Exit a parse tree produced by SolidityParser#functionTypeParameter.
    def exitFunctionTypeParameter(self, ctx:SolidityParser.FunctionTypeParameterContext):
        pass


    # Enter a parse tree produced by SolidityParser#variableDeclaration.
    def enterVariableDeclaration(self, ctx:SolidityParser.VariableDeclarationContext):
        pass

    # Exit a parse tree produced by SolidityParser#variableDeclaration.
    def exitVariableDeclaration(self, ctx:SolidityParser.VariableDeclarationContext):
        pass


    # Enter a parse tree produced by SolidityParser#typeName.
    def enterTypeName(self, ctx:SolidityParser.TypeNameContext):
        pass

    # Exit a parse tree produced by SolidityParser#typeName.
    def exitTypeName(self, ctx:SolidityParser.TypeNameContext):
        pass


    # Enter a parse tree produced by SolidityParser#userDefinedTypeName.
    def enterUserDefinedTypeName(self, ctx:SolidityParser.UserDefinedTypeNameContext):
        pass

    # Exit a parse tree produced by SolidityParser#userDefinedTypeName.
    def exitUserDefinedTypeName(self, ctx:SolidityParser.UserDefinedTypeNameContext):
        pass


    # Enter a parse tree produced by SolidityParser#mappingKey.
    def enterMappingKey(self, ctx:SolidityParser.MappingKeyContext):
        pass

    # Exit a parse tree produced by SolidityParser#mappingKey.
    def exitMappingKey(self, ctx:SolidityParser.MappingKeyContext):
        pass


    # Enter a parse tree produced by SolidityParser#mapping.
    def enterMapping(self, ctx:SolidityParser.MappingContext):
        pass

    # Exit a parse tree produced by SolidityParser#mapping.
    def exitMapping(self, ctx:SolidityParser.MappingContext):
        pass


    # Enter a parse tree produced by SolidityParser#mappingKeyName.
    def enterMappingKeyName(self, ctx:SolidityParser.MappingKeyNameContext):
        pass

    # Exit a parse tree produced by SolidityParser#mappingKeyName.
    def exitMappingKeyName(self, ctx:SolidityParser.MappingKeyNameContext):
        pass


    # Enter a parse tree produced by SolidityParser#mappingValueName.
    def enterMappingValueName(self, ctx:SolidityParser.MappingValueNameContext):
        pass

    # Exit a parse tree produced by SolidityParser#mappingValueName.
    def exitMappingValueName(self, ctx:SolidityParser.MappingValueNameContext):
        pass


    # Enter a parse tree produced by SolidityParser#functionTypeName.
    def enterFunctionTypeName(self, ctx:SolidityParser.FunctionTypeNameContext):
        pass

    # Exit a parse tree produced by SolidityParser#functionTypeName.
    def exitFunctionTypeName(self, ctx:SolidityParser.FunctionTypeNameContext):
        pass


    # Enter a parse tree produced by SolidityParser#storageLocation.
    def enterStorageLocation(self, ctx:SolidityParser.StorageLocationContext):
        pass

    # Exit a parse tree produced by SolidityParser#storageLocation.
    def exitStorageLocation(self, ctx:SolidityParser.StorageLocationContext):
        pass


    # Enter a parse tree produced by SolidityParser#stateMutability.
    def enterStateMutability(self, ctx:SolidityParser.StateMutabilityContext):
        pass

    # Exit a parse tree produced by SolidityParser#stateMutability.
    def exitStateMutability(self, ctx:SolidityParser.StateMutabilityContext):
        pass


    # Enter a parse tree produced by SolidityParser#block.
    def enterBlock(self, ctx:SolidityParser.BlockContext):
        pass

    # Exit a parse tree produced by SolidityParser#block.
    def exitBlock(self, ctx:SolidityParser.BlockContext):
        pass


    # Enter a parse tree produced by SolidityParser#statement.
    def enterStatement(self, ctx:SolidityParser.StatementContext):
        pass

    # Exit a parse tree produced by SolidityParser#statement.
    def exitStatement(self, ctx:SolidityParser.StatementContext):
        pass


    # Enter a parse tree produced by SolidityParser#expressionStatement.
    def enterExpressionStatement(self, ctx:SolidityParser.ExpressionStatementContext):
        pass

    # Exit a parse tree produced by SolidityParser#expressionStatement.
    def exitExpressionStatement(self, ctx:SolidityParser.ExpressionStatementContext):
        pass


    # Enter a parse tree produced by SolidityParser#ifStatement.
    def enterIfStatement(self, ctx:SolidityParser.IfStatementContext):
        pass

    # Exit a parse tree produced by SolidityParser#ifStatement.
    def exitIfStatement(self, ctx:SolidityParser.IfStatementContext):
        pass


    # Enter a parse tree produced by SolidityParser#tryStatement.
    def enterTryStatement(self, ctx:SolidityParser.TryStatementContext):
        pass

    # Exit a parse tree produced by SolidityParser#tryStatement.
    def exitTryStatement(self, ctx:SolidityParser.TryStatementContext):
        pass


    # Enter a parse tree produced by SolidityParser#catchClause.
    def enterCatchClause(self, ctx:SolidityParser.CatchClauseContext):
        pass

    # Exit a parse tree produced by SolidityParser#catchClause.
    def exitCatchClause(self, ctx:SolidityParser.CatchClauseContext):
        pass


    # Enter a parse tree produced by SolidityParser#whileStatement.
    def enterWhileStatement(self, ctx:SolidityParser.WhileStatementContext):
        pass

    # Exit a parse tree produced by SolidityParser#whileStatement.
    def exitWhileStatement(self, ctx:SolidityParser.WhileStatementContext):
        pass


    # Enter a parse tree produced by SolidityParser#simpleStatement.
    def enterSimpleStatement(self, ctx:SolidityParser.SimpleStatementContext):
        pass

    # Exit a parse tree produced by SolidityParser#simpleStatement.
    def exitSimpleStatement(self, ctx:SolidityParser.SimpleStatementContext):
        pass


    # Enter a parse tree produced by SolidityParser#uncheckedStatement.
    def enterUncheckedStatement(self, ctx:SolidityParser.UncheckedStatementContext):
        pass

    # Exit a parse tree produced by SolidityParser#uncheckedStatement.
    def exitUncheckedStatement(self, ctx:SolidityParser.UncheckedStatementContext):
        pass


    # Enter a parse tree produced by SolidityParser#forStatement.
    def enterForStatement(self, ctx:SolidityParser.ForStatementContext):
        pass

    # Exit a parse tree produced by SolidityParser#forStatement.
    def exitForStatement(self, ctx:SolidityParser.ForStatementContext):
        pass


    # Enter a parse tree produced by SolidityParser#inlineAssemblyStatement.
    def enterInlineAssemblyStatement(self, ctx:SolidityParser.InlineAssemblyStatementContext):
        pass

    # Exit a parse tree produced by SolidityParser#inlineAssemblyStatement.
    def exitInlineAssemblyStatement(self, ctx:SolidityParser.InlineAssemblyStatementContext):
        pass


    # Enter a parse tree produced by SolidityParser#inlineAssemblyStatementFlag.
    def enterInlineAssemblyStatementFlag(self, ctx:SolidityParser.InlineAssemblyStatementFlagContext):
        pass

    # Exit a parse tree produced by SolidityParser#inlineAssemblyStatementFlag.
    def exitInlineAssemblyStatementFlag(self, ctx:SolidityParser.InlineAssemblyStatementFlagContext):
        pass


    # Enter a parse tree produced by SolidityParser#doWhileStatement.
    def enterDoWhileStatement(self, ctx:SolidityParser.DoWhileStatementContext):
        pass

    # Exit a parse tree produced by SolidityParser#doWhileStatement.
    def exitDoWhileStatement(self, ctx:SolidityParser.DoWhileStatementContext):
        pass


    # Enter a parse tree produced by SolidityParser#continueStatement.
    def enterContinueStatement(self, ctx:SolidityParser.ContinueStatementContext):
        pass

    # Exit a parse tree produced by SolidityParser#continueStatement.
    def exitContinueStatement(self, ctx:SolidityParser.ContinueStatementContext):
        pass


    # Enter a parse tree produced by SolidityParser#breakStatement.
    def enterBreakStatement(self, ctx:SolidityParser.BreakStatementContext):
        pass

    # Exit a parse tree produced by SolidityParser#breakStatement.
    def exitBreakStatement(self, ctx:SolidityParser.BreakStatementContext):
        pass


    # Enter a parse tree produced by SolidityParser#returnStatement.
    def enterReturnStatement(self, ctx:SolidityParser.ReturnStatementContext):
        pass

    # Exit a parse tree produced by SolidityParser#returnStatement.
    def exitReturnStatement(self, ctx:SolidityParser.ReturnStatementContext):
        pass


    # Enter a parse tree produced by SolidityParser#throwStatement.
    def enterThrowStatement(self, ctx:SolidityParser.ThrowStatementContext):
        pass

    # Exit a parse tree produced by SolidityParser#throwStatement.
    def exitThrowStatement(self, ctx:SolidityParser.ThrowStatementContext):
        pass


    # Enter a parse tree produced by SolidityParser#emitStatement.
    def enterEmitStatement(self, ctx:SolidityParser.EmitStatementContext):
        pass

    # Exit a parse tree produced by SolidityParser#emitStatement.
    def exitEmitStatement(self, ctx:SolidityParser.EmitStatementContext):
        pass


    # Enter a parse tree produced by SolidityParser#revertStatement.
    def enterRevertStatement(self, ctx:SolidityParser.RevertStatementContext):
        pass

    # Exit a parse tree produced by SolidityParser#revertStatement.
    def exitRevertStatement(self, ctx:SolidityParser.RevertStatementContext):
        pass


    # Enter a parse tree produced by SolidityParser#variableDeclarationStatement.
    def enterVariableDeclarationStatement(self, ctx:SolidityParser.VariableDeclarationStatementContext):
        pass

    # Exit a parse tree produced by SolidityParser#variableDeclarationStatement.
    def exitVariableDeclarationStatement(self, ctx:SolidityParser.VariableDeclarationStatementContext):
        pass


    # Enter a parse tree produced by SolidityParser#variableDeclarationList.
    def enterVariableDeclarationList(self, ctx:SolidityParser.VariableDeclarationListContext):
        pass

    # Exit a parse tree produced by SolidityParser#variableDeclarationList.
    def exitVariableDeclarationList(self, ctx:SolidityParser.VariableDeclarationListContext):
        pass


    # Enter a parse tree produced by SolidityParser#identifierList.
    def enterIdentifierList(self, ctx:SolidityParser.IdentifierListContext):
        pass

    # Exit a parse tree produced by SolidityParser#identifierList.
    def exitIdentifierList(self, ctx:SolidityParser.IdentifierListContext):
        pass


    # Enter a parse tree produced by SolidityParser#elementaryTypeName.
    def enterElementaryTypeName(self, ctx:SolidityParser.ElementaryTypeNameContext):
        pass

    # Exit a parse tree produced by SolidityParser#elementaryTypeName.
    def exitElementaryTypeName(self, ctx:SolidityParser.ElementaryTypeNameContext):
        pass


    # Enter a parse tree produced by SolidityParser#expression.
    def enterExpression(self, ctx:SolidityParser.ExpressionContext):
        pass

    # Exit a parse tree produced by SolidityParser#expression.
    def exitExpression(self, ctx:SolidityParser.ExpressionContext):
        pass


    # Enter a parse tree produced by SolidityParser#primaryExpression.
    def enterPrimaryExpression(self, ctx:SolidityParser.PrimaryExpressionContext):
        pass

    # Exit a parse tree produced by SolidityParser#primaryExpression.
    def exitPrimaryExpression(self, ctx:SolidityParser.PrimaryExpressionContext):
        pass


    # Enter a parse tree produced by SolidityParser#expressionList.
    def enterExpressionList(self, ctx:SolidityParser.ExpressionListContext):
        pass

    # Exit a parse tree produced by SolidityParser#expressionList.
    def exitExpressionList(self, ctx:SolidityParser.ExpressionListContext):
        pass


    # Enter a parse tree produced by SolidityParser#nameValueList.
    def enterNameValueList(self, ctx:SolidityParser.NameValueListContext):
        pass

    # Exit a parse tree produced by SolidityParser#nameValueList.
    def exitNameValueList(self, ctx:SolidityParser.NameValueListContext):
        pass


    # Enter a parse tree produced by SolidityParser#nameValue.
    def enterNameValue(self, ctx:SolidityParser.NameValueContext):
        pass

    # Exit a parse tree produced by SolidityParser#nameValue.
    def exitNameValue(self, ctx:SolidityParser.NameValueContext):
        pass


    # Enter a parse tree produced by SolidityParser#functionCallArguments.
    def enterFunctionCallArguments(self, ctx:SolidityParser.FunctionCallArgumentsContext):
        pass

    # Exit a parse tree produced by SolidityParser#functionCallArguments.
    def exitFunctionCallArguments(self, ctx:SolidityParser.FunctionCallArgumentsContext):
        pass


    # Enter a parse tree produced by SolidityParser#functionCall.
    def enterFunctionCall(self, ctx:SolidityParser.FunctionCallContext):
        pass

    # Exit a parse tree produced by SolidityParser#functionCall.
    def exitFunctionCall(self, ctx:SolidityParser.FunctionCallContext):
        pass


    # Enter a parse tree produced by SolidityParser#assemblyBlock.
    def enterAssemblyBlock(self, ctx:SolidityParser.AssemblyBlockContext):
        pass

    # Exit a parse tree produced by SolidityParser#assemblyBlock.
    def exitAssemblyBlock(self, ctx:SolidityParser.AssemblyBlockContext):
        pass


    # Enter a parse tree produced by SolidityParser#assemblyItem.
    def enterAssemblyItem(self, ctx:SolidityParser.AssemblyItemContext):
        pass

    # Exit a parse tree produced by SolidityParser#assemblyItem.
    def exitAssemblyItem(self, ctx:SolidityParser.AssemblyItemContext):
        pass


    # Enter a parse tree produced by SolidityParser#assemblyExpression.
    def enterAssemblyExpression(self, ctx:SolidityParser.AssemblyExpressionContext):
        pass

    # Exit a parse tree produced by SolidityParser#assemblyExpression.
    def exitAssemblyExpression(self, ctx:SolidityParser.AssemblyExpressionContext):
        pass


    # Enter a parse tree produced by SolidityParser#assemblyMember.
    def enterAssemblyMember(self, ctx:SolidityParser.AssemblyMemberContext):
        pass

    # Exit a parse tree produced by SolidityParser#assemblyMember.
    def exitAssemblyMember(self, ctx:SolidityParser.AssemblyMemberContext):
        pass


    # Enter a parse tree produced by SolidityParser#assemblyCall.
    def enterAssemblyCall(self, ctx:SolidityParser.AssemblyCallContext):
        pass

    # Exit a parse tree produced by SolidityParser#assemblyCall.
    def exitAssemblyCall(self, ctx:SolidityParser.AssemblyCallContext):
        pass


    # Enter a parse tree produced by SolidityParser#assemblyLocalDefinition.
    def enterAssemblyLocalDefinition(self, ctx:SolidityParser.AssemblyLocalDefinitionContext):
        pass

    # Exit a parse tree produced by SolidityParser#assemblyLocalDefinition.
    def exitAssemblyLocalDefinition(self, ctx:SolidityParser.AssemblyLocalDefinitionContext):
        pass


    # Enter a parse tree produced by SolidityParser#assemblyAssignment.
    def enterAssemblyAssignment(self, ctx:SolidityParser.AssemblyAssignmentContext):
        pass

    # Exit a parse tree produced by SolidityParser#assemblyAssignment.
    def exitAssemblyAssignment(self, ctx:SolidityParser.AssemblyAssignmentContext):
        pass


    # Enter a parse tree produced by SolidityParser#assemblyIdentifierOrList.
    def enterAssemblyIdentifierOrList(self, ctx:SolidityParser.AssemblyIdentifierOrListContext):
        pass

    # Exit a parse tree produced by SolidityParser#assemblyIdentifierOrList.
    def exitAssemblyIdentifierOrList(self, ctx:SolidityParser.AssemblyIdentifierOrListContext):
        pass


    # Enter a parse tree produced by SolidityParser#assemblyIdentifierList.
    def enterAssemblyIdentifierList(self, ctx:SolidityParser.AssemblyIdentifierListContext):
        pass

    # Exit a parse tree produced by SolidityParser#assemblyIdentifierList.
    def exitAssemblyIdentifierList(self, ctx:SolidityParser.AssemblyIdentifierListContext):
        pass


    # Enter a parse tree produced by SolidityParser#assemblyStackAssignment.
    def enterAssemblyStackAssignment(self, ctx:SolidityParser.AssemblyStackAssignmentContext):
        pass

    # Exit a parse tree produced by SolidityParser#assemblyStackAssignment.
    def exitAssemblyStackAssignment(self, ctx:SolidityParser.AssemblyStackAssignmentContext):
        pass


    # Enter a parse tree produced by SolidityParser#labelDefinition.
    def enterLabelDefinition(self, ctx:SolidityParser.LabelDefinitionContext):
        pass

    # Exit a parse tree produced by SolidityParser#labelDefinition.
    def exitLabelDefinition(self, ctx:SolidityParser.LabelDefinitionContext):
        pass


    # Enter a parse tree produced by SolidityParser#assemblySwitch.
    def enterAssemblySwitch(self, ctx:SolidityParser.AssemblySwitchContext):
        pass

    # Exit a parse tree produced by SolidityParser#assemblySwitch.
    def exitAssemblySwitch(self, ctx:SolidityParser.AssemblySwitchContext):
        pass


    # Enter a parse tree produced by SolidityParser#assemblyCase.
    def enterAssemblyCase(self, ctx:SolidityParser.AssemblyCaseContext):
        pass

    # Exit a parse tree produced by SolidityParser#assemblyCase.
    def exitAssemblyCase(self, ctx:SolidityParser.AssemblyCaseContext):
        pass


    # Enter a parse tree produced by SolidityParser#assemblyFunctionDefinition.
    def enterAssemblyFunctionDefinition(self, ctx:SolidityParser.AssemblyFunctionDefinitionContext):
        pass

    # Exit a parse tree produced by SolidityParser#assemblyFunctionDefinition.
    def exitAssemblyFunctionDefinition(self, ctx:SolidityParser.AssemblyFunctionDefinitionContext):
        pass


    # Enter a parse tree produced by SolidityParser#assemblyFunctionReturns.
    def enterAssemblyFunctionReturns(self, ctx:SolidityParser.AssemblyFunctionReturnsContext):
        pass

    # Exit a parse tree produced by SolidityParser#assemblyFunctionReturns.
    def exitAssemblyFunctionReturns(self, ctx:SolidityParser.AssemblyFunctionReturnsContext):
        pass


    # Enter a parse tree produced by SolidityParser#assemblyFor.
    def enterAssemblyFor(self, ctx:SolidityParser.AssemblyForContext):
        pass

    # Exit a parse tree produced by SolidityParser#assemblyFor.
    def exitAssemblyFor(self, ctx:SolidityParser.AssemblyForContext):
        pass


    # Enter a parse tree produced by SolidityParser#assemblyIf.
    def enterAssemblyIf(self, ctx:SolidityParser.AssemblyIfContext):
        pass

    # Exit a parse tree produced by SolidityParser#assemblyIf.
    def exitAssemblyIf(self, ctx:SolidityParser.AssemblyIfContext):
        pass


    # Enter a parse tree produced by SolidityParser#assemblyLiteral.
    def enterAssemblyLiteral(self, ctx:SolidityParser.AssemblyLiteralContext):
        pass

    # Exit a parse tree produced by SolidityParser#assemblyLiteral.
    def exitAssemblyLiteral(self, ctx:SolidityParser.AssemblyLiteralContext):
        pass


    # Enter a parse tree produced by SolidityParser#tupleExpression.
    def enterTupleExpression(self, ctx:SolidityParser.TupleExpressionContext):
        pass

    # Exit a parse tree produced by SolidityParser#tupleExpression.
    def exitTupleExpression(self, ctx:SolidityParser.TupleExpressionContext):
        pass


    # Enter a parse tree produced by SolidityParser#numberLiteral.
    def enterNumberLiteral(self, ctx:SolidityParser.NumberLiteralContext):
        pass

    # Exit a parse tree produced by SolidityParser#numberLiteral.
    def exitNumberLiteral(self, ctx:SolidityParser.NumberLiteralContext):
        pass


    # Enter a parse tree produced by SolidityParser#identifier.
    def enterIdentifier(self, ctx:SolidityParser.IdentifierContext):
        pass

    # Exit a parse tree produced by SolidityParser#identifier.
    def exitIdentifier(self, ctx:SolidityParser.IdentifierContext):
        pass


    # Enter a parse tree produced by SolidityParser#hexLiteral.
    def enterHexLiteral(self, ctx:SolidityParser.HexLiteralContext):
        pass

    # Exit a parse tree produced by SolidityParser#hexLiteral.
    def exitHexLiteral(self, ctx:SolidityParser.HexLiteralContext):
        pass


    # Enter a parse tree produced by SolidityParser#overrideSpecifier.
    def enterOverrideSpecifier(self, ctx:SolidityParser.OverrideSpecifierContext):
        pass

    # Exit a parse tree produced by SolidityParser#overrideSpecifier.
    def exitOverrideSpecifier(self, ctx:SolidityParser.OverrideSpecifierContext):
        pass


    # Enter a parse tree produced by SolidityParser#stringLiteral.
    def enterStringLiteral(self, ctx:SolidityParser.StringLiteralContext):
        pass

    # Exit a parse tree produced by SolidityParser#stringLiteral.
    def exitStringLiteral(self, ctx:SolidityParser.StringLiteralContext):
        pass



del SolidityParser