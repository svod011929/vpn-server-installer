#!/bin/bash

# install_vpn_adguard.sh
# Скрипт автоматической установки VPN-сервера с VLESS + TLS + 3X-UI + AdGuard Home
# Автор: KodoDrive
# Версия: 3.0 (полностью переписанная)
# Дата: $(date)

set -euo pipefail

# ===============================================
# ОСНОВНЫЕ ПЕРЕМЕННЫЕ
# ===============================================

# Версия скрипта
SCRIPT_VERSION="3.0.0"
SCRIPT_URL="https://raw.githubusercontent.com/svod011929/vpn-server-installer/main/install_vpn_adguard.sh"
REPO_URL="https://github.com/svod011929/vpn-server-installer"

# Логирование
LOG_FILE="/var/log/vpn-installer.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Переменные конфигурации
DOMAIN=""
EMAIL=""
XUI_USERNAME="admin"
XUI_PASSWORD=""
ADGUARD_PASSWORD=""
VLESS_PORT="443"
XUI_PORT="54321"
ADGUARD_PORT="3000"
AUTO_PASSWORD=false
AUTO_CONFIRM=false
DEBUG_MODE=false
INSTALL_STATE_FILE="/tmp/vpn-install-state"

# Системные переменные
OS=""
OS_ID=""
VER=""
ARCH=""
RAM_MB=""
DISK_GB=""

# Поддерживаемые дистрибутивы
SUPPORTED_OS=("ubuntu" "debian" "centos" "rhel" "fedora" "almalinux" "rocky")

# ===============================================
# ФУНКЦИИ ВЫВОДА
# ===============================================

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

print_debug() {
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1" | tee -a "$LOG_FILE"
    fi
}

print_header() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}║${NC} $(printf "%-36s" "$1") ${BLUE}║${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}" | tee -a "$LOG_FILE"
}

# ===============================================
# ФУНКЦИИ УПРАВЛЕНИЯ СОСТОЯНИЕМ
# ===============================================

save_install_state() {
    local step="$1"
    cat > "$INSTALL_STATE_FILE" << EOF
DOMAIN="$DOMAIN"
EMAIL="$EMAIL"
XUI_USERNAME="$XUI_USERNAME"
XUI_PASSWORD="$XUI_PASSWORD"
ADGUARD_PASSWORD="$ADGUARD_PASSWORD"
VLESS_PORT="$VLESS_PORT"
XUI_PORT="$XUI_PORT"
ADGUARD_PORT="$ADGUARD_PORT"
INSTALL_STEP="$step"
TIMESTAMP="$(date)"
EOF
    print_debug "Сохранено состояние: $step"
}

load_install_state() {
    if [ -f "$INSTALL_STATE_FILE" ]; then
        source "$INSTALL_STATE_FILE"
        print_status "Найдено состояние установки. Последний шаг: $INSTALL_STEP"
        if [ "$AUTO_CONFIRM" != true ]; then
            read -p "Продолжить с последнего шага? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                rm -f "$INSTALL_STATE_FILE"
                return 1
            fi
        fi
        return 0
    fi
    return 1
}

cleanup_on_error() {
    local exit_code=$?
    print_error "Установка прервана с кодом $exit_code. Выполняю откат..."

    # Остановка сервисов
    systemctl stop x-ui 2>/dev/null || true
    systemctl stop AdGuardHome 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true

    # Удаление файлов
    rm -rf /opt/3x-ui 2>/dev/null || true
    rm -rf /opt/AdGuardHome 2>/dev/null || true
    rm -f /etc/systemd/system/x-ui.service 2>/dev/null || true
    rm -f /etc/systemd/system/AdGuardHome.service 2>/dev/null || true

    # Восстановление DNS
    if [ -f /etc/resolv.conf.backup ]; then
        mv /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null || true
    fi

    # Восстановление автоматических обновлений
    restore_auto_updates

    systemctl daemon-reload

    print_status "Откат завершен. Проверьте логи в $LOG_FILE"
    exit $exit_code
}

trap cleanup_on_error ERR

# ===============================================
# ФУНКЦИИ ИНТЕРФЕЙСА
# ===============================================

show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║  ██╗   ██╗██████╗ ███╗   ██╗    ██╗███╗   ██╗███████╗████████╗║
║  ██║   ██║██╔══██╗████╗  ██║    ██║████╗  ██║██╔════╝╚══██╔══╝║
║  ██║   ██║██████╔╝██╔██╗ ██║    ██║██╔██╗ ██║███████╗   ██║   ║
║  ╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║    ██║██║╚██╗██║╚════██║   ██║   ║
║   ╚████╔╝ ██║     ██║ ╚████║    ██║██║ ╚████║███████║   ██║   ║
║    ╚═══╝  ╚═╝     ╚═╝  ╚═══╝    ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ║
║                                                               ║
║              VPN Server Auto Installer v3.0                  ║
║           VLESS + TLS + 3X-UI + AdGuard Home                 ║
║                                                               ║
║                    Made by KodoDrive                         ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

show_help() {
    cat << EOF
VPN Server Auto Installer v${SCRIPT_VERSION}

Автоматическая установка VPN-сервера с VLESS + TLS + 3X-UI + AdGuard Home

ИСПОЛЬЗОВАНИЕ:
  bash <(curl -fsSL ${SCRIPT_URL})

ОПЦИИ:
  --domain DOMAIN              Ваш домен (например: vpn.example.com)
  --email EMAIL               Email для SSL сертификата
  --xui-password PASSWORD     Пароль для панели 3X-UI
  --adguard-password PASSWORD Пароль для AdGuard Home
  --vless-port PORT          Порт для VLESS (по умолчанию: 443)
  --xui-port PORT            Порт для 3X-UI (по умолчанию: 54321)
  --adguard-port PORT        Порт для AdGuard (по умолчанию: 3000)
  --auto-password            Автоматическая генерация паролей
  --auto-confirm             Автоматическое подтверждение
  --debug                    Режим отладки
  --help                     Показать справку
  --version                  Показать версию

ПРИМЕРЫ:
  # Интерактивная установка
  bash <(curl -fsSL ${SCRIPT_URL})

  # Автоматическая установка с параметрами
  bash <(curl -fsSL ${SCRIPT_URL}) \\
    --domain "vpn.example.com" \\
    --email "admin@example.com" \\
    --auto-password \\
    --auto-confirm

ПОДДЕРЖКА:
  GitHub: ${REPO_URL}
  Issues: ${REPO_URL}/issues

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --email)
                EMAIL="$2"
                shift 2
                ;;
            --xui-password)
                XUI_PASSWORD="$2"
                shift 2
                ;;
            --adguard-password)
                ADGUARD_PASSWORD="$2"
                shift 2
                ;;
            --vless-port)
                VLESS_PORT="$2"
                shift 2
                ;;
            --xui-port)
                XUI_PORT="$2"
                shift 2
                ;;
            --adguard-port)
                ADGUARD_PORT="$2"
                shift 2
                ;;
            --auto-password)
                AUTO_PASSWORD=true
                shift
                ;;
            --auto-confirm)
                AUTO_CONFIRM=true
                shift
                ;;
            --debug)
                DEBUG_MODE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            --version)
                echo "VPN Server Auto Installer v${SCRIPT_VERSION}"
                echo "Repository: ${REPO_URL}"
                exit 0
                ;;
            *)
                print_error "Неизвестный параметр: $1"
                echo "Используйте --help для справки"
                exit 1
                ;;
        esac
    done
}

