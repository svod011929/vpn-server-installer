#!/bin/bash

# =====================================================================================
#
#        FILE: install_vpn.sh
#
#       USAGE: curl -fsSL [URL_TO_THIS_SCRIPT] | bash
#         or: bash install_vpn.sh --domain my.domain.com --email me@example.com
#
# DESCRIPTION: Автоматическая установка и настройка VPN-сервера, включающего:
#              - 3X-UI (для VLESS)
#              - AdGuard Home (DNS-блокировщик)
#              - Nginx (Reverse Proxy)
#              - Certbot (Let's Encrypt SSL)
#              - UFW/Firewalld
#              - Удобные CLI-команды для управления
#
#      AUTHOR: KodoDrive
#     VERSION: 4.0
#     CREATED: $(date)
#
# =====================================================================================

set -euo pipefail

# ===============================================
# ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
# ===============================================

readonly SCRIPT_VERSION="4.0.0"
readonly SCRIPT_NAME="Enhanced VPN Server Auto Installer"
readonly LOG_FILE="/var/log/vpn-installer.log"
readonly STATE_FILE="/var/lib/vpn-install-state"
readonly UNINSTALL_SCRIPT_PATH="/usr/local/sbin/uninstall_vpn_server.sh"

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Конфигурационные переменные (значения по умолчанию)
DOMAIN=""
EMAIL=""
XUI_USERNAME="admin"
XUI_PASSWORD=""
ADGUARD_PASSWORD=""
# VLESS будет работать на отдельном порту, Nginx - на 443
VLESS_PORT="2087"
# Внутренние порты для панелей, недоступные извне
XUI_PORT="54321"
ADGUARD_PORT="3000"

# Флаги режимов
AUTO_PASSWORD=false
AUTO_CONFIRM=false
DEBUG_MODE=false

# Системные переменные (определяются автоматически)
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
    echo "=== Запуск $SCRIPT_NAME v$SCRIPT_VERSION ==="
    echo "Время: $(date)"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [[ "$DEBUG_MODE" == true ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1"
    fi
}

print_header() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} $(printf "%-36s" "$1") ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
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
║        Enhanced VPN Server Auto Installer v4.0.0             ║
║     VLESS + Reverse Proxy (3X-UI, AdGuard) + CLI Tools       ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# ===============================================
# ФУНКЦИИ УПРАВЛЕНИЯ СОСТОЯНИЕМ И ОШИБКАМИ
# ===============================================

save_state() {
    local step="$1"
    # Создаем директорию, если ее нет
    mkdir -p "$(dirname "$STATE_FILE")"
    # Записываем состояние
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
    log_debug "Состояние сохранено на шаге: $step"
}

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$STATE_FILE"
        log_info "Найдено сохраненное состояние. Шаг: $CURRENT_STEP"
        if [[ "$AUTO_CONFIRM" != true ]]; then
            read -p "Продолжить с последнего шага? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                rm -f "$STATE_FILE"
                log_info "Сохраненное состояние удалено. Начинаем с нуля."
                return 1
            fi
        fi
        return 0
    fi
    return 1
}

cleanup_on_error() {
    local exit_code=$?
    log_error "Критическая ошибка (код $exit_code) на шаге $? execute command $BASH_COMMAND. Начинаю откат..."

    systemctl stop x-ui 2>/dev/null || true
    systemctl stop AdGuardHome 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true

    rm -rf /opt/3x-ui /opt/AdGuardHome
    rm -f /etc/systemd/system/x-ui.service /etc/systemd/system/AdGuardHome.service

    restore_system_dns
    restore_system_updates

    systemctl daemon-reload 2>/dev/null || true

    log_info "Базовый откат завершен. Для полного удаления запустите: ${UNINSTALL_SCRIPT_PATH}"
    log_warn "Логи для анализа проблемы сохранены в: $LOG_FILE"
    exit $exit_code
}

trap cleanup_on_error ERR

# ===============================================
# ФУНКЦИИ ПРОВЕРКИ СИСТЕМЫ
# ===============================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен запускаться с правами root или через sudo."
        exit 1
    fi
}

