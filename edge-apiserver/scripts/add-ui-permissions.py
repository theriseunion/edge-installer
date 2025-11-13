#!/usr/bin/env python3
"""
为现有 Platform RoleTemplate 添加 uiPermissions 字段
"""

import re

# RoleTemplate 名称到 uiPermissions 的映射
PLATFORM_UI_PERMISSIONS = {
    'platform-view-users': ['platform/user.view'],
    'platform-manage-users': ['platform/user.view', 'platform/user.manage'],
    'platform-view-roles': ['platform/role.view'],
    'platform-manage-roles': ['platform/role.view', 'platform/role.manage'],
    'platform-view-clusters': ['platform/cluster.view'],
    'platform-manage-clusters': ['platform/cluster.view', 'platform/cluster.manage'],
    'platform-view-workspaces': ['platform/workspace.view'],
    'platform-manage-workspaces': ['platform/workspace.view', 'platform/workspace.manage'],
    'platform-manage-platform-settings': ['platform/settings.view', 'platform/settings.manage'],
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
        if name not in PLATFORM_UI_PERMISSIONS:
            continue

        # 检查是否已有 uiPermissions
        if 'uiPermissions:' in doc:
            print(f"⚠️  {name} 已有 uiPermissions，跳过")
            continue

        permissions = PLATFORM_UI_PERMISSIONS[name]

        # 在 spec: 下的 displayName 前插入 uiPermissions
        # 找到 spec: 的位置
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
    file_path = '../templates/roletemplates/platform-roletemplates.yaml'

    print("开始为 Platform RoleTemplate 添加 uiPermissions...")
    print()

    count = add_ui_permissions_to_file(file_path)

    print()
    print(f"完成！共更新了 {count} 个 RoleTemplate")

if __name__ == '__main__':
    main()
