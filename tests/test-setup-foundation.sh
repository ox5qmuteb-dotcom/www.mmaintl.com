#!/usr/bin/env bash

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SETUP_SCRIPT="$ROOT/setup-foundation.sh"
HOOK_SOURCE="$ROOT/scripts/hooks/pre-commit"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEMP_DIR"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    grep -Fq -- "$2" "$1" || fail "Expected '$2' in $1"
}

new_repository() {
    local directory=$1
    mkdir -p -- "$directory"
    git -C "$directory" init -q
    mkdir -p -- "$directory/scripts/hooks"
    cp -- "$HOOK_SOURCE" "$directory/scripts/hooks/pre-commit"
}

run_setup() {
    local directory=$1
    shift
    local -a environment=() options=()
    local argument
    for argument in "$@"; do
        if [[ $argument == --* ]]; then
            options+=("$argument")
        else
            environment+=("$argument")
        fi
    done
    (cd -- "$directory" && env "${environment[@]}" bash "$SETUP_SCRIPT" --non-interactive "${options[@]}" >"$directory/setup.log" 2>&1)
}

remote_cases=(
    'https://github.com/team-sample/project-name.git'
    'https://github.com/team-sample/project-name'
    'git@github.com:team-sample/project-name.git'
    'ssh://git@github.com/team-sample/project-name/'
)

index=0
for remote in "${remote_cases[@]}"; do
    directory="$TEMP_DIR/remote-$index"
    new_repository "$directory"
    git -C "$directory" remote add origin "$remote"
    run_setup "$directory" GITHUB_BRANCH=release/2026
    assert_contains "$directory/.env.example" 'GITHUB_OWNER=team-sample'
    assert_contains "$directory/.env.example" 'GITHUB_REPO=project-name'
    [[ ! -e $directory/.env ]] || fail "Created .env for $remote"
    [[ ! -e $directory/package.json ]] || fail "Created package.json for $remote"
    assert_contains "$directory/setup.log" 'package.json غير موجود'
    [[ -x $directory/.git/hooks/pre-commit ]] || fail "Hook not installed for $remote"
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' \
        "$directory/.github/config/sramm.config.json" || fail "Invalid config JSON for $remote"
    ((index += 1))
done
printf 'PASS: HTTPS/SSH remotes with and without .git\n'

directory="$TEMP_DIR/no-remote"
new_repository "$directory"
if run_setup "$directory"; then fail "Accepted missing owner/repo in non-interactive mode"; fi
assert_contains "$directory/setup.log" 'عيّنه عبر متغير البيئة'

directory="$TEMP_DIR/env-no-remote"
new_repository "$directory"
run_setup "$directory" REPO_OWNER=group-one REPO_NAME=repo-one ENVIRONMENT_NAME=staging \
    REQUIRED_REVIEWER=reviewer-one RUNNER_LABELS=self-hosted,linux,secure
assert_contains "$directory/.env.example" 'ENVIRONMENT_NAME=staging'
assert_contains "$directory/.env.example" 'REQUIRED_REVIEWER=reviewer-one'
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' \
    "$directory/.github/config/sramm.config.json" || fail 'Invalid JSON with environment overrides'
printf 'PASS: missing remote, non-interactive failure, and configurable values\n'

directory="$TEMP_DIR/preserved"
new_repository "$directory"
git -C "$directory" remote add origin https://github.com/team-sample/preserved
printf 'local secret stays local\n' >"$directory/.env"
printf 'keep this user template\n' >"$directory/.env.example"
run_setup "$directory"
[[ $(cat "$directory/.env") == 'local secret stays local' ]] || fail 'Changed existing .env'
[[ $(cat "$directory/.env.example") == 'keep this user template' ]] || fail 'Changed existing .env.example'
run_setup "$directory" --force
[[ $(cat "$directory/.env") == 'local secret stays local' ]] || fail '--force changed .env'
[[ -n $(find "$directory/.git/foundation-setup-backups" -type f -print -quit) ]] || fail 'Missing template backup'
assert_contains "$directory/.gitignore" '!.env.example'
if grep -Fqx 'package-lock.json' "$directory/.gitignore"; then fail 'Ignored package-lock.json'; fi
if grep -Eqi 'moteb|example\.com' "$directory/.env.example" "$directory/.github/config/sramm.config.json"; then
    fail 'Found hardcoded personal configuration'
fi
printf 'PASS: .env preservation, explicit template backup, and clean defaults\n'

directory="$TEMP_DIR/kept-hook"
new_repository "$directory"
git -C "$directory" remote add origin https://github.com/team-sample/kept-hook
printf '#!/usr/bin/env bash\necho custom\n' >"$directory/.git/hooks/pre-commit"
run_setup "$directory"
assert_contains "$directory/.git/hooks/pre-commit" 'echo custom'
printf 'PASS: existing local hook is preserved\n'

