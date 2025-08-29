#!/bin/bash

# install_vpn_adguard.sh
# Скрипт автоматической установки VPN-сервера с VLESS + TLS + 3X-UI + AdGuard Home
# Автор: KodoDrive
# Версия: 3.1 (полностью переписанная с исправлениями)
# Дата: $(date)

set -euo pipefail

# ===============================================
# ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
# ===============================================

readonly SCRIPT_VERSION="3.1.0"
readonly SCRIPT_NAME="VPN Server Auto Installer"
readonly LOG_FILE="/var/log/vpn-installer.log"
readonly STATE_FILE="/tmp/vpn-install-state"

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Конфигурационные переменные
DOMAIN=""
EMAIL=""
XUI_USERNAME="admin"
XUI_PASSWORD=""
ADGUARD_PASSWORD=""
VLESS_PORT="443"
XUI_PORT="54321"
ADGUARD_PORT="3000"

# Флаги режимов
AUTO_PASSWORD=false
AUTO_CONFIRM=false
DEBUG_MODE=false

# Системные переменные (будут определены автоматически)
OS_ID=""
OS_NAME=""
OS_VERSION=""
ARCH=""
RAM_MB=0
DISK_GB=0
SERVER_IP=""

# Поддерживаемые системы
readonly SUPPORTED_DISTROS=("ubuntu" "debian" "centos" "rhel" "fedora" "almalinux" "rocky")

# ===============================================
# ФУНКЦИИ ЛОГИРОВАНИЯ И ВЫВОДА
# ===============================================

setup_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1
    echo "=== Запуск $SCRIPT_NAME v$SCRIPT_VERSION ===" | tee -a "$LOG_FILE"
    echo "Время: $(date)" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_debug() {
    if [[ "$DEBUG_MODE" == true ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1" | tee -a "$LOG_FILE"
    fi
}

print_header() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}║${NC} $(printf "%-36s" "$1") ${BLUE}║${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}" | tee -a "$LOG_FILE"
}

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
║              VPN Server Auto Installer v3.1                  ║
║           VLESS + TLS + 3X-UI + AdGuard Home                 ║
║                                                               ║
║                    Made by KodoDrive                         ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# ===============================================
# ФУНКЦИИ УПРАВЛЕНИЯ СОСТОЯНИЕМ
# ===============================================

save_state() {
    local step="$1"
    cat > "$STATE_FILE" << EOF
DOMAIN="$DOMAIN"
EMAIL="$EMAIL"
XUI_USERNAME="$XUI_USERNAME"
XUI_PASSWORD="$XUI_PASSWORD"
ADGUARD_PASSWORD="$ADGUARD_PASSWORD"
VLESS_PORT="$VLESS_PORT"
XUI_PORT="$XUI_PORT"
ADGUARD_PORT="$ADGUARD_PORT"
CURRENT_STEP="$step"
TIMESTAMP="$(date)"
OS_ID="$OS_ID"
ARCH="$ARCH"
EOF
    log_debug "Состояние сохранено: $step"
}

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
        log_info "Найдено сохраненное состояние. Текущий шаг: $CURRENT_STEP"
        if [[ "$AUTO_CONFIRM" != true ]]; then
            read -p "Продолжить с последнего шага? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                rm -f "$STATE_FILE"
                return 1
            fi
        fi
        return 0
    fi
    return 1
}

cleanup_on_error() {
    local exit_code=$?
    log_error "Ошибка выполнения (код $exit_code). Начинаю откат..."

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
    restore_system_dns

    # Восстановление автообновлений
    restore_system_updates

    systemctl daemon-reload 2>/dev/null || true

    log_info "Откат завершен. Логи: $LOG_FILE"
    exit $exit_code
}

trap cleanup_on_error ERR

# ===============================================
# ФУНКЦИИ ПРОВЕРКИ СИСТЕМЫ
# ===============================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Скрипт должен запускаться с правами root"
        log_info "Используйте: sudo $0"
        exit 1
    fi
}

detect_system() {
    print_header "АНАЛИЗ СИСТЕМЫ"

    # Определение ОС
    if [[ ! -f /etc/os-release ]]; then
        log_error "Не удалось определить операционную систему"
        exit 1
    fi

    source /etc/os-release
    OS_ID="$ID"
    OS_NAME="$NAME"
    OS_VERSION="${VERSION_ID:-unknown}"

    log_info "ОС: $OS_NAME $OS_VERSION"

    # Проверка совместимости
    local supported=false
    for distro in "${SUPPORTED_DISTROS[@]}"; do
        if [[ "$OS_ID" == "$distro"* ]]; then
            supported=true
            break
        fi
    done

    if [[ "$supported" != true ]]; then
        log_error "Неподдерживаемая ОС: $OS_NAME"
        log_info "Поддерживаемые: ${SUPPORTED_DISTROS[*]}"
        exit 1
    fi

    # Определение архитектуры
    case "$(uname -m)" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        *) 
            log_error "Неподдерживаемая архитектура: $(uname -m)"
            exit 1
            ;;
    esac

    log_info "Архитектура: $ARCH"

    # Проверка ресурсов
    RAM_MB=$(free -m | awk 'NR==2{print $2}')
    DISK_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')

    log_info "ОЗУ: ${RAM_MB}MB, Диск: ${DISK_GB}GB"

    # Проверка минимальных требований
    if [[ $RAM_MB -lt 512 ]]; then
        log_error "Недостаточно ОЗУ (минимум 512MB, доступно ${RAM_MB}MB)"
        exit 1
    fi

    if [[ $DISK_GB -lt 2 ]]; then
        log_error "Недостаточно места на диске (минимум 2GB, доступно ${DISK_GB}GB)"
        exit 1
    fi

    # Проверка интернета
    log_info "Проверка подключения к интернету..."
    if ! timeout 15 curl -s --max-time 10 https://google.com >/dev/null 2>&1; then
        log_error "Нет подключения к интернету"
        exit 1
    fi

    # Получение IP сервера
    SERVER_IP=$(get_server_ip)
    log_info "IP сервера: $SERVER_IP"

    log_info "Система совместима ✅"
}

