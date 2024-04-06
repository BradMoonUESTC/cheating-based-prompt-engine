from typing import Any, List, Optional, Tuple, Union, Dict


class Position:
    """
    Contains the cursor position (line and column) in the source code.
    """
    def __init__(self, line: int, col: int) -> None:
        self.line: int = line
        self.column: int = col

class Location:
    """
    Contains the location (start line/column & end line/column) of a node in the source code.

    Attributes:
    ----------
    start: Position - The line and column of the start of the node
    end: Position - The line and column of the end of the node
    """

    def __init__(self, start: Tuple[int, int], end: Tuple[int, int]) -> None:
        self.start: Position = Position(start[0], start[1])
        self.end: Position = Position(end[0], end[1])


class Range:
    """
    Contains the range (offset start & offset end) of a node in the source code.

    Attributes:
    ----------
    offset_start: int - The offset of the start of the node
    offset_end: int - The offset of the end of the node
    """

    def __init__(self, offset_start: int, offset_end: int) -> None:
        self.offset_start: int = offset_start
        self.offset_end: int = offset_end


class BaseASTNode:
    """
    Base class for all AST nodes. Contains base information that all nodes have.

    Attributes:
    ----------
    type: str - The string representation of a type of the node
    loc: Location - The location (start line/column & end line/column) of the node in the source code
    range: Range - The range (offset start & offset end) of the node in the source code
    children: List[BaseASTNode] - The list of children nodes of the node
    """

    def __init__(
        self, type: str = None, range: Range = None, loc: Optional[Location] = None
    ) -> None:
        self.type: str = type if type else self.type
        self.loc: Location = loc
        self.range: Range = range

    def __new__(cls, *args, **kwargs) -> "BaseASTNode":
        o = object.__new__(cls)
        setattr(o, "type", cls.__name__)
        return o

    def add_loc(self, loc: Location) -> None:
        self.loc = loc

    def add_range(self, range: Range) -> None:
        self.range = range


class SourceUnit(BaseASTNode):
    """
    A root node of the AST. Contains all the nodes in the source code. Basically is a parsed compilation unit (a compound file).
    """

    def __init__(self, children: List[BaseASTNode]) -> None:
        self.children = children
        self.errors = []


class ContractDefinition(BaseASTNode):
    """
    A node representing a contract definition.
    """

    def __init__(
        self,
        name: str,
        base_contracts: List["InheritanceSpecifier"],
        kind: str,
        children: List[BaseASTNode],
    ) -> None:
        self.name: str = name
        self.base_contracts: List["InheritanceSpecifier"] = base_contracts
        self.kind: str = kind
        self.children: List[BaseASTNode] = children


class InheritanceSpecifier(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self, base_name: "UserDefinedTypeName", arguments: List["Expression"]
    ) -> None:
        self.base_name: "UserDefinedTypeName" = base_name
        self.arguments: List["Expression"] = arguments


class UserDefinedTypeName(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, name_path: str) -> None:
        self.name_path: str = name_path


class PragmaDirective(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, name: str, value: str) -> None:
        self.name: str = name
        self.value: str = value


class ImportDirective(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        path: str,
        path_literal: "StringLiteral",
        unit_alias: Optional[str] = None,
        unit_alias_identifier: Optional["Identifier"] = None,
        symbol_aliases: Optional[List[Tuple[str, Optional[str]]]] = None,
        symbol_aliases_identifiers: Optional[
            List[Tuple["Identifier", Optional["Identifier"]]]
        ] = None,
    ) -> None:
        self.path: str = path
        self.path_literal: "StringLiteral" = path_literal
        self.unit_alias: Optional[str] = unit_alias
        self.unit_alias_identifier: Optional["Identifier"] = unit_alias_identifier
        self.symbol_aliases: Optional[List[Tuple[str, Optional[str]]]] = symbol_aliases
        self.symbol_aliases_identifiers: Optional[
            List[Tuple["Identifier", Optional["Identifier"]]]
        ] = symbol_aliases_identifiers


class StateVariableDeclaration(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        variables: List["StateVariableDeclarationVariable"],
        initial_value: Optional["Expression"] = None,
    ) -> None:
        self.variables: List["StateVariableDeclarationVariable"] = variables
        self.initial_value: Optional["Expression"] = initial_value


