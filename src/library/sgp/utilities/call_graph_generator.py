import logging
import re
import subprocess
import os
import pydot
import networkx as nx
from collections import defaultdict

from tool.PDG_parser import antlr_listener
from utilities.contract_extractor import extract_function_from_solidity


def parse_dot_file(path):
    with open(path) as f:
        dot_string = f.read()

    # Initialize an empty directed graph
    digraph = nx.DiGraph()

    # Split the dot string into lines
    lines = dot_string.split('\n')

    # Define regex patterns
    node_pattern = re.compile(r'^"(.*?)" \[label="(.*?)"\]')
    edge_pattern = re.compile(r'^"(.*?)" -> "(.*?)"')

    # Initialize labels dictionary
    labels = {}

    # Process each line
    for line in lines:
        # Check if the line defines a node
        node_match = node_pattern.match(line)
        if node_match:
            # Extract node name and label
            node_name = node_match.group(1)
            node_label = node_match.group(2)

            # Update labels dictionary
            labels[node_name] = node_label
            digraph.add_node(node_name)
        else:
            # Check if the line defines an edge
            edge_match = edge_pattern.match(line)
            if edge_match:
                # Extract source and target of the edge
                source = edge_match.group(1)
                target = edge_match.group(2)

                # Add the edge to the graph
                digraph.add_edge(source, target)

    return digraph, labels


def antlr_call_graph(sol_file, function_label):
    """
    Return callers and callees associated with respective source codes in a dict.
    """
    listener = antlr_listener(sol_file)
    state_var_related_functions = listener.get_related_state_variables(function_label)
    callers = listener.get_function_callers(function_label)
    callees = listener.get_function_callees(function_label)
    functions = set()
    for s in state_var_related_functions.values():
        functions = functions.union(s)

    return {each: listener.get_functions().get(each, {}).get('source', '') for each in functions}, {each: listener.get_functions().get(each, {}).get('source', '') for each in callers}, {each: listener.get_functions().get(each, {}).get('source', '') for each in callees}


def get_callers_callees(sol_file, function_label, solc_version):
    digraph, labels = generate_call_graph(sol_file, solc_version)

    if not digraph:
        # if
        logging.debug('[ERROR] Slither call graph failed!')
        state_var_functions, callers, callees = antlr_call_graph(sol_file, function_label)

        return state_var_functions, callers, callees
    else:
        callers_src = {}
        callees_src = {}
        logging.debug('[INFO] Slither Call graph generated successfully!')
        # Find callers of the function
        callers = find_callers(digraph, labels, function_label)
        for caller in callers:
            callers_src[caller] = extract_function_from_solidity(caller, sol_file)
        # Find callees of the function
        callees = find_callees(digraph, labels, function_label)
        for callee in callees:
            callees_src[callee] = extract_function_from_solidity(callee, sol_file)



        return {}, callers_src, callees_src


def find_callers(digraph, labels, function_label):
    # Find the function name that corresponds to the function_label
    function = None
    for func, label in labels.items():
        if label == function_label:
            function = func
            break

    if function is None:
        raise ValueError("No function found with label: " + function_label)

    # Find all nodes that have an edge to the function
    callers = defaultdict(list)
    for node in digraph.nodes():
        for path in nx.all_simple_paths(digraph, source=node, target=function):
            if len(path) > 1: #exclude the function itself
                callers[labels[node]].extend(labels.get(n, n) for n in path) #exclude the caller and the callee

    return callers

def find_callees(digraph, labels, function_label):
    # Find the function name that corresponds to the function_label
    function = None
    for func, label in labels.items():
        if label == function_label:
            function = func
            break

    if function is None:
        raise ValueError("No function found with label: " + function_label)

    # Find all nodes that have an edge to the function
    callees = defaultdict(list)
    for node in digraph.nodes():
        for path in nx.all_simple_paths(digraph, source=function, target=node):
            if len(path) > 1 and node in labels.keys(): #exclude the function itself
                callees[labels[node]].extend(labels.get(n, n) for n in path) #exclude the caller and the callee
    return callees

def generate_call_graph(path, solc_version):
    logging.debug('slither '+path+' --print call-graph')
    if solc_version:
        subprocess.check_output('solc-select use ' + solc_version.replace('^', '') + ' --always-install',stderr=subprocess.STDOUT, shell=True)
    p = subprocess.run(['slither', path, '--print', 'call-graph'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    # subprocess.check_output('slither '+path+' --print call-graph', stderr=subprocess.STDOUT, shell=True)
    directory = path.rsplit('/', 1)[0]
    digraph = None
    for file in os.listdir(directory):
        if file.endswith('.dot') and 'all_contracts' in file:
            cg_file = os.path.join(directory, file)
            digraph, labels = parse_dot_file(cg_file)
    for file in os.listdir(directory):
        if file.endswith('.dot'):
            os.remove(os.path.join(directory, file))
    if not digraph:
        return None, None
    else:
        return digraph, labels


