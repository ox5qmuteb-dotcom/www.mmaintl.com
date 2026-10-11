#!/usr/bin/env bash

set -Eeuo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

log_info() { printf '%s[ℹ]%s %s\n' "$BLUE" "$NC" "$*"; }
log_success() { printf '%s[✓]%s %s\n' "$GREEN" "$NC" "$*"; }
log_warning() { printf '%s[!]%s %s\n' "$YELLOW" "$NC" "$*"; }
log_error() { printf '%s[✗]%s %s\n' "$RED" "$NC" "$*" >&2; }

on_error() {
    local status=$1 line=$2
    log_error "فشل الإعداد عند السطر $line (رمز الخروج $status). لم تُستبدل الملفات الموجودة دون --force."
    exit "$status"
}
trap 'on_error "$?" "$LINENO"' ERR

REPO_OWNER=${REPO_OWNER:-${GITHUB_OWNER:-}}
REPO_NAME=${REPO_NAME:-${GITHUB_REPO:-}}
GITHUB_BRANCH=${GITHUB_BRANCH:-main}
RUNNER_TYPE=${RUNNER_TYPE:-self-hosted}
RUNNER_LABELS=${RUNNER_LABELS:-self-hosted,linux}
ENVIRONMENT_NAME=${ENVIRONMENT_NAME:-}
REQUIRED_REVIEWER=${REQUIRED_REVIEWER:-}
NODE_VERSION=${NODE_VERSION:-22}
NPM_CACHE_STRATEGY=${NPM_CACHE_STRATEGY:-npm}
JOB_TIMEOUT_MINUTES=${JOB_TIMEOUT_MINUTES:-15}
OVERWRITE_EXISTING=${OVERWRITE_EXISTING:-false}
NONINTERACTIVE=${NONINTERACTIVE:-false}

usage() {
    cat <<'EOF'
Usage: setup-foundation.sh [--force] [--non-interactive] [--help]

Repository and configuration values may be provided through environment variables:
REPO_OWNER, REPO_NAME, GITHUB_BRANCH, RUNNER_TYPE, RUNNER_LABELS,
ENVIRONMENT_NAME, REQUIRED_REVIEWER, NODE_VERSION, NPM_CACHE_STRATEGY,
JOB_TIMEOUT_MINUTES. --force backs up and replaces existing generated templates.
--non-interactive prevents prompts when repository information is unavailable.
EOF
}

while (($#)); do
    case "$1" in
        --force) OVERWRITE_EXISTING=true ;;
        --non-interactive) NONINTERACTIVE=true ;;
        --help|-h) usage; exit 0 ;;
        *) log_error "خيار غير معروف: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_error "الأداة المطلوبة غير موجودة: $1"
        return 1
    fi
}

valid_owner() {
    [[ $1 =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$ ]]
}

valid_repo_name() {
    [[ $1 =~ ^[A-Za-z0-9]([A-Za-z0-9._-]{0,98}[A-Za-z0-9])?$ ]]
}

parse_remote() {
    local url=$1 path
    case "$url" in
        https://*|http://*|ssh://*|git://*)
            local authority_path=${url#*://}
            [[ $authority_path == */* ]] || return 1
            path=${authority_path#*/}
            ;;
        *@*:*/*)
            path=${url#*:}
            ;;
        *)
            return 1
            ;;
    esac

    while [[ $path == */ ]]; do path=${path%/}; done
    [[ $path == *.git ]] && path=${path%.git}
    [[ $path != */*/* && $path == */* ]] || return 1

    local owner=${path%%/*} repo=${path#*/}
    valid_owner "$owner" && valid_repo_name "$repo" || return 1
    printf '%s\n%s\n' "$owner" "$repo"
}

prompt_for_value() {
    local prompt=$1 variable=$2 value
    if [[ $NONINTERACTIVE == true || ${CI:-false} == true || ! -r /dev/tty || ! -w /dev/tty ]]; then
        log_error "لم أتمكن من تحديد $variable. عيّنه عبر متغير البيئة في الوضع غير التفاعلي."
        return 1
    fi

    while true; do
        printf '%s' "$prompt" >/dev/tty
        IFS= read -r value </dev/tty || {
            log_error "تعذر قراءة $variable من الطرفية."
            return 1
        }
        if [[ $variable == REPO_OWNER ]] && valid_owner "$value"; then
            REPO_OWNER=$value
            return 0
        elif [[ $variable == REPO_NAME ]] && valid_repo_name "$value"; then
            REPO_NAME=$value
            return 0
        fi
        log_warning "القيمة غير صالحة؛ حاول مرة أخرى."
    done
}

