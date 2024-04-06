
# 48,pragma
# 170,compiler_version
# 35,import
# 121,import_statement
# 127,variable_name
# 15,contract
# 2,abstract
# 37,interface
# 40,library
# 39,is
# 94,，
# 66,using
# 28,for
# 74,{
# 75,}
# 77,;
# 30,function
# 22,event
# 13,constructor
# 43,modifier
# 50,public
# 23,external
# 38,internal
# 49,private
# 67,view
# 68,virtual
# 46,override
# 47,payable
# 51,pure
# 53,return


# overall
PRAGMA_ID = 48
COMPILER_VERSION_ID = 170
IMPORT_ID = 35
IMPORT_STATEMENT_ID = 121
VARIABLE_NAME_ID = 127
USING_ID = 66
FOR_ID = 28
LEFT_BRACKET_ID = 74
RIGHT_BRACKET_ID = 75
IS_ID = 39
COMMA_ID = 94
SEMICOLON_ID = 77

# subcontract
CONTRACT_ID = 15  # kind
INTERFACE_ID = 37
LIBRARY_ID = 40
ABSTRACT_ID = 2

# function
EVENT_ID = 22  # kind
MODIFIER_ID = 43
FUNCTION_ID = 30
CONSTRUCTOR_ID = 13
PUBLIC_ID = 50  # visibility
EXTERNAL_ID = 23
INTERNAL_ID = 38
PRIVATE_ID = 49
VIEW_ID = 6 # others
VIRTUAL_ID = 68
OVERRIDE_ID = 46
PAYABLE_ID = 47
PURE_ID = 51
RETURN_ID = 53


CLONE_TYPE=2



SUBCONTRACT_IDS = {CONTRACT_ID: 'contract', INTERFACE_ID: 'interface', LIBRARY_ID: 'library', ABSTRACT_ID: 'abstract'}
FUNCTION_IDS = {EVENT_ID: 'event', MODIFIER_ID: 'modifier', FUNCTION_ID: 'function', CONSTRUCTOR_ID: 'constructor'}
FUNCTION_VISIBILITY_IDS = {PUBLIC_ID: 'public', EXTERNAL_ID: 'external', INTERNAL_ID: 'internal', PRIVATE_ID: 'private'}