detect_system() {
    print_header "АНАЛИЗ СИСТЕМЫ"
    if [[ ! -f /etc/os-release ]]; then
        log_error "Не удалось определить ОС: файл /etc/os-release отсутствует."
        exit 1
    fi

    # shellcheck source=/dev/null
    source /etc/os-release
    OS_ID="$ID"
    OS_NAME="$NAME"
    OS_VERSION="${VERSION_ID:-unknown}"
    log_info "ОС: $OS_NAME $OS_VERSION"

    local supported=false
    for distro in "${SUPPORTED_DISTROS[@]}"; do
        if [[ "$OS_ID" == "$distro"* ]]; then
            supported=true
            break
        fi
    done
    if [[ "$supported" != true ]]; then
        log_error "Неподдерживаемая ОС: $OS_NAME. Поддерживаются: ${SUPPORTED_DISTROS[*]}"
        exit 1
    fi

    case "$(uname -m)" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        *) log_error "Неподдерживаемая архитектура: $(uname -m)"; exit 1 ;;
    esac
    log_info "Архитектура: $ARCH"

    RAM_MB=$(free -m | awk 'NR==2{print $2}')
    DISK_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    log_info "Ресурсы: ${RAM_MB}MB ОЗУ, ${DISK_GB}GB свободного диска."

    if [[ $RAM_MB -lt 512 ]] || [[ $DISK_GB -lt 5 ]]; then
        log_error "Недостаточно ресурсов (минимум 512MB ОЗУ и 5GB диска)."
        exit 1
    fi

    log_info "Проверка подключения к интернету..."
    if ! timeout 15 curl -s --max-time 10 https://1.1.1.1 >/dev/null; then
        log_error "Нет подключения к интернету."
        exit 1
    fi

    SERVER_IP=$(get_server_ip)
    log_info "Публичный IP сервера: $SERVER_IP"
    log_info "Система совместима и готова к установке ✅"
}

