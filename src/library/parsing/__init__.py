from antlr4 import CommonTokenStream, InputStream
from .SolidityLexer import SolidityLexer
from .SolidityParser import parseString
from .callgraph import CallGraph

def parse(source:str):
    lexer = SolidityLexer(InputStream(source))
    stream = CommonTokenStream(lexer)
    parser = SolidityParser(stream)
    return parser.sourceUnit()

def get_tokens(source:str):
    lexer = SolidityLexer(InputStream(source))
    return lexer.getAllTokens()