get_server_ip() {
    local ip
    local services=("ifconfig.me" "icanhazip.com" "ipecho.net/plain" "ifconfig.co")

    for service in "${services[@]}"; do
        ip=$(timeout 10 curl -s --max-time 5 "https://$service" 2>/dev/null | tr -d '\n\r' | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$')
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
    done

    echo "unknown"
}

# ===============================================
# ФУНКЦИИ РАБОТЫ С ПАКЕТАМИ
# ===============================================

fix_package_manager() {
    print_header "НАСТРОЙКА ПАКЕТНОГО МЕНЕДЖЕРА"

    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        fix_apt_locks
        disable_auto_updates
        update_package_lists
    elif [[ "$OS_ID" == "centos" ]] || [[ "$OS_ID" == "rhel" ]] || [[ "$OS_ID" == "fedora" ]] || [[ "$OS_ID" == "almalinux" ]] || [[ "$OS_ID" == "rocky" ]]; then
        update_yum_dnf
    fi
}

fix_apt_locks() {
    log_info "Проверка блокировок APT..."

    local max_wait=300
    local waited=0

    while [[ $waited -lt $max_wait ]]; do
        if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && \
           ! fuser /var/lib/dpkg/lock >/dev/null 2>&1 && \
           ! fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
            log_info "APT блокировки освобождены"
            return 0
        fi

        if [[ $waited -eq 0 ]]; then
            log_warn "Ожидание освобождения блокировок APT..."
        fi

        sleep 10
        waited=$((waited + 10))
        echo -n "."
    done

    echo ""
    log_warn "Принудительное освобождение блокировок APT"

    # Остановка процессов
    systemctl stop unattended-upgrades 2>/dev/null || true
    systemctl stop apt-daily.timer 2>/dev/null || true
    systemctl stop apt-daily-upgrade.timer 2>/dev/null || true

    pkill -f "apt" 2>/dev/null || true
    pkill -f "dpkg" 2>/dev/null || true
    pkill -f "unattended-upgrade" 2>/dev/null || true

    sleep 5

    # Удаление блокировок
    rm -f /var/lib/dpkg/lock-frontend
    rm -f /var/lib/dpkg/lock
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock

    # Восстановление dpkg
    dpkg --configure -a 2>/dev/null || true
}

disable_auto_updates() {
    log_info "Временное отключение автообновлений..."

    # Маскируем службы
    systemctl mask apt-daily.timer 2>/dev/null || true
    systemctl mask apt-daily-upgrade.timer 2>/dev/null || true
    systemctl stop unattended-upgrades 2>/dev/null || true

    # Создаем временную конфигурацию
    cat > /etc/apt/apt.conf.d/99temp-disable-auto-update << 'EOF'
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "0";
EOF
}

restore_system_updates() {
    log_info "Восстановление автообновлений..."

    rm -f /etc/apt/apt.conf.d/99temp-disable-auto-update 2>/dev/null
    systemctl unmask apt-daily.timer 2>/dev/null || true
    systemctl unmask apt-daily-upgrade.timer 2>/dev/null || true
}

update_package_lists() {
    log_info "Обновление списков пакетов..."

    export DEBIAN_FRONTEND=noninteractive

    for attempt in {1..3}; do
        if apt-get update -qq; then
            break
        fi
        log_warn "Попытка $attempt обновления не удалась, повторяю..."
        sleep 5
    done

    log_info "Обновление системы..."
    apt-get upgrade -y -qq || log_warn "Частичные проблемы при обновлении"
}

update_yum_dnf() {
    log_info "Обновление системы (RPM-based)..."

    if command -v dnf >/dev/null 2>&1; then
        dnf update -y -q || log_warn "Частичные проблемы при обновлении"
    else
        yum update -y -q || log_warn "Частичные проблемы при обновлении"
    fi
}

install_dependencies() {
    print_header "УСТАНОВКА ЗАВИСИМОСТЕЙ"
    save_state "installing_dependencies"

    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        apt-get install -y -qq \
            curl wget unzip tar \
            software-properties-common \
            ca-certificates gnupg lsb-release \
            net-tools dnsutils \
            apache2-utils openssl \
            systemd ufw cron \
            nginx certbot python3-certbot-nginx || {
            log_error "Не удалось установить зависимости"
            exit 1
        }
    else
        # RPM-based системы
        local pkg_manager="yum"
        if command -v dnf >/dev/null 2>&1; then
            pkg_manager="dnf"
        fi

        $pkg_manager install -y -q \
            curl wget unzip tar \
            ca-certificates \
            net-tools bind-utils \
            httpd-tools openssl \
            systemd firewalld cronie \
            nginx certbot python3-certbot-nginx || {
            log_error "Не удалось установить зависимости"
            exit 1
        }
    fi

    log_info "Зависимости установлены ✅"
}

# ===============================================
# ФУНКЦИИ ВАЛИДАЦИИ И ПОЛЬЗОВАТЕЛЬСКОГО ВВОДА
# ===============================================

validate_domain() {
    local domain="$1"

    [[ -n "$domain" ]] || return 1
    [[ ${#domain} -le 253 ]] || return 1
    [[ "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] || return 1

    return 0
}

validate_email() {
    local email="$1"

    [[ -n "$email" ]] || return 1
    [[ ${#email} -le 254 ]] || return 1
    [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || return 1

    return 0
}

validate_port() {
    local port="$1"

    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    [[ $port -ge 1 && $port -le 65535 ]] || return 1

    return 0
}

generate_password() {
    local length=${1:-20}

    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 32 | tr -d "=+/" | cut -c1-${length}
    else
        < /dev/urandom tr -dc 'A-Za-z0-9' | head -c${length}
    fi
}

get_user_input() {
    print_header "НАСТРОЙКА ПАРАМЕТРОВ"

    # Домен
    if [[ -z "$DOMAIN" ]]; then
        while true; do
            read -p "Введите ваш домен (например, vpn.example.com): " DOMAIN
            if validate_domain "$DOMAIN"; then
                break
            else
                log_error "Неверный формат домена"
            fi
        done
    else
        if ! validate_domain "$DOMAIN"; then
            log_error "Неверный домен: $DOMAIN"
            exit 1
        fi
    fi
    log_info "Домен: $DOMAIN"

    # Email
    if [[ -z "$EMAIL" ]]; then
        while true; do
            read -p "Введите email для SSL сертификата: " EMAIL
            if validate_email "$EMAIL"; then
                break
            else
                log_error "Неверный формат email"
            fi
        done
    else
        if ! validate_email "$EMAIL"; then
            log_error "Неверный email: $EMAIL"
            exit 1
        fi
    fi
    log_info "Email: $EMAIL"

    # Генерация паролей
    generate_passwords

    # Валидация портов
    validate_ports

    # Подтверждение
    if [[ "$AUTO_CONFIRM" != true ]]; then
        show_configuration_summary
        read -p "Продолжить установку? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Установка отменена пользователем"
            exit 0
        fi
    fi

    save_state "user_input_completed"
}

generate_passwords() {
    if [[ -z "$XUI_PASSWORD" ]]; then
        if [[ "$AUTO_PASSWORD" == true ]]; then
            XUI_PASSWORD=$(generate_password 20)
            log_info "Сгенерирован пароль для 3X-UI"
        else
            read -p "Пароль для 3X-UI (Enter для автогенерации): " XUI_PASSWORD
            if [[ -z "$XUI_PASSWORD" ]]; then
                XUI_PASSWORD=$(generate_password 20)
                log_info "Сгенерирован пароль для 3X-UI"
            fi
        fi
    fi

    if [[ -z "$ADGUARD_PASSWORD" ]]; then
        if [[ "$AUTO_PASSWORD" == true ]]; then
            ADGUARD_PASSWORD=$(generate_password 20)
            log_info "Сгенерирован пароль для AdGuard"
        else
            read -p "Пароль для AdGuard (Enter для автогенерации): " ADGUARD_PASSWORD
            if [[ -z "$ADGUARD_PASSWORD" ]]; then
                ADGUARD_PASSWORD=$(generate_password 20)
                log_info "Сгенерирован пароль для AdGuard"
            fi
        fi
    fi
}

validate_ports() {
    for port in "$VLESS_PORT" "$XUI_PORT" "$ADGUARD_PORT"; do
        if ! validate_port "$port"; then
            log_error "Неверный порт: $port"
            exit 1
        fi
    done

    # Проверка дублирования
    local ports=("$VLESS_PORT" "$XUI_PORT" "$ADGUARD_PORT")
    local unique_ports=($(printf "%s\n" "${ports[@]}" | sort -u))

    if [[ ${#ports[@]} -ne ${#unique_ports[@]} ]]; then
        log_error "Порты не должны дублироваться"
        exit 1
    fi

    log_info "VLESS: $VLESS_PORT, 3X-UI: $XUI_PORT, AdGuard: $ADGUARD_PORT"
}

show_configuration_summary() {
    echo ""
    log_warn "Конфигурация установки:"
    echo "  Домен: $DOMAIN"
    echo "  Email: $EMAIL"
    echo "  IP сервера: $SERVER_IP"
    echo "  Порт VLESS: $VLESS_PORT"
    echo "  Порт 3X-UI: $XUI_PORT"
    echo "  Порт AdGuard: $ADGUARD_PORT"
    echo "  Пароли: [будут сгенерированы]"
    echo ""
}

# ===============================================
# ФУНКЦИИ ПРОВЕРКИ ПОРТОВ И СЕРВИСОВ
# ===============================================

check_port_used() {
    local port="$1"

    if command -v netstat >/dev/null 2>&1; then
        netstat -tuln 2>/dev/null | grep -q ":$port "
    elif command -v ss >/dev/null 2>&1; then
        ss -tuln 2>/dev/null | grep -q ":$port "
    else
        return 1
    fi
}

stop_conflicting_services() {
    print_header "ОСТАНОВКА КОНФЛИКТУЮЩИХ СЕРВИСОВ"
    save_state "stopping_conflicts"

    local services=("apache2" "httpd" "nginx" "systemd-resolved" "bind9" "named" "dnsmasq")

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_info "Остановка сервиса: $service"
            systemctl stop "$service" 2>/dev/null || true
            systemctl disable "$service" 2>/dev/null || true
        fi
    done

    # Принудительная очистка DNS портов
    systemctl mask systemd-resolved 2>/dev/null || true
    pkill -9 dnsmasq 2>/dev/null || true
    pkill -9 named 2>/dev/null || true

    log_info "Конфликтующие сервисы остановлены ✅"
}

check_dns_resolution() {
    print_header "ПРОВЕРКА DNS"

    log_info "IP сервера: $SERVER_IP"

    local domain_ip
    if command -v dig >/dev/null 2>&1; then
        domain_ip=$(timeout 10 dig +short "$DOMAIN" 2>/dev/null | head -n1)
    elif command -v nslookup >/dev/null 2>&1; then
        domain_ip=$(timeout 10 nslookup "$DOMAIN" 2>/dev/null | awk '/^Address: / { print $2 }' | head -n1)
    fi

    if [[ -n "$domain_ip" ]]; then
        log_info "IP домена: $domain_ip"
        if [[ "$SERVER_IP" != "$domain_ip" ]]; then
            log_warn "DNS домена не указывает на этот сервер"
            log_warn "Это может вызвать проблемы с SSL сертификатом"
        else
            log_info "DNS настроен правильно ✅"
        fi
    else
        log_warn "Не удалось разрешить домен $DOMAIN"
    fi
}

# ===============================================
# ФУНКЦИИ НАСТРОЙКИ FIREWALL
# ===============================================

configure_firewall() {
    print_header "НАСТРОЙКА FIREWALL"
    save_state "configuring_firewall"

    # Установка UFW если нужно
    if ! command -v ufw >/dev/null 2>&1; then
        if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
            apt-get install -y -qq ufw
        else
            log_warn "UFW недоступен, используем firewalld"
            configure_firewalld
            return 0
        fi
    fi

    # Настройка UFW
    ufw --force reset >/dev/null 2>&1
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1

    # SSH
    local ssh_port="22"
    if command -v ss >/dev/null 2>&1; then
        ssh_port=$(ss -tlnp 2>/dev/null | awk '/sshd.*LISTEN/ {split($4,a,":"); print a[length(a)]}' | head -n1)
        [[ -z "$ssh_port" ]] && ssh_port="22"
    fi

    # Открытие портов
    ufw allow "$ssh_port/tcp" comment "SSH" >/dev/null 2>&1
    ufw allow 80/tcp comment "HTTP" >/dev/null 2>&1
    ufw allow 443/tcp comment "HTTPS" >/dev/null 2>&1
    ufw allow "$XUI_PORT/tcp" comment "3X-UI" >/dev/null 2>&1
    ufw allow "$ADGUARD_PORT/tcp" comment "AdGuard" >/dev/null 2>&1
    ufw allow 53/tcp comment "DNS TCP" >/dev/null 2>&1
    ufw allow 53/udp comment "DNS UDP" >/dev/null 2>&1

    if [[ "$VLESS_PORT" != "443" ]]; then
        ufw allow "$VLESS_PORT/tcp" comment "VLESS" >/dev/null 2>&1
    fi

    ufw --force enable >/dev/null 2>&1

    log_info "Firewall настроен ✅"
}

configure_firewalld() {
    systemctl enable firewalld
    systemctl start firewalld

    firewall-cmd --permanent --add-port=22/tcp
    firewall-cmd --permanent --add-port=80/tcp
    firewall-cmd --permanent --add-port=443/tcp
    firewall-cmd --permanent --add-port="$XUI_PORT/tcp"
    firewall-cmd --permanent --add-port="$ADGUARD_PORT/tcp"
    firewall-cmd --permanent --add-port=53/tcp
    firewall-cmd --permanent --add-port=53/udp

    if [[ "$VLESS_PORT" != "443" ]]; then
        firewall-cmd --permanent --add-port="$VLESS_PORT/tcp"
    fi

    firewall-cmd --reload

    log_info "Firewalld настроен ✅"
}

# ===============================================
# ФУНКЦИИ SSL СЕРТИФИКАТОВ
# ===============================================

setup_ssl() {
    print_header "НАСТРОЙКА SSL"
    save_state "setting_up_ssl"

    # Создание временной конфигурации Nginx
    setup_temporary_nginx

    # Получение сертификата
    obtain_ssl_certificate

    # Настройка автообновления
    setup_ssl_renewal
}

setup_temporary_nginx() {
    log_info "Настройка временного веб-сервера..."

    mkdir -p /var/www/html
    echo "Setup in progress..." > /var/www/html/index.html

    cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
        try_files \$uri =404;
    }

    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF

    # Создание симлинка
    mkdir -p /etc/nginx/sites-enabled
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/

    # Проверка и запуск
    if nginx -t >/dev/null 2>&1; then
        systemctl enable nginx
        systemctl start nginx
        sleep 3

        if ! systemctl is-active --quiet nginx; then
            log_error "Nginx не запустился"
            exit 1
        fi
    else
        log_error "Ошибка в конфигурации Nginx"
        nginx -t
        exit 1
    fi
}

obtain_ssl_certificate() {
    log_info "Получение SSL сертификата для $DOMAIN..."

    local certbot_cmd="certbot certonly --webroot --webroot-path=/var/www/html --email $EMAIL --agree-tos --non-interactive --domains $DOMAIN"

    if $certbot_cmd; then
        log_info "SSL сертификат получен ✅"

        # Проверка файлов сертификата
        if [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]] && [[ -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem" ]]; then
            log_info "Файлы сертификата найдены ✅"
        else
            log_error "Файлы сертификата не найдены"
            exit 1
        fi
    else
        log_error "Не удалось получить SSL сертификат"
        log_error "Убедитесь что домен $DOMAIN указывает на IP $SERVER_IP"
        exit 1
    fi
}

setup_ssl_renewal() {
    log_info "Настройка автообновления SSL..."

    cat > /etc/cron.d/certbot-renewal << 'EOF'
0 12 * * * root /usr/bin/certbot renew --quiet --post-hook "systemctl reload nginx"
EOF

    # Включение cron
    systemctl enable cron 2>/dev/null || systemctl enable crond 2>/dev/null || true
    systemctl start cron 2>/dev/null || systemctl start crond 2>/dev/null || true

    log_info "Автообновление SSL настроено ✅"
}

# ===============================================
# ФУНКЦИИ УСТАНОВКИ 3X-UI
# ===============================================

install_3x_ui() {
    print_header "УСТАНОВКА 3X-UI"
    save_state "installing_3x_ui"

    # Попытка автоматической установки
    if install_3x_ui_auto; then
        log_info "3X-UI установлен автоматически ✅"
    else
        log_warn "Переход к ручной установке..."
        install_3x_ui_manual
    fi

    configure_3x_ui_service
    log_info "3X-UI установлен и настроен ✅"
}

install_3x_ui_auto() {
    log_info "Автоматическая установка 3X-UI..."

    # Скачивание скрипта
    if ! curl -fsSL "https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh" -o /tmp/3x-ui-install.sh; then
        return 1
    fi

    chmod +x /tmp/3x-ui-install.sh

    # Автоматический ввод
    echo -e "y\n$XUI_USERNAME\n$XUI_PASSWORD\n$XUI_PORT\ny\n" | timeout 300 bash /tmp/3x-ui-install.sh >/dev/null 2>&1 || return 1

    # Проверка установки
    if [[ -f "/opt/3x-ui/x-ui" ]] && [[ -f "/etc/systemd/system/x-ui.service" ]]; then
        return 0
    else
        return 1
    fi
}

install_3x_ui_manual() {
    log_info "Ручная установка 3X-UI..."

    cd /opt

    # Получение последней версии
    local version
    version=$(curl -fsSL "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" 2>/dev/null | grep -oP '"tag_name": "\K[^"]*' || echo "v2.3.4")
    log_info "Версия 3X-UI: $version"

    # Скачивание
    local url="https://github.com/MHSanaei/3x-ui/releases/download/$version/x-ui-linux-${ARCH}.tar.gz"

    if ! wget -q --show-progress "$url" -O x-ui.tar.gz; then
        log_error "Не удалось скачать 3X-UI"
        exit 1
    fi

    # Извлечение
    tar -zxf x-ui.tar.gz
    rm x-ui.tar.gz

    # Переименование
    if [[ -d "x-ui" ]]; then
        mv x-ui 3x-ui
    fi

    cd 3x-ui
    chmod +x x-ui

    # Создание сервиса
    create_3x_ui_service
    systemctl daemon-reload
    systemctl enable x-ui
}

create_3x_ui_service() {
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
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF
}

configure_3x_ui_service() {
    log_info "Настройка 3X-UI..."

    # Запуск
    systemctl start x-ui

    # Ожидание запуска
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        if systemctl is-active --quiet x-ui; then
            break
        fi
        sleep 2
        attempts=$((attempts + 1))
    done

    if systemctl is-active --quiet x-ui; then
        log_info "3X-UI запущен на порту $XUI_PORT ✅"

        # Настройка через CLI
        if [[ -f "/opt/3x-ui/x-ui" ]]; then
            /opt/3x-ui/x-ui setting -username "$XUI_USERNAME" -password "$XUI_PASSWORD" -port "$XUI_PORT" >/dev/null 2>&1 || true
            systemctl restart x-ui
        fi
    else
        log_error "3X-UI не запустился"
        systemctl status x-ui --no-pager
        exit 1
    fi
}

# ===============================================
# ФУНКЦИИ УСТАНОВКИ ADGUARD HOME
# ===============================================

install_adguard() {
    print_header "УСТАНОВКА ADGUARD HOME"
    save_state "installing_adguard"

    # Подготовка DNS
    prepare_dns_environment

    # Установка AdGuard
    download_and_install_adguard

    # Создание конфигурации
    create_adguard_configuration

    # Запуск и настройка
    start_and_configure_adguard

    log_info "AdGuard Home установлен и настроен ✅"
}

prepare_dns_environment() {
    log_info "Подготовка DNS окружения..."

    # Остановка системных DNS сервисов
    systemctl stop systemd-resolved 2>/dev/null || true
    systemctl disable systemd-resolved 2>/dev/null || true
    systemctl mask systemd-resolved 2>/dev/null || true

    # Остановка других DNS сервисов
    pkill -9 dnsmasq 2>/dev/null || true
    pkill -9 named 2>/dev/null || true

    # Настройка временного resolv.conf
    if [[ -f /etc/resolv.conf ]]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup
        cat > /etc/resolv.conf << 'EOF'
# Temporary DNS during AdGuard installation
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
    fi

    log_info "DNS окружение подготовлено ✅"
}

restore_system_dns() {
    if [[ -f /etc/resolv.conf.backup ]]; then
        mv /etc/resolv.conf.backup /etc/resolv.conf
    fi
}

download_and_install_adguard() {
    log_info "Загрузка AdGuard Home для $ARCH..."

    # Очистка и создание директории
    rm -rf /opt/AdGuardHome
    mkdir -p /opt/AdGuardHome

    # Создание временной директории
    local temp_dir="/tmp/adguard-install"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    cd "$temp_dir"

    # Скачивание
    local url="https://static.adguard.com/adguardhome/release/AdGuardHome_linux_${ARCH}.tar.gz"

    if ! wget -q --show-progress "$url" -O AdGuardHome.tar.gz; then
        log_error "Не удалось скачать AdGuard Home"
        log_error "URL: $url"
        exit 1
    fi

    # Проверка архива
    if ! tar -tzf AdGuardHome.tar.gz >/dev/null 2>&1; then
        log_error "Поврежденный архив AdGuard Home"
        exit 1
    fi

    # Извлечение
    tar -zxf AdGuardHome.tar.gz

    # Перемещение файлов
    if [[ -d "AdGuardHome" ]]; then
        cp -r AdGuardHome/* /opt/AdGuardHome/
        rm -rf "$temp_dir"
    else
        log_error "Неожиданная структура архива AdGuard"
        ls -la "$temp_dir"
        exit 1
    fi

    # Проверка бинарного файла
    if [[ ! -f "/opt/AdGuardHome/AdGuardHome" ]]; then
        log_error "Бинарный файл AdGuard не найден"
        exit 1
    fi

    # Установка прав
    chmod +x /opt/AdGuardHome/AdGuardHome
    chown -R root:root /opt/AdGuardHome

    # Проверка работоспособности
    if ! /opt/AdGuardHome/AdGuardHome --version >/dev/null 2>&1; then
        log_error "Бинарный файл AdGuard поврежден"
        exit 1
    fi

    log_info "AdGuard Home загружен ✅"
}

create_adguard_configuration() {
    log_info "Создание конфигурации AdGuard Home..."

    # Создание директорий
    mkdir -p /opt/AdGuardHome/{data,work,conf}

    # Генерация хеша пароля
    local password_hash
    if command -v htpasswd >/dev/null 2>&1; then
        password_hash=$(htpasswd -bnBC 12 "" "$ADGUARD_PASSWORD" | tr -d ':\n' | sed 's/^[^$]*//')
    else
        password_hash="\$2a\$12\$$(openssl rand -base64 16 | tr -d "=+/")"
    fi

    # Создание конфигурации
    cat > /opt/AdGuardHome/AdGuardHome.yaml << EOF
# AdGuard Home Configuration
# Generated by VPN Auto Installer v$SCRIPT_VERSION
# $(date)

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

  # Logging
  anonymize_client_ip: false
  querylog_enabled: true
  querylog_file_enabled: true
  querylog_interval: 24h
  querylog_size_memory: 1000

  # Statistics
  statistics_interval: 1

  # Protection
  protection_enabled: true
  blocking_mode: default
  blocked_response_ttl: 10
  parental_block_host: family-block.dns.adguard.com
  safebrowsing_block_host: standard-block.dns.adguard.com

  # Filtering
  filtering_enabled: true
  filters_update_interval: 24
  parental_enabled: false
  safesearch_enabled: false
  safebrowsing_enabled: true

  # Cache
  cache_size: 4194304
  cache_ttl_min: 0
  cache_ttl_max: 0
  cache_optimistic: false
  safebrowsing_cache_size: 1048576
  safesearch_cache_size: 1048576
  parental_cache_size: 1048576

  # Performance
  max_goroutines: 300

  # Client settings
  resolve_clients: true
  use_private_ptr_resolvers: true
  local_ptr_upstreams: []

  # Access control
  allowed_clients: []
  disallowed_clients: []
  blocked_hosts:
    - version.bind
    - id.server
    - hostname.bind

  trusted_proxies:
    - 127.0.0.0/8
    - ::1/128

  # Upstream DNS
  upstream_dns:
    - https://dns.cloudflare.com/dns-query
    - https://dns.google/dns-query
    - https://dns.quad9.net/dns-query
    - 1.1.1.1
    - 8.8.8.8

  upstream_timeout: 10s
  bootstrap_dns:
    - 9.9.9.10
    - 149.112.112.10

  # Additional settings
  all_servers: false
  fastest_addr: false
  fastest_timeout: 1s
  serve_http3: false
  use_http3_upstreams: false
  enable_dnssec: false
  aaaa_disabled: false
  use_dns64: false
  serve_plain_dns: true

  edns_client_subnet:
    enabled: false

  bogus_nxdomain: []
  private_networks: []

# TLS (disabled)
tls:
  enabled: false

# Filter lists
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

# DHCP (disabled)
dhcp:
  enabled: false

# Clients
clients:
  runtime_sources:
    whois: true
    arp: true
    rdns: true
    dhcp: true
    hosts: true
  persistent: []

# Logging
log_compress: false
log_localtime: false
log_max_backups: 0
log_max_size: 100
log_max_age: 3
log_file: ""
verbose: false

# System
os:
  group: ""
  user: ""
  rlimit_nofile: 0

schema_version: 27
EOF

    # Права на файлы
    chmod 644 /opt/AdGuardHome/AdGuardHome.yaml
    chown root:root /opt/AdGuardHome/AdGuardHome.yaml

    log_info "Конфигурация AdGuard создана ✅"
}

start_and_configure_adguard() {
    log_info "Запуск AdGuard Home..."

    # Создание systemd сервиса
    create_adguard_service

    # Проверка конфигурации
    cd /opt/AdGuardHome
    if ! ./AdGuardHome --check-config --config ./AdGuardHome.yaml; then
        log_error "Ошибка в конфигурации AdGuard"
        exit 1
    fi

    # Запуск сервиса
    systemctl daemon-reload
    systemctl enable AdGuardHome
    systemctl start AdGuardHome

    # Ожидание запуска
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        if systemctl is-active --quiet AdGuardHome && check_port_used "$ADGUARD_PORT"; then
            break
        fi
        sleep 2
        attempts=$((attempts + 1))
    done

    if systemctl is-active --quiet AdGuardHome; then
        log_info "AdGuard Home запущен на порту $ADGUARD_PORT ✅"

        # Проверка веб-интерфейса
        sleep 3
        if timeout 10 curl -s "http://localhost:$ADGUARD_PORT" >/dev/null 2>&1; then
            log_info "Веб-интерфейс AdGuard доступен ✅"
        fi

        # Проверка DNS
        if timeout 10 nslookup google.com localhost >/dev/null 2>&1; then
            log_info "DNS сервер AdGuard работает ✅"
        fi
    else
        log_error "AdGuard Home не запустился"
        diagnose_adguard_failure
        exit 1
    fi
}

create_adguard_service() {
    cat > /etc/systemd/system/AdGuardHome.service << EOF
[Unit]
Description=AdGuard Home
Documentation=https://github.com/AdguardTeam/AdGuardHome
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/AdGuardHome
ExecStart=/opt/AdGuardHome/AdGuardHome --config /opt/AdGuardHome/AdGuardHome.yaml --work-dir /opt/AdGuardHome --no-check-update
Restart=on-failure
RestartSec=10
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF
}

diagnose_adguard_failure() {
    log_error "Диагностика проблем AdGuard Home:"

    # Статус сервиса
    systemctl status AdGuardHome --no-pager || true

    # Логи
    journalctl -u AdGuardHome --no-pager -n 10 || true

    # Файлы
    ls -la /opt/AdGuardHome/ || true

    # Порты
    netstat -tuln | grep -E ":($ADGUARD_PORT|53) " || log_info "Порты свободны"

    # Процессы
    ps aux | grep -i adguard | grep -v grep || log_info "Процессы не найдены"
}

# ===============================================
# ФУНКЦИИ ФИНАЛЬНОЙ НАСТРОЙКИ
# ===============================================

configure_final_nginx() {
    print_header "ФИНАЛЬНАЯ НАСТРОЙКА NGINX"
    save_state "configuring_final_nginx"

    # Создание финальной конфигурации
    create_final_nginx_config

    # Создание главной страницы
    create_main_page

    # Проверка и перезагрузка
    if nginx -t; then
        systemctl reload nginx
        log_info "Nginx настроен ✅"
    else
        log_error "Ошибка в конфигурации Nginx"
        nginx -t
        exit 1
    fi
}

create_final_nginx_config() {
    cat > /etc/nginx/sites-available/default << EOF
server_tokens off;

# HTTP -> HTTPS redirect
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

# HTTPS server
server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name $DOMAIN;

    # SSL configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Main site
    location / {
        root /var/www/html;
        index index.html;
        try_files \$uri \$uri/ =404;
    }

    # Logs
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
}
EOF

    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
}

create_main_page() {
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
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
            color: #333;
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
        .header h1 { font-size: 2.5rem; margin-bottom: 10px; }
        .content { padding: 40px; }
        .panel {
            background: #f8f9fa;
            border-radius: 12px;
            padding: 25px;
            margin-bottom: 25px;
            border-left: 4px solid #28a745;
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
            transition: transform 0.2s;
        }
        .button:hover { transform: translateY(-2px); }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        .stat {
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
        .status {
            display: inline-block;
            width: 10px;
            height: 10px;
            background: #28a745;
            border-radius: 50%;
            margin-right: 8px;
            animation: pulse 2s infinite;
        }
        @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
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
            <p>Безопасное подключение готово</p>
        </div>

        <div class="content">
            <div class="panel">
                <h4><span class="status"></span>Сервер успешно настроен</h4>
                <p><strong>Домен:</strong> $DOMAIN</p>
                <p><strong>IP:</strong> $SERVER_IP</p>
                <p><strong>Установлено:</strong> $(date '+%d.%m.%Y %H:%M')</p>
            </div>

            <div class="panel">
                <h3>📊 Панели управления</h3>
                <a href="https://$DOMAIN:$XUI_PORT" class="button" target="_blank">3X-UI Panel</a>
                <a href="http://$DOMAIN:$ADGUARD_PORT" class="button" target="_blank">AdGuard Home</a>
                <p style="margin-top: 15px; padding: 10px; background: #e9ecef; border-radius: 6px;">
                    <small><strong>Логин:</strong> admin<br>
                    <strong>Пароли:</strong> в файле /root/vpn-server-info.txt</small>
                </p>
            </div>

            <div class="stats">
                <div class="stat">
                    <div class="stat-value">$VLESS_PORT</div>
                    <div>VLESS Port</div>
                </div>
                <div class="stat">
                    <div class="stat-value">$XUI_PORT</div>
                    <div>3X-UI Port</div>
                </div>
                <div class="stat">
                    <div class="stat-value">$ADGUARD_PORT</div>
                    <div>AdGuard Port</div>
                </div>
                <div class="stat">
                    <div class="stat-value">53</div>
                    <div>DNS Port</div>
                </div>
            </div>

            <div class="panel">
                <h3>📱 Настройка VPN</h3>
                <ol style="margin-left: 20px;">
                    <li>Откройте 3X-UI панель</li>
                    <li>Войдите (admin / пароль из инструкций)</li>
                    <li>Создайте пользователя VLESS с TLS</li>
                    <li>Домен: <strong>$DOMAIN</strong>, Порт: <strong>$VLESS_PORT</strong></li>
                    <li>Скачайте конфигурацию</li>
                </ol>
                <div style="background: #fff3cd; padding: 15px; border-radius: 8px; margin: 15px 0;">
                    <strong>Клиенты:</strong> v2rayNG (Android), Shadowrocket (iOS), v2rayN (Windows), ClashX (macOS)
                </div>
            </div>

            <div class="panel">
                <h3>🛡️ DNS с блокировкой рекламы</h3>
                <p>DNS сервер: <strong>$SERVER_IP</strong> (порт 53)</p>
                <p>Настройте в параметрах сети для блокировки рекламы на всех устройствах.</p>
            </div>
        </div>

        <div class="footer">
            <p>🚀 VPN Auto Installer v$SCRIPT_VERSION</p>
            <p>Сделано для вашей безопасности в интернете</p>
        </div>
    </div>
</body>
</html>
EOF
}

create_instructions() {
    print_header "СОЗДАНИЕ ИНСТРУКЦИЙ"

    local instructions="/root/vpn-server-info.txt"

    cat > "$instructions" << EOF
╔═══════════════════════════════════════════════════════════════╗
║                    VPN SERVER INFORMATION                    ║
╚═══════════════════════════════════════════════════════════════╝

Установлено: $(date)
Версия: $SCRIPT_VERSION
Домен: $DOMAIN
IP: $SERVER_IP

╔═══════════════════════════════════════════════════════════════╗
║                        ДОСТУП К ПАНЕЛЯМ                      ║
╚═══════════════════════════════════════════════════════════════╝

🌐 Главная: https://$DOMAIN

📊 3X-UI: https://$DOMAIN:$XUI_PORT
   Логин: $XUI_USERNAME
   Пароль: $XUI_PASSWORD

🛡️ AdGuard: http://$DOMAIN:$ADGUARD_PORT
   Логин: admin
   Пароль: $ADGUARD_PASSWORD

╔═══════════════════════════════════════════════════════════════╗
║                          ПОРТЫ                               ║
╚═══════════════════════════════════════════════════════════════╝

VLESS: $VLESS_PORT
3X-UI: $XUI_PORT
AdGuard: $ADGUARD_PORT
DNS: 53
HTTP: 80 → HTTPS
HTTPS: 443

╔═══════════════════════════════════════════════════════════════╗
║                      НАСТРОЙКА VPN                           ║
╚═══════════════════════════════════════════════════════════════╝

1. Панель: https://$DOMAIN:$XUI_PORT
2. Логин: $XUI_USERNAME, Пароль: (выше)
3. Создать пользователя VLESS с TLS
4. Домен: $DOMAIN, Порт: $VLESS_PORT
5. Скачать конфигурацию
6. Импорт в клиент

Клиенты:
- Android: v2rayNG
- iOS: Shadowrocket
- Windows: v2rayN
- macOS: ClashX

╔═══════════════════════════════════════════════════════════════╗
║                    DNS С БЛОКИРОВКОЙ                         ║
╚═══════════════════════════════════════════════════════════════╝

DNS: $SERVER_IP (порт 53)
Настройте в параметрах сети устройства.

╔═══════════════════════════════════════════════════════════════╗
║                    УПРАВЛЕНИЕ                                ║
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

╔═══════════════════════════════════════════════════════════════╗
║                      БЕЗОПАСНОСТЬ                            ║
╚═══════════════════════════════════════════════════════════════╝

✅ SSL сертификат (автообновление)
✅ Firewall настроен
✅ Безопасные конфигурации

Рекомендации:
- Обновляйте систему регулярно
- Меняйте пароли каждые 3-6 месяцев
- Следите за логами

СОХРАНИТЕ ЭТОТ ФАЙЛ!

EOF

    chmod 600 "$instructions"
    log_info "Инструкции: $instructions"
}

# ===============================================
# ФУНКЦИИ ФИНАЛИЗАЦИИ
# ===============================================

show_final_results() {
    print_header "УСТАНОВКА ЗАВЕРШЕНА"

    echo ""
    log_info "🎉 VPN-сервер успешно установлен!"
    echo ""
    echo -e "${GREEN}🌐 Главная:${NC} https://$DOMAIN"
    echo ""
    echo -e "${GREEN}📊 3X-UI:${NC} https://$DOMAIN:$XUI_PORT"
    echo -e "${GREEN}   Логин:${NC} $XUI_USERNAME"
    echo -e "${GREEN}   Пароль:${NC} $XUI_PASSWORD"
    echo ""
    echo -e "${GREEN}🛡️ AdGuard:${NC} http://$DOMAIN:$ADGUARD_PORT"
    echo -e "${GREEN}   Логин:${NC} admin"
    echo -e "${GREEN}   Пароль:${NC} $ADGUARD_PASSWORD"
    echo ""
    echo -e "${GREEN}🔒 DNS:${NC} $SERVER_IP:53"
    echo ""
    log_warn "ВАЖНО: Сохраните пароли!"
    log_info "📋 Инструкции: /root/vpn-server-info.txt"
    log_info "📝 Логи: $LOG_FILE"
    echo ""
}

cleanup_installation() {
    print_header "ЗАВЕРШЕНИЕ"

    # Удаление временных файлов
    rm -f "$STATE_FILE"
    rm -f /tmp/3x-ui-install.sh
    rm -rf /tmp/adguard-install

    # Восстановление автообновлений
    restore_system_updates

    # Очистка пакетного кеша
    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        apt-get autoremove -y >/dev/null 2>&1 || true
        apt-get autoclean >/dev/null 2>&1 || true
    fi

    log_info "Очистка завершена ✅"
}

# ===============================================
# ФУНКЦИИ АРГУМЕНТОВ И СПРАВКИ
# ===============================================

show_help() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

Автоматическая установка VPN-сервера с VLESS + TLS + 3X-UI + AdGuard Home

ИСПОЛЬЗОВАНИЕ:
  curl -fsSL https://your-script-url | bash

ОПЦИИ:
  --domain DOMAIN              Домен сервера
  --email EMAIL               Email для SSL
  --xui-password PASSWORD     Пароль 3X-UI
  --adguard-password PASSWORD Пароль AdGuard
  --vless-port PORT          Порт VLESS (443)
  --xui-port PORT            Порт 3X-UI (54321)
  --adguard-port PORT        Порт AdGuard (3000)
  --auto-password            Автогенерация паролей
  --auto-confirm             Без запросов подтверждения
  --debug                    Отладочный режим
  --help                     Эта справка
  --version                  Версия скрипта

ПРИМЕРЫ:
  # Интерактивная установка
  curl -fsSL https://your-script-url | bash

  # Автоматическая установка
  curl -fsSL https://your-script-url | bash -s -- \\
    --domain vpn.example.com \\
    --email admin@example.com \\
    --auto-password \\
    --auto-confirm

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --domain) DOMAIN="$2"; shift 2 ;;
            --email) EMAIL="$2"; shift 2 ;;
            --xui-password) XUI_PASSWORD="$2"; shift 2 ;;
            --adguard-password) ADGUARD_PASSWORD="$2"; shift 2 ;;
            --vless-port) VLESS_PORT="$2"; shift 2 ;;
            --xui-port) XUI_PORT="$2"; shift 2 ;;
            --adguard-port) ADGUARD_PORT="$2"; shift 2 ;;
            --auto-password) AUTO_PASSWORD=true; shift ;;
            --auto-confirm) AUTO_CONFIRM=true; shift ;;
            --debug) DEBUG_MODE=true; shift ;;
            --help) show_help; exit 0 ;;
            --version) echo "$SCRIPT_NAME v$SCRIPT_VERSION"; exit 0 ;;
            *) log_error "Неизвестный параметр: $1"; exit 1 ;;
        esac
    done
}

