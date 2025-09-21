#!/bin/bash

# =====================================================================================
#
#        FILE: install_vpn.sh
#
#       USAGE: curl -fsSL [URL_TO_THIS_SCRIPT] | bash
#         or: bash install_vpn.sh --domain my.domain.com --email me@example.com
#
# DESCRIPTION: Автоматическая установка и настройка VPN-сервера.
#
#      AUTHOR: KodoDrive
#     VERSION: 4.0.4 (Восстановлена функция parse_arguments, исправлена логика вызова)
#     CREATED: $(date)
#
# =====================================================================================

set -euo pipefail

# ===============================================
# ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ И КОНСТАНТЫ
# ===============================================

readonly SCRIPT_VERSION="4.0.4"
readonly SCRIPT_NAME="Enhanced VPN Server Auto Installer"
readonly LOG_FILE="/var/log/vpn-installer.log"
readonly STATE_FILE="/var/lib/vpn-install-state"
readonly UNINSTALL_SCRIPT_PATH="/usr/local/sbin/uninstall_vpn_server.sh"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

DOMAIN=""
EMAIL=""
XUI_USERNAME="admin"
XUI_PASSWORD=""
ADGUARD_PASSWORD=""
VLESS_PORT="2087"
XUI_PORT="54321"
ADGUARD_PORT="3000"

AUTO_PASSWORD=false
AUTO_CONFIRM=false
DEBUG_MODE=false

OS_ID=""
OS_NAME=""
OS_VERSION=""
ARCH=""
SERVER_IP=""

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

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { if [[ "$DEBUG_MODE" == true ]]; then echo -e "${PURPLE}[DEBUG]${NC} $1"; fi; }

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
║        Enhanced VPN Server Auto Installer v4.0.4             ║
║     VLESS + Reverse Proxy (3X-UI, AdGuard) + CLI Tools       ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# ===============================================
# УПРАВЛЕНИЕ ОШИБКАМИ
# ===============================================

cleanup_on_error() {
    local exit_code=$?
    log_error "Критическая ошибка (код $exit_code) на строке $LINENO. Начинаю откат..."
    systemctl stop x-ui 2>/dev/null || true
    systemctl stop AdGuardHome 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true
    rm -rf /opt/3x-ui /opt/AdGuardHome
    rm -f /etc/systemd/system/x-ui.service /etc/systemd/system/AdGuardHome.service
    systemctl daemon-reload 2>/dev/null || true
    log_info "Базовый откат завершен. Для полного удаления запустите: ${UNINSTALL_SCRIPT_PATH}"
    log_warn "Логи для анализа проблемы сохранены в: $LOG_FILE"
    exit $exit_code
}

trap cleanup_on_error ERR