class FileLevelConstant(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        type_name: "TypeName",
        name: str,
        initial_value: "Expression",
        is_declared_const: bool,
        is_immutable: bool,
    ) -> None:
        self.type_name: "TypeName" = type_name
        self.name: str = name
        self.initial_value: "Expression" = initial_value
        self.is_declared_const: bool = is_declared_const
        self.is_immutable: bool = is_immutable


class UsingForDeclaration(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        type_name: Optional["TypeName"],
        functions: List[str],
        operators: List[Optional[str]],
        library_name: Optional[str] = None,
        is_global: bool = False,
    ) -> None:
        self.type_name: Optional["TypeName"] = type_name
        self.functions: List[str] = functions
        self.operators: List[Optional[str]] = operators
        self.library_name: Optional[str] = library_name
        self.is_global: bool = is_global


class StructDefinition(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, name: str, members: List["VariableDeclaration"]) -> None:
        self.name: str = name
        self.members: List["VariableDeclaration"] = members


class ModifierDefinition(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        name: str,
        parameters: Optional[List["VariableDeclaration"]] = None,
        is_virtual: bool = False,
        override: Optional[List["UserDefinedTypeName"]] = None,
        body: Optional["Block"] = None,
    ) -> None:
        self.name: str = name
        self.parameters: Optional[List["VariableDeclaration"]] = parameters
        self.is_virtual: bool = is_virtual
        self.override: Optional[List["UserDefinedTypeName"]] = override
        self.body: Optional["Block"] = body


class ModifierInvocation(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self, name: str, arguments: Optional[List["Expression"]] = None
    ) -> None:
        self.name: str = name
        self.arguments: Optional[List["Expression"]] = arguments


class FunctionDefinition(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        name: Optional[str],
        parameters: List["VariableDeclaration"],
        modifiers: List["ModifierInvocation"],
        state_mutability: Optional[str] = None,  # TODO: make enum
        visibility: str = "default",  # TODO: make enum
        return_parameters: Optional[List["VariableDeclaration"]] = None,
        body: Optional["Block"] = None,
        override: Optional[List["UserDefinedTypeName"]] = None,
        is_constructor: bool = False,
        is_receive_ether: bool = False,
        is_fallback: bool = False,
        is_virtual: bool = False,
    ) -> None:
        self.name: Optional[str] = name
        self.parameters: List["VariableDeclaration"] = parameters
        self.modifiers: List["ModifierInvocation"] = modifiers
        self.state_mutability: Optional[str] = state_mutability
        self.visibility: str = visibility
        self.return_parameters: Optional[
            List["VariableDeclaration"]
        ] = return_parameters
        self.body: Optional["Block"] = body
        self.override: Optional[List["UserDefinedTypeName"]] = override
        self.is_constructor: bool = is_constructor
        self.is_receive_ether: bool = is_receive_ether
        self.is_fallback: bool = is_fallback
        self.is_virtual: bool = is_virtual


class CustomErrorDefinition(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, name: str, parameters: List["VariableDeclaration"]) -> None:
        self.name: str = name
        self.parameters: List["VariableDeclaration"] = parameters


class TypeDefinition(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, name: str, definition: "ElementaryTypeName") -> None:
        self.name: str = name
        self.definition: "ElementaryTypeName" = definition


class RevertStatement(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, revert_call: "FunctionCall") -> None:
        self.revert_call: "FunctionCall" = revert_call


class EventDefinition(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self, name: str, parameters: List["VariableDeclaration"], is_anonymous: bool
    ) -> None:
        self.name: str = name
        self.parameters: List["VariableDeclaration"] = parameters
        self.is_anonymous: bool = is_anonymous


class EnumValue(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, name: str) -> None:
        self.name: str = name


class EnumDefinition(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, name: str, members: List[EnumValue]) -> None:
        self.name: str = name
        self.members: List[EnumValue] = members