fake_bin="$TEMP_DIR/fake-bin"
mkdir -p -- "$fake_bin"
cat >"$fake_bin/node" <<'EOF'
#!/usr/bin/env bash
[[ ${1:-} == --version ]] && printf 'v22.4.0\n'
EOF
cat >"$fake_bin/npm" <<'EOF'
#!/usr/bin/env bash
set -e
if [[ ${1:-} == --version ]]; then
    printf '10.8.0\n'
    exit 0
fi
printf '%s\n' "$1" >>"$NPM_LOG"
if [[ $1 == ci && ${FAKE_CI_FAIL:-false} == true ]]; then exit 1; fi
if [[ $1 == install && ${FAKE_INSTALL_FAIL:-false} == true ]]; then exit 1; fi
EOF
chmod +x "$fake_bin/node" "$fake_bin/npm"

directory="$TEMP_DIR/with-lock"
new_repository "$directory"
git -C "$directory" remote add origin https://github.com/team-sample/with-lock
printf '{}\n' >"$directory/package.json"
printf '{}\n' >"$directory/package-lock.json"
npm_log="$TEMP_DIR/npm-with-lock.log"
run_setup "$directory" PATH="$fake_bin:$PATH" NPM_LOG="$npm_log" NODE_VERSION=22
[[ $(cat "$npm_log") == ci ]] || fail 'Expected npm ci for package-lock.json'

directory="$TEMP_DIR/bad-lock"
new_repository "$directory"
git -C "$directory" remote add origin https://github.com/team-sample/bad-lock
printf '{}\n' >"$directory/package.json"
printf '{}\n' >"$directory/package-lock.json"
npm_log="$TEMP_DIR/npm-bad-lock.log"
if run_setup "$directory" PATH="$fake_bin:$PATH" NPM_LOG="$npm_log" NODE_VERSION=22 FAKE_CI_FAIL=true; then
    fail 'Accepted failed npm ci'
fi
[[ $(cat "$npm_log") == ci ]] || fail 'Fell back from failed npm ci to npm install'

directory="$TEMP_DIR/no-lock"
new_repository "$directory"
git -C "$directory" remote add origin https://github.com/team-sample/no-lock
printf '{}\n' >"$directory/package.json"
npm_log="$TEMP_DIR/npm-no-lock.log"
run_setup "$directory" PATH="$fake_bin:$PATH" NPM_LOG="$npm_log" NODE_VERSION=22
[[ $(cat "$npm_log") == install ]] || fail 'Expected npm install without a lockfile'
assert_contains "$directory/setup.log" 'لا يوجد package-lock.json'

directory="$TEMP_DIR/wrong-node"
new_repository "$directory"
git -C "$directory" remote add origin https://github.com/team-sample/wrong-node
printf '{}\n' >"$directory/package.json"
npm_log="$TEMP_DIR/npm-wrong-node.log"
if run_setup "$directory" PATH="$fake_bin:$PATH" NPM_LOG="$npm_log" NODE_VERSION=20; then
    fail 'Accepted the wrong Node.js major version'
fi
[[ ! -e $npm_log ]] || fail 'Ran npm despite a Node.js version mismatch'
printf 'PASS: package.json, lockfile, npm failure, and Node.js checks\n'

check_staged_path() {
    local path=$1 expect_rejection=$2 dir="$TEMP_DIR/hook-$RANDOM-$RANDOM"
    new_repository "$dir"
    mkdir -p -- "$dir/$(dirname -- "$path")"
    printf 'test\n' >"$dir/$path"
    git -C "$dir" add -- "$path"
    if (cd -- "$dir" && bash scripts/hooks/pre-commit); then
        [[ $expect_rejection == false ]] || fail "Hook allowed sensitive staged path: $(printf %q "$path")"
    else
        [[ $expect_rejection == true ]] || fail "Hook rejected ordinary staged path: $(printf %q "$path")"
    fi
}

check_staged_path '.env' true
check_staged_path '.env.local' true
check_staged_path '.env.production' true
check_staged_path '.env.example' false
check_staged_path '.secrets/token' true
check_staged_path 'nested/.secrets' true
check_staged_path 'private.key' true
check_staged_path 'private.pem' true
check_staged_path 'not-a.keynote' false
check_staged_path 'literal*.key' true
check_staged_path 'bracket[1].txt' false
check_staged_path 'package-lock.json' false
check_staged_path $'newline\nprivate.pem' true
check_staged_path $'odd\nfilename.txt' false
printf 'PASS: sensitive staged paths and filenames containing newlines\n'

printf 'All setup-foundation tests passed.\n'