# ===============================================
# ПРОВЕРКА СИСТЕМЫ
# ===============================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен запускаться с правами root или через sudo."
        exit 1
    fi
}
detect_system() {
    print_header "АНАЛИЗ СИСТЕМЫ"
    if [[ ! -f /etc/os-release ]]; then log_error "Не удалось определить ОС."; exit 1; fi
    # shellcheck source=/dev/null
    source /etc/os-release
    OS_ID="$ID"
    OS_NAME="$NAME"
    OS_VERSION="${VERSION_ID:-unknown}"
    log_info "ОС: $OS_NAME $OS_VERSION"
    local supported=false
    for distro in "${SUPPORTED_DISTROS[@]}"; do
        if [[ "$OS_ID" == "$distro"* ]]; then supported=true; break; fi
    done
    if [[ "$supported" != true ]]; then log_error "Неподдерживаемая ОС: $OS_NAME."; exit 1; fi
    case "$(uname -m)" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) log_error "Неподдерживаемая архитектура: $(uname -m)"; exit 1 ;;
    esac
    log_info "Архитектура: $ARCH"
    if ! timeout 15 curl -s --max-time 10 https://1.1.1.1 >/dev/null; then log_error "Нет подключения к интернету."; exit 1; fi
    SERVER_IP=$(get_server_ip)
    log_info "Публичный IP сервера: $SERVER_IP"
    log_info "Система совместима и готова к установке ✅"
}
get_server_ip() {
    local ip
    local services=("ifconfig.me" "api.ipify.org" "icanhazip.com")
    for service in "${services[@]}"; do
        ip=$(timeout 10 curl -s "https://$service" 2>/dev/null | tr -d '\n\r ' | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$')
        if [[ -n "$ip" ]]; then echo "$ip"; return 0; fi
    done
    log_error "Не удалось определить публичный IP адрес сервера."
    exit 1
}

# ===============================================
# УСТАНОВКА И НАСТРОЙКА
# ===============================================
install_dependencies() {
    print_header "УСТАНОВКА ЗАВИСИМОСТЕЙ"
    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq curl wget unzip tar systemd ufw cron nginx certbot python3-certbot-nginx net-tools dnsutils
    else
        local pkg_mgr="yum" && if command -v dnf >/dev/null; then pkg_mgr="dnf"; fi
        $pkg_mgr install -y -q curl wget unzip tar systemd firewalld cronie nginx certbot python3-certbot-nginx net-tools bind-utils
    fi
    log_info "Зависимости успешно установлены ✅"
}
validate_domain() { [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; }
validate_email() { [[ "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; }
generate_password() { < /dev/urandom tr -dc 'A-Za-z0-9' | head -c${1:-16}; }
get_user_input() {
    print_header "НАСТРОЙКА ПАРАМЕТРОВ"
    if [[ -z "$DOMAIN" ]]; then
        while true; do read -p "Введите ваш домен: " DOMAIN; if validate_domain "$DOMAIN"; then break; else log_error "Неверный формат домена."; fi; done
    elif ! validate_domain "$DOMAIN"; then log_error "Неверный домен: $DOMAIN"; exit 1; fi
    log_info "Домен: $DOMAIN"
    if [[ -z "$EMAIL" ]]; then
        while true; do read -p "Введите ваш email для SSL: " EMAIL; if validate_email "$EMAIL"; then break; else log_error "Неверный формат email."; fi; done
    elif ! validate_email "$EMAIL"; then log_error "Неверный email: $EMAIL"; exit 1; fi
    log_info "Email: $EMAIL"
    if [[ -z "$XUI_PASSWORD" ]]; then
        if [[ "$AUTO_PASSWORD" == true ]]; then XUI_PASSWORD=$(generate_password); log_info "Пароль 3X-UI сгенерирован.";
        else read -p "Пароль 3X-UI [Enter для генерации]: " XUI_PASSWORD; [[ -z "$XUI_PASSWORD" ]] && XUI_PASSWORD=$(generate_password) && log_info "Пароль 3X-UI сгенерирован."; fi
    fi
    if [[ -z "$ADGUARD_PASSWORD" ]]; then
        if [[ "$AUTO_PASSWORD" == true ]]; then ADGUARD_PASSWORD=$(generate_password); log_info "Пароль AdGuard сгенерирован.";
        else read -p "Пароль AdGuard [Enter для генерации]: " ADGUARD_PASSWORD; [[ -z "$ADGUARD_PASSWORD" ]] && ADGUARD_PASSWORD=$(generate_password) && log_info "Пароль AdGuard сгенерирован."; fi
    fi
    if [[ "$AUTO_CONFIRM" != true ]]; then
        echo -e "\n${YELLOW}Проверьте параметры:${NC}\n  Домен: $DOMAIN\n  Email: $EMAIL\n  Порт VLESS: $VLESS_PORT"
        read -p "Продолжить установку? (y/n): " -n 1 -r; echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then log_info "Установка отменена."; exit 0; fi
    fi
}

stop_conflicting_services() {
    print_header "ОСВОБОЖДЕНИЕ СЕТЕВЫХ ПОРТОВ"
    local services=("apache2" "httpd" "caddy" "systemd-resolved")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_warn "Остановка конфликтующего сервиса: $service"
            systemctl stop "$service"; systemctl disable "$service"
        fi
    done
    systemctl stop nginx 2>/dev/null || true
}
fix_local_dns() {
    log_info "Настройка локального DNS-резолвера на время установки..."
    if [ -L /etc/resolv.conf ]; then rm -f /etc/resolv.conf; fi
    cat > /etc/resolv.conf << EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
}
check_dns_resolution() {
    print_header "ПРОВЕРКА DNS ЗАПИСИ ДОМЕНА"
    local resolved_ip
    resolved_ip=$(dig +short "$DOMAIN" @1.1.1.1 2>/dev/null | head -n1)
    if [[ -z "$resolved_ip" ]]; then
        log_warn "Не удалось разрешить DNS-имя $DOMAIN. Убедитесь, что A-запись указывает на $SERVER_IP."
        sleep 5
    elif [[ "$resolved_ip" != "$SERVER_IP" ]]; then
        log_error "DNS домена $DOMAIN указывает на $resolved_ip, а не на IP сервера $SERVER_IP. Исправьте A-запись."
        exit 1
    else
        log_info "DNS запись домена корректна ✅"
    fi
}
configure_firewall() {
    print_header "НАСТРОЙКА FIREWALL"
    if command -v ufw >/dev/null; then
        ufw --force reset >/dev/null
        ufw default deny incoming; ufw default allow outgoing
        ufw allow 22/tcp; ufw allow 80/tcp; ufw allow 443/tcp
        ufw allow "$VLESS_PORT/tcp"; ufw allow 53/tcp; ufw allow 53/udp
        ufw --force enable
        log_info "Firewall UFW настроен ✅"
    elif command -v firewalld >/dev/null; then
        systemctl start firewalld && systemctl enable firewalld
        firewall-cmd --permanent --zone=public --add-service=ssh --add-service=http --add-service=https
        firewall-cmd --permanent --zone=public --add-port="$VLESS_PORT/tcp" --add-port=53/tcp --add-port=53/udp
        firewall-cmd --reload
        log_info "Firewall Firewalld настроен ✅"
    else
        log_warn "Firewall не найден. Пропускаем настройку."
    fi
}
setup_ssl() {
    print_header "ПОЛУЧЕНИЕ SSL СЕРТИФИКАТА"
    mkdir -p /var/www/html
    chown www-data:www-data /var/www/html
    log_info "Настройка временного Nginx для проверки Certbot..."
    cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    server_name $DOMAIN;
    root /var/www/html;
    location /.well-known/acme-challenge/ { allow all; }
}
EOF
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
    nginx -t && systemctl restart nginx
    log_info "Запрос сертификата для $DOMAIN через webroot..."
    certbot certonly --webroot -w /var/www/html -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive --quiet
    if [[ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
        log_error "Certbot сообщил об успехе, но файл сертификата не найден! Проверьте лог /var/log/letsencrypt/letsencrypt.log."
        exit 1
    fi
    log_info "SSL сертификат успешно получен ✅"
    systemctl stop nginx
    (crontab -l 2>/dev/null; echo "0 2 * * * certbot renew --quiet --post-hook \"systemctl reload nginx\"") | crontab -
    log_info "Автообновление SSL настроено ✅"
}
install_3x_ui() {
    print_header "УСТАНОВКА ПАНЕЛИ 3X-UI"
    log_info "Запуск неинтерактивного установщика 3X-UI..."
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) install
    log_info "Настройка 3X-UI для работы через reverse proxy..."
    /usr/local/x-ui/x-ui setting -username "$XUI_USERNAME" -password "$XUI_PASSWORD" -port "$XUI_PORT" -listen "127.0.0.1" >/dev/null
    systemctl restart x-ui
    if systemctl is-active --quiet x-ui; then
        log_info "Панель 3X-UI установлена и запущена ✅"
    else
        log_error "Панель 3X-UI не запустилась. Логи: journalctl -u x-ui"
        exit 1
    fi
}
install_adguard() {
    print_header "УСТАНОВКА ADGUARD HOME"
    log_info "Загрузка и установка AdGuard Home..."
    local url="https://static.adguard.com/adguardhome/release/AdGuardHome_linux_${ARCH}.tar.gz"
    wget -qO- "$url" | tar -xz -C /tmp
    mkdir -p /opt/AdGuardHome
    mv /tmp/AdGuardHome/* /opt/AdGuardHome
    rm -rf /tmp/AdGuardHome
    log
