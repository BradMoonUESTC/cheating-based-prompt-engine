from typing import List
from typing_extensions import override
from antlr4.error.ErrorListener import ErrorListener

class SGPError:
    def __init__(self, message, line, column):
        self.message = message
        self.line = line
        self.column = column

    def __str__(self):
        return f"{self.message} ({self.line}:{self.column})"

class SGPErrorListener(ErrorListener):
    def __init__(self):
        super().__init__()
        self._errors: List[SGPError] = []

    @override
    def syntaxError(self, recognizer, offendingSymbol, line, column, msg, e):
        self._errors.append(SGPError(msg, line, column))

    def get_errors(self) -> List[SGPError]:
        return self._errors

    def has_errors(self) -> bool:
        return len(self._errors) > 0
