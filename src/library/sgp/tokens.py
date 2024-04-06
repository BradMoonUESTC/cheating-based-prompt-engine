from typing import List, Dict, Any

def rsplit(input_string: str, value: str) -> List[str]:
    index = input_string.rfind(value)
    return [input_string[:index], input_string[index + 1:]]

def normalize_token_type(value: str) -> str:
    if value.endswith("'"):
        value = value[:-1]
    if value.startswith("'"):
        value = value[1:]
    return value

def get_token_type(value: str) -> str:
    TYPE_TOKENS = [
        'var',
        'bool',
        'address',
        'string',
        'Int',
        'Uint',
        'Byte',
        'Fixed',
        'UFixed',
    ]

    if value in ['Identifier', 'from']:
        return 'Identifier'
    elif value in ['TrueLiteral', 'FalseLiteral']:
        return 'Boolean'
    elif value == 'VersionLiteral':
        return 'Version'
    elif value == 'StringLiteral':
        return 'String'
    elif value in TYPE_TOKENS:
        return 'Type'
    elif value == 'NumberUnit':
        return 'Subdenomination'
    elif value == 'DecimalNumber':
        return 'Numeric'
    elif value == 'HexLiteral':
        return 'Hex'
    elif value == 'ReservedKeyword':
        return 'Reserved'
    elif not value.isalnum():
        return 'Punctuator'
    else:
        return 'Keyword'

def get_token_type_map(tokens: str) -> Dict[int, str]:
    lines = tokens.split('\n')
    token_map = {}

    for line in lines:
        value, key = rsplit(line, '=')
        token_map[int(key)] = normalize_token_type(value)

    return token_map

#TODO: sort it out
def build_token_list(tokens_arg: List[Dict[str, Any]], options: Dict[str, Any]) -> List[Dict[str, Any]]:
    token_types = get_token_type_map(tokens_arg)
    result = []

    for token in tokens_arg:
        type_str = get_token_type(token_types[token['type']])
        node = {'type': type_str, 'value': token['text']}

        if options.get('range', False):
            node['range'] = [token['startIndex'], token['stopIndex'] + 1]

        if options.get('loc', False):
            node['loc'] = {
                'start': {'line': token['line'], 'column': token['charPositionInLine']},
                'end': {'line': token['line'], 'column': token['charPositionInLine'] + len(token['text']) if token['text'] else 0}
            }

        result.append(node)

    return result
