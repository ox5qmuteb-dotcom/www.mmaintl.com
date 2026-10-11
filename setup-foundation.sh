#!/usr/bin/env bash

# SRAMM Secure CI - Foundation Setup Script
# المرحلة الأولى: إعداد الأساس الأول
# آخر تحديث: 25 سبتمبر 2026

set -e

# ===== الألوان للإخراج =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ===== الدوال المساعدة =====
log_info() {
    echo -e "${BLUE}[ℹ]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# ===== الفحص الأولي =====
check_prerequisites() {
    log_info "فحص المتطلبات الأولية..."

    if ! command -v git &> /dev/null; then
        log_error "Git غير مثبت. يرجى تثبيت Git أولاً."
        exit 1
    fi
    log_success "Git موجود"

    if ! command -v node &> /dev/null; then
        log_warning "Node.js غير مثبت. سيتم تثبيت النسخة 22"
        # في بيئة حقيقية، قد تحتاج إلى تثبيت Node.js
    else
        NODE_VERSION=$(node -v)
        log_success "Node.js $NODE_VERSION موجود"
    fi

    if ! command -v npm &> /dev/null; then
        log_error "npm غير موجود. تأكد من تثبيت Node.js بشكل صحيح."
        exit 1
    fi
    log_success "npm موجود"
}

# ===== إعداد الـ Repository =====
setup_repository() {
    log_info "إعداد المستودع..."

    # التحقق من أننا في المستودع الصحيح
    if [ ! -d ".git" ]; then
        log_error "لا نحن في مستودع git. يرجى تشغيل هذا السكريبت من جذر المستودع."
        exit 1
    fi

    # الحصول على معلومات المستودع
    REPO_NAME=$(git config --get remote.origin.url | grep -oP '(?<=/)[\w-]+(?=\.git)')
    REPO_OWNER=$(git config --get remote.origin.url | grep -oP '(?<=:)[\w-]+(?=/)')
    
    if [ -z "$REPO_NAME" ] || [ -z "$REPO_OWNER" ]; then
        log_warning "لا يمكن تحديد بيانات المستودع تلقائياً"
        read -p "أدخل مالك المستودع (owner): " REPO_OWNER
        read -p "أدخل اسم المستودع (repo name): " REPO_NAME
    fi

    log_success "المستودع: $REPO_OWNER/$REPO_NAME"
}

# ===== إعداد المتغيرات البيئية =====
setup_environment() {
    log_info "إعداد متغيرات البيئة..."

    # إنشاء ملف .env.example
    cat > .env.example << 'EOF'
# SRAMM Secure CI Configuration
# هذا ملف مثال، انسخه إلى .env وأكمل القيم

# معلومات GitHub
GITHUB_OWNER=ox5qmuteb-dotcom
GITHUB_REPO=sramm-secure-ci
GITHUB_BRANCH=main

# إعدادات Self-Hosted Runner
RUNNER_LABELS="self-hosted,linux,moteb-alotaibi"
RUNNER_URL="https://github.com/$GITHUB_OWNER/$GITHUB_REPO"

# إعدادات Environment
ENVIRONMENT_NAME="moteb-alotaibi-secure"
REQUIRED_REVIEWER="moteb-alotaibi"

# إعدادات Node.js
NODE_VERSION=22
NPM_CACHE_STRATEGY="npm"

# إعدادات Timeout
JOB_TIMEOUT_MINUTES=15

# المطور الأساسي
PRIMARY_DEVELOPER="moteb alotaibi"
PRIMARY_DEVELOPER_EMAIL="moteb.alotaibi@example.com"
EOF

    log_success "تم إنشاء ملف .env.example"

    # إنشاء .env إذا لم يكن موجوداً
    if [ ! -f ".env" ]; then
        cp .env.example .env
        log_warning "تم إنشاء ملف .env - يرجى تحديثه بالقيم الصحيحة"
    else
        log_success "ملف .env موجود بالفعل"
    fi
}

# ===== إعداد مجلد .github =====
setup_github_config() {
    log_info "إعداد إعدادات GitHub..."

    # التحقق من مجلد .github
    if [ ! -d ".github" ]; then
        mkdir -p .github
        log_success "تم إنشاء مجلد .github"
    fi

    if [ ! -d ".github/workflows" ]; then
        mkdir -p .github/workflows
        log_success "تم إنشاء مجلد .github/workflows"
    fi

    # التحقق من وجود ملف ci.yml
    if [ ! -f ".github/workflows/ci.yml" ]; then
        log_warning "ملف .github/workflows/ci.yml غير موجود"
        log_info "يرجى إضافة ملف workflow يدويًا أو استخدام GitHub Web UI"
    else
        log_success "ملف ci.yml موجود"
    fi
}

# ===== إعداد npm =====
setup_npm() {
    log_info "إعداد npm والمتطلبات..."

    if [ ! -f "package.json" ]; then
        log_warning "ملف package.json غير موجود"
        log_info "تم إنشاء package.json افتراضي"
        
        npm init -y > /dev/null 2>&1
    fi

    log_info "تثبيت المتطلبات..."
    npm ci || npm install

    log_success "تم تثبيت المتطلبات بنجاح"
}

# ===== إعداد .gitignore =====
setup_gitignore() {
    log_info "إعداد .gitignore..."

    if [ ! -f ".gitignore" ]; then
        cat > .gitignore << 'EOF'
# Environment
.env
.env.local
.env.*.local

# Dependencies
node_modules/
package-lock.json
yarn.lock

# Build
dist/
build/
*.log

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Secrets
*.key
*.pem
.secrets/

# CI/CD
.github/workflows/*.bak
EOF
        log_success "تم إنشاء ملف .gitignore"
    else
        log_success "ملف .gitignore موجود"
    fi
}

# ===== إعداد Git Hooks =====
setup_git_hooks() {
    log_info "إعداد Git hooks..."

    if [ ! -d ".git/hooks" ]; then
        mkdir -p .git/hooks
    fi

    # إنشاء pre-commit hook
    cat > .git/hooks/pre-commit << 'EOF'
#!/usr/bin/env bash
# Pre-commit hook: منع commit الملفات الحساسة

RESTRICTED_FILES=(".env" ".secrets" "*.key" "*.pem")

for file in "${RESTRICTED_FILES[@]}"; do
    if git ls-files --cached | grep -q "$file"; then
        echo "Error: Cannot commit $file"
        exit 1
    fi
done

exit 0
EOF

    chmod +x .git/hooks/pre-commit
    log_success "تم إعداد Git hooks"
}

# ===== إنشاء ملف Configuration =====
setup_config_file() {
    log_info "إنشاء ملف التكوين المركزي..."

    mkdir -p .github/config

    cat > .github/config/sramm.config.json << 'EOF'
{
  "version": "1.0",
  "name": "SRAMM Secure CI",
  "description": "نظام تكامل مستمر آمن مع فصل كامل للبيئات",
  "lastUpdated": "2026-09-25",
  
  "repository": {
    "owner": "ox5qmuteb-dotcom",
    "name": "sramm-secure-ci",
    "branch": "main",
    "visibility": "public"
  },

  "workflows": {
    "ci": {
      "name": "SRAMM",
      "file": ".github/workflows/ci.yml",
      "triggers": ["pull_request", "push"],
      "jobs": {
        "docs-pr": {
          "name": "SRAMM — Verify documentation",
          "condition": "pull_request",
          "runner": "ubuntu-latest",
          "timeout": 15
        },
        "docs-secure": {
          "name": "SRAMM — moteb alotaibi",
          "condition": "push to main",
          "runner": "self-hosted",
          "labels": ["self-hosted", "linux", "moteb-alotaibi"],
          "environment": "moteb-alotaibi-secure",
          "timeout": 15
        }
      }
    }
  },

  "security": {
    "environment": "moteb-alotaibi-secure",
    "requiredReviewers": ["moteb-alotaibi"],
    "preventSelfReview": true,
    "restrictedFiles": [".env", ".secrets", "*.key", "*.pem"],
    "publicRepository": true,
    "notes": "لا تضع أسرار أو بيانات حساسة في هذا المستودع العام"
  },

  "developer": {
    "name": "moteb alotaibi",
    "role": "Maintainer & Reviewer",
    "responsibilities": [
      "إدارة self-hosted runner",
      "مراجعة و موافقة على deployments",
      "تحديث إعدادات Environment",
      "متابعة أداء CI/CD"
    ]
  },

  "nodeConfig": {
    "version": 22,
    "cache": "npm",
    "installCommand": "npm ci",
    "buildCommand": "npm run docs:build"
  }
}
EOF

    log_success "تم إنشاء ملف التكوين sramm.config.json"
}

# ===== تقرير ملخص =====
print_summary() {
    log_info "ملخص الإعداد الأول"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  SRAMM Secure CI - Foundation Setup Complete"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "المتطلبات المكتملة:"
    echo "  ✓ فحص المتطلبات الأولية"
    echo "  ✓ إعداد بيانات المستودع"
    echo "  ✓ إعداد متغيرات البيئة (.env)"
    echo "  ✓ إعداد مجلد .github/workflows"
    echo "  ✓ إعداد npm والمتطلبات"
    echo "  ✓ إعداد .gitignore"
    echo "  ✓ إعداد Git hooks"
    echo "  ✓ إنشاء ملف التكوين المركزي"
    echo ""
    echo "الخطوات التالية:"
    echo "  1. حدّث ملف .env بالقيم الصحيحة"
    echo "  2. أضف ملف .github/workflows/ci.yml إلى المستودع"
    echo "  3. أنشئ Environment 'moteb-alotaibi-secure' في GitHub"
    echo "  4. أضف moteb-alotaibi كـ Required reviewer"
    echo "  5. سجّل self-hosted runner بـ labels المطلوبة"
    echo "  6. اختبر الـ workflow بـ Pull Request"
    echo ""
    echo "المستودع: $REPO_OWNER/$REPO_NAME"
    echo "الفرع: main"
    echo "المطور الأساسي: moteb alotaibi"
    echo ""
    echo "════════════════════════════════════════════════��══════════"
}

# ===== تشغيل الإعداد الكامل =====
main() {
    echo ""
    log_info "بدء إعداد الأساس الأول لـ SRAMM Secure CI"
    echo ""

    check_prerequisites
    setup_repository
    setup_environment
    setup_github_config
    setup_npm
    setup_gitignore
    setup_git_hooks
    setup_config_file
    print_summary

    echo ""
    log_success "اكتمل إعداد الأساس الأول بنجاح! 🎉"
}

# تشغيل البرنامج الرئيسي
main "$@"
