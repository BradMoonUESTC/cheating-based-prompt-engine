import os
import simplejson
from typing import Dict

from antlr4.CommonTokenStream import CommonTokenStream
from antlr4.InputStream import InputStream as ANTLRInputStream

from .parser.SolidityLexer import SolidityLexer
from .parser.SolidityParser import SolidityParser

from .sgp_visitor import SGPVisitorOptions, SGPVisitor,SolidityInfoVisitor
from .sgp_error_listener import SGPErrorListener
from .ast_node_types import SourceUnit
from .tokens import build_token_list
from .utils import string_from_snake_to_camel_case


class ParserError(Exception):
    """
    An exception raised when the parser encounters an error.            
    """

    def __init__(self, errors) -> None:
        """
        Parameters
        ----------
        errors : List[Dict[str, Any]] - A list of errors encountered by the parser.        
        """
        super().__init__()
        error = errors[0]
        self.message = f"{error['message']} ({error['line']}:{error['column']})"
        self.errors = errors


def parse(
    input_string: str,
    options: SGPVisitorOptions = SGPVisitorOptions(),
    dump_json: bool = False,
    dump_path: str = "./out",
) -> SourceUnit:
    """
    Parse a Solidity source string into an AST.

    Parameters
    ----------
    input_string : str - The Solidity source string to parse.
    options : SGPVisitorOptions - Options to pass to the parser.
    dump_json : bool - Whether to dump the AST as a JSON file.
    dump_path : str - The path to dump the AST JSON file to.

    Returns
    -------
    SourceUnit - The root of an AST of the Solidity source string.    
    """

    input_stream = ANTLRInputStream(input_string)
    lexer = SolidityLexer(input_stream)
    token_stream = CommonTokenStream(lexer)
    parser = SolidityParser(token_stream)

    listener = SGPErrorListener()
    lexer.removeErrorListeners()
    lexer.addErrorListener(listener)

    parser.removeErrorListeners()
    parser.addErrorListener(listener)
    source_unit = parser.sourceUnit()


    ast_builder = SGPVisitor(options)
    try:
        source_unit: SourceUnit = ast_builder.visit(source_unit)
    except Exception as e:
        raise Exception("AST was not generated")
    else:
        if source_unit is None:
            raise Exception("AST was not generated")

    # TODO: sort it out
    token_list = []
    if options.tokens:
        token_list = build_token_list(token_stream.getTokens(), options)

    if not options.errors_tolerant and listener.has_errors():
        raise ParserError(errors=listener.get_errors())

    if options.errors_tolerant and listener.has_errors():
        source_unit.errors = listener.get_errors()

    # TODO: sort it out
    if options.tokens:
        source_unit["tokens"] = token_list

    if dump_json:
        os.makedirs(dump_path, exist_ok=True)
        with open(os.path.join(dump_path, "ast.json"), "w") as f:
            s = simplejson.dumps(
                source_unit,
                default=lambda obj: {
                    string_from_snake_to_camel_case(k): v
                    for k, v in obj.__dict__.items()
                },
            )
            f.write(s)
    return source_unit



def get_antlr_parsing(path):
    with open(path, 'r', encoding='utf-8', errors="ignore") as file:
        code = file.read()

    input_stream = ANTLRInputStream(code)
    lexer = SolidityLexer(input_stream)
    token_stream = CommonTokenStream(lexer)
    parser = SolidityParser(token_stream)
    tree = parser.sourceUnit()

    visitor = SolidityInfoVisitor(code)
    visitor.visit(tree)

    return visitor.results



def get_antlr_ast(path):
    with open(path, 'r', encoding='utf-8', errors="ignore") as file:
        code = file.read()

    parse(code,dump_json=True,dump_path="./")