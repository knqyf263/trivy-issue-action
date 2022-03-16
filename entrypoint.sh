#!/bin/bash

if [ -z "$INPUT_LABEL" ]; then
    echo "INPUT_LABEL must be set."
    exit 1
fi

if [ -z "$INPUT_FILENAME" ]; then
    echo "INPUT_FILENAME must be set."
    exit 1
fi

if [ -z "$GITHUB_REPOSITORY" ]; then
    echo "GITHUB_REPOSITORY must be set."
    exit 1
fi

issues=$(gh --repo "$GITHUB_REPOSITORY" issue list --label "$INPUT_LABEL" --json title --jq '.[].title')

json_file=$(cat "$INPUT_FILENAME")
target_length=$(echo "$json_file" | jq length)

# Iterate targets
for i in $(seq 0 $((target_length - 1))); do
    vuln_length=$(echo "$json_file" | jq ".Results[$i].Vulnerabilities | length")

    # Iterate vulnerabilities
    for j in $(seq 0 $((vuln_length - 1))); do
        vuln=$(echo "$json_file" | jq ".Results[$i].Vulnerabilities[$j]")

        vuln_id=$(echo "$vuln" | jq -r ".VulnerabilityID")
        pkg_name=$(echo "$vuln" | jq -r ".PkgName")

        issue_title="$pkg_name: $vuln_id"
        echo "Processing $issue_title..."

        # Skip creating a new issue when the issue is already created
        if echo "$issues" | grep -q "^$issue_title$"; then
            echo "Already exists"
            continue
        fi

        title=$(echo "$vuln" | jq -r ".Title // empty")
        : ${title:='N/A'}

        description=$(echo "$vuln" | jq -r ".Description")
        severity=$(echo "$vuln" | jq -r ".Severity")
        primary_url=$(echo "$vuln" | jq -r ".PrimaryURL")
        references=$(echo "$vuln" | jq -r ".References | join(\"\n- \")")
        references="- ${references}" # for bullet points in markdown

        body=$(
            cat << EOF | envsubst
## Title
${title}

## Description
${description}

## Severity
${severity}

## Primary URL
${primary_url}

## References
${references}
EOF
        )

        if [ -n "$INPUT_ASSIGNEE" ]; then
            assignee="--assignee $INPUT_ASSIGNEE"
        fi

        # Create a new issue
        gh --repo "$GITHUB_REPOSITORY" issue create --title "$issue_title" --body "$body" --label "$INPUT_LABEL" $assignee
        echo ""
    done
done

# Associate issues with the specified project
if [ -n "$INPUT_PROJECT_ID" ]; then
    echo "Creating cards in the project $INPUT_PROJECT_ID..."
    issue_numbers=$(gh --repo "$GITHUB_REPOSITORY" issue list --label "$INPUT_LABEL" --json number --jq '.[].number')
    echo "$issue_numbers" | while read -r number; do
        issue_id=$(gh api /repos/${GITHUB_REPOSITORY}/issues/${number} --jq .id)
        gh api /projects/columns/${INPUT_PROJECT_ID}/cards -F content_id=$issue_id -F content_type="Issue"
    done
fi
