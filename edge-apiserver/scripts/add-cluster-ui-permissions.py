#!/usr/bin/env python3
"""
为现有 Cluster RoleTemplate 添加 uiPermissions 字段
"""

import re

# RoleTemplate 名称到 uiPermissions 的映射
CLUSTER_UI_PERMISSIONS = {
    'cluster-view-nodes': ['cluster/node.view'],
    'cluster-manage-nodes': ['cluster/node.view', 'cluster/node.manage', 'cluster/node.terminal'],
    'cluster-view-nodegroup': ['cluster/nodegroup.view'],
    'cluster-manage-nodegroup': ['cluster/nodegroup.view', 'cluster/nodegroup.manage'],
    'cluster-view-projects': ['cluster/namespace.view'],
    'cluster-manage-projects': ['cluster/namespace.view', 'cluster/namespace.manage'],
    'cluster-view-monitoring': ['cluster/monitoring.view'],
    'cluster-manage-monitoring': ['cluster/monitoring.view', 'cluster/monitoring.manage'],
    'cluster-view-members': ['cluster/member.view'],
    'cluster-manage-members': ['cluster/member.view', 'cluster/member.manage'],
    'cluster-view-roles': ['cluster/role.view'],
    'cluster-manage-roles': ['cluster/role.view', 'cluster/role.manage'],
}

def add_ui_permissions_to_file(file_path):
    """为指定文件中的 RoleTemplate 添加 uiPermissions"""

    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 分割为多个 RoleTemplate 文档
    documents = content.split('\n---\n')

    updated_count = 0
    for i in range(len(documents)):
        doc = documents[i]

        # 查找 RoleTemplate name
        name_match = re.search(r'^\s+name:\s+(\S+)$', doc, re.MULTILINE)
        if not name_match:
            continue

        name = name_match.group(1)

        # 检查是否需要添加 uiPermissions
        if name not in CLUSTER_UI_PERMISSIONS:
            continue

        # 检查是否已有 uiPermissions
        if 'uiPermissions:' in doc:
            print(f"⚠️  {name} 已有 uiPermissions，跳过")
            continue

        permissions = CLUSTER_UI_PERMISSIONS[name]

        # 在 spec: 下的 displayName 前插入 uiPermissions
        spec_match = re.search(r'^spec:$', doc, re.MULTILINE)
        if not spec_match:
            print(f"⚠️  {name} 未找到 spec: 字段")
            continue

        # 构造 uiPermissions YAML
        ui_perms_yaml = "  uiPermissions:\n"
        for perm in permissions:
            ui_perms_yaml += f"    - {perm}\n"

        # 在 displayName 前插入
        doc = re.sub(
            r'(^spec:$\n)',
            f'\\1{ui_perms_yaml}',
            doc,
            flags=re.MULTILINE
        )

        documents[i] = doc
        updated_count += 1
        print(f"✓ {name}: 添加了 {len(permissions)} 个 uiPermissions")

    # 重新组合
    new_content = '\n---\n'.join(documents)

    # 写回文件
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(new_content)

    return updated_count

def main():
    file_path = '../templates/roletemplates/cluster-roletemplates.yaml'

    print("开始为 Cluster RoleTemplate 添加 uiPermissions...")
    print()

    count = add_ui_permissions_to_file(file_path)

    print()
    print(f"完成！共更新了 {count} 个 RoleTemplate")

if __name__ == '__main__':
    main()
