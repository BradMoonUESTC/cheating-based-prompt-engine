from .SolidityLexer import SolidityLexer
from antlr4 import *
from .utils import *
from .constantTokenId import *
import logging

# logging.basicConfig(filename='parser.log', encoding='utf-8', level=logging.DEBUG,filemode='a')

def getTokenStream(input_stream):
    try:
        # input_stream = FileStream(file_path)  # change encoding of FileStream from ascii to utf-8
        lexer = SolidityLexer(input_stream)  # remove ord()
        return CommonTokenStream(lexer)
    except Exception:
        return CommonTokenStream()

def parseToken(string):
    if (string is None) or ('channel=1' in string):
        return None, None, None
    info_list = string[1:-1].split(',',1)[-1].rsplit(',',2)
    content = stringClean(info_list[0].split('=')[1])
    id = int(info_list[1][1:-1])
    loc = info_list[2]
    return id, content, loc

def forwardUntil(i, stream, expect_id, max_length):
    output = ''
    while i < max_length:
        id, content, loc = parseToken(str(stream[i]))
        if id is not None:
            output += content
            if id == expect_id:
                return i, content, loc, output
        if id == SEMICOLON_ID:
            return i, output.replace(';',''), loc, output
        i += 1
    return None, '', None, None

def getFunction(i, stream, max_length, function_id, start, outside_contract):
    left_bracket_count = 0
    right_bracket_count = 0

    function_name = None
    kind = FUNCTION_IDS[function_id]
    normalized_output = kind
    original_output = kind
    loc = None
    function_body = True
    visibility = None # public, private, internal, external
    check_key = True
    is_fallback = False
    is_pure = False
    is_view = False
    is_virtual = False
    is_payable = False
    is_override = False
    while i < max_length:
        id, content, loc = parseToken(str(stream[i]))
        if id is not None:
            # extract content
            if function_name is None:
                if id == 127:
                    function_name = content
                else:
                    function_name = ''
            if id in FUNCTION_VISIBILITY_IDS.keys():
                visibility = FUNCTION_VISIBILITY_IDS[id]
            if id == RETURN_ID:
                check_key = False
            elif check_key:
                if id == PURE_ID:
                    is_pure = True
                elif id == VIEW_ID:
                    is_view = True
                elif id == VIRTUAL_ID:
                    is_virtual = True
                elif id == PAYABLE_ID:
                    is_payable = True
                elif id == OVERRIDE_ID:
                    is_override = True
            if (CLONE_TYPE == 2) and (id == 127):
                normalized_output += 'x'
                original_output += content
            else:
                normalized_output += content
                original_output += content

            # identify boundary of function
            if (id == SEMICOLON_ID) and (left_bracket_count == 0):
                function_body = False
                break
            elif id == LEFT_BRACKET_ID:
                left_bracket_count += 1
            elif id == RIGHT_BRACKET_ID:
                right_bracket_count += 1
            if (left_bracket_count != 0) and (left_bracket_count == right_bracket_count):
                break
        i += 1
    if loc is None:
        return i, '', None
    if (function_name == '') and (kind!=FUNCTION_IDS[CONSTRUCTOR_ID]):
        is_fallback = True
    if visibility is None:
        if is_fallback:
            visibility = FUNCTION_VISIBILITY_IDS[EXTERNAL_ID]
        elif outside_contract:
            visibility = FUNCTION_VISIBILITY_IDS[INTERNAL_ID]
        elif kind != FUNCTION_IDS[CONSTRUCTOR_ID]:
            visibility = FUNCTION_VISIBILITY_IDS[PUBLIC_ID]
    return i, normalized_output, {
        'name':function_name, 
        # 'hash':hash, 
        'kind':kind, 
        'visibility': visibility,
        'is_fallback': is_fallback,
        'is_pure': is_pure,
        'is_view': is_view,
        'is_virtual': is_virtual,
        'is_payable': is_payable,
        'is_override': is_override,
        'function_body':function_body, 
        'loc':{'start':start,'end':loc}, 
        'output':original_output}
                

def getUsingFor(i, stream, max_length):
    content = 'using'
    if i+1 < max_length:
        id, content_temp, loc = parseToken(str(stream[i+1]))
        if id is not None:
            if id == VARIABLE_NAME_ID:
                content += content_temp
                return i+1, content, loc
    return i, content, None