class VariableDeclaration(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        is_indexed: bool,
        is_state_var: bool,
        type_name: Optional["TypeName"] = None,
        name: Optional[str] = None,
        identifier: Optional["Identifier"] = None,
        is_declared_const: Optional[bool] = None,
        storage_location: Optional[str] = None,  # TODO: make enum
        expression: Optional["Expression"] = None,
        visibility: Optional[str] = None,  # TODO: make enum
    ) -> None:
        self.is_indexed: bool = is_indexed
        self.is_state_var: bool = is_state_var
        self.type_name: Optional["TypeName"] = type_name
        self.name: Optional[str] = name
        self.identifier: Optional["Identifier"] = identifier
        self.is_declared_const: Optional[bool] = is_declared_const
        self.storage_location: Optional[str] = storage_location
        self.expression: Optional["Expression"] = expression
        self.visibility: Optional[str] = visibility


class StateVariableDeclarationVariable(VariableDeclaration):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        is_immutable: bool,
        override: Optional[List["UserDefinedTypeName"]] = None,
        **kwargs
    ) -> None:
        super().__init__(**kwargs)
        self.is_immutable: bool = is_immutable
        self.override: Optional[List["UserDefinedTypeName"]] = override


class ArrayTypeName(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self, base_type_name: "TypeName", length: Optional["Expression"] = None
    ) -> None:
        self.base_type_name = base_type_name
        self.length = length


class Mapping(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        key_type: Union["ElementaryTypeName", "UserDefinedTypeName"],
        key_name: Optional["Identifier"] = None,
        value_type: "TypeName" = None,
        value_name: Optional["Identifier"] = None,
    ) -> None:
        self.key_type: Union["ElementaryTypeName", "UserDefinedTypeName"] = key_type
        self.key_name: Optional["Identifier"] = key_name
        self.value_type: "TypeName" = value_type
        self.value_name: Optional["Identifier"] = value_name


class FunctionTypeName(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        parameter_types: List["VariableDeclaration"],
        return_types: List["VariableDeclaration"],
        visibility: str,  # TODO: make enum
        state_mutability: Optional[str] = None,  # TODO: make enum
    ) -> None:
        self.parameter_types: List["VariableDeclaration"] = parameter_types
        self.return_types: List["VariableDeclaration"] = return_types
        self.visibility: str = visibility
        self.state_mutability: Optional[str] = state_mutability


class Block(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, statements: List[BaseASTNode]) -> None:
        self.statements: List[BaseASTNode] = statements


class ExpressionStatement(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, expression: Optional["Expression"] = None) -> None:
        self.expression: Optional["Expression"] = expression


class IfStatement(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        condition: "Expression",
        true_body: "Statement",
        false_body: Optional["Statement"] = None,
    ) -> None:
        self.condition: "Expression" = condition
        self.true_body: "Statement" = true_body
        self.false_body: Optional["Statement"] = false_body


class UncheckedStatement(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, block: "Block") -> None:
        self.block: "Block" = block


class TryStatement(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        expression: "Expression",
        return_parameters: Optional[List["VariableDeclaration"]] = None,
        body: "Block" = None,
        catch_clauses: List["CatchClause"] = [],
    ) -> None:
        self.expression: "Expression" = expression
        self.return_parameters: Optional[
            List["VariableDeclaration"]
        ] = return_parameters
        self.body: "Block" = body
        self.catch_clauses: List["CatchClause"] = catch_clauses


class CatchClause(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        is_reason_string_type: bool,
        kind: Optional[str] = None,
        parameters: Optional[List["VariableDeclaration"]] = None,
        body: "Block" = None,
    ) -> None:
        self.is_reason_string_type: bool = is_reason_string_type
        self.kind: Optional[str] = kind
        self.parameters: Optional[List["VariableDeclaration"]] = parameters
        self.body: "Block" = body


class WhileStatement(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, condition: "Expression", body: "Statement") -> None:
        self.condition: "Expression" = condition
        self.body: "Statement" = body


class ForStatement(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        init_expression: Optional["SimpleStatement"] = None,
        condition_expression: Optional["Expression"] = None,
        loop_expression: Optional["ExpressionStatement"] = None,
        body: Optional["Statement"] = None,
    ) -> None:
        self.init_expression: Optional["SimpleStatement"] = init_expression
        self.condition_expression: Optional["Expression"] = condition_expression
        self.loop_expression: Optional["ExpressionStatement"] = loop_expression
        self.body: Optional["Statement"] = body


