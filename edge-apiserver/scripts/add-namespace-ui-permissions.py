#!/usr/bin/env python3
"""
为 Namespace RoleTemplate 添加 uiPermissions 字段并创建缺失的标准 RoleTemplate
Story 3: Namespace 层级 RoleTemplate 标准化
"""

import re

# RoleTemplate 名称到 uiPermissions 的映射
NAMESPACE_UI_PERMISSIONS = {
    # 工作负载管理
    'namespace-view-app-workloads': [
        'namespace/deployment.view',
        'namespace/statefulset.view',
        'namespace/daemonset.view',
        'namespace/job.view',
        'namespace/cronjob.view',
        'namespace/pod.view'
    ],
    'namespace-manage-app-workloads': [
        'namespace/deployment.view',
        'namespace/deployment.manage',
        'namespace/statefulset.view',
        'namespace/statefulset.manage',
        'namespace/daemonset.view',
        'namespace/daemonset.manage',
        'namespace/job.view',
        'namespace/job.manage',
        'namespace/cronjob.view',
        'namespace/cronjob.manage',
        'namespace/pod.view',
        'namespace/pod.manage',
        'namespace/pod.logs',
        'namespace/pod.terminal'
    ],

    # 配置管理
    'namespace-view-configmaps': ['namespace/configmap.view'],
    'namespace-manage-configmaps': ['namespace/configmap.view', 'namespace/configmap.manage'],
    'namespace-view-secrets': ['namespace/secret.view'],
    'namespace-manage-secrets': ['namespace/secret.view', 'namespace/secret.manage'],
    'namespace-view-serviceaccount': ['namespace/serviceaccount.view'],
    'namespace-manage-serviceaccount': ['namespace/serviceaccount.view', 'namespace/serviceaccount.manage'],

    # 存储管理
    'namespace-view-persistentvolumeclaims': ['namespace/persistentvolumeclaim.view'],
    'namespace-manage-persistentvolumeclaims': ['namespace/persistentvolumeclaim.view', 'namespace/persistentvolumeclaim.manage'],

    # 访问控制
    'namespace-view-members': ['namespace/member.view'],
    'namespace-manage-members': ['namespace/member.view', 'namespace/member.manage'],
    'namespace-view-roles': ['namespace/role.view'],
    'namespace-manage-roles': ['namespace/role.view', 'namespace/role.manage'],

    # 监控管理
    'namespace-view-monitoring': ['namespace/monitoring.view'],
    'namespace-manage-monitoring': ['namespace/monitoring.view', 'namespace/monitoring.manage'],

    # 应用发布
    'namespace-view-app-releases': ['namespace/app-release.view'],
    'namespace-create-app-releases': ['namespace/app-release.view', 'namespace/app-release.create'],
    'namespace-delete-app-releases': ['namespace/app-release.view', 'namespace/app-release.delete'],
    'namespace-manage-app-releases': ['namespace/app-release.view', 'namespace/app-release.manage'],

    # 项目设置
    'namespace-view-project-settings': ['namespace/project-settings.view'],
    'namespace-manage-project-settings': ['namespace/project-settings.view', 'namespace/project-settings.manage'],

    # 工作负载模板
    'namespace-view-workloadtemplates': ['namespace/workload-template.view'],
    'namespace-manage-workloadtemplates': ['namespace/workload-template.view', 'namespace/workload-template.manage'],

    # 通知
    'namespace-receive-notification': ['namespace/notification.receive'],

    # 告警（扩展）
    'monitor-alerting-agent-namespace-view-alerts': ['namespace/alert.view'],
    'monitor-alerting-agent-namespace-view-rulegroups': ['namespace/alert-rule.view'],
    'monitor-alerting-agent-namespace-manage-rulegroups': ['namespace/alert-rule.view', 'namespace/alert-rule.manage'],
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

        # 跳过空文档或注释
        if not doc.strip() or doc.strip().startswith('#'):
            continue

        # 查找 RoleTemplate name
        name_match = re.search(r'^\s+name:\s+(\S+)$', doc, re.MULTILINE)
        if not name_match:
            continue

        name = name_match.group(1)

        # 检查是否需要添加 uiPermissions
        if name not in NAMESPACE_UI_PERMISSIONS:
            print(f"⚠️  {name} 不在映射表中，跳过")
            continue

        # 检查是否已有 uiPermissions
        if 'uiPermissions:' in doc:
            print(f"⚠️  {name} 已有 uiPermissions，跳过")
            continue

        permissions = NAMESPACE_UI_PERMISSIONS[name]

        # 在 spec: 下的第一个字段前插入 uiPermissions
        spec_match = re.search(r'^spec:$', doc, re.MULTILINE)
        if not spec_match:
            print(f"⚠️  {name} 未找到 spec: 字段")
            continue

        # 构造 uiPermissions YAML
        ui_perms_yaml = "  uiPermissions:\n"
        for perm in permissions:
            ui_perms_yaml += f"    - {perm}\n"

        # 在 spec: 后的下一行插入
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

def create_new_roletemplates():
    """生成新的标准 RoleTemplate 定义"""

    new_templates = """---
# 新增标准 RoleTemplate - Story 3
# Services 管理
---
apiVersion: iam.theriseunion.io/v1alpha1
kind: RoleTemplate
metadata:
  labels:
    app.kubernetes.io/managed-by: Helm
    iam.theriseunion.io/category: namespace-service-network
    iam.theriseunion.io/scope: namespace
    theriseunion.io/managed: 'true'
    iam.theriseunion.io/scope-value: default
    iam.theriseunion.io/aggregate-to-namespace-viewer: "true"
  name: namespace-view-services
spec:
  uiPermissions:
    - namespace/service.view
    - namespace/ingress.view
  displayName:
    zh: 查看服务
    en: View Services
  description:
    zh: 允许查看命名空间内的服务和路由
    en: Allows viewing services and ingresses within the namespace
  rules:
  - apiGroups:
    - '*'
    resources:
    - services
    - ingresses
    verbs:
    - get
    - list
    - watch
---
apiVersion: iam.theriseunion.io/v1alpha1
kind: RoleTemplate
metadata:
  annotations:
    iam.theriseunion.io/dependencies: '["namespace-view-services"]'
  labels:
    app.kubernetes.io/managed-by: Helm
    iam.theriseunion.io/category: namespace-service-network
    iam.theriseunion.io/scope: namespace
    theriseunion.io/managed: 'true'
    iam.theriseunion.io/scope-value: default
    iam.theriseunion.io/aggregate-to-namespace-operator: "true"
  name: namespace-manage-services
spec:
  uiPermissions:
    - namespace/service.view
    - namespace/service.manage
    - namespace/ingress.view
    - namespace/ingress.manage
  displayName:
    zh: 管理服务
    en: Manage Services
  description:
    zh: 允许管理命名空间内的服务和路由
    en: Allows managing services and ingresses within the namespace
  rules:
  - apiGroups:
    - '*'
    resources:
    - services
    - ingresses
    verbs:
    - '*'
---
# Workloads 标准命名 (保留 app-workloads 兼容)
---
apiVersion: iam.theriseunion.io/v1alpha1
kind: RoleTemplate
metadata:
  annotations:
    iam.theriseunion.io/standard-name-for: namespace-view-app-workloads
    iam.theriseunion.io/dependencies: '["namespace-view-persistentvolumeclaims","namespace-view-secrets","namespace-view-configmaps"]'
  labels:
    app.kubernetes.io/managed-by: Helm
    iam.theriseunion.io/category: namespace-application-workloads
    iam.theriseunion.io/scope: namespace
    theriseunion.io/managed: 'true'
    iam.theriseunion.io/scope-value: default
    iam.theriseunion.io/aggregate-to-namespace-viewer: "true"
  name: namespace-view-workloads
spec:
  uiPermissions:
    - namespace/deployment.view
    - namespace/statefulset.view
    - namespace/daemonset.view
    - namespace/job.view
    - namespace/cronjob.view
    - namespace/pod.view
  displayName:
    zh: 查看工作负载
    en: View Workloads
  description:
    zh: 允许查看命名空间内的所有工作负载资源（标准命名版本）
    en: Allows viewing all workload resources within the namespace (standard naming)
  rules:
  - apiGroups:
    - '*'
    resources:
    - applications
    - controllerrevisions
    - deployments
    - replicasets
    - statefulsets
    - daemonsets
    - jobs
    - cronjobs
    - pods
    - pods/log
    - pods/containers
    - horizontalpodautoscalers
    - configmaps
    - secrets
    verbs:
    - get
    - list
    - watch
---
apiVersion: iam.theriseunion.io/v1alpha1
kind: RoleTemplate
metadata:
  annotations:
    iam.theriseunion.io/standard-name-for: namespace-manage-app-workloads
    iam.theriseunion.io/dependencies: '["namespace-view-workloads"]'
  labels:
    app.kubernetes.io/managed-by: Helm
    iam.theriseunion.io/category: namespace-application-workloads
    iam.theriseunion.io/scope: namespace
    theriseunion.io/managed: 'true'
    iam.theriseunion.io/scope-value: default
    iam.theriseunion.io/aggregate-to-namespace-operator: "true"
  name: namespace-manage-workloads
spec:
  uiPermissions:
    - namespace/deployment.view
    - namespace/deployment.manage
    - namespace/statefulset.view
    - namespace/statefulset.manage
    - namespace/daemonset.view
    - namespace/daemonset.manage
    - namespace/job.view
    - namespace/job.manage
    - namespace/cronjob.view
    - namespace/cronjob.manage
    - namespace/pod.view
    - namespace/pod.manage
    - namespace/pod.logs
    - namespace/pod.terminal
  displayName:
    zh: 管理工作负载
    en: Manage Workloads
  description:
    zh: 允许管理命名空间内的所有工作负载资源（标准命名版本）
    en: Allows managing all workload resources within the namespace (standard naming)
  rules:
  - apiGroups:
    - '*'
    resources:
    - services
    - applications
    - controllerrevisions
    - deployments
    - replicasets
    - statefulsets
    - daemonsets
    - jobs
    - cronjobs
    - pods
    - pods/log
    - pods/exec
    - pods/containers
    - services
    - ingresses
    - router
    - workloads
    - horizontalpodautoscalers
    verbs:
    - '*'
  - apiGroups:
    - '*'
    resources:
    - secrets
    verbs:
    - list
---
# Config-Storage 整合 RoleTemplate
---
apiVersion: iam.theriseunion.io/v1alpha1
kind: RoleTemplate
metadata:
  annotations:
    iam.theriseunion.io/aggregates: '["namespace-view-configmaps","namespace-view-secrets","namespace-view-persistentvolumeclaims"]'
  labels:
    app.kubernetes.io/managed-by: Helm
    iam.theriseunion.io/category: namespace-configuration-storage
    iam.theriseunion.io/scope: namespace
    theriseunion.io/managed: 'true'
    iam.theriseunion.io/scope-value: default
    iam.theriseunion.io/aggregate-to-namespace-viewer: "true"
  name: namespace-view-config-storage
spec:
  uiPermissions:
    - namespace/configmap.view
    - namespace/secret.view
    - namespace/persistentvolumeclaim.view
  displayName:
    zh: 查看配置与存储
    en: View Config & Storage
  description:
    zh: 允许查看配置字典、保密字典和持久卷声明（整合权限）
    en: Allows viewing configmaps, secrets and PVCs (aggregated permission)
  rules:
  - apiGroups:
    - '*'
    resources:
    - configmaps
    - secrets
    - persistentvolumeclaims
    verbs:
    - get
    - list
    - watch
  - apiGroups:
    - '*'
    resources:
    - pods
    verbs:
    - list
---
apiVersion: iam.theriseunion.io/v1alpha1
kind: RoleTemplate
metadata:
  annotations:
    iam.theriseunion.io/dependencies: '["namespace-view-config-storage"]'
    iam.theriseunion.io/aggregates: '["namespace-manage-configmaps","namespace-manage-secrets","namespace-manage-persistentvolumeclaims"]'
  labels:
    app.kubernetes.io/managed-by: Helm
    iam.theriseunion.io/category: namespace-configuration-storage
    iam.theriseunion.io/scope: namespace
    theriseunion.io/managed: 'true'
    iam.theriseunion.io/scope-value: default
    iam.theriseunion.io/aggregate-to-namespace-operator: "true"
  name: namespace-manage-config-storage
spec:
  uiPermissions:
    - namespace/configmap.view
    - namespace/configmap.manage
    - namespace/secret.view
    - namespace/secret.manage
    - namespace/persistentvolumeclaim.view
    - namespace/persistentvolumeclaim.manage
  displayName:
    zh: 管理配置与存储
    en: Manage Config & Storage
  description:
    zh: 允许管理配置字典、保密字典和持久卷声明（整合权限）
    en: Allows managing configmaps, secrets and PVCs (aggregated permission)
  rules:
  - apiGroups:
    - '*'
    resources:
    - configmaps
    - secrets
    - persistentvolumeclaims
    verbs:
    - '*'
  - apiGroups:
    - '*'
    resources:
    - pods
    verbs:
    - list
"""

    return new_templates

def main():
    file_path = '../templates/roletemplates/namespace-roletemplates.yaml'

    print("=" * 60)
    print("Story 3: Namespace RoleTemplate 标准化")
    print("=" * 60)
    print()

    print("步骤 1: 为现有 RoleTemplate 添加 uiPermissions...")
    print("-" * 60)
    count = add_ui_permissions_to_file(file_path)
    print()
    print(f"✓ 完成！共更新了 {count} 个 RoleTemplate")
    print()

    print("步骤 2: 添加新的标准 RoleTemplate...")
    print("-" * 60)
    new_templates = create_new_roletemplates()

    with open(file_path, 'a', encoding='utf-8') as f:
        f.write('\n' + new_templates)

    print("✓ 添加了 6 个新的标准 RoleTemplate:")
    print("  - namespace-view-services")
    print("  - namespace-manage-services")
    print("  - namespace-view-workloads (标准命名)")
    print("  - namespace-manage-workloads (标准命名)")
    print("  - namespace-view-config-storage (整合)")
    print("  - namespace-manage-config-storage (整合)")
    print()

    print("=" * 60)
    print("完成！Namespace RoleTemplate 标准化已完成")
    print("=" * 60)

if __name__ == '__main__':
    main()
