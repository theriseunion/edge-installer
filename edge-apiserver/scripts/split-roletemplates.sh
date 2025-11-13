#!/bin/bash

# 拆分 roletemplates.yaml 为多个文件
# 按 scope 分类：platform, cluster, workspace, nodegroup, namespace

TEMPLATES_DIR="../templates"
ROLETEMPLATES_DIR="${TEMPLATES_DIR}/roletemplates"
INPUT_FILE="${TEMPLATES_DIR}/roletemplates.yaml"

# 创建目录
mkdir -p "${ROLETEMPLATES_DIR}"

# 提取文件头部注释
echo "提取文件头部注释..."
head -4 "${INPUT_FILE}" > "${ROLETEMPLATES_DIR}/_header.yaml"

# 使用 awk 按 scope 拆分文件
echo "按 scope 拆分文件..."
awk '
BEGIN {
    scope = ""
    content = ""
    in_resource = 0
}

# 匹配资源开始
/^---$/ {
    if (content != "" && scope != "") {
        # 输出到对应的文件
        print content >> (outdir "/" scope "-roletemplates.yaml")
    }
    content = "---\n"
    in_resource = 1
    scope = ""
    next
}

# 在资源中查找 scope label
in_resource == 1 && /iam\.theriseunion\.io\/scope:/ {
    match($0, /scope: (.+)$/, arr)
    scope = arr[1]
    gsub(/^[ \t]+|[ \t]+$/, "", scope)  # trim
    # 将 global 替换为 platform
    if (scope == "global") {
        scope = "platform"
    }
}

# 累积内容
in_resource == 1 {
    content = content $0 "\n"
}

END {
    # 输出最后一个资源
    if (content != "" && scope != "") {
        print content >> (outdir "/" scope "-roletemplates.yaml")
    }
}
' outdir="${ROLETEMPLATES_DIR}" "${INPUT_FILE}"

echo "拆分完成！生成的文件："
ls -lh "${ROLETEMPLATES_DIR}"

echo ""
echo "各 scope 的 RoleTemplate 数量："
for file in "${ROLETEMPLATES_DIR}"/*-roletemplates.yaml; do
    if [ -f "$file" ]; then
        count=$(grep -c "^---$" "$file" 2>/dev/null || echo 0)
        echo "$(basename $file): $count 个 RoleTemplate"
    fi
done