class InlineAssemblyStatement(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        language: Optional[str] = None,
        flags: List[str] = [],
        body: Optional["AssemblyBlock"] = None,
    ) -> None:
        self.language: Optional[str] = language
        self.flags: List[str] = flags
        self.body: Optional["AssemblyBlock"] = body


class DoWhileStatement(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, condition: "Expression", body: "Statement") -> None:
        self.condition: "Expression" = condition
        self.body: "Statement" = body


class ContinueStatement(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self) -> None:
        pass


class Break(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self) -> None:
        pass


class Continue(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self) -> None:
        pass


class BreakStatement(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self) -> None:
        pass


class ReturnStatement(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, expression: Optional["Expression"] = None) -> None:
        self.expression: Optional["Expression"] = expression


class EmitStatement(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, event_call: "FunctionCall") -> None:
        self.event_call: "FunctionCall" = event_call


class ThrowStatement(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self) -> None:
        pass


class VariableDeclarationStatement(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        variables: List[Union[BaseASTNode, None]],
        initial_value: Optional["Expression"] = None,
    ) -> None:
        self.variables: List[Union[BaseASTNode, None]] = variables
        self.initial_value: Optional["Expression"] = initial_value


class ElementaryTypeName(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, name: str, state_mutability: Optional[str] = None) -> None:
        self.name: str = name
        self.state_mutability: Optional[str] = state_mutability  # TODO: make enum


class FunctionCall(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        expression: "Expression",
        arguments: List["Expression"],
        names: List[str],
        identifiers: List["Identifier"],
    ) -> None:
        self.expression: "Expression" = expression
        self.arguments: List["Expression"] = arguments
        self.names: List[str] = names
        self.identifiers: List["Identifier"] = identifiers


class AssemblyBlock(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, operations: List["AssemblyItem"]) -> None:
        self.operations: List["AssemblyItem"] = operations


class AssemblyCall(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self, function_name: str, arguments: List["AssemblyExpression"]
    ) -> None:
        self.function_name: str = function_name
        self.arguments: List["AssemblyExpression"] = arguments


class AssemblyLocalDefinition(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        names: Union[List["Identifier"], List["AssemblyMemberAccess"]],
        expression: Optional["AssemblyExpression"] = None,
    ) -> None:
        self.names: Union[List["Identifier"], List["AssemblyMemberAccess"]] = names
        self.expression: Optional["AssemblyExpression"] = expression


class AssemblyAssignment(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        names: Union[List["Identifier"], List["AssemblyMemberAccess"]],
        expression: "AssemblyExpression",
    ) -> None:
        self.names: Union[List["Identifier"], List["AssemblyMemberAccess"]] = names
        self.expression: "AssemblyExpression" = expression


class AssemblyStackAssignment(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, name: str, expression: "AssemblyExpression") -> None:
        self.name: str = name
        self.expression: "AssemblyExpression" = expression


class LabelDefinition(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, name: str) -> None:
        self.name: str = name


class AssemblySwitch(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self, expression: "AssemblyExpression", cases: List["AssemblyCase"]
    ) -> None:
        self.expression: "AssemblyExpression" = expression
        self.cases: List["AssemblyCase"] = cases


class AssemblyCase(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self, value: Optional["AssemblyLiteral"], block: "AssemblyBlock", default: bool
    ) -> None:
        self.value: Optional["AssemblyLiteral"] = value
        self.block: "AssemblyBlock" = block
        self.default: bool = default


class AssemblyFunctionDefinition(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        name: str,
        arguments: List["Identifier"],
        return_arguments: List["Identifier"],
        body: "AssemblyBlock",
    ) -> None:
        self.name: str = name
        self.arguments: List["Identifier"] = arguments
        self.return_arguments: List["Identifier"] = return_arguments
        self.body: "AssemblyBlock" = body


