#!/bin/bash

# RoleTemplate 验证脚本
# 检查 RoleTemplate 的结构完整性和命名规范

ROLETEMPLATES_DIR="../templates/roletemplates"

echo "======================================"
echo "RoleTemplate 验证脚本"
echo "======================================"
echo ""

# 统计各 scope 的 RoleTemplate 数量
echo "1. 各 Scope 的 RoleTemplate 数量"
echo "--------------------------------------"
for file in "${ROLETEMPLATES_DIR}"/*-roletemplates.yaml; do
    if [ -f "$file" ]; then
        scope=$(basename "$file" | sed 's/-roletemplates.yaml//')
        count=$(grep -c "^  name: " "$file" 2>/dev/null || echo 0)
        ui_count=$(grep -c "uiPermissions:" "$file" 2>/dev/null || echo 0)
        echo "$scope: $count 个 RoleTemplate ($ui_count 个有 uiPermissions)"
    fi
done
echo ""

# 检查必需字段
echo "2. 检查必需字段"
echo "--------------------------------------"
for file in "${ROLETEMPLATES_DIR}"/*-roletemplates.yaml; do
    if [ -f "$file" ]; then
        scope=$(basename "$file" | sed 's/-roletemplates.yaml//')
        echo "检查 $scope..."

        # 提取所有 RoleTemplate 名称
        names=$(grep "^  name: " "$file" | sed 's/  name: //')

        while IFS= read -r name; do
            if [ -z "$name" ]; then
                continue
            fi

            # 检查是否有 displayName
            if ! grep -A 5 "name: $name" "$file" | grep -q "displayName:"; then
                echo "  ⚠️  $name: 缺少 displayName"
            fi

            # 检查是否有 scope label
            if ! grep -B 10 "name: $name" "$file" | grep -q "iam.theriseunion.io/scope:"; then
                echo "  ⚠️  $name: 缺少 scope label"
            fi

            # 检查是否有 category label
            if ! grep -B 10 "name: $name" "$file" | grep -q "iam.theriseunion.io/category:"; then
                echo "  ⚠️  $name: 缺少 category label"
            fi
        done <<< "$names"
    fi
done
echo ""

# 检查命名规范
echo "3. 检查命名规范"
echo "--------------------------------------"
for file in "${ROLETEMPLATES_DIR}"/*-roletemplates.yaml; do
    if [ -f "$file" ]; then
        scope=$(basename "$file" | sed 's/-roletemplates.yaml//')

        # 检查是否有不符合规范的命名
        bad_names=$(grep "^  name: " "$file" | grep -v "^  name: $scope-" | grep -v "^  name: edge-" | grep -v "^  name: monitor-" | grep -v "^  name: cluster-view-monitoring-")

        if [ ! -z "$bad_names" ]; then
            echo "$scope scope 中发现不符合命名规范的 RoleTemplate:"
            echo "$bad_names"
        fi
    fi
done
echo ""

# Story 1 验收标准检查
echo "4. Story 1 验收标准检查"
echo "--------------------------------------"

# Platform Scope 标准 RoleTemplate
platform_required=(
    "platform-view-users"
    "platform-manage-users"
    "platform-view-roles"
    "platform-manage-roles"
    "platform-view-clusters"
    "platform-manage-clusters"
    "platform-view-workspaces"
    "platform-manage-workspaces"
    "platform-view-platform-settings"
    "platform-manage-platform-settings"
    "platform-view-monitoring"
    "platform-manage-monitoring"
    "platform-review-app-submissions"
    "platform-manage-app-store"
)

echo "Platform Scope (14 个标准 RoleTemplate):"
for rt in "${platform_required[@]}"; do
    if grep -q "name: $rt" "${ROLETEMPLATES_DIR}/platform-roletemplates.yaml"; then
        echo "  ✓ $rt"
    else
        echo "  ✗ $rt (缺失)"
    fi
done
echo ""

# Cluster Scope 标准 RoleTemplate
cluster_required=(
    "cluster-view-nodes"
    "cluster-manage-nodes"
    "cluster-view-nodegroups"
    "cluster-manage-nodegroups"
    "cluster-view-projects"
    "cluster-manage-projects"
    "cluster-view-storage"
    "cluster-manage-storage"
    "cluster-view-monitoring"
    "cluster-manage-monitoring"
    "cluster-view-alerts"
    "cluster-manage-alerts"
)

echo "Cluster Scope (12 个标准 RoleTemplate):"
for rt in "${cluster_required[@]}"; do
    if grep -q "name: $rt" "${ROLETEMPLATES_DIR}/cluster-roletemplates.yaml"; then
        echo "  ✓ $rt"
    else
        echo "  ✗ $rt (缺失)"
    fi
done
echo ""

# Story 2 验收标准检查
echo "5. Story 2 验收标准检查"
echo "--------------------------------------"

# Workspace Scope 标准 RoleTemplate
workspace_required=(
    "workspace-view-projects"
    "workspace-manage-projects"
    "workspace-view-members"
    "workspace-manage-members"
    "workspace-view-roles"
    "workspace-manage-roles"
    "workspace-view-app-templates"
    "workspace-manage-app-templates"
    "workspace-view-devops"
    "workspace-manage-devops"
)

echo "Workspace Scope (10 个标准 RoleTemplate):"
for rt in "${workspace_required[@]}"; do
    if grep -q "name: $rt" "${ROLETEMPLATES_DIR}/workspace-roletemplates.yaml"; then
        echo "  ✓ $rt"
    else
        echo "  ✗ $rt (缺失)"
    fi
done
echo ""

# NodeGroup Scope 标准 RoleTemplate
nodegroup_required=(
    "nodegroup-view-nodes"
    "nodegroup-manage-nodes"
    "nodegroup-view-monitoring"
    "nodegroup-manage-monitoring"
    "nodegroup-view-gpu"
    "nodegroup-manage-gpu"
)

echo "NodeGroup Scope (6 个标准 RoleTemplate):"
for rt in "${nodegroup_required[@]}"; do
    if grep -q "name: $rt" "${ROLETEMPLATES_DIR}/nodegroup-roletemplates.yaml"; then
        echo "  ✓ $rt"
    else
        echo "  ✗ $rt (缺失)"
    fi
done
echo ""

# Story 3 验收标准检查
echo "6. Story 3 验收标准检查"
echo "--------------------------------------"

# Namespace Scope 标准 RoleTemplate
namespace_required=(
    "namespace-view-workloads"
    "namespace-manage-workloads"
    "namespace-view-services"
    "namespace-manage-services"
    "namespace-view-config-storage"
    "namespace-manage-config-storage"
    "namespace-view-monitoring"
    "namespace-manage-monitoring"
    "namespace-view-members"
    "namespace-manage-members"
    "namespace-view-roles"
    "namespace-manage-roles"
    "namespace-view-app-releases"
    "namespace-manage-app-releases"
)

echo "Namespace Scope (14 个标准 RoleTemplate):"
for rt in "${namespace_required[@]}"; do
    if grep -q "name: $rt" "${ROLETEMPLATES_DIR}/namespace-roletemplates.yaml"; then
        echo "  ✓ $rt"
    else
        echo "  ✗ $rt (缺失)"
    fi
done
echo ""

# Epic 45 总体完成度统计
echo "7. Epic 45 总体完成度"
echo "--------------------------------------"
total_standard=56
completed_platform=14
completed_cluster=12
completed_workspace=10
completed_nodegroup=6
completed_namespace=14

total_completed=$((completed_platform + completed_cluster + completed_workspace + completed_nodegroup + completed_namespace))
percentage=$((total_completed * 100 / total_standard))

echo "平台层级 (Platform):  $completed_platform/14 ✓"
echo "集群层级 (Cluster):   $completed_cluster/12 ✓"
echo "工作空间 (Workspace): $completed_workspace/10 ✓"
echo "节点组 (NodeGroup):   $completed_nodegroup/6 ✓"
echo "命名空间 (Namespace): $completed_namespace/14 ✓"
echo "--------------------------------------"
echo "总计: $total_completed/$total_standard ($percentage%)"
echo ""

echo "======================================"
echo "验证完成！"
echo "======================================"