def getSubcontract(i, stream, max_length, subcontract_id, start):
    left_bracket_count = 0
    right_bracket_count = 0

    subcontract_name = None
    kind = SUBCONTRACT_IDS[subcontract_id]
    normalized_output = kind
    original_output = kind
    loc = None
    functions = []
    checking_parent = False
    inheritance = []
    using_for = []
    while i < max_length:
        id, content, loc = parseToken(str(stream[i]))
        if id is not None:
            if (subcontract_name is None) and (id ==VARIABLE_NAME_ID):
                subcontract_name = content
            if (left_bracket_count == 0) and (id == IS_ID):
                checking_parent = True
            if checking_parent:
                if id == VARIABLE_NAME_ID:
                    inheritance.append(content)
            elif id == USING_ID:
                i, content, loc = getUsingFor(i, stream, max_length)
                if loc is not None:
                    using_for.append(content.replace('using',''))
                    # normalized_output += using_for_content
                    # original_output += using_for_content
            if (CLONE_TYPE == 2) and (id == VARIABLE_NAME_ID):
                normalized_output += 'x'
                original_output += content
            elif id in FUNCTION_IDS.keys():
                i, function, function_entry = getFunction(i+1, stream, max_length, id, loc, False)
                if normalized_output is None:
                    continue
                normalized_output += function
                original_output += function_entry['output']
                functions.append(function_entry)
            elif id == LEFT_BRACKET_ID:
                normalized_output += content
                original_output += content
                left_bracket_count += 1
                checking_parent = False
            elif id == RIGHT_BRACKET_ID:
                normalized_output += content
                original_output += content
                right_bracket_count += 1
            else:
                normalized_output += content
                original_output += content
            if (left_bracket_count != 0) and (left_bracket_count == right_bracket_count):
                break
        i += 1
    if loc is None:
        return i, '', None
    # hash = hashString(normalized_output)
    return i, normalized_output, {
        'name':subcontract_name, 
        # 'hash':hash, 
        'kind':kind, 
        'functions':functions, 
        'inheritance':inheritance,
        'using_for':using_for,
        'loc':{'start':start,'end':loc}, 
        'output':original_output
        }


def parseStream(stream:CommonTokenStream):
    try:
        stream.fill()
        stream = stream.getTokens(0, len(stream.tokens))
        length = len(stream)
        compiler = ''
        # imports_project = {}
        imports = []
        subcontracts = []
        functions = []
        normalized_output = ''
        original_output = ''

        i = 0
        while i < length:
            id, content, loc = parseToken(str(stream[i]))
            if id is not None:
                if id == PRAGMA_ID:
                    i, compiler_, _, content = forwardUntil(i+1, stream, COMPILER_VERSION_ID, length)
                    original_output += content
                    compiler = compiler_.replace('solidity','')
                elif id == IMPORT_ID:
                    i, import_statement, _, content = forwardUntil(i+1, stream, IMPORT_STATEMENT_ID, length)
                    original_output += content
                    imports.append(import_statement)
                elif (CLONE_TYPE == 2) and (id == VARIABLE_NAME_ID):
                    original_output += content
                    content = 'x'
                elif id in SUBCONTRACT_IDS.keys():
                    i, content, subcontract = getSubcontract(i+1, stream, length, id, loc)
                    if subcontract is not None:
                        original_output += subcontract['output']
                        subcontract['compiler'] = compiler
                        subcontract['imports'] = imports
                        subcontracts.append(subcontract)
                    imports = []
                elif id in FUNCTION_IDS.keys():
                    i, content, function = getFunction(i+1, stream, length, id, loc, True)
                    functions.append(function)
                    original_output += function['output']

                normalized_output += content
            i += 1
        return {'subcontracts': subcontracts, 'functions': functions, 'output':original_output}
    except Exception:
        traceback.print_exc()
        return {'subcontracts': subcontracts, 'functions': functions, 'output':original_output}

def parseString(content):
    return parseStream(getTokenStream(InputStream(content)))

def parseFile(file_path):
    return parseStream(getTokenStream(FileStream(file_path, encoding='utf-8')))

