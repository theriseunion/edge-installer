#!/usr/bin/env python3
"""
拆分 roletemplates.yaml 为多个文件
按 scope 分类：platform, cluster, workspace, nodegroup, namespace
同时将 global scope 替换为 platform
"""

import os
import re
import yaml

# 路径配置
TEMPLATES_DIR = "../templates"
ROLETEMPLATES_DIR = os.path.join(TEMPLATES_DIR, "roletemplates")
INPUT_FILE = os.path.join(TEMPLATES_DIR, "roletemplates.yaml")

def main():
    # 创建目录
    os.makedirs(ROLETEMPLATES_DIR, exist_ok=True)

    # 读取整个文件
    with open(INPUT_FILE, 'r', encoding='utf-8') as f:
        content = f.read()

    # 提取头部注释（前4行）
    lines = content.split('\n')
    header = '\n'.join(lines[:4]) + '\n'

    # 按 --- 分割文档
    documents = content.split('\n---\n')

    # 按 scope 分组
    scopes = {}

    for doc in documents[1:]:  # 跳过头部
        if not doc.strip():
            continue

        # 查找 scope label
        scope_match = re.search(r'iam\.theriseunion\.io/scope:\s*(\w+)', doc)
        if scope_match:
            scope = scope_match.group(1)

            # 将 global 替换为 platform
            if scope == 'global':
                scope = 'platform'
                # 同时替换文档中的 scope label
                doc = re.sub(
                    r'(iam\.theriseunion\.io/scope:)\s*global',
                    r'\1 platform',
                    doc
                )
                # 替换 RoleTemplate name 中的 global- 为 platform-
                doc = re.sub(
                    r'(\s+name:\s+)global-',
                    r'\1platform-',
                    doc
                )

            if scope not in scopes:
                scopes[scope] = []

            scopes[scope].append(doc)

    # 写入各个 scope 的文件
    for scope, docs in scopes.items():
        output_file = os.path.join(ROLETEMPLATES_DIR, f"{scope}-roletemplates.yaml")

        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(header)
            for doc in docs:
                f.write('---\n')
                f.write(doc)
                if not doc.endswith('\n'):
                    f.write('\n')

        print(f"✓ {scope}-roletemplates.yaml: {len(docs)} 个 RoleTemplate")

    print(f"\n拆分完成！文件保存在: {ROLETEMPLATES_DIR}")
    print(f"总计: {sum(len(docs) for docs in scopes.values())} 个 RoleTemplate")

if __name__ == '__main__':
    main()