# ===============================================
# ГЛАВНАЯ ФУНКЦИЯ
# ===============================================

main() {
    # Инициализация
    setup_logging
    parse_arguments "$@"
    show_banner

    # Проверка восстановления состояния
    if load_state; then
        case "$CURRENT_STEP" in
            "user_input_completed")
                fix_package_manager
                install_dependencies
                stop_conflicting_services
                configure_firewall
                check_dns_resolution
                setup_ssl
                install_3x_ui
                install_adguard
                configure_final_nginx
                create_instructions
                show_final_results
                cleanup_installation
                return 0
                ;;
            "installing_dependencies")
                stop_conflicting_services
                configure_firewall
                check_dns_resolution
                setup_ssl
                install_3x_ui
                install_adguard
                configure_final_nginx
                create_instructions
                show_final_results
                cleanup_installation
                return 0
                ;;
            # Добавить другие точки восстановления по необходимости
        esac
    fi

    # Полная установка с начала
    check_root
    detect_system
    get_user_input
    fix_package_manager
    install_dependencies
    stop_conflicting_services
    configure_firewall
    check_dns_resolution
    setup_ssl
    install_3x_ui
    install_adguard
    configure_final_nginx
    create_instructions
    show_final_results
    cleanup_installation

    log_info "🎉 Установка полностью завершена!"
}

# Запуск главной функции
main "$@"