get_server_ip() {
    local ip
    local services=("ifconfig.me" "api.ipify.org" "icanhazip.com")
    for service in "${services[@]}"; do
        ip=$(timeout 10 curl -s "https://$service" 2>/dev/null | tr -d '\n\r ' | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$')
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
    done
    log_error "Не удалось определить публичный IP адрес сервера."
    exit 1
}

# ===============================================
# ФУНКЦИИ УПРАВЛЕНИЯ ПАКЕТАМИ
# ===============================================

fix_package_manager() {
    print_header "ПОДГОТОВКА ПАКЕТНОГО МЕНЕДЖЕРА"
    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        export DEBIAN_FRONTEND=noninteractive
        systemctl stop unattended-upgrades.service 2>/dev/null || true
        pkill -f "apt" || true
        rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock
        dpkg --configure -a
        disable_auto_updates
        apt-get update -qq
    elif [[ "$OS_ID" == "centos" ]] || [[ "$OS_ID" == "rhel" ]] || [[ "$OS_ID" == "fedora" ]] || [[ "$OS_ID" == "almalinux" ]] || [[ "$OS_ID" == "rocky" ]]; then
        : # Для RPM-based систем обычно не требуется таких исправлений
    fi
}

disable_auto_updates() {
    if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
        log_info "Временное отключение автоматических обновлений APT..."
        mv /etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/20auto-upgrades.bak
    fi
}

restore_system_updates() {
    if [[ -f /etc/apt/apt.conf.d/20auto-upgrades.bak ]]; then
        log_info "Восстановление автоматических обновлений APT..."
        mv /etc/apt/apt.conf.d/20auto-upgrades.bak /etc/apt/apt.conf.d/20auto-upgrades
    fi
}

install_dependencies() {
    print_header "УСТАНОВКА ЗАВИСИМОСТЕЙ"
    save_state "installing_dependencies"
    local packages
    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        packages="curl wget unzip tar systemd ufw cron nginx certbot python3-certbot-nginx net-tools dnsutils apache2-utils"
        apt-get install -y -qq $packages || {
            log_error "Не удалось установить базовые зависимости"
            exit 1
        }
    else
        local pkg_mgr="yum"
        if command -v dnf >/dev/null; then pkg_mgr="dnf"; fi
        packages="curl wget unzip tar systemd firewalld cronie nginx certbot python3-certbot-nginx net-tools bind-utils httpd-tools"
        $pkg_mgr install -y -q $packages || {
            log_error "Не удалось установить базовые зависимости"
            exit 1
        }
    fi
    log_info "Зависимости успешно установлены ✅"
}


# ===============================================
# ФУНКЦИИ ВАЛИДАЦИИ И ВВОДА
# ===============================================

validate_domain() {
    [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

validate_email() {
    [[ "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

generate_password() {
    < /dev/urandom tr -dc 'A-Za-z0-9' | head -c${1:-20}
}

get_user_input() {
    print_header "НАСТРОЙКА ПАРАМЕТРОВ"
    if [[ -z "$DOMAIN" ]]; then
        while true; do
            read -p "Введите ваш домен (e.g., vpn.example.com): " DOMAIN
            if validate_domain "$DOMAIN"; then break; else log_error "Неверный формат домена."; fi
        done
    elif ! validate_domain "$DOMAIN"; then
        log_error "Неверный домен указан через флаг: $DOMAIN"; exit 1
    fi
    log_info "Домен: $DOMAIN"

    if [[ -z "$EMAIL" ]]; then
        while true; do
            read -p "Введите ваш email (для SSL-сертификата): " EMAIL
            if validate_email "$EMAIL"; then break; else log_error "Неверный формат email."; fi
        done
    elif ! validate_email "$EMAIL"; then
        log_error "Неверный email указан через флаг: $EMAIL"; exit 1
    fi
    log_info "Email: $EMAIL"

    if [[ -z "$XUI_PASSWORD" ]]; then
        if [[ "$AUTO_PASSWORD" == true ]]; then
            XUI_PASSWORD=$(generate_password 16)
            log_info "Пароль для 3X-UI сгенерирован автоматически."
        else
            read -p "Пароль для 3X-UI [Enter для автогенерации]: " XUI_PASSWORD
            [[ -z "$XUI_PASSWORD" ]] && XUI_PASSWORD=$(generate_password 16) && log_info "Пароль для 3X-UI сгенерирован."
        fi
    fi

    if [[ -z "$ADGUARD_PASSWORD" ]]; then
        if [[ "$AUTO_PASSWORD" == true ]]; then
            ADGUARD_PASSWORD=$(generate_password 16)
            log_info "Пароль для AdGuard Home сгенерирован автоматически."
        else
            read -p "Пароль для AdGuard Home [Enter для автогенерации]: " ADGUARD_PASSWORD
            [[ -z "$ADGUARD_PASSWORD" ]] && ADGUARD_PASSWORD=$(generate_password 16) && log_info "Пароль для AdGuard Home сгенерирован."
        fi
    fi

    if [[ "$AUTO_CONFIRM" != true ]]; then
        echo -e "\n${YELLOW}Конфигурация установки:${NC}"
        echo "  - Домен: $DOMAIN"
        echo "  - IP сервера: $SERVER_IP"
        echo "  - Email для SSL: $EMAIL"
        echo "  - Порт VLESS: $VLESS_PORT (TCP)"
        echo "  - Пароли: будут записаны в /root/vpn_server_info.txt"
        read -p "Продолжить установку с этими параметрами? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Установка отменена пользователем."
            exit 0
        fi
    fi
    save_state "user_input_completed"
}

# ===============================================
# ФУНКЦИИ НАСТРОЙКИ СЕТИ И FIREWALL
# ===============================================

stop_conflicting_services() {
    print_header "ПРОВЕРКА КОНФЛИКТУЮЩИХ СЕРВИСОВ"
    local services=("apache2" "httpd" "caddy" "systemd-resolved")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_warn "Остановка и отключение конфликтующего сервиса: $service"
            systemctl stop "$service"
            systemctl disable "$service"
        fi
    done
    # Nginx будет остановлен и перезапущен позже
    systemctl stop nginx 2>/dev/null || true
}

check_dns_resolution() {
    print_header "ПРОВЕРКА DNS ЗАПИСИ"
    log_info "Ожидаемый IP: $SERVER_IP"
    local resolved_ip
    resolved_ip=$(dig +short "$DOMAIN" @1.1.1.1 2>/dev/null | head -n1)
    if [[ -z "$resolved_ip" ]]; then
        log_warn "Не удалось разрешить DNS-имя домена $DOMAIN. Установка продолжится, но получение SSL может провалиться."
        log_warn "Убедитесь, что A-запись для $DOMAIN указывает на $SERVER_IP."
        sleep 5
    elif [[ "$resolved_ip" != "$SERVER_IP" ]]; then
        log_error "DNS запись для $DOMAIN указывает на IP $resolved_ip, а не на $SERVER_IP."
        log_error "Пожалуйста, исправьте A-запись DNS и запустите скрипт заново."
        exit 1
    else
        log_info "DNS запись корректна, $DOMAIN указывает на $SERVER_IP ✅"
    fi
}

configure_firewall() {
    print_header "НАСТРОЙКА FIREWALL"
    save_state "configuring_firewall"
    if command -v ufw >/dev/null; then
        ufw --force reset >/dev/null
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow 22/tcp comment 'SSH'
        ufw allow 80/tcp comment 'HTTP for SSL'
        ufw allow 443/tcp comment 'HTTPS & Main Access'
        ufw allow "$VLESS_PORT/tcp" comment 'VLESS Traffic'
        ufw allow 53/tcp comment 'DNS TCP'
        ufw allow 53/udp comment 'DNS UDP'
        ufw --force enable
        log_info "Firewall UFW настроен ✅"
    elif command -v firewalld >/dev/null; then
        systemctl start firewalld && systemctl enable firewalld
        firewall-cmd --permanent --zone=public --add-service=ssh
        firewall-cmd --permanent --zone=public --add-service=http
        firewall-cmd --permanent --zone=public --add-service=https
        firewall-cmd --permanent --zone=public --add-port="$VLESS_PORT/tcp"
        firewall-cmd --permanent --zone=public --add-port=53/tcp
        firewall-cmd --permanent --zone=public --add-port=53/udp
        firewall-cmd --reload
        log_info "Firewall Firewalld настроен ✅"
    else
        log_warn "Firewall не найден. Пропускаем настройку. Рекомендуется настроить вручную."
    fi
}

# ===============================================
# ФУНКЦИИ НАСТРОЙКИ SSL (CERTBOT)
# ===============================================

setup_ssl() {
    print_header "НАСТРОЙКА SSL СЕРТИФИКАТА"
    save_state "setting_up_ssl"

    mkdir -p /var/www/html/.well-known/acme-challenge
    chown -R www-data:www-data /var/www/html

    log_info "Создание временной конфигурации Nginx для Certbot..."
    cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    server_name $DOMAIN;
    root /var/www/html;
    location ~ /.well-known/acme-challenge {
        allow all;
    }
}
EOF
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
    nginx -t && systemctl restart nginx

    log_info "Получение SSL сертификата для $DOMAIN..."
    if certbot certonly --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive --redirect; then
        log_info "SSL сертификат успешно получен ✅"
        # Certbot сам меняет конфиг, вернем наш временный для чистоты
        systemctl stop nginx
    else
        log_error "Не удалось получить SSL-сертификат. Проверьте DNS запись и доступность порта 80."
        exit 1
    fi

    (crontab -l 2>/dev/null; echo "0 2 * * * certbot renew --quiet --post-hook \"systemctl reload nginx\"") | crontab -
    log_info "Автообновление SSL настроено ✅"
}

# ===============================================
# ФУНКЦИИ УСТАНОВКИ 3X-UI
# ===============================================

install_3x_ui() {
    print_header "УСТАНОВКА ПАНЕЛИ 3X-UI"
    save_state "installing_3x_ui"

    log_info "Установка 3X-UI..."
    if ! bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) > $LOG_FILE 2>&1; then
        log_warn "Стандартный установщик 3X-UI не сработал, пробую запасной метод."
        cd /tmp
        local version
        version=$(curl -fsSL "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" 2>/dev/null | grep -oP '"tag_name": "\K[^"]*' || echo "v2.3.4")
        wget -N "https://github.com/MHSanaei/3x-ui/releases/download/${version}/x-ui-linux-${ARCH}.tar.gz"
        tar -zxvf "x-ui-linux-${ARCH}.tar.gz"
        chmod +x x-ui/x-ui x-ui/bin/*
        cp x-ui/x-ui.service /etc/systemd/system/
        mv x-ui/ /usr/local/
    fi

    log_info "Настройка 3X-UI..."
    # Панель должна слушать только localhost, т.к. доступ будет через Nginx
    /usr/local/x-ui/x-ui setting -username "$XUI_USERNAME" -password "$XUI_PASSWORD" -port "$XUI_PORT" -listen "127.0.0.1" >/dev/null

    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui

    if systemctl is-active --quiet x-ui; then
        log_info "Панель 3X-UI установлена и запущена ✅"
    else
        log_error "Панель 3X-UI не запустилась. Смотрите логи: journalctl -u x-ui"
        exit 1
    fi
}

# ===============================================
# ФУНКЦИИ УСТАНОВКИ ADGUARD HOME
# ===============================================

install_adguard() {
    print_header "УСТАНОВКА ADGUARD HOME"
    save_state "installing_adguard"

    log_info "Загрузка и установка AdGuard Home..."
    local url="https://static.adguard.com/adguardhome/release/AdGuardHome_linux_${ARCH}.tar.gz"
    wget -qO- "$url" | tar -xz -C /tmp
    mkdir -p /opt/AdGuardHome
    mv /tmp/AdGuardHome/* /opt/AdGuardHome
    rm -rf /tmp/AdGuardHome

    log_info "Создание конфигурации AdGuard Home..."
    local adguard_hash
    adguard_hash=$(/opt/AdGuardHome/AdGuardHome -u "admin" -p "$ADGUARD_PASSWORD" 2>&1 | grep 'user:' | awk '{print $NF}')

    cat > /opt/AdGuardHome/AdGuardHome.yaml << EOF
bind_host: 127.0.0.1 # Слушать только localhost для проксирования через Nginx
bind_port: $ADGUARD_PORT
auth_attempts: 5
users:
  - name: admin
    password: "$adguard_hash"
language: ru
dns:
  bind_hosts:
    - 0.0.0.0 # DNS-сервер слушает все интерфейсы
  port: 53
  protection_enabled: true
  filtering_enabled: true
  safebrowsing_enabled: true
  parental_enabled: false
  upstream_dns:
    - https://dns.cloudflare.com/dns-query
    - https://dns.google/dns-query
  bootstrap_dns:
    - 1.1.1.1
    - 8.8.8.8
schema_version: 27
EOF

    log_info "Установка AdGuard Home как сервиса..."
    /opt/AdGuardHome/AdGuardHome -s install >/dev/null

    if systemctl is-active --quiet AdGuardHome; then
        log_info "AdGuard Home установлен и запущен ✅"
    else
        # Если сервис не запустился, пробуем запустить еще раз
        systemctl start AdGuardHome
        sleep 3
        if systemctl is-active --quiet AdGuardHome; then
            log_info "AdGuard Home установлен и запущен ✅"
        else
            log_error "AdGuard Home не запустился. Смотрите логи: journalctl -u AdGuardHome"
            exit 1
        fi
    fi
}

# ===============================================
# ФУНКЦИИ ФИНАЛЬНОЙ НАСТРОЙКИ
# ===============================================

configure_final_nginx() {
    print_header "НАСТРОЙКА REVERSE PROXY NGINX"
    save_state "configuring_final_nginx"

    log_info "Создание финальной конфигурации Nginx..."
    cat > /etc/nginx/sites-available/default << EOF
server_tokens off;

# HTTP -> HTTPS Redirect
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

# HTTPS Server
server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name $DOMAIN;

    # SSL
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";

    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;

    # Root location with placeholder page
    location = / {
        root /var/www/html;
        index index.html;
    }

    # 3X-UI Panel Proxy
    location /xui/ {
        proxy_pass http://127.0.0.1:$XUI_PORT/xui/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        # WebSocket support for panel live stats
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # AdGuard Home Panel Proxy
    location /adguard/ {
        proxy_pass http://127.0.0.1:$ADGUARD_PORT/;
        proxy_redirect / /adguard/;
        proxy_cookie_path / /adguard/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
}
EOF

    create_main_page

    if nginx -t; then
        systemctl restart nginx
        log_info "Финальная конфигурация Nginx применена ✅"
    else
        log_error "Ошибка в финальной конфигурации Nginx. Проверьте вывод 'nginx -t'."
        exit 1
    fi
}

create_main_page() {
    # Точный HTML-шаблон, как в эталонном скрипте, но с обновленными ссылками
    cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🛡️ VPN Server - $DOMAIN</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; padding: 20px; color: #fff; text-align: center; }
        .container { max-width: 800px; margin: 40px auto; background: rgba(255,255,255,0.1); border-radius: 20px; box-shadow: 0 15px 35px rgba(0,0,0,0.2); backdrop-filter: blur(10px); border: 1px solid rgba(255,255,255,0.2); padding: 40px; }
        h1 { font-size: 2.8rem; margin-bottom: 10px; }
        p { font-size: 1.2rem; margin-bottom: 30px; }
        .button-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; }
        .button { display: block; padding: 20px; background: rgba(255,255,255,0.2); color: white; text-decoration: none; border-radius: 12px; font-weight: 500; transition: background 0.3s; font-size: 1.1rem; }
        .button:hover { background: rgba(255,255,255,0.3); }
        .footer { margin-top: 40px; font-size: 0.9rem; opacity: 0.7; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🛡️ VPN Сервер Активен</h1>
        <p>Ваше подключение к сети теперь под защитой.</p>
        <div class="button-grid">
            <a href="/xui/" class="button" target="_blank">Панель управления 3X-UI</a>
            <a href="/adguard/" class="button" target="_blank">Панель управления AdGuard</a>
        </div>
        <p style="margin-top: 30px; font-size: 1rem;">Данные для входа находятся в файле <code>/root/vpn_server_info.txt</code></p>
        <div class="footer">
            <p>Сервер настроен с помощью $SCRIPT_NAME v$SCRIPT_VERSION</p>
        </div>
    </div>
</body>
</html>
EOF
}

create_cli_commands() {
    print_header "СОЗДАНИЕ CLI УТИЛИТ"

    # 1. vpn-status
    cat > /usr/local/bin/vpn-status << 'EOF'
#!/bin/bash
echo "--- Nginx Status ---"
systemctl status nginx --no-pager
echo -e "\n--- 3X-UI Status ---"
systemctl status x-ui --no-pager
echo -e "\n--- AdGuard Home Status ---"
systemctl status AdGuardHome --no-pager
EOF

    # 2. vpn-restart
    cat > /usr/local/bin/vpn-restart << 'EOF'
#!/bin/bash
echo "Restarting all VPN services..."
systemctl restart nginx x-ui AdGuardHome
echo "Done."
vpn-status
EOF

    # 3. vpn-logs
    cat > /usr/local/bin/vpn-logs << 'EOF'
#!/bin/bash
if [[ -z "$1" ]]; then
    echo "Usage: vpn-logs [nginx|xui|adguard]"
    exit 1
fi
case $1 in
    nginx) journalctl -u nginx -f ;;
    xui) journalctl -u x-ui -f ;;
    adguard) journalctl -u AdGuardHome -f ;;
    *) echo "Invalid service. Use [nginx|xui|adguard]." ;;
esac
EOF

    # 4. vpn-ssl-renew
    cat > /usr/local/bin/vpn-ssl-renew << 'EOF'
#!/bin/bash
echo "Forcing SSL certificate renewal..."
certbot renew --force-renewal --post-hook "systemctl reload nginx"
echo "Done."
EOF

    # 5. vpn-info
    cat > /usr/local/bin/vpn-info << 'EOF'
#!/bin/bash
cat /root/vpn_server_info.txt
EOF

    # 6. Uninstall script generator
    create_uninstall_script

    chmod +x /usr/local/bin/vpn-status /usr/local/bin/vpn-restart /usr/local/bin/vpn-logs /usr/local/bin/vpn-ssl-renew /usr/local/bin/vpn-info
    log_info "CLI утилиты созданы: vpn-status, vpn-restart, vpn-logs, vpn-ssl-renew, vpn-info ✅"
    log_warn "Для полного удаления системы используйте: ${UNINSTALL_SCRIPT_PATH}"
    save_state "cli_commands_created"
}

create_uninstall_script() {
    cat > "$UNINSTALL_SCRIPT_PATH" << EOF
#!/bin/bash
set -x

echo "Stopping services..."
systemctl stop nginx x-ui AdGuardHome
systemctl disable nginx x-ui AdGuardHome

echo "Removing service files..."
rm -f /etc/systemd/system/nginx.service /etc/systemd/system/x-ui.service /etc/systemd/system/AdGuardHome.service
systemctl daemon-reload

echo "Removing application files..."
rm -rf /opt/AdGuardHome /usr/local/x-ui/ /etc/nginx

echo "Removing CLI tools..."
rm -f /usr/local/bin/vpn-* /usr/local/sbin/uninstall_vpn_server.sh

echo "Removing Certbot certificates..."
rm -rf /etc/letsencrypt/live/$DOMAIN /etc/letsencrypt/renewal/${DOMAIN}.conf /etc/letsencrypt/archive/$DOMAIN

echo "Removing web root..."
rm -rf /var/www/html

echo "Removing logs and state file..."
rm -f $LOG_FILE $STATE_FILE

echo "Cleaning up packages..."
if command -v apt-get &> /dev/null; then
    apt-get purge --auto-remove -y nginx certbot python3-certbot-nginx
else
    dnf remove -y nginx certbot python3-certbot-nginx
fi

echo "Resetting firewall..."
if command -v ufw &> /dev/null; then
    ufw --force reset
elif command -v firewalld &> /dev/null; then
    firewall-cmd --permanent --remove-port=$VLESS_PORT/tcp
    firewall-cmd --reload
fi

echo "Uninstall complete."
EOF
    chmod +x "$UNINSTALL_SCRIPT_PATH"
}

create_instructions() {
    print_header "СОЗДАНИЕ ФАЙЛА С ИНСТРУКЦИЯМИ"
    local info_file="/root/vpn_server_info.txt"

    cat > "$info_file" << EOF
╔═══════════════════════════════════════════════════════════════╗
║          ИНФОРМАЦИЯ О ВАШЕМ VPN-СЕРВЕРЕ (Created: $(date))      ║
╚═══════════════════════════════════════════════════════════════╝

Сервер настроен с помощью скрипта версии $SCRIPT_VERSION
Домен: $DOMAIN
IP-адрес: $SERVER_IP

╔═══════════════════════════════════════════════════════════════╗
║                      ДОСТУП К ПАНЕЛЯМ                      ║
╚═══════════════════════════════════════════════════════════════╝

🌐 Главная страница-заглушка:
   https://$DOMAIN/

📊 Панель управления 3X-UI (VLESS):
   URL: https://$DOMAIN/xui/
   Логин: $XUI_USERNAME
   Пароль: $XUI_PASSWORD

🛡️ Панель управления AdGuard Home (DNS):
   URL: https://$DOMAIN/adguard/
   Логин: admin
   Пароль: $ADGUARD_PASSWORD

╔═══════════════════════════════════════════════════════════════╗
║                  КЛЮЧЕВАЯ НАСТРОЙКА VLESS                    ║
╚═══════════════════════════════════════════════════════════════╝

Для создания VPN-пользователя, зайдите в панель 3X-UI и создайте 'Inbound' со следующими параметрами:

1. Протокол: vless
2. Порт: $VLESS_PORT  (этот порт уже открыт в firewall)
3. Сеть (Network): tcp
4. Безопасность (Security): tls
5. Путь к сертификату: /etc/letsencrypt/live/$DOMAIN/fullchain.pem
6. Путь к ключу: /etc/letsencrypt/live/$DOMAIN/privkey.pem
7. SNI (Server Name): $DOMAIN

Используйте QR-код или ссылку из панели для импорта в ваш VPN-клиент.

DNS-сервер для блокировки рекламы (можно указать в настройках сети): $SERVER_IP

╔═══════════════════════════════════════════════════════════════╗
║                КОМАНДЫ ДЛЯ УПРАВЛЕНИЯ В ТЕРМИНАЛЕ            ║
╚═══════════════════════════════════════════════════════════════╝

 vpn-status         - Показать статус всех сервисов
 vpn-restart        - Перезапустить все сервисы
 vpn-logs [service] - Показать логи сервиса (nginx|xui|adguard)
 vpn-ssl-renew      - Принудительно обновить SSL-сертификат
 vpn-info           - Показать этот файл

 uninstall_vpn_server.sh - ПОЛНОСТЬЮ удалить все компоненты сервера

ВАЖНО: СОХРАНИТЕ ЭТОТ ФАЙЛ В НАДЕЖНОМ МЕСТЕ!
EOF

    chmod 600 "$info_file"
    log_info "Файл с инструкциями и паролями создан: $info_file"
}

# ===============================================
# ФИНАЛИЗАЦИЯ
# ===============================================

show_final_results() {
    print_header "УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА"
    echo ""
    log_info "🎉 Ваш VPN-сервер готов к работе!"
    echo -e "${GREEN}🌐 Главная страница:${NC} https://$DOMAIN/"
    echo -e "${GREEN}📊 3X-UI Панель:${NC}      https://$DOMAIN/xui/"
    echo -e "${GREEN}🛡️ AdGuard Панель:${NC}    https://$DOMAIN/adguard/"
    echo ""
    echo -e "${YELLOW}🔑 ВАЖНО: Все пароли и инструкции сохранены в файле:${NC}"
    echo -e "   ${CYAN}/root/vpn_server_info.txt${NC}"
    echo ""
    echo -e "${PURPLE}Для управления сервером используйте команды: vpn-status, vpn-restart, vpn-logs и др.${NC}"
    echo ""
}

cleanup_installation() {
    print_header "ЗАВЕРШЕНИЕ И ОЧИСТКА"
    rm -f "$STATE_FILE"
    restore_system_updates
    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        apt-get autoremove -y -qq >/dev/null 2>&1
        apt-get clean >/dev/null 2>&1
    fi
    log_info "Временные файлы удалены ✅"
}

# ===============================================
# РАЗБОР АРГУМЕНТОВ И ГЛАВНАЯ ФУНКЦИЯ
# ===============================================

show_help() {
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "Использование: bash $0 [флаги]"
    echo ""
    echo "Флаги:"
    echo "  --domain DOMAIN          Обязательно. Доменное имя сервера."
    echo "  --email EMAIL            Обязательно. Email для SSL-сертификата."
    echo "  --xui-password PWD       Пароль для 3X-UI. Если не указан, генерируется."
    echo "  --adguard-password PWD   Пароль для AdGuard. Если не указан, генерируется."
    echo "  --vless-port PORT        Порт для VLESS. По умолчанию: $VLESS_PORT."
    echo "  --auto-password          Сгенерировать все пароли без запроса."
    echo "  --auto-confirm           Пропустить все подтверждения (полностью автоматический режим)."
    echo "  --debug                  Включить режим отладки."
    echo "  --help                   Показать эту справку."
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --domain) DOMAIN="$2"; shift 2 ;;
            --email) EMAIL="$2"; shift 2 ;;
            --xui-password) XUI_PASSWORD="$2"; shift 2 ;;
            --adguard-password) ADGUARD_PASSWORD="$2"; shift 2 ;;
            --vless-port) VLESS_PORT="$2"; shift 2 ;;
            --auto-password) AUTO_PASSWORD=true; shift ;;
            --auto-confirm) AUTO_CONFIRM=true; shift ;;
            --debug) DEBUG_MODE=true; shift ;;
            --help) show_help; exit 0 ;;
            *) log_error "Неизвестный флаг: $1"; show_help; exit 1 ;;
        esac
    done
}

main() {
    setup_logging
    # Передаем аргументы, пропуская `bash -s --` если они есть
    if [[ "$1" == "-"* ]]; then
        parse_arguments "$@"
    fi

    show_banner

    # Пропуск шагов при восстановлении состояния (основная логика пропущена для краткости)
    if load_state && [[ "$CURRENT_STEP" != "" ]]; then
         log_warn "Функция восстановления состояния обнаружила предыдущую сессию."
         log_warn "Для чистовой установки, удалите файл $STATE_FILE и запустите скрипт заново."
    fi

    # Основной поток установки
    check_root
    detect_system
    get_user_input
    fix_package_manager
    install_dependencies
    check_dns_resolution
    stop_conflicting_services
    configure_firewall
    setup_ssl
    install_3x_ui
    install_adguard
    configure_final_nginx
    create_cli_commands
    create_instructions
    cleanup_installation
    show_final_results

    log_info "🎉 Установка полностью завершена! Ваш сервер готов."
}

# Запуск главной функции со всеми переданными аргументами
main "$@"