class AssemblyFor(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        pre: Union["AssemblyBlock", "AssemblyExpression"],
        condition: "AssemblyExpression",
        post: Union["AssemblyBlock", "AssemblyExpression"],
        body: "AssemblyBlock",
    ) -> None:
        self.pre: Union["AssemblyBlock", "AssemblyExpression"] = pre
        self.condition: "AssemblyExpression" = condition
        self.post: Union["AssemblyBlock", "AssemblyExpression"] = post
        self.body: "AssemblyBlock" = body


class AssemblyIf(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, condition: "AssemblyExpression", body: "AssemblyBlock") -> None:
        self.condition: "AssemblyExpression" = condition
        self.body: "AssemblyBlock" = body


class AssemblyLiteral(BaseASTNode):
    """
    Placeholder class for AssemblyLiteral
    #TODO: add docstring
    """

    def __init__(self) -> None:
        pass


class AssemblyMemberAccess(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, expression: "Identifier", member_name: "Identifier") -> None:
        self.expression: "Identifier" = expression
        self.member_name: "Identifier" = member_name


class NewExpression(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, type_name: "TypeName") -> None:
        self.type_name: "TypeName" = type_name


class TupleExpression(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self, components: List[Union[BaseASTNode, None]], isArray: bool
    ) -> None:
        self.components: List[Union[BaseASTNode, None]] = components
        self.is_array: bool = isArray


class NameValueExpression(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, expression: "Expression", arguments: "NameValueList") -> None:
        self.expression: "Expression" = expression
        self.arguments: "NameValueList" = arguments


class NumberLiteral(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, number: str, subdenomination: Optional[str] = None) -> None:
        self.number: str = number
        self.subdenomination: Optional[str] = subdenomination


class BooleanLiteral(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, value: bool) -> None:
        self.value: bool = value


class HexLiteral(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, value: str, parts: List[str]) -> None:
        self.value: str = value
        self.parts: List[str] = parts


class StringLiteral(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, value: str, parts: List[str], is_unicode: List[bool]) -> None:
        self.value: str = value
        self.parts: List[str] = parts
        self.is_unicode: List[bool] = is_unicode


class Identifier(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, name: str) -> None:
        self.name: str = name


# TODO: convert to enum
BINARY_OP_VALUES = (
    "+",
    "-",
    "*",
    "/",
    "**",
    "%",
    "<<",
    ">>",
    "&&",
    "||",
    ",,",
    "&",
    ",",
    "^",
    "<",
    ">",
    "<=",
    ">=",
    "==",
    "!=",
    "=",
    ",=",
    "^=",
    "&=",
    "<<=",
    ">>=",
    "+=",
    "-=",
    "*=",
    "/=",
    "%=",
    "|",
    "|=",
)

# TODO: convert to enum
UNARY_OP_VALUES = ("-", "+", "++", "--", "~", "after", "delete", "!")


class BinaryOperation(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, left: "Expression", right: "Expression", operator: str) -> None:
        self.left: "Expression" = left
        self.right: "Expression" = right
        self.operator: str = operator  # TODO: make enum


class UnaryOperation(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self, operator: str, sub_expression: "Expression", is_prefix: bool
    ) -> None:
        self.operator: str = operator  # TODO: make enum
        self.sub_expression: "Expression" = sub_expression
        self.is_prefix: bool = is_prefix


class Conditional(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        condition: "Expression",
        true_expression: "Expression",
        false_expression: "Expression",
    ) -> None:
        self.condition: "Expression" = condition
        self.true_expression: "Expression" = true_expression
        self.false_expression: "Expression" = false_expression


class IndexAccess(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, base: "Expression", index: "Expression") -> None:
        self.base: "Expression" = base
        self.index: "Expression" = index


class IndexRangeAccess(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        base: "Expression",
        index_start: Optional["Expression"] = None,
        index_end: Optional["Expression"] = None,
    ) -> None:
        self.base: "Expression" = base
        self.index_start: Optional["Expression"] = index_start
        self.index_end: Optional["Expression"] = index_end


class MemberAccess(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, expression: "Expression", member_name: str) -> None:
        self.expression: "Expression" = expression
        self.member_name: str = member_name


class HexNumber(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, value: str) -> None:
        self.value: str = value


