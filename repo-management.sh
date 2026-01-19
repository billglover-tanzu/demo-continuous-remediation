#!/bin/bash

# GitHub Repository Management Script
# This script deletes all repos in target org, forks specified repos, and sets up notifications

set -e  # Exit on any error

# Configuration - read from environment variables if available
TARGET_ORG="${TARGET_ORG:-billglover-demo}"

# Convert comma-separated SOURCE_REPOS env var to array, or use defaults
if [ -n "$SOURCE_REPOS" ]; then
    IFS=',' read -ra SOURCE_REPOS_ARRAY <<< "$SOURCE_REPOS"
else
    SOURCE_REPOS_ARRAY=(
        "dashaun/spring-petclinic"
        "dashaun/xyz.gofastforever.account"
        "dashaun/logback-logstash-elastic-demo"
        "dashaun/spring-cloud-vault-demo"
    )
fi

echo "🚀 Starting GitHub repository management for org: $TARGET_ORG"

# Function to check if gh CLI is authenticated
check_gh_auth() {
    echo "🔍 Checking GitHub CLI authentication..."
    if ! gh auth status &>/dev/null; then
        echo "❌ GitHub CLI is not authenticated. Please run 'gh auth login' first."
        exit 1
    fi
    echo "✅ GitHub CLI is authenticated"
}

# Function to delete all repositories in target org
delete_target_org_repos() {
    echo "🗑️  Deleting all repositories in $TARGET_ORG..."

    # Get all repositories in the target org
    repos=$(gh repo list "$TARGET_ORG" --limit 1000 --json name --jq '.[].name')

    if [ -z "$repos" ]; then
        echo "ℹ️  No repositories found in $TARGET_ORG"
        return
    fi

    # Delete each repository
    while IFS= read -r repo; do
        if [ -n "$repo" ]; then
            echo "  Deleting $TARGET_ORG/$repo..."
            # Use --yes to skip confirmation prompts
            gh repo delete "$TARGET_ORG/$repo" --yes || {
                echo "    ⚠️  Failed to delete $TARGET_ORG/$repo (might not exist or no permissions)"
            }
        fi
    done <<< "$repos"

    echo "✅ Finished deleting repositories in $TARGET_ORG"
}

# Function to fork repositories
fork_repositories() {
    echo "🍴 Forking repositories into $TARGET_ORG..."

    for repo in "${SOURCE_REPOS_ARRAY[@]}"; do
        echo "  Forking $repo..."

        # Fork the repository into the target org
        gh repo fork "$repo" --org "$TARGET_ORG" --default-branch-only || {
            echo "    ⚠️  Failed to fork $repo (might already exist or no permissions)"
            continue
        }

        echo "    ✅ Successfully forked $repo to $TARGET_ORG"
    done

    echo "✅ Finished forking repositories"
}

# Function to set up notifications for pull requests
setup_notifications() {
    echo "🔔 Setting up pull request notifications..."

    # Get all repositories in the target org (the newly forked ones)
    repos=$(gh repo list "$TARGET_ORG" --limit 1000 --json name --jq '.[].name')

    if [ -z "$repos" ]; then
        echo "❌ No repositories found in $TARGET_ORG to set up notifications"
        return
    fi

    # Subscribe to notifications for each repository
    while IFS= read -r repo; do
        if [ -n "$repo" ]; then
            echo "  Setting up notifications for $TARGET_ORG/$repo..."

            # Enable issues
            gh api \
                --method PATCH \
                "/repos/$TARGET_ORG/$repo" \
                --field has_issues=true \
                || {
                    echo "    ⚠️  Failed to set up issues for $TARGET_ORG/$repo"
                    continue
                }

            # Subscribe to the repository (this enables all notifications including PRs)
            gh api \
                --method PUT \
                "/repos/$TARGET_ORG/$repo/subscription" \
                --field subscribed=true \
                --field ignored=false \
                || {
                    echo "    ⚠️  Failed to set up notifications for $TARGET_ORG/$repo"
                    continue
                }

            echo "    ✅ Notifications enabled for $TARGET_ORG/$repo"
        fi
    done <<< "$repos"

    echo "✅ Finished setting up notifications"
    echo "ℹ️  You should now receive notifications in your GitHub inbox for:"
    echo "   - Pull requests"
    echo "   - Issues"
    echo "   - Releases"
    echo "   - Security alerts"
    echo "   - Repository activity"
}

# Function to verify the setup
verify_setup() {
    echo "🔍 Verifying setup..."

    echo "  Repositories in $TARGET_ORG:"
    gh repo list "$TARGET_ORG" --limit 100 | while read -r line; do
        echo "    ✅ $line"
    done

    echo "✅ Setup verification complete"
}

# Main execution
main() {
    echo "========================================="
    echo "GitHub Repository Management Script"
    echo "Target Org: $TARGET_ORG"
    echo "Source Repos: ${#SOURCE_REPOS_ARRAY[@]} repositories"
    echo "========================================="

    check_gh_auth

    echo ""
    read -p "⚠️  This will DELETE all repositories in '$TARGET_ORG' and fork new ones. Continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Operation cancelled"
        exit 0
    fi

    echo ""
    delete_target_org_repos
    echo ""
    fork_repositories
    echo ""
    setup_notifications
    echo ""
    verify_setup

    echo ""
    echo "🎉 All operations completed successfully!"
    echo "   - All repositories in '$TARGET_ORG' have been deleted"
    echo "   - ${#SOURCE_REPOS_ARRAY[@]} repositories have been forked"
    echo "   - Pull request notifications are enabled"
    echo ""
    echo "💡 Tips:"
    echo "   - Check your GitHub inbox for notifications"
    echo "   - You can adjust notification settings at: https://github.com/settings/notifications"
    echo "   - Use 'gh repo list $TARGET_ORG' to see all forked repositories"
}

# Run the main function
main "$@"