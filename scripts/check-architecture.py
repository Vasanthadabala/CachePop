#!/usr/bin/env python3
"""Check feature boundaries; optionally type-check the domain without app/UI/adapter sources."""
from pathlib import Path
import argparse
import collections
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
DECLARATION = re.compile(r'^(?:(?:nonisolated|final|private|indirect) )*(?:struct|enum|class|actor|protocol) (\w+)', re.M)

def code(text):
    # Comments and literal prose cannot create dependencies. Keep the source scanner small:
    # Swift's compiler, invoked by --typecheck, is the definitive domain dependency check.
    return re.sub(r'/\*.*?\*/|//[^\n]*|""".*?"""|"(?:\\.|[^"\\])*"', '', text, flags=re.S)

def check(root=ROOT):
    sources = sorted((root / 'CachePop').rglob('*.swift'))
    domain = [p for p in sources if 'Domain' in p.parts]
    data = [p for p in sources if 'Data' in p.parts]
    presentation = [p for p in sources if 'Presentation' in p.parts or 'Shared' in p.parts]
    names = lambda paths: set().union(*(set(DECLARATION.findall(code(p.read_text()))) for p in paths))
    domain_names = names(domain)
    data_names = names(data) - domain_names
    presentation_names = names(presentation) - domain_names - data_names
    failures = []
    def reject(path, message): failures.append(f'{path.relative_to(root)}: {message}')
    for path in domain:
        source = code(path.read_text())
        imports = set(re.findall(r'^import (\w+)', source, re.M))
        if imports - {'Foundation'}: reject(path, f'domain imports platform/UI frameworks: {sorted(imports)}')
        dependencies = set(re.findall(r'\b\w+\b', source)) & (data_names | presentation_names)
        if dependencies: reject(path, f'domain depends on outer-layer types: {sorted(dependencies)}')
    for path in data:
        source = code(path.read_text())
        if re.search(r'^import (SwiftUI|Observation)\b|@Observable\b|\bAppTheme\b', source, re.M):
            reject(path, 'data contains presentation state or styling')
        dependencies = set(re.findall(r'\b\w+\b', source)) & presentation_names
        if dependencies: reject(path, f'data depends on presentation types: {sorted(dependencies)}')
    for path in sources:
        if not (path.stem.endswith('ViewModel') or path.stem in {'AppSettings', 'CleanHistory'}): continue
        source = code(path.read_text())
        dependencies = set(re.findall(r'\b\w+\b', source)) & data_names
        if dependencies: reject(path, f'view model depends on concrete data types: {sorted(dependencies)}')
        if re.search(r'\b(UserDefaults|FileManager|NSOpenPanel|NSSavePanel|SMAppService|NSRunningApplication)\b', source):
            reject(path, 'view model performs storage or native dialog work')
    for feature in (root / 'CachePop/Features').iterdir():
        if not feature.is_dir(): continue
        for path in feature.glob('*.swift'): reject(path, 'feature source must declare a Domain, Data or Presentation responsibility')
    duplicates = [name for name,count in collections.Counter(p.name for p in sources).items() if count > 1]
    if duplicates: failures.append(f'Duplicate source basenames cause Xcode output collisions: {duplicates}')
    if failures:
        print('\n'.join(failures), file=sys.stderr)
        return False
    print(f'Architecture checks passed: {len(sources)} app sources, {len(domain)} domain files, {len(data)} data files.')
    return True

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--typecheck', action='store_true', help='compile domain sources without any implementation or UI sources')
    args = parser.parse_args()
    if not check(): return 1
    if args.typecheck:
        sources = sorted(str(p) for p in (ROOT/'CachePop').rglob('*.swift') if 'Domain' in p.parts)
        sources.append(str(ROOT/'CachePopShared/FanSample.swift'))
        command = ['xcrun', 'swiftc', '-typecheck', '-swift-version', '5', '-default-isolation', 'MainActor',
                   '-warnings-as-errors', '-module-cache-path', '/tmp/CachePop-architecture-module-cache'] + sources
        result = subprocess.run(command, cwd=ROOT)
        if result.returncode: return result.returncode
        print('Domain compiled independently with warnings treated as errors.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