# ===============================================
# ФУНКЦИИ ПРОВЕРКИ СИСТЕМЫ
# ===============================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен запускаться с правами root!"
        print_status "Используйте: sudo $0"
        exit 1
    fi
}

detect_system() {
    print_header "ОПРЕДЕЛЕНИЕ СИСТЕМЫ"

    # Проверка ОС
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        OS_ID=$ID
        print_status "ОС: $OS $VER"

        # Проверка совместимости
        local supported=false
        for supported_os in "${SUPPORTED_OS[@]}"; do
            if [[ "$OS_ID" == "$supported_os"* ]]; then
                supported=true
                break
            fi
        done

        if [ "$supported" = false ]; then
            print_error "Неподдерживаемая ОС: $OS"
            print_status "Поддерживаемые ОС: ${SUPPORTED_OS[*]}"
            exit 1
        fi
    else
        print_error "Не удалось определить операционную систему"
        exit 1
    fi

    # Проверка архитектуры
    ARCH=$(uname -m)
    print_status "Архитектура: $ARCH"

    case $ARCH in
        x86_64|amd64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="armv7"
            ;;
        *)
            print_error "Неподдерживаемая архитектура: $ARCH"
            exit 1
            ;;
    esac

    # Проверка ресурсов
    RAM_MB=$(free -m | awk 'NR==2{print $2}')
    DISK_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')

    print_status "ОЗУ: ${RAM_MB}MB"
    print_status "Свободное место: ${DISK_GB}GB"

    # Проверка минимальных требований
    if [ "$RAM_MB" -lt 512 ]; then
        print_error "Недостаточно RAM. Требуется минимум 512MB"
        exit 1
    fi

    if [ "$DISK_GB" -lt 2 ]; then
        print_error "Недостаточно свободного места. Требуется минимум 2GB"
        exit 1
    fi

    # Проверка интернета
    print_status "Проверка интернет подключения..."
    if ! timeout 15 curl -s --max-time 10 https://google.com > /dev/null; then
        print_error "Нет подключения к интернету"
        exit 1
    fi
    print_status "Интернет подключение: ✅"

    # Проверка systemd
    if ! command -v systemctl &> /dev/null; then
        print_error "Требуется systemd для управления сервисами"
        exit 1
    fi

    print_status "Система совместима ✅"
}

# ===============================================
# ФУНКЦИИ УПРАВЛЕНИЯ ПАКЕТАМИ
# ===============================================

wait_for_apt_lock() {
    local max_wait=300  # 5 минут
    local wait_time=0

    print_status "Проверка блокировок пакетного менеджера..."

    while [ $wait_time -lt $max_wait ]; do
        if ! fuser /var/lib/dpkg/lock >/dev/null 2>&1 && \
           ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && \
           ! fuser /var/lib/apt/lists/lock >/dev/null 2>&1 && \
           ! fuser /var/cache/apt/archives/lock >/dev/null 2>&1; then
            print_status "Блокировки освобождены ✅"
            return 0
        fi

        if [ $wait_time -eq 0 ]; then
            print_warning "Обнаружены активные процессы пакетного менеджера"
            print_status "Ожидание завершения автоматических обновлений..."
        fi

        sleep 10
        wait_time=$((wait_time + 10))
        echo -n "."
    done

    echo ""
    print_warning "Превышено время ожидания освобождения блокировок"

    if [ "$AUTO_CONFIRM" != true ]; then
        read -p "Принудительно остановить процессы обновления? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            force_kill_apt_processes
        else
            print_error "Невозможно продолжить без освобождения блокировок"
            exit 1
        fi
    else
        force_kill_apt_processes
    fi
}

force_kill_apt_processes() {
    print_status "Принудительная остановка процессов пакетного менеджера..."

    # Остановка systemd служб
    systemctl stop unattended-upgrades 2>/dev/null || true
    systemctl stop apt-daily.timer 2>/dev/null || true
    systemctl stop apt-daily-upgrade.timer 2>/dev/null || true
    systemctl stop apt-daily.service 2>/dev/null || true
    systemctl stop apt-daily-upgrade.service 2>/dev/null || true

    # Завершение процессов
    pkill -f "apt" || true
    pkill -f "dpkg" || true
    pkill -f "unattended-upgrade" || true

    sleep 3

    # Принудительное завершение
    pkill -9 -f "apt" || true
    pkill -9 -f "dpkg" || true
    pkill -9 -f "unattended-upgrade" || true

    # Удаление блокировок
    rm -f /var/lib/dpkg/lock-frontend
    rm -f /var/lib/dpkg/lock
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock

    # Восстановление пакетной системы
    dpkg --configure -a 2>/dev/null || true

    print_status "Процессы остановлены ✅"
}

disable_auto_updates() {
    print_status "Временное отключение автоматических обновлений..."

    # Останавливаем службы
    systemctl stop unattended-upgrades 2>/dev/null || true
    systemctl disable unattended-upgrades 2>/dev/null || true
    systemctl mask apt-daily.timer 2>/dev/null || true
    systemctl mask apt-daily-upgrade.timer 2>/dev/null || true

    # Создаем временную конфигурацию
    cat > /etc/apt/apt.conf.d/99disable-auto-update << 'EOF'
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "0";
EOF

    print_status "Автоматические обновления отключены"
}

restore_auto_updates() {
    print_status "Восстановление автоматических обновлений..."

    # Удаляем временную конфигурацию
    rm -f /etc/apt/apt.conf.d/99disable-auto-update

    # Восстанавливаем службы
    systemctl unmask apt-daily.timer 2>/dev/null || true
    systemctl unmask apt-daily-upgrade.timer 2>/dev/null || true
    systemctl enable unattended-upgrades 2>/dev/null || true

    print_status "Автоматические обновления восстановлены"
}

