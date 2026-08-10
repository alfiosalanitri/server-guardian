#!/bin/bash
# Tags a new release. Looks at the commits since the last tag, suggests a
# semver bump from their conventional-commit prefixes (feat -> minor,
# fix -> patch, "!"/BREAKING CHANGE -> major), lets you confirm or override
# it, then creates and pushes the tag. Pushing the tag triggers the
# .github/workflows/release.yml GitHub Action.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { printf "${GREEN}[+]${NC} %s\n" "$*"; }
warning() { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
error()   { printf "${RED}[x]${NC} %s\n" "$*"; exit 1; }

cd "$(git rev-parse --show-toplevel)"

[ -z "$(git status --porcelain)" ] || error "Working tree is not clean. Commit or stash your changes first."

git fetch --tags --quiet

last_tag=$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n1)

if [ -z "$last_tag" ]; then
  warning "No previous tag found, this will be the first release."
  range="HEAD"
  last_version="0.0.0"
else
  range="$last_tag..HEAD"
  last_version="${last_tag#v}"
fi

commits=$(git log "$range" --pretty=format:'%s')
[ -n "$commits" ] || error "No commits since ${last_tag:-the beginning}. Nothing to release."

echo ""
info "Commits since ${last_tag:-the beginning}:"
echo "$commits" | sed 's/^/    /'
echo ""

# Suggest a bump from conventional-commit prefixes.
bump="patch"
if echo "$commits" | grep -Eiq '^[a-z]+(\([^)]*\))?!:|BREAKING CHANGE'; then
  bump="major"
elif echo "$commits" | grep -Eiq '^feat(\([^)]*\))?:'; then
  bump="minor"
elif echo "$commits" | grep -Eiq '^fix(\([^)]*\))?:'; then
  bump="patch"
fi

IFS='.' read -r major minor patch <<< "$last_version"
case "$bump" in
  major) suggested="$((major + 1)).0.0" ;;
  minor) suggested="$major.$((minor + 1)).0" ;;
  patch) suggested="$major.$minor.$((patch + 1))" ;;
esac

info "Current version : v$last_version"
info "Suggested bump  : $bump -> v$suggested"
echo ""

read -r -p "New version [v$suggested]: " new_version
new_version="${new_version:-v$suggested}"
[[ "$new_version" == v* ]] || new_version="v$new_version"

[[ "$new_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || error "\"$new_version\" is not a valid semver tag (expected vX.Y.Z)."
git rev-parse "$new_version" >/dev/null 2>&1 && error "Tag $new_version already exists."

echo ""
read -r -p "Create and push tag $new_version? [y/N]: " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { warning "Aborted, no tag created."; exit 0; }

git tag -a "$new_version" -m "$new_version"
git push origin "$new_version"

info "Tag $new_version pushed. GitHub Actions will build the release."