setup_repository() {
    check_command git
    local root remote parsed
    root=$(git rev-parse --show-toplevel) || {
        log_error "شغّل السكربت داخل مستودع Git."
        return 1
    }
    cd -- "$root"

    remote=$(git remote get-url origin 2>/dev/null || true)
    if [[ -n $remote ]]; then
        parsed=$(parse_remote "$remote" || true)
        if [[ -n $parsed ]]; then
            local detected_owner=${parsed%%$'\n'*}
            local detected_repo=${parsed#*$'\n'}
            REPO_OWNER=${REPO_OWNER:-$detected_owner}
            REPO_NAME=${REPO_NAME:-$detected_repo}
        else
            log_warning "تعذر تحليل عنوان origin؛ أدخل بيانات المستودع أو عيّنها عبر البيئة."
        fi
    else
        log_warning "لا يوجد remote باسم origin؛ أدخل بيانات المستودع أو عيّنها عبر البيئة."
    fi

    if [[ -z $REPO_OWNER ]]; then prompt_for_value "مالك المستودع (owner): " REPO_OWNER; fi
    if [[ -z $REPO_NAME ]]; then prompt_for_value "اسم المستودع (repo): " REPO_NAME; fi
    valid_owner "$REPO_OWNER" || { log_error "REPO_OWNER غير صالح: $REPO_OWNER"; return 1; }
    valid_repo_name "$REPO_NAME" || { log_error "REPO_NAME غير صالح: $REPO_NAME"; return 1; }
    if [[ ! $GITHUB_BRANCH =~ ^[A-Za-z0-9._/-]+$ ]] || ! git check-ref-format --branch "$GITHUB_BRANCH" >/dev/null; then
        log_error "اسم الفرع غير صالح: $GITHUB_BRANCH"
        return 1
    fi

    ENVIRONMENT_NAME=${ENVIRONMENT_NAME:-${REPO_NAME}-secure}
    [[ $ENVIRONMENT_NAME =~ ^[A-Za-z0-9_.-]+$ ]] || {
        log_error "ENVIRONMENT_NAME يحتوي محارف غير صالحة."
        return 1
    }
    [[ $RUNNER_TYPE =~ ^[A-Za-z0-9_.-]+$ ]] || {
        log_error "RUNNER_TYPE يحتوي محارف غير صالحة."
        return 1
    }
    [[ $RUNNER_LABELS =~ ^[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+)*$ ]] || {
        log_error "RUNNER_LABELS يجب أن تكون labels مفصولة بفواصل."
        return 1
    }
    if [[ -n $REQUIRED_REVIEWER && ! $REQUIRED_REVIEWER =~ ^[A-Za-z0-9-]+$ ]]; then
        log_error "REQUIRED_REVIEWER يجب أن يكون اسم حساب GitHub أو فارغًا."
        return 1
    fi
    [[ $NODE_VERSION =~ ^[0-9]+$ ]] || { log_error "NODE_VERSION يجب أن يكون رقم إصدار رئيسيًا."; return 1; }
    [[ $JOB_TIMEOUT_MINUTES =~ ^[1-9][0-9]*$ ]] || {
        log_error "JOB_TIMEOUT_MINUTES يجب أن يكون عددًا صحيحًا موجبًا."
        return 1
    }
    [[ $NPM_CACHE_STRATEGY =~ ^[A-Za-z0-9_-]+$ ]] || {
        log_error "NPM_CACHE_STRATEGY يحتوي محارف غير صالحة."
        return 1
    }

    log_success "المستودع: $REPO_OWNER/$REPO_NAME"
}

backup_file() {
    local source=$1 backup_dir backup
    check_command cp
    check_command date
    backup_dir=$(git rev-parse --git-path foundation-setup-backups)
    [[ $backup_dir == /* ]] || backup_dir="$PWD/$backup_dir"
    mkdir -p -- "$backup_dir"
    backup="$backup_dir/$(basename -- "$source").$(date +%Y%m%d%H%M%S).$$"
    cp -a -- "$source" "$backup"
    log_warning "حُفظت نسخة احتياطية من $source داخل .git/foundation-setup-backups."
}

write_generated_file() {
    local destination=$1 temp
    if [[ -e $destination || -L $destination ]]; then
        if [[ $OVERWRITE_EXISTING != true ]]; then
            cat >/dev/null
            log_warning "حُفظ الملف الموجود دون تغيير: $destination (استخدم --force بعد مراجعته)."
            return 0
        fi
        backup_file "$destination"
    fi

    check_command mktemp
    check_command chmod
    check_command mv
    temp=$(mktemp "${destination}.tmp.XXXXXX")
    cat >"$temp"
    chmod 0644 "$temp"
    mv -f -- "$temp" "$destination"
    log_success "تم إنشاء/تحديث $destination"
}

setup_environment() {
    local runner_url="https://github.com/$REPO_OWNER/$REPO_NAME"
    write_generated_file .env.example <<EOF
# SRAMM Secure CI configuration template; no secrets are included.
GITHUB_OWNER=$REPO_OWNER
GITHUB_REPO=$REPO_NAME
GITHUB_BRANCH=$GITHUB_BRANCH
RUNNER_TYPE=$RUNNER_TYPE
RUNNER_LABELS="$RUNNER_LABELS"
RUNNER_URL=$runner_url
ENVIRONMENT_NAME=$ENVIRONMENT_NAME
REQUIRED_REVIEWER=$REQUIRED_REVIEWER
NODE_VERSION=$NODE_VERSION
NPM_CACHE_STRATEGY=$NPM_CACHE_STRATEGY
JOB_TIMEOUT_MINUTES=$JOB_TIMEOUT_MINUTES
EOF

    if [[ -e .env || -L .env ]]; then
        log_warning "ملف .env موجود؛ لم يُقرأ أو يُنشأ أو يُعدّل."
    else
        log_warning "لم يُنشأ .env. انسخ .env.example يدويًا إذا احتجت ملف إعداد محليًا."
    fi
}

ensure_directory() {
    local directory=$1
    if [[ -L $directory ]]; then
        log_error "رفض استخدام مجلد رمزي موجود: $directory"
        return 1
    fi
    if [[ -e $directory && ! -d $directory ]]; then
        log_error "المسار موجود وليس مجلدًا: $directory"
        return 1
    fi
    mkdir -p -- "$directory"
}

setup_github_config() {
    ensure_directory .github
    ensure_directory .github/workflows
    ensure_directory .github/config

    if [[ -f .github/workflows/ci.yml ]]; then
        log_success "ملف workflow موجود."
    else
        log_warning "لا يوجد .github/workflows/ci.yml؛ لم يُنشأ workflow تلقائيًا."
    fi

    local labels_json='[' label separator=''
    local remaining=$RUNNER_LABELS
    while [[ $remaining == *,* ]]; do
        label=${remaining%%,*}
        labels_json+="$separator\"$label\""
        separator=', '
        remaining=${remaining#*,}
    done
    labels_json+="$separator\"$remaining\"]"

    local reviewers_json='[]'
    if [[ -n $REQUIRED_REVIEWER ]]; then
        reviewers_json="[\"$REQUIRED_REVIEWER\"]"
    fi

    write_generated_file .github/config/sramm.config.json <<EOF
{
  "version": "1.0",
  "name": "$REPO_NAME Secure CI",
  "repository": {
    "owner": "$REPO_OWNER",
    "name": "$REPO_NAME",
    "branch": "$GITHUB_BRANCH"
  },
  "runner": {
    "type": "$RUNNER_TYPE",
    "labels": $labels_json,
    "environment": "$ENVIRONMENT_NAME",
    "requiredReviewers": $reviewers_json,
    "timeoutMinutes": $JOB_TIMEOUT_MINUTES
  },
  "nodeConfig": {
    "version": $NODE_VERSION,
    "cache": "$NPM_CACHE_STRATEGY"
  }
}
EOF
}

setup_npm() {
    if [[ ! -f package.json ]]; then
        log_warning "package.json غير موجود؛ تخطّيت إعداد npm ولم أُنشئ ملفات مشروع."
        return 0
    fi

    check_command node
    check_command npm
    local installed_node node_major
    installed_node=$(node --version) || {
        log_error "تعذر قراءة إصدار Node.js."
        return 1
    }
    [[ $installed_node =~ ^v([0-9]+)\. ]] || {
        log_error "تعذر تحليل إصدار Node.js: $installed_node"
        return 1
    }
    node_major=${BASH_REMATCH[1]}
    if [[ $node_major != "$NODE_VERSION" ]]; then
        log_error "يتطلب الإعداد Node.js $NODE_VERSION.x (المثبت: $installed_node). ثبّت الإصدار المطلوب ثم أعد التشغيل."
        return 1
    fi

    local npm_version
    npm_version=$(npm --version) || {
        log_error "تعذر تشغيل npm أو قراءة إصداره."
        return 1
    }
    log_info "Node.js $installed_node وnpm $npm_version موجودان."

    if [[ -f package-lock.json || -f npm-shrinkwrap.json ]]; then
        log_info "تثبيت الاعتماديات باستخدام npm ci من ملف القفل."
        npm ci || {
            log_error "فشل npm ci؛ لم يتم التراجع بصمت إلى npm install."
            return 1
        }
    else
        log_warning "لا يوجد package-lock.json أو npm-shrinkwrap.json؛ سيُستخدم npm install وقد ينشئ ملف قفل."
        npm install || {
            log_error "فشل npm install."
            return 1
        }
    fi
    log_success "تم تثبيت الاعتماديات بنجاح."
}

setup_gitignore() {
    local ignore_file=.gitignore
    check_command grep
    if [[ -L $ignore_file ]]; then
        log_error "رفض تعديل .gitignore لأنه رابط رمزي."
        return 1
    fi
    if [[ -e $ignore_file && ! -f $ignore_file ]]; then
        log_error ".gitignore موجود وليس ملفًا عاديًا."
        return 1
    fi
    [[ -f $ignore_file ]] || : >"$ignore_file"
    if [[ -s $ignore_file ]]; then
        check_command tail
        local last_byte
        last_byte=$(tail -c 1 -- "$ignore_file"; printf '.')
        last_byte=${last_byte%.}
        if [[ $last_byte != $'\n' ]]; then printf '\n' >>"$ignore_file"; fi
    fi

    local pattern
    for pattern in '.env' '.env.*' '!.env.example' '.secrets/' '*.key' '*.pem' 'node_modules/'; do
        if ! grep -Fqx -- "$pattern" "$ignore_file"; then
            printf '%s\n' "$pattern" >>"$ignore_file"
        fi
    done
    log_success "تم التأكد من قواعد تجاهل الملفات الحساسة؛ لم تتم إضافة package-lock.json."
}

setup_git_hooks() {
    check_command install
    ensure_directory scripts
    ensure_directory scripts/hooks
    if [[ ! -f scripts/hooks/pre-commit ]]; then
        log_error "ملف hook الموزع scripts/hooks/pre-commit غير موجود."
        return 1
    fi

    local hooks_dir hook
    hooks_dir=$(git rev-parse --git-path hooks)
    [[ $hooks_dir == /* ]] || hooks_dir="$PWD/$hooks_dir"
    ensure_directory "$hooks_dir"
    hook="$hooks_dir/pre-commit"

    if [[ -e $hook || -L $hook ]]; then
        log_warning "تم الإبقاء على hook الموجود دون تغيير: $hook"
        log_info "راجع scripts/hooks/pre-commit لدمجه يدويًا عند الحاجة."
        return 0
    fi
    install -m 0755 scripts/hooks/pre-commit "$hook"
    log_success "تم تثبيت hook محلي؛ النسخة الموزعة موجودة في scripts/hooks/pre-commit."
}

print_summary() {
    printf '\n%s\n' '==========================================================='
    printf 'اكتمل إعداد أساس المستودع %s/%s على الفرع %s.\n' "$REPO_OWNER" "$REPO_NAME" "$GITHUB_BRANCH"
    printf '%s\n' 'راجع .env.example والإعدادات الناتجة؛ لم يُنشأ أو يُعدّل .env.'
    printf '%s\n' 'Git hooks محلية وليست موزعة تلقائيًا؛ النسخة الموزعة في scripts/hooks/pre-commit.'
    printf '%s\n\n' '==========================================================='
}

main() {
    log_info "بدء إعداد أساس آمن وقابل لإعادة التشغيل."
    setup_repository
    setup_environment
    setup_github_config
    setup_npm
    setup_gitignore
    setup_git_hooks
    print_summary
}

main "$@"
