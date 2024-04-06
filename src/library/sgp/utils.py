from typing import Any


def string_from_snake_to_camel_case(input: str) -> str:
    """
    Convert a string from snake_case to camelCase.

    Parameters
    ----------
    input : str - The string to convert.

    Returns
    -------
    str - The converted string.

    Examples
    --------
    >>> string_from_snake_to_camel_case("hello_world")
    "helloWorld"
    >>> string_from_snake_to_camel_case("helloWorld")
    "helloWorld"
    """

    if not input:
        return input
    if "_" not in input:
        return input
    s = input.split("_")
    return s[0] + "".join(i.title() for i in s[1:])
