"""Checks the SeaStock contract files without extra tools: YAML parses, every $ref resolves,
operationIds are unique, every operation carries x-roles / x-brd / x-ticket / x-sprint and
responses, and every {path} parameter is declared. Run: python contracts/check.py"""
import pathlib
import re
import sys

import yaml

HERE = pathlib.Path(__file__).parent
FILES = ['common.yaml', 'tablet-sync.yaml', 'receiving.yaml', 'inventory.yaml', 'transactions.yaml',
         'identity.yaml', 'customers-vessels.yaml', 'devices.yaml', 'articles.yaml', 'audit.yaml']
docs = {f: yaml.safe_load((HERE / f).read_text(encoding='utf-8')) for f in FILES}
errors = []


def resolve(file, ref):
    target, _, pointer = ref.partition('#')
    target = target.removeprefix('./') or file
    if target not in docs:
        return f'unknown file {target}'
    node = docs[target]
    for part in [p for p in pointer.split('/') if p]:
        if not isinstance(node, dict) or part not in node:
            return f'missing {pointer} in {target}'
        node = node[part]
    return None


def walk(file, node, where):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == '$ref' and isinstance(v, str):
                problem = resolve(file, v)
                if problem:
                    errors.append(f'{file} {where}: $ref {v} -> {problem}')
            else:
                walk(file, v, f'{where}/{k}')
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(file, v, f'{where}[{i}]')


ops = {}
for f, doc in docs.items():
    if doc.get('openapi') != '3.1.0':
        errors.append(f'{f}: openapi must be 3.1.0')
    walk(f, doc, '')
    for path, item in (doc.get('paths') or {}).items():
        for method, op in item.items():
            if method not in ('get', 'post', 'put', 'patch', 'delete'):
                continue
            oid = op.get('operationId')
            if oid in ops:
                errors.append(f'{f} {method} {path}: operationId {oid} also in {ops[oid]}')
            ops[oid] = f
            for key in ('x-roles', 'x-brd', 'x-ticket', 'x-sprint', 'responses', 'summary'):
                if key not in op:
                    errors.append(f'{f} {method} {path}: missing {key}')
            declared = set()
            for p in op.get('parameters', []):
                if '$ref' in p:
                    target, _, pointer = p['$ref'].partition('#')
                    node = docs[target.removeprefix('./') or f]
                    for part in [x for x in pointer.split('/') if x]:
                        node = node[part]
                    p = node
                if p.get('in') == 'path':
                    declared.add(p['name'])
            for name in re.findall(r'{(\w+)}', path):
                if name not in declared:
                    errors.append(f'{f} {method} {path}: path parameter {name} not declared')

print(f'{len(ops)} operations in {len(FILES)} files')
for e in errors:
    print('ERROR', e)
sys.exit(1 if errors else 0)