class DecimalNumber(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(self, value: str) -> None:
        self.value: str = value


class NameValueList(BaseASTNode):
    """
    #TODO: add docstring
    """

    def __init__(
        self,
        names: List[str],
        identifiers: List["Identifier"],
        arguments: List["Expression"],
    ) -> None:
        self.names: List[str] = names
        self.identifiers: List["Identifier"] = identifiers
        self.arguments: List["Expression"] = arguments


class ASTNode:
    """
    #TODO: add docstring
    """

    pass


# TODO: make enum
class AssemblyItem(ASTNode):
    """
    #TODO: add docstring
    """

    pass


# TODO: make enum
class AssemblyExpression(AssemblyItem):
    """
    #TODO: add docstring
    """

    pass


# TODO: make enum
class Expression(ASTNode):
    """
    #TODO: add docstring
    """

    pass


# TODO: make enum
class PrimaryExpression(Expression):
    """
    #TODO: add docstring
    """

    pass


# TODO: make enum
class Statement(ASTNode):
    """
    #TODO: add docstring
    """

    pass


# TODO: make enum
class SimpleStatement(Statement):
    """
    #TODO: add docstring
    """

    pass


# class TypeName:
#     pass

# class Statement:
#     pass

# class SourceUnit(ASTNode):
#     pass

# class PragmaDirective(ASTNode):
#     pass

# class ImportDirective(ASTNode):
#     pass

# class ContractDefinition(ASTNode):
#     pass

# class InheritanceSpecifier(ASTNode):
#     pass

# class StateVariableDeclaration(ASTNode):
#     pass

# class UsingForDeclaration(ASTNode):
#     pass

# class StructDefinition(ASTNode):
#     pass

# class ModifierDefinition(ASTNode):
#     pass

# class ModifierInvocation(ASTNode):
#     pass

# class FunctionDefinition(ASTNode):
#     pass

# class EventDefinition(ASTNode):
#     pass

# class CustomErrorDefinition(ASTNode):
#     pass

# class EnumValue(ASTNode):
#     pass

# class EnumDefinition(ASTNode):
#     pass

# class VariableDeclaration(ASTNode):
#     pass


class TypeName(ASTNode):
    """
    #TODO: add docstring
    """

    pass


# class UserDefinedTypeName(ASTNode):
#     pass

# class Mapping(ASTNode):
#     pass

# class FunctionTypeName(ASTNode):
#     pass

# class Block(ASTNode):
#     pass

# class ElementaryTypeName(ASTNode):
#     pass

# class AssemblyBlock(ASTNode):
#     pass

# class AssemblyCall(ASTNode):
#     pass

# class AssemblyLocalDefinition(ASTNode):
#     pass

# class AssemblyAssignment(ASTNode):
#     pass

# class AssemblyStackAssignment(ASTNode):
#     pass

# class LabelDefinition(ASTNode):
#     pass

# class AssemblySwitch(ASTNode):
#     pass

# class AssemblyCase(ASTNode):
#     pass

# class AssemblyFunctionDefinition(ASTNode):
#     pass

# class AssemblyFor(ASTNode):
#     pass

# class AssemblyIf(ASTNode):
#     pass

# class AssemblyLiteral(ASTNode):
#     pass

# class TupleExpression(ASTNode):
#     pass

# class BinaryOperation(ASTNode):
#     pass

# class Conditional(ASTNode):
#     pass

# class IndexAccess(ASTNode):
#     pass

# class IndexRangeAccess(ASTNode):
#     pass

# class NameValueList(ASTNode):
#     pass

# class AssemblyMemberAccess(ASTNode):
#     pass

# class CatchClause(ASTNode):
#     pass

# class FileLevelConstant(ASTNode):
#     pass

# class TypeDefinition(ASTNode):
#     pass

# class BooleanLiteral(PrimaryExpression):
#     pass

# class HexLiteral(PrimaryExpression):
#     pass

# class StringLiteral(PrimaryExpression):
#     pass

# class NumberLiteral(PrimaryExpression):
#     pass

# class Identifier(PrimaryExpression):
#     pass

# class TupleExpression(PrimaryExpression):
#     pass

# class TypeName(PrimaryExpression):
#     pass

# class TypeName(TypeName):
#     pass