install_dependencies() {
    print_header "УСТАНОВКА ЗАВИСИМОСТЕЙ"
    save_install_state "installing_dependencies"

    export DEBIAN_FRONTEND=noninteractive

    if command -v apt-get &> /dev/null; then
        print_status "Установка зависимостей (Debian/Ubuntu)..."

        # Отключаем автоматические обновления
        disable_auto_updates

        # Ждем освобождения блокировок
        wait_for_apt_lock

        # Обновляем списки пакетов
        print_status "Обновление списков пакетов..."
        for attempt in {1..3}; do
            if apt-get update -qq; then
                break
            fi
            print_warning "Попытка $attempt обновления списков неудачна"
            sleep 5
        done

        # Обновляем систему
        print_status "Обновление системы..."
        apt-get upgrade -y -qq || print_warning "Проблемы при обновлении системы"

        # Устанавливаем базовые пакеты
        print_status "Установка базовых пакетов..."
        apt-get install -y -qq \
            curl \
            wget \
            unzip \
            software-properties-common \
            ca-certificates \
            gnupg \
            lsb-release \
            net-tools \
            apache2-utils \
            dnsutils \
            openssl \
            systemd \
            ufw \
            cron || {
            print_error "Не удалось установить базовые пакеты"
            exit 1
        }

    elif command -v yum &> /dev/null; then
        print_status "Установка зависимостей (CentOS/RHEL)..."
        yum update -y -q || print_warning "Проблемы при обновлении системы"
        yum install -y -q \
            curl \
            wget \
            unzip \
            epel-release \
            ca-certificates \
            net-tools \
            httpd-tools \
            bind-utils \
            openssl \
            firewalld \
            cronie || {
            print_error "Не удалось установить базовые пакеты"
            exit 1
        }

    elif command -v dnf &> /dev/null; then
        print_status "Установка зависимостей (Fedora)..."
        dnf update -y -q || print_warning "Проблемы при обновлении системы"
        dnf install -y -q \
            curl \
            wget \
            unzip \
            ca-certificates \
            net-tools \
            httpd-tools \
            bind-utils \
            openssl \
            firewalld \
            cronie || {
            print_error "Не удалось установить базовые пакеты"
            exit 1
        }
    fi

    print_status "Зависимости установлены ✅"
}

# ===============================================
# ФУНКЦИИ ПРОВЕРКИ ПОРТОВ
# ===============================================

check_port_in_use() {
    local port="$1"

    if command -v netstat &> /dev/null; then
        netstat -tuln 2>/dev/null | grep ":$port " > /dev/null
    elif command -v ss &> /dev/null; then
        ss -tuln 2>/dev/null | grep ":$port " > /dev/null
    else
        if command -v lsof &> /dev/null; then
            lsof -i ":$port" > /dev/null 2>&1
        else
            return 1
        fi
    fi
}

stop_conflicting_services() {
    print_status "Остановка конфликтующих сервисов..."

    local services=("apache2" "httpd" "nginx" "systemd-resolved" "bind9" "named" "dnsmasq")

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            print_status "Остановка сервиса: $service"
            systemctl stop "$service" || true
            systemctl disable "$service" || true
        fi
    done

    # Освобождение DNS портов
    systemctl mask systemd-resolved 2>/dev/null || true
    pkill -9 dnsmasq 2>/dev/null || true
    pkill -9 named 2>/dev/null || true

    sleep 3
    print_status "Конфликтующие сервисы остановлены ✅"
}

check_ports() {
    print_header "ПРОВЕРКА ПОРТОВ"

    local ports=("$VLESS_PORT" "$XUI_PORT" "$ADGUARD_PORT" "80" "53")
    local blocked_ports=()

    for port in "${ports[@]}"; do
        if check_port_in_use "$port"; then
            blocked_ports+=("$port")
            print_warning "Порт $port занят"
        fi
    done

    if [ ${#blocked_ports[@]} -gt 0 ]; then
        print_warning "Заняты порты: ${blocked_ports[*]}"
        if [ "$AUTO_CONFIRM" != true ]; then
            read -p "Остановить конфликтующие сервисы? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                stop_conflicting_services
            fi
        else
            stop_conflicting_services
        fi
    fi

    print_status "Проверка портов завершена ✅"
}

# ===============================================
# ФУНКЦИИ ВАЛИДАЦИИ
# ===============================================

validate_domain() {
    local domain="$1"

    if [ -z "$domain" ]; then
        return 1
    fi

    if [[ ! $domain =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        return 1
    fi

    if [ ${#domain} -gt 253 ]; then
        return 1
    fi

    return 0
}

validate_email() {
    local email="$1"

    if [ -z "$email" ]; then
        return 1
    fi

    if ! echo "$email" | grep -E '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' > /dev/null; then
        return 1
    fi

    if [ ${#email} -gt 254 ]; then
        return 1
    fi

    return 0
}

validate_ports() {
    for port_var in VLESS_PORT XUI_PORT ADGUARD_PORT; do
        port_value="${!port_var}"
        if ! [[ "$port_value" =~ ^[0-9]+$ ]] || [ "$port_value" -lt 1 ] || [ "$port_value" -gt 65535 ]; then
            print_error "Неверный порт для $port_var: $port_value"
            exit 1
        fi
    done

    if [ "$VLESS_PORT" = "$XUI_PORT" ] || [ "$VLESS_PORT" = "$ADGUARD_PORT" ] || [ "$XUI_PORT" = "$ADGUARD_PORT" ]; then
        print_error "Порты не должны дублироваться"
        exit 1
    fi

    print_status "Порт VLESS: $VLESS_PORT"
    print_status "Порт 3X-UI: $XUI_PORT"
    print_status "Порт AdGuard: $ADGUARD_PORT"
}

# ===============================================
# ФУНКЦИИ РАБОТЫ С DNS
# ===============================================

get_server_ip() {
    local ip=""
    local services=("ifconfig.me" "icanhazip.com" "ipecho.net/plain" "ifconfig.co")

    for service in "${services[@]}"; do
        ip=$(timeout 10 curl -s --max-time 5 "https://$service" 2>/dev/null | tr -d '\n\r' || echo "")
        if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "$ip"
            return 0
        fi
    done

    echo "unknown"
}

resolve_domain() {
    local domain="$1"
    local ip=""

    if command -v dig &> /dev/null; then
        ip=$(timeout 10 dig +short "$domain" +time=5 2>/dev/null | head -n1)
    elif command -v nslookup &> /dev/null; then
        ip=$(timeout 10 nslookup "$domain" 2>/dev/null | awk '/^Address: / { print $2 }' | head -n1)
    fi

    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "$ip"
    else
        echo ""
    fi
}

check_domain_dns() {
    print_header "ПРОВЕРКА DNS"

    local server_ip
    server_ip=$(get_server_ip)

    if [ "$server_ip" = "unknown" ]; then
        print_warning "Не удалось определить IP сервера"
        return 0
    fi

    print_status "IP сервера: $server_ip"

    local domain_ip
    domain_ip=$(resolve_domain "$DOMAIN")

    if [ -n "$domain_ip" ]; then
        print_status "IP домена: $domain_ip"
        if [ "$server_ip" != "$domain_ip" ]; then
            print_warning "DNS домена не указывает на этот сервер"
            print_warning "Это может вызвать проблемы с SSL сертификатом"
        else
            print_status "DNS настроен правильно ✅"
        fi
    else
        print_warning "Не удалось разрешить домен $DOMAIN"
    fi
}

# ===============================================
# ФУНКЦИИ ГЕНЕРАЦИИ ПАРОЛЕЙ
# ===============================================

generate_secure_password() {
    local length=${1:-20}

    if command -v openssl &> /dev/null; then
        openssl rand -base64 32 | tr -d "=+/" | cut -c1-${length}
    else
        < /dev/urandom tr -dc 'A-Za-z0-9' | head -c${length}
    fi
}

generate_passwords() {
    if [ -z "$XUI_PASSWORD" ]; then
        if [ "$AUTO_PASSWORD" = true ]; then
            XUI_PASSWORD=$(generate_secure_password 20)
            print_status "Сгенерирован пароль для 3X-UI"
        else
            read -p "Введите пароль для 3X-UI (Enter для автогенерации): " XUI_PASSWORD
            if [ -z "$XUI_PASSWORD" ]; then
                XUI_PASSWORD=$(generate_secure_password 20)
                print_status "Сгенерирован пароль для 3X-UI"
            fi
        fi
    fi

    if [ -z "$ADGUARD_PASSWORD" ]; then
        if [ "$AUTO_PASSWORD" = true ]; then
            ADGUARD_PASSWORD=$(generate_secure_password 20)
            print_status "Сгенерирован пароль для AdGuard"
        else
            read -p "Введите пароль для AdGuard (Enter для автогенерации): " ADGUARD_PASSWORD
            if [ -z "$ADGUARD_PASSWORD" ]; then
                ADGUARD_PASSWORD=$(generate_secure_password 20)
                print_status "Сгенерирован пароль для AdGuard"
            fi
        fi
    fi
}

# ===============================================
# ФУНКЦИИ ПОЛЬЗОВАТЕЛЬСКОГО ВВОДА
# ===============================================

get_user_input() {
    print_header "НАСТРОЙКА ПАРАМЕТРОВ"

    # Домен
    if [ -z "$DOMAIN" ]; then
        while true; do
            read -p "Введите ваш домен (например, vpn.example.com): " DOMAIN
            if validate_domain "$DOMAIN"; then
                break
            else
                print_error "Неверный формат домена"
            fi
        done
    else
        if ! validate_domain "$DOMAIN"; then
            print_error "Неверный формат домена: $DOMAIN"
            exit 1
        fi
        print_status "Домен: $DOMAIN"
    fi

    # Email
    if [ -z "$EMAIL" ]; then
        while true; do
            read -p "Введите email для SSL сертификата: " EMAIL
            if validate_email "$EMAIL"; then
                break
            else
                print_error "Неверный формат email"
            fi
        done
    else
        if ! validate_email "$EMAIL"; then
            print_error "Неверный формат email: $EMAIL"
            exit 1
        fi
        print_status "Email: $EMAIL"
    fi

    # Генерация паролей
    generate_passwords

    # Валидация портов
    validate_ports

    # Финальное подтверждение
    if [ "$AUTO_CONFIRM" != true ]; then
        echo ""
        print_warning "Проверьте настройки:"
        echo "  Домен: $DOMAIN"
        echo "  Email: $EMAIL"
        echo "  Порт VLESS: $VLESS_PORT"
        echo "  Порт 3X-UI: $XUI_PORT"
        echo "  Порт AdGuard: $ADGUARD_PORT"
        echo ""
        read -p "Начать установку? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Установка отменена"
            exit 0
        fi
    fi

    save_install_state "parameters_configured"
}

# ===============================================
# ФУНКЦИИ НАСТРОЙКИ FIREWALL
# ===============================================

configure_firewall() {
    print_header "НАСТРОЙКА FIREWALL"
    save_install_state "configuring_firewall"

    # Установка UFW если нет
    if ! command -v ufw &> /dev/null; then
        if command -v apt-get &> /dev/null; then
            apt-get install -y -qq ufw
        elif command -v yum &> /dev/null; then
            yum install -y -q ufw
        elif command -v dnf &> /dev/null; then
            dnf install -y -q ufw
        fi
    fi

    # Настройка UFW
    ufw --force reset >/dev/null 2>&1
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1

    # SSH порт
    local ssh_port="22"
    if command -v ss &> /dev/null; then
        ssh_port=$(ss -tlnp | awk '/sshd.*LISTEN/ {split($4,a,":"); print a[length(a)]}' | head -n1)
    fi
    [ -z "$ssh_port" ] && ssh_port="22"

    # Открытие портов
    ufw allow "$ssh_port"/tcp comment "SSH" >/dev/null 2>&1
    ufw allow 80/tcp comment "HTTP" >/dev/null 2>&1
    ufw allow 443/tcp comment "HTTPS" >/dev/null 2>&1
    ufw allow "$XUI_PORT"/tcp comment "3X-UI" >/dev/null 2>&1
    ufw allow "$ADGUARD_PORT"/tcp comment "AdGuard" >/dev/null 2>&1
    ufw allow 53/tcp comment "DNS TCP" >/dev/null 2>&1
    ufw allow 53/udp comment "DNS UDP" >/dev/null 2>&1

    if [ "$VLESS_PORT" != "443" ]; then
        ufw allow "$VLESS_PORT"/tcp comment "VLESS" >/dev/null 2>&1
    fi

    ufw --force enable >/dev/null 2>&1

    print_status "Firewall настроен ✅"
}

# ===============================================
# ФУНКЦИИ УСТАНОВКИ NGINX
# ===============================================

install_nginx() {
    print_header "УСТАНОВКА NGINX"
    save_install_state "installing_nginx"

    if command -v apt-get &> /dev/null; then
        apt-get install -y -qq nginx
    elif command -v yum &> /dev/null; then
        yum install -y -q nginx
    elif command -v dnf &> /dev/null; then
        dnf install -y -q nginx
    fi

    # Создание директорий
    mkdir -p /var/www/html
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled

    systemctl enable nginx
    systemctl stop nginx || true

    print_status "Nginx установлен ✅"
}

install_certbot() {
    print_header "УСТАНОВКА CERTBOT"
    save_install_state "installing_certbot"

    if command -v apt-get &> /dev/null; then
        if command -v snap &> /dev/null; then
            snap install --classic certbot 2>/dev/null || apt-get install -y -qq certbot python3-certbot-nginx
        else
            apt-get install -y -qq certbot python3-certbot-nginx
        fi
    elif command -v yum &> /dev/null; then
        yum install -y -q certbot python3-certbot-nginx
    elif command -v dnf &> /dev/null; then
        dnf install -y -q certbot python3-certbot-nginx
    fi

    # Создание симлинка если нужно
    if [ -f "/snap/bin/certbot" ] && [ ! -f "/usr/bin/certbot" ]; then
        ln -sf /snap/bin/certbot /usr/bin/certbot
    fi

    print_status "Certbot установлен ✅"
}

get_ssl_certificate() {
    print_header "ПОЛУЧЕНИЕ SSL СЕРТИФИКАТА"
    save_install_state "getting_ssl_certificate"

    # Создание временной конфигурации nginx
    cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
    echo "Server setup in progress..." > /var/www/html/index.html

    # Запуск nginx
    systemctl start nginx
    sleep 3

    if ! systemctl is-active --quiet nginx; then
        print_error "Nginx не запустился"
        exit 1
    fi

    # Получение сертификата
    print_status "Получение SSL сертификата для $DOMAIN..."

    if certbot certonly --webroot --webroot-path=/var/www/html --email "$EMAIL" --agree-tos --non-interactive --domains "$DOMAIN"; then
        print_status "SSL сертификат получен ✅"

        # Автообновление
        cat > /etc/cron.d/certbot-renewal << 'EOF'
0 12 * * * root /usr/bin/certbot renew --quiet --post-hook "systemctl reload nginx"
EOF
        systemctl enable cron 2>/dev/null || systemctl enable crond 2>/dev/null || true

    else
        print_error "Не удалось получить SSL сертификат"
        print_error "Проверьте что домен $DOMAIN указывает на IP $(get_server_ip)"
        exit 1
    fi
}

# ===============================================
# ФУНКЦИИ УСТАНОВКИ 3X-UI
# ===============================================

install_3x_ui() {
    print_header "УСТАНОВКА 3X-UI"
    save_install_state "installing_3x_ui"

    # Попытка автоматической установки
    if install_3x_ui_automatic; then
        print_status "3X-UI установлен автоматически ✅"
    else
        print_warning "Переходим к ручной установке"
        install_3x_ui_manual
    fi

    configure_3x_ui
    print_status "3X-UI установлен и настроен ✅"
}

install_3x_ui_automatic() {
    print_status "Автоматическая установка 3X-UI..."

    # Скачивание скрипта
    if ! curl -Ls "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh" > /tmp/3x-ui-install.sh; then
        return 1
    fi

    chmod +x /tmp/3x-ui-install.sh

    # Автоматическая установка
    echo -e "y\n$XUI_USERNAME\n$XUI_PASSWORD\n$XUI_PORT\ny\n" | timeout 300 bash /tmp/3x-ui-install.sh 2>/dev/null || return 1

    # Проверка успешности
    if [ -f "/opt/3x-ui/x-ui" ] && [ -f "/etc/systemd/system/x-ui.service" ]; then
        return 0
    else
        return 1
    fi
}

install_3x_ui_manual() {
    print_status "Ручная установка 3X-UI..."

    cd /opt

    # Получение версии
    local version
    version=$(curl -s "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep -oP '"tag_name": "\K[^"]*' || echo "v2.3.4")

    # Скачивание
    local url="https://github.com/MHSanaei/3x-ui/releases/download/$version/x-ui-linux-${ARCH}.tar.gz"

    if ! wget -q --show-progress "$url" -O x-ui.tar.gz; then
        print_error "Не удалось скачать 3X-UI"
        exit 1
    fi

    tar -zxf x-ui.tar.gz
    rm x-ui.tar.gz

    if [ -d "x-ui" ]; then
        mv x-ui 3x-ui
    fi

    cd 3x-ui
    chmod +x x-ui

    # Создание сервиса
    create_3xui_service
    systemctl daemon-reload
    systemctl enable x-ui
}

create_3xui_service() {
    cat > /etc/systemd/system/x-ui.service << EOF
[Unit]
Description=3x-ui Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/3x-ui
ExecStart=/opt/3x-ui/x-ui
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

configure_3x_ui() {
    print_status "Настройка 3X-UI..."

    systemctl start x-ui

    # Ожидание запуска
    local attempts=0
    while [ $attempts -lt 30 ]; do
        if systemctl is-active --quiet x-ui; then
            break
        fi
        sleep 2
        attempts=$((attempts + 1))
    done

    if systemctl is-active --quiet x-ui; then
        print_status "3X-UI запущен на порту $XUI_PORT ✅"

        # Настройка через CLI если возможно
        if [ -f "/opt/3x-ui/x-ui" ]; then
            /opt/3x-ui/x-ui setting -username "$XUI_USERNAME" -password "$XUI_PASSWORD" -port "$XUI_PORT" 2>/dev/null || true
            systemctl restart x-ui
        fi
    else
        print_error "3X-UI не запустился"
        journalctl -u x-ui --no-pager -n 20
        exit 1
    fi
}

# ===============================================
# ФУНКЦИИ УСТАНОВКИ ADGUARD HOME
# ===============================================

install_adguard() {
    print_header "УСТАНОВКА ADGUARD HOME"
    save_install_state "installing_adguard"

    # Остановка DNS сервисов
    systemctl stop systemd-resolved 2>/dev/null || true
    systemctl disable systemd-resolved 2>/dev/null || true

    # Создание директории
    mkdir -p /opt/AdGuardHome
    cd /opt/AdGuardHome

    # Скачивание
    local url="https://static.adguard.com/adguardhome/release/AdGuardHome_linux_${ARCH}.tar.gz"

    if ! wget -q --show-progress "$url" -O AdGuardHome.tar.gz; then
        print_error "Не удалось скачать AdGuard Home"
        exit 1
    fi

    tar -zxf AdGuardHome.tar.gz

    if [ -d "AdGuardHome" ]; then
        mv AdGuardHome/* ./
        rmdir AdGuardHome
    fi

    rm -f AdGuardHome.tar.gz
    chmod +x AdGuardHome

    # Создание сервиса
    create_adguard_service

    # Создание конфигурации
    create_adguard_config

    systemctl daemon-reload
    systemctl enable AdGuardHome

    print_status "AdGuard Home установлен ✅"
}

create_adguard_service() {
    cat > /etc/systemd/system/AdGuardHome.service << EOF
[Unit]
Description=AdGuard Home
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/AdGuardHome
ExecStart=/opt/AdGuardHome/AdGuardHome --config /opt/AdGuardHome/AdGuardHome.yaml --work-dir /opt/AdGuardHome
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

create_adguard_config() {
    print_status "Создание конфигурации AdGuard..."

    # Создание поддиректорий
    mkdir -p /opt/AdGuardHome/data
    mkdir -p /opt/AdGuardHome/work

    # Генерация хеша пароля
    local password_hash
    if command -v htpasswd &> /dev/null; then
        password_hash=$(htpasswd -bnBC 12 "" "$ADGUARD_PASSWORD" | tr -d ':\n' | sed 's/^[^$]*//')
    else
        password_hash="\$2a\$12\$$(echo -n "$ADGUARD_PASSWORD" | openssl passwd -apr1 -stdin | cut -d'$' -f4-)"
    fi

    cat > /opt/AdGuardHome/AdGuardHome.yaml << EOF
bind_host: 0.0.0.0
bind_port: $ADGUARD_PORT
users:
  - name: admin
    password: $password_hash
auth_attempts: 5
block_auth_min: 15
http_proxy: ""
language: ru
theme: auto
debug_pprof: false
web_session_ttl: 720
dns:
  bind_hosts:
    - 0.0.0.0
  port: 53
  statistics_interval: 90
  querylog_enabled: true
  querylog_file_enabled: true
  querylog_interval: 2160h
  querylog_size_memory: 1000
  anonymize_client_ip: false
  protection_enabled: true
  blocking_mode: default
  blocking_ipv4: ""
  blocking_ipv6: ""
  blocked_response_ttl: 10
  parental_block_host: family-block.dns.adguard.com
  safebrowsing_block_host: standard-block.dns.adguard.com
  rewrites: []
  safebrowsing_cache_size: 1048576
  safesearch_cache_size: 1048576
  parental_cache_size: 1048576
  cache_size: 4194304
  cache_ttl_min: 0
  cache_ttl_max: 0
  cache_optimistic: false
  bogus_nxdomain: []
  aaaa_disabled: false
  enable_dnssec: false
  edns_client_subnet:
    custom_ip: ""
    enabled: false
    use_custom: false
  max_goroutines: 300
  handle_ddr: true
  ipset: []
  ipset_file: ""
  bootstrap_dns:
    - 9.9.9.10
    - 149.112.112.10
    - 2620:fe::10
    - 2620:fe::fe:10
  all_servers: false
  fastest_addr: false
  fastest_timeout: 1s
  allowed_clients: []
  disallowed_clients: []
  blocked_hosts:
    - version.bind
    - id.server
    - hostname.bind
  trusted_proxies:
    - 127.0.0.0/8
    - ::1/128
  upstream_dns:
    - https://dns.cloudflare.com/dns-query
    - https://dns.google/dns-query
    - https://dns.quad9.net/dns-query
    - 1.1.1.1
    - 1.0.0.1
    - 8.8.8.8
    - 8.8.4.4
  upstream_dns_file: ""
  upstream_timeout: 10s
  private_networks: []
  use_dns64: false
  dns64_prefixes: []
  serve_plain_dns: true
  filtering_enabled: true
  filters_update_interval: 24
  parental_enabled: false
  safesearch_enabled: false
  safebrowsing_enabled: true
  resolve_clients: true
  use_private_ptr_resolvers: true
  local_ptr_upstreams: []
  serve_http3: false
  use_http3_upstreams: false
tls:
  enabled: false
  server_name: ""
  force_https: false
  port_https: 443
  port_dns_over_tls: 853
  port_dns_over_quic: 853
  port_dnscrypt: 0
  dnscrypt_config_file: ""
  allow_unencrypted_doh: false
  certificate_chain: ""
  private_key: ""
  certificate_path: ""
  private_key_path: ""
  strict_sni_check: false
filters:
  - enabled: true
    url: https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
    name: AdGuard DNS filter
    id: 1
  - enabled: true
    url: https://someonewhocares.org/hosts/zero/hosts
    name: Dan Pollock's List
    id: 2
  - enabled: true
    url: https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
    name: Steven Black's List
    id: 3
whitelist_filters: []
user_rules:
  - '@@||speedtest.net^'
  - '@@||fast.com^'
  - '@@||netflix.com^'
  - '@@||youtube.com^'
dhcp:
  enabled: false
  interface_name: ""
  local_domain_name: lan
  dhcpv4:
    gateway_ip: ""
    subnet_mask: ""
    range_start: ""
    range_end: ""
    lease_duration: 86400
    icmp_timeout_msec: 1000
    options: []
  dhcpv6:
    range_start: ""
    lease_duration: 86400
    ra_slaac_only: false
    ra_allow_slaac: false
clients:
  runtime_sources:
    whois: true
    arp: true
    rdns: true
    dhcp: true
    hosts: true
  persistent: []
log_file: ""
log_max_backups: 0
log_max_size: 100
log_max_age: 3
log_compress: false
log_localtime: false
verbose: false
os:
  group: ""
  user: ""
  rlimit_nofile: 0
schema_version: 20
EOF

    chmod 644 /opt/AdGuardHome/AdGuardHome.yaml
    print_status "Конфигурация AdGuard создана ✅"
}

configure_adguard() {
    print_header "НАСТРОЙКА ADGUARD HOME"
    save_install_state "configuring_adguard"

    # Освобождение порта 53
    if check_port_in_use "53"; then
        print_status "Освобождение порта 53..."
        systemctl stop systemd-resolved 2>/dev/null || true
        pkill -9 dnsmasq 2>/dev/null || true

        if [ -f /etc/resolv.conf ]; then
            cp /etc/resolv.conf /etc/resolv.conf.backup
            echo "nameserver 8.8.8.8" > /etc/resolv.conf
            echo "nameserver 1.1.1.1" >> /etc/resolv.conf
        fi
    fi

    # Запуск AdGuard
    systemctl start AdGuardHome

    # Ожидание запуска
    local attempts=0
    while [ $attempts -lt 30 ]; do
        if systemctl is-active --quiet AdGuardHome; then
            break
        fi
        sleep 2
        attempts=$((attempts + 1))
    done

    if systemctl is-active --quiet AdGuardHome; then
        print_status "AdGuard Home запущен на порту $ADGUARD_PORT ✅"

        # Проверка веб-интерфейса
        sleep 5
        if timeout 10 curl -s "http://localhost:$ADGUARD_PORT" > /dev/null; then
            print_status "Веб-интерфейс AdGuard доступен ✅"
        fi
    else
        print_error "AdGuard Home не запустился"
        systemctl status AdGuardHome
        journalctl -u AdGuardHome --no-pager -n 20
        exit 1
    fi
}

# ===============================================
# ФУНКЦИИ ФИНАЛЬНОЙ НАСТРОЙКИ
# ===============================================

configure_nginx_final() {
    print_header "ФИНАЛЬНАЯ НАСТРОЙКА NGINX"
    save_install_state "configuring_nginx_final"

    # Создание SSL конфигурации
    create_nginx_ssl_config

    # Создание главной страницы
    create_main_page

    # Проверка и перезагрузка
    if nginx -t; then
        systemctl reload nginx
        print_status "Nginx настроен ✅"
    else
        print_error "Ошибка в конфигурации Nginx"
        nginx -t
        exit 1
    fi
}

create_nginx_ssl_config() {
    cat > /etc/nginx/sites-available/default << EOF
server_tokens off;

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        root /var/www/html;
        index index.html;
        try_files \$uri \$uri/ =404;
    }

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
}
EOF

    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
}

create_main_page() {
    local server_ip
    server_ip=$(get_server_ip)

    cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🛡️ VPN Server - $DOMAIN</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: #333;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 900px;
            margin: 0 auto;
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
            color: white;
            text-align: center;
            padding: 40px 20px;
        }
        .header h1 {
            font-size: 2.5rem;
            margin-bottom: 10px;
            font-weight: 700;
        }
        .content { padding: 40px; }
        .info-card {
            background: #f8f9fa;
            border-radius: 12px;
            padding: 25px;
            margin-bottom: 25px;
            border-left: 4px solid #28a745;
        }
        .panel {
            background: white;
            border: 1px solid #dee2e6;
            border-radius: 12px;
            padding: 25px;
            margin-bottom: 25px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .button {
            display: inline-block;
            padding: 12px 24px;
            background: linear-gradient(135deg, #007bff, #0056b3);
            color: white;
            text-decoration: none;
            border-radius: 8px;
            margin: 8px 8px 8px 0;
            font-weight: 500;
            transition: all 0.3s ease;
        }
        .button:hover {
            transform: translateY(-2px);
            text-decoration: none;
            color: white;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        .stat-item {
            text-align: center;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 8px;
        }
        .stat-value {
            font-size: 1.5rem;
            font-weight: 700;
            color: #007bff;
        }
        .footer {
            background: #343a40;
            color: white;
            text-align: center;
            padding: 30px;
        }
        .status-indicator {
            display: inline-block;
            width: 10px;
            height: 10px;
            background: #28a745;
            border-radius: 50%;
            margin-right: 8px;
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.5; }
            100% { opacity: 1; }
        }
        @media (max-width: 768px) {
            .header h1 { font-size: 2rem; }
            .content { padding: 20px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🛡️ VPN Server</h1>
            <p>Безопасное соединение установлено</p>
        </div>

        <div class="content">
            <div class="info-card">
                <h4><span class="status-indicator"></span><strong>Статус: Сервер успешно настроен</strong></h4>
                <p><strong>Домен:</strong> $DOMAIN</p>
                <p><strong>IP сервера:</strong> $server_ip</p>
                <p><strong>Дата установки:</strong> $(date '+%d.%m.%Y %H:%M')</p>
            </div>

            <div class="panel">
                <h3>📊 Панели управления</h3>
                <p>Прямой доступ к интерфейсам управления:</p>
                <a href="https://$DOMAIN:$XUI_PORT" class="button" target="_blank">3X-UI Panel</a>
                <a href="http://$DOMAIN:$ADGUARD_PORT" class="button" target="_blank">AdGuard Home</a>
                <div style="margin-top: 15px; padding: 10px; background: #e9ecef; border-radius: 6px;">
                    <small><strong>Логин:</strong> admin<br>
                    <strong>Пароли:</strong> указаны в файле /root/vpn-server-info.txt</small>
                </div>
            </div>

            <div class="stats-grid">
                <div class="stat-item">
                    <div class="stat-value">$VLESS_PORT</div>
                    <div class="stat-label">VLESS Port</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value">$XUI_PORT</div>
                    <div class="stat-label">3X-UI Port</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value">$ADGUARD_PORT</div>
                    <div class="stat-label">AdGuard Port</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value">53</div>
                    <div class="stat-label">DNS Port</div>
                </div>
            </div>

            <div class="panel">
                <h3>📱 Настройка VPN</h3>
                <ol style="margin: 15px 0 15px 20px;">
                    <li>Откройте 3X-UI панель по ссылке выше</li>
                    <li>Войдите используя логин "admin" и пароль из файла инструкций</li>
                    <li>Создайте нового пользователя VLESS с TLS</li>
                    <li>Используйте домен: <strong>$DOMAIN</strong> и порт: <strong>$VLESS_PORT</strong></li>
                    <li>Скачайте конфигурацию или QR-код</li>
                    <li>Импортируйте в VPN клиент</li>
                </ol>

                <div style="background: #fff3cd; padding: 15px; border-radius: 8px; margin: 15px 0;">
                    <h5>📱 Рекомендуемые клиенты:</h5>
                    <p><strong>Android:</strong> v2rayNG</p>
                    <p><strong>iOS:</strong> Shadowrocket</p>
                    <p><strong>Windows:</strong> v2rayN</p>
                    <p><strong>macOS:</strong> ClashX</p>
                </div>
            </div>

            <div class="panel">
                <h3>🛡️ DNS с блокировкой рекламы</h3>
                <p>DNS сервер для автоматической блокировки рекламы:</p>
                <div style="margin: 15px 0; padding: 10px; background: #f8f9fa; border-radius: 6px;">
                    <p><strong>DNS:</strong> $server_ip или $DOMAIN</p>
                    <p><strong>Порт:</strong> 53</p>
                </div>
                <p>Настройте в параметрах сети вашего устройства.</p>
            </div>
        </div>

        <div class="footer">
            <p>🚀 Powered by <strong>VPN Auto Installer v$SCRIPT_VERSION</strong></p>
            <p>Создано для обеспечения безопасности в интернете</p>
        </div>
    </div>
</body>
</html>
EOF
}

create_instructions() {
    print_header "СОЗДАНИЕ ИНСТРУКЦИЙ"

    local instructions_file="/root/vpn-server-info.txt"
    local server_ip
    server_ip=$(get_server_ip)

    cat > "$instructions_file" << EOF
╔═══════════════════════════════════════════════════════════════╗
║                    VPN SERVER INFORMATION                    ║
╚═══════════════════════════════════════════════════════════════╝

Дата установки: $(date)
Версия скрипта: $SCRIPT_VERSION
Домен: $DOMAIN
IP сервера: $server_ip

╔═══════════════════════════════════════════════════════════════╗
║                        ДОСТУП К ПАНЕЛЯМ                      ║
╚═══════════════════════════════════════════════════════════════╝

🌐 Главная страница: https://$DOMAIN

📊 3X-UI Панель: https://$DOMAIN:$XUI_PORT
   Логин: $XUI_USERNAME
   Пароль: $XUI_PASSWORD

🛡️ AdGuard Home: http://$DOMAIN:$ADGUARD_PORT
   Логин: admin
   Пароль: $ADGUARD_PASSWORD

╔═══════════════════════════════════════════════════════════════╗
║                          ПОРТЫ                               ║
╚═══════════════════════════════════════════════════════════════╝

VLESS: $VLESS_PORT
3X-UI: $XUI_PORT
AdGuard: $ADGUARD_PORT
DNS: 53
HTTP: 80 → HTTPS redirect
HTTPS: 443

╔═══════════════════════════════════════════════════════════════╗
║                      НАСТРОЙКА VPN                           ║
╚═══════════════════════════════════════════════════════════════╝

1. Откройте 3X-UI: https://$DOMAIN:$XUI_PORT
2. Войдите (логин: $XUI_USERNAME, пароль выше)
3. Создайте пользователя VLESS с TLS
4. Домен: $DOMAIN, Порт: $VLESS_PORT
5. Скачайте конфигурацию или QR-код
6. Импортируйте в VPN клиент

Клиенты:
- Android: v2rayNG
- iOS: Shadowrocket
- Windows: v2rayN
- macOS: ClashX

╔═══════════════════════════════════════════════════════════════╗
║                      DNS БЛОКИРОВКА                          ║
╚═══════════════════════════════════════════════════════════════╝

DNS сервер: $server_ip или $DOMAIN
Порт: 53

Настройте в параметрах сети для блокировки рекламы.

╔═══════════════════════════════════════════════════════════════╗
║                    УПРАВЛЕНИЕ СЕРВИСАМИ                      ║
╚═══════════════════════════════════════════════════════════════╝

Статус:
systemctl status x-ui
systemctl status AdGuardHome
systemctl status nginx

Перезапуск:
systemctl restart x-ui
systemctl restart AdGuardHome
systemctl restart nginx

Логи:
journalctl -u x-ui -f
journalctl -u AdGuardHome -f
journalctl -u nginx -f

╔═══════════════════════════════════════════════════════════════╗
║                        БЕЗОПАСНОСТЬ                          ║
╚═══════════════════════════════════════════════════════════════╝

✅ SSL сертификат (автообновление настроено)
✅ Firewall настроен
✅ Безопасные конфигурации сервисов

Рекомендации:
- Регулярно обновляйте систему
- Меняйте пароли каждые 3-6 месяцев
- Мониторьте логи сервисов
- Делайте резервные копии

СОХРАНИТЕ ЭТОТ ФАЙЛ В БЕЗОПАСНОМ МЕСТЕ!

EOF

    chmod 600 "$instructions_file"
    print_status "Инструкции созданы: $instructions_file"
}

show_final_info() {
    echo ""
    print_header "УСТАНОВКА ЗАВЕРШЕНА"
    echo ""
    print_status "🎉 VPN-сервер успешно установлен и настроен!"
    echo ""
    echo -e "${GREEN}🌐 Главная страница:${NC} https://$DOMAIN"
    echo ""
    echo -e "${GREEN}📊 3X-UI Панель:${NC} https://$DOMAIN:$XUI_PORT"
    echo -e "${GREEN}   Логин:${NC} $XUI_USERNAME"
    echo -e "${GREEN}   Пароль:${NC} $XUI_PASSWORD"
    echo ""
    echo -e "${GREEN}🛡️ AdGuard Home:${NC} http://$DOMAIN:$ADGUARD_PORT"
    echo -e "${GREEN}   Логин:${NC} admin"
    echo -e "${GREEN}   Пароль:${NC} $ADGUARD_PASSWORD"
    echo ""
    echo -e "${GREEN}🔒 DNS сервер:${NC} $(get_server_ip):53"
    echo ""
    print_warning "ВАЖНО: Сохраните пароли в безопасном месте!"
    print_status "📋 Инструкции: /root/vpn-server-info.txt"
    print_status "📝 Логи: $LOG_FILE"
    echo ""
    print_status "Перейдите на https://$DOMAIN для начала работы"
    echo ""
}

cleanup() {
    print_header "ЗАВЕРШЕНИЕ"

    # Удаление временных файлов
    rm -f "$INSTALL_STATE_FILE"
    rm -f /tmp/3x-ui-install.sh
    rm -f /tmp/x-ui.tar.gz
    rm -f /tmp/AdGuardHome.tar.gz

    # Восстановление автообновлений
    restore_auto_updates

    # Очистка кеша пакетов
    if command -v apt-get &> /dev/null; then
        apt-get autoremove -y >/dev/null 2>&1 || true
        apt-get autoclean >/dev/null 2>&1 || true
    fi

    print_status "Очистка завершена ✅"
}

# ===============================================
# ГЛАВНАЯ ФУНКЦИЯ
# ===============================================

main() {
    # Парсинг аргументов
    parse_args "$@"

    # Баннер
    show_banner

    # Проверка восстановления
    if load_install_state; then
        case "$INSTALL_STEP" in
            "parameters_configured")
                install_dependencies
                configure_firewall
                install_nginx
                install_certbot
                get_ssl_certificate
                install_3x_ui
                install_adguard
                configure_adguard
                configure_nginx_final
                create_instructions
                show_final_info
                cleanup
                return 0
                ;;
            "installing_dependencies")
                configure_firewall
                install_nginx
                install_certbot
                get_ssl_certificate
                install_3x_ui
                install_adguard
                configure_adguard
                configure_nginx_final
                create_instructions
                show_final_info
                cleanup
                return 0
                ;;
            *)
                print_status "Продолжаем с этапа: $INSTALL_STEP"
                ;;
        esac
    fi

    # Полная установка
    check_root
    detect_system
    get_user_input
    check_ports
    check_domain_dns
    install_dependencies
    configure_firewall
    install_nginx
    install_certbot
    get_ssl_certificate
    install_3x_ui
    install_adguard
    configure_adguard
    configure_nginx_final
    create_instructions
    show_final_info
    cleanup

    print_status "🎉 Все операции завершены успешно!"
}

# Запуск
main "$@"
