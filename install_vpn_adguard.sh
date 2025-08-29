#!/bin/bash

# install_vless_adguard.sh
# Скрипт автоматической установки VPN-сервера с VLESS + TLS + 3X-UI + AdGuard Home
# Автор: KodoDrive
# Версия: 2.0
# Установка: bash <(curl -fsSL https://github.com/svod011929/vpn-server-installer/blob/main/install_vpn_adguard.sh)

set -euo pipefail

# Версия скрипта
SCRIPT_VERSION="2.0.0"
SCRIPT_URL="https://raw.githubusercontent.com/kododrive/vpn-server-installer/main/install_vless_adguard.sh"
REPO_URL="https://github.com/kododrive/vpn-server-installer"

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
NC='\033[0m' # No Color

# Переменные по умолчанию
DOMAIN=""
EMAIL=""
XUI_PASSWORD=""
ADGUARD_PASSWORD=""
VLESS_PORT="443"
XUI_PORT="54321"
ADGUARD_PORT="3000"
AUTO_PASSWORD=false
AUTO_CONFIRM=false
DEBUG_MODE=false
INSTALL_STATE_FILE="/tmp/vpn-install-state"

# Поддерживаемые дистрибутивы
SUPPORTED_OS=("ubuntu" "debian" "centos" "rhel" "fedora" "almalinux" "rocky")

# Функции для вывода цветного текста
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

# Функция сохранения состояния установки
save_install_state() {
    local step="$1"
    cat > "$INSTALL_STATE_FILE" << EOF
DOMAIN="$DOMAIN"
EMAIL="$EMAIL"
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

# Функция загрузки состояния установки
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

# Функция очистки при ошибке
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

    # Восстановление firewall
    ufw --force reset 2>/dev/null || true

    systemctl daemon-reload

    print_status "Откат завершен. Проверьте логи в $LOG_FILE"
    exit $exit_code
}

trap cleanup_on_error ERR

# Функция показа баннера
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
║              VPN Server Auto Installer v${SCRIPT_VERSION}              ║
║           VLESS + TLS + 3X-UI + AdGuard Home                 ║
║                                                               ║
║                    Made by KodoDrive                         ║
║            https://github.com/kododrive                      ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Функция показа справки
show_help() {
    cat << EOF
VPN Server Auto Installer v${SCRIPT_VERSION}

Автоматическая установка VPN-сервера с VLESS + TLS + 3X-UI + AdGuard Home

ИСПОЛЬЗОВАНИЕ:
  bash <(curl -fsSL ${SCRIPT_URL})

  Или с параметрами:
  bash <(curl -fsSL ${SCRIPT_URL}) [ОПЦИИ]

ОПЦИИ:
  --domain DOMAIN              Ваш домен (например: vpn.example.com)
  --email EMAIL               Email для SSL сертификата
  --xui-password PASSWORD     Пароль для панели 3X-UI
  --adguard-password PASSWORD Пароль для AdGuard Home
  --vless-port PORT          Порт для VLESS (по умолчанию: 443)
  --xui-port PORT            Порт для 3X-UI (по умолчанию: 54321)
  --adguard-port PORT        Порт для AdGuard (по умолчанию: 3000)
  --auto-password            Автоматическая генерация паролей
  --auto-confirm            Автоматическое подтверждение без запросов
  --debug                   Режим отладки
  --help                    Показать эту справку
  --version                 Показать версию скрипта

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

# Функция парсинга аргументов командной строки
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

# Функция проверки root прав
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен запускаться с правами root!"
        print_status "Используйте: sudo $0"
        exit 1
    fi
}

# Функция проверки зависимостей
check_dependencies() {
    print_header "ПРОВЕРКА ЗАВИСИМОСТЕЙ"

    local deps=("curl" "wget" "openssl" "systemctl" "netstat" "dig" "ufw")
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
            print_warning "Отсутствует зависимость: $dep"
        else
            print_debug "Найдена зависимость: $dep"
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_status "Устанавливаю недостающие зависимости..."
        if command -v apt-get &> /dev/null; then
            apt-get update
            for dep in "${missing_deps[@]}"; do
                case $dep in
                    "dig")
                        apt-get install -y dnsutils
                        ;;
                    "netstat")
                        apt-get install -y net-tools
                        ;;
                    *)
                        apt-get install -y "$dep"
                        ;;
                esac
            done
        elif command -v yum &> /dev/null; then
            for dep in "${missing_deps[@]}"; do
                case $dep in
                    "dig")
                        yum install -y bind-utils
                        ;;
                    "netstat")
                        yum install -y net-tools
                        ;;
                    *)
                        yum install -y "$dep"
                        ;;
                esac
            done
        elif command -v dnf &> /dev/null; then
            for dep in "${missing_deps[@]}"; do
                case $dep in
                    "dig")
                        dnf install -y bind-utils
                        ;;
                    "netstat")
                        dnf install -y net-tools
                        ;;
                    *)
                        dnf install -y "$dep"
                        ;;
                esac
            done
        fi
    fi

    print_status "Все зависимости установлены ✅"
}

# Функция проверки системы
check_system() {
    print_header "ПРОВЕРКА СИСТЕМЫ"

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
        *)
            print_error "Неподдерживаемая архитектура: $ARCH"
            exit 1
            ;;
    esac

    # Проверка RAM
    RAM_MB=$(free -m | awk 'NR==2{print $2}')
    print_status "ОЗУ: ${RAM_MB}MB"

    if [ $RAM_MB -lt 512 ]; then
        print_error "Недостаточно RAM. Требуется минимум 512MB, у вас: ${RAM_MB}MB"
        exit 1
    elif [ $RAM_MB -lt 1024 ]; then
        print_warning "Рекомендуется минимум 1GB RAM. У вас: ${RAM_MB}MB"
        if [ "$AUTO_CONFIRM" != true ]; then
            read -p "Продолжить? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi

    # Проверка свободного места
    DISK_GB=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    print_status "Свободное место: ${DISK_GB}GB"

    if [ $DISK_GB -lt 2 ]; then
        print_error "Недостаточно свободного места. Требуется минимум 2GB"
        exit 1
    fi

    # Проверка интернета
    if ! curl -s --max-time 10 https://google.com > /dev/null; then
        print_error "Нет подключения к интернету"
        exit 1
    fi
    print_status "Интернет подключение: ✅"
}

# Функция проверки портов
check_ports() {
    print_header "ПРОВЕРКА ПОРТОВ"

    local ports=("$VLESS_PORT" "$XUI_PORT" "$ADGUARD_PORT" "80" "53")
    local blocked_ports=()

    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep ":$port " > /dev/null; then
            blocked_ports+=("$port")
            print_warning "Порт $port уже занят"
        else
            print_debug "Порт $port свободен"
        fi
    done

    if [ ${#blocked_ports[@]} -gt 0 ]; then
        print_error "Заняты критически важные порты: ${blocked_ports[*]}"
        if [ "$AUTO_CONFIRM" != true ]; then
            read -p "Попробовать остановить конфликтующие сервисы? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                # Попытка остановить известные сервисы
                systemctl stop apache2 2>/dev/null || true
                systemctl stop nginx 2>/dev/null || true
                systemctl stop systemd-resolved 2>/dev/null || true
                sleep 2

                # Повторная проверка
                local still_blocked=()
                for port in "${blocked_ports[@]}"; do
                    if netstat -tuln 2>/dev/null | grep ":$port " > /dev/null; then
                        still_blocked+=("$port")
                    fi
                done

                if [ ${#still_blocked[@]} -gt 0 ]; then
                    print_error "Порты все еще заняты: ${still_blocked[*]}"
                    exit 1
                fi
            else
                exit 1
            fi
        else
            exit 1
        fi
    fi

    print_status "Все необходимые порты свободны ✅"
}

# Функция валидации домена
validate_domain() {
    local domain="$1"

    # Улучшенная регулярка для доменов
    if [[ ! $domain =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        return 1
    fi

    # Проверка длины
    if [ ${#domain} -gt 253 ]; then
        return 1
    fi

    return 0
}

# Функция валидации email
validate_email() {
    local email="$1"

    # Основная проверка формата
    if ! echo "$email" | grep -E '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' > /dev/null; then
        return 1
    fi

    # Дополнительная проверка домена email
    local domain="${email##*@}"
    if command -v dig &> /dev/null; then
        if ! dig +short mx "$domain" +time=5 > /dev/null 2>&1 && 
           ! dig +short a "$domain" +time=5 > /dev/null 2>&1; then
            print_warning "Домен email $domain может быть недоступен"
        fi
    fi

    return 0
}

# Функция проверки DNS
check_domain_dns() {
    print_header "ПРОВЕРКА DNS"

    local server_ip
    local domain_ip

    # Получение IP сервера
    server_ip=$(curl -s --max-time 10 ifconfig.me 2>/dev/null || curl -s --max-time 10 icanhazip.com 2>/dev/null || echo "unknown")

    if [ "$server_ip" = "unknown" ]; then
        print_warning "Не удалось определить IP адрес сервера"
        return 0
    fi

    print_status "IP сервера: $server_ip"

    # Получение IP домена
    if command -v dig &> /dev/null; then
        domain_ip=$(dig +short "$DOMAIN" +time=5 2>/dev/null | head -n1)
    else
        domain_ip=$(nslookup "$DOMAIN" 2>/dev/null | awk '/^Address: / { print $2 }' | head -n1)
    fi

    if [ -z "$domain_ip" ]; then
        print_warning "Не удалось получить IP для домена $DOMAIN"
        print_warning "Убедитесь, что домен настроен правильно"

        if [ "$AUTO_CONFIRM" != true ]; then
            read -p "Продолжить без проверки DNS? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
        return 0
    fi

    print_status "IP домена: $domain_ip"

    if [ "$server_ip" != "$domain_ip" ]; then
        print_warning "DNS домена $DOMAIN не указывает на этот сервер!"
        print_warning "Это может привести к проблемам с SSL сертификатом"

        if [ "$AUTO_CONFIRM" != true ]; then
            read -p "Продолжить? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        print_status "DNS настроен правильно ✅"
    fi
}

# Функция генерации безопасных паролей
generate_secure_password() {
    local length=${1:-16}
    openssl rand -hex "$length" | cut -c1-$((length * 2))
}

# Функция получения пользовательского ввода
get_user_input() {
    print_header "НАСТРОЙКА ПАРАМЕТРОВ"

    # Домен
    if [ -z "$DOMAIN" ]; then
        while true; do
            read -p "Введите ваш домен (например, vpn.example.com): " DOMAIN
            if validate_domain "$DOMAIN"; then
                break
            else
                print_error "Неверный формат домена. Попробуйте снова."
                print_status "Примеры правильных доменов: vpn.example.com, my-server.net"
            fi
        done
    else
        if ! validate_domain "$DOMAIN"; then
            print_error "Неверный формат домена: $DOMAIN"
            exit 1
        fi
        print_status "Домен: $DOMAIN"
    fi

    # Email для SSL
    if [ -z "$EMAIL" ]; then
        while true; do
            read -p "Введите email для SSL сертификата: " EMAIL
            if validate_email "$EMAIL"; then
                break
            else
                print_error "Неверный формат email. Попробуйте снова."
            fi
        done
    else
        if ! validate_email "$EMAIL"; then
            print_error "Неверный формат email: $EMAIL"
            exit 1
        fi
        print_status "Email: $EMAIL"
    fi

    # Пароль для 3X-UI
    if [ -z "$XUI_PASSWORD" ]; then
        if [ "$AUTO_PASSWORD" = true ]; then
            XUI_PASSWORD=$(generate_secure_password 16)
            print_status "Сгенерирован пароль для 3X-UI: $XUI_PASSWORD"
        else
            read -p "Введите пароль для панели 3X-UI (оставьте пустым для генерации): " XUI_PASSWORD
            if [ -z "$XUI_PASSWORD" ]; then
                XUI_PASSWORD=$(generate_secure_password 16)
                print_status "Сгенерирован пароль для 3X-UI: $XUI_PASSWORD"
            fi
        fi
    else
        print_status "Пароль 3X-UI: [установлен]"
    fi

    # Пароль для AdGuard
    if [ -z "$ADGUARD_PASSWORD" ]; then
        if [ "$AUTO_PASSWORD" = true ]; then
            ADGUARD_PASSWORD=$(generate_secure_password 16)
            print_status "Сгенерирован пароль для AdGuard: $ADGUARD_PASSWORD"
        else
            read -p "Введите пароль для AdGuard Home (оставьте пустым для генерации): " ADGUARD_PASSWORD
            if [ -z "$ADGUARD_PASSWORD" ]; then
                ADGUARD_PASSWORD=$(generate_secure_password 16)
                print_status "Сгенерирован пароль для AdGuard: $ADGUARD_PASSWORD"
            fi
        fi
    else
        print_status "Пароль AdGuard: [установлен]"
    fi

    # Проверка портов
    print_status "Порт VLESS: $VLESS_PORT"
    print_status "Порт 3X-UI: $XUI_PORT"
    print_status "Порт AdGuard: $ADGUARD_PORT"

    # Финальное подтверждение
    if [ "$AUTO_CONFIRM" != true ]; then
        echo ""
        print_warning "Проверьте настройки:"
        echo "  Домен: $DOMAIN"
        echo "  Email: $EMAIL"  
        echo "  Порт VLESS: $VLESS_PORT"
        echo "  Порт 3X-UI: $XUI_PORT"
        echo "  Порт AdGuard: $ADGUARD_PORT"
        echo "  Пароль 3X-UI: $XUI_PASSWORD"
        echo "  Пароль AdGuard: $ADGUARD_PASSWORD"
        echo ""
        read -p "Начать установку? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Установка отменена"
            exit 0
        fi
    fi

    print_status "Настройки приняты. Начинаем установку..."
    save_install_state "parameters_configured"
    sleep 2
}

# Функция обновления системы
update_system() {
    print_header "ОБНОВЛЕНИЕ СИСТЕМЫ"
    save_install_state "updating_system"

    if command -v apt-get &> /dev/null; then
        print_status "Обновление пакетов (Debian/Ubuntu)..."
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
        apt-get install -y curl wget unzip software-properties-common
    elif command -v yum &> /dev/null; then
        print_status "Обновление пакетов (CentOS/RHEL)..."
        yum update -y
        yum install -y curl wget unzip epel-release
    elif command -v dnf &> /dev/null; then
        print_status "Обновление пакетов (Fedora)..."
        dnf update -y
        dnf install -y curl wget unzip
    fi

    print_status "Система обновлена ✅"
}

# Функция настройки firewall
configure_firewall() {
    print_header "НАСТРОЙКА FIREWALL"
    save_install_state "configuring_firewall"

    # Установка ufw если не установлен
    if ! command -v ufw &> /dev/null; then
        if command -v apt-get &> /dev/null; then
            apt-get install -y ufw
        elif command -v yum &> /dev/null; then
            yum install -y ufw
        elif command -v dnf &> /dev/null; then
            dnf install -y ufw
        fi
    fi

    # Сброс правил
    ufw --force reset

    # Базовые правила
    ufw default deny incoming
    ufw default allow outgoing

    # SSH
    ufw allow ssh

    # HTTP/HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp

    # Кастомные порты
    if [ "$VLESS_PORT" != "443" ]; then
        ufw allow "$VLESS_PORT"/tcp
    fi

    ufw allow "$XUI_PORT"/tcp
    ufw allow "$ADGUARD_PORT"/tcp

    # DNS для AdGuard
    ufw allow 53/tcp
    ufw allow 53/udp

    # Включение firewall
    ufw --force enable

    print_status "Firewall настроен ✅"
}

# Функция установки Nginx
install_nginx() {
    print_header "УСТАНОВКА NGINX"
    save_install_state "installing_nginx"

    if command -v apt-get &> /dev/null; then
        apt-get install -y nginx
    elif command -v yum &> /dev/null; then
        yum install -y nginx
    elif command -v dnf &> /dev/null; then
        dnf install -y nginx
    fi

    # Остановка nginx (будет запущен после настройки SSL)
    systemctl stop nginx
    systemctl enable nginx

    print_status "Nginx установлен ✅"
}

# Функция установки Certbot
install_certbot() {
    print_header "УСТАНОВКА CERTBOT"
    save_install_state "installing_certbot"

    if command -v apt-get &> /dev/null; then
        apt-get install -y certbot python3-certbot-nginx
    elif command -v yum &> /dev/null; then
        yum install -y certbot python3-certbot-nginx
    elif command -v dnf &> /dev/null; then
        dnf install -y certbot python3-certbot-nginx
    fi

    print_status "Certbot установлен ✅"
}

# Функция получения SSL сертификата
get_ssl_certificate() {
    print_header "ПОЛУЧЕНИЕ SSL СЕРТИФИКАТА"
    save_install_state "getting_ssl_certificate"

    # Временная конфигурация nginx для верификации
    cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}
EOF

    # Создание директории для веб-рута
    mkdir -p /var/www/html

    # Запуск nginx
    systemctl start nginx

    # Получение сертификата
    print_status "Получение SSL сертификата для $DOMAIN..."

    if certbot certonly --webroot \
        --webroot-path=/var/www/html \
        --email "$EMAIL" \
        --agree-tos \
        --non-interactive \
        --domains "$DOMAIN"; then
        print_status "SSL сертификат получен ✅"
    else
        print_error "Не удалось получить SSL сертификат"
        print_error "Проверьте что домен $DOMAIN указывает на этот сервер"
        exit 1
    fi

    # Настройка автообновления
    echo "0 12 * * * /usr/bin/certbot renew --quiet" | crontab -

    print_status "Автообновление SSL настроено ✅"
}

# Функция установки 3X-UI
install_3x_ui() {
    print_header "УСТАНОВКА 3X-UI"
    save_install_state "installing_3x_ui"

    # Скачивание 3X-UI
    cd /opt

    # Определение последней версии
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/MHSanaei/3x-ui/releases/latest | grep -oP '"tag_name": "\K[^"]*')

    if [ -z "$latest_version" ]; then
        print_warning "Не удалось определить последнюю версию 3X-UI, используем фиксированную версию"
        latest_version="v2.3.4"
    fi

    print_status "Скачивание 3X-UI $latest_version..."

    # Скачивание архива
    local download_url="https://github.com/MHSanaei/3x-ui/releases/download/$latest_version/x-ui-linux-${ARCH}.tar.gz"

    if ! wget -O x-ui.tar.gz "$download_url"; then
        print_error "Не удалось скачать 3X-UI"
        exit 1
    fi

    # Извлечение
    tar -zxf x-ui.tar.gz
    rm x-ui.tar.gz

    # Переименование папки
    mv x-ui 3x-ui 2>/dev/null || true
    cd 3x-ui

    # Создание systemd сервиса
    cat > /etc/systemd/system/x-ui.service << EOF
[Unit]
Description=3x-ui Service
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/opt/3x-ui
ExecStart=/opt/3x-ui/x-ui
Restart=on-failure
RestartPreventExitStatus=1
RestartSec=5s
KillMode=mixed
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Установка прав
    chmod +x x-ui

    systemctl daemon-reload
    systemctl enable x-ui

    print_status "3X-UI установлен ✅"
}

# Функция настройки 3X-UI
configure_3x_ui() {
    print_header "НАСТРОЙКА 3X-UI"
    save_install_state "configuring_3x_ui"

    # Создание конфигурационного файла
    mkdir -p /opt/3x-ui/db

    # Базовая конфигурация
    cat > /opt/3x-ui/config.json << EOF
{
  "api": {
    "services": [
      "HandlerService",
      "LoggerService",
      "StatsService"
    ],
    "tag": "api"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": $XUI_PORT,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ],
  "policy": {
    "system": {
      "statsInboundDownlink": true,
      "statsInboundUplink": true
    }
  },
  "routing": {
    "rules": [
      {
        "inboundTag": [
          "api"
        ],
        "outboundTag": "api",
        "type": "field"
      }
    ]
  },
  "stats": {}
}
EOF

    # Запуск 3X-UI
    systemctl start x-ui

    # Ожидание запуска
    sleep 5

    # Проверка статуса
    if systemctl is-active --quiet x-ui; then
        print_status "3X-UI запущен ✅"
    else
        print_error "Не удалось запустить 3X-UI"
        systemctl status x-ui
        exit 1
    fi

    print_status "3X-UI настроен ✅"
    print_status "Панель управления: https://$DOMAIN:$XUI_PORT"
}

# Функция установки AdGuard Home
install_adguard() {
    print_header "УСТАНОВКА ADGUARD HOME"
    save_install_state "installing_adguard"

    cd /opt

    # Скачивание AdGuard Home
    print_status "Скачивание AdGuard Home..."

    local adguard_url
    case $ARCH in
        amd64)
            adguard_url="https://static.adguard.com/adguardhome/release/AdGuardHome_linux_amd64.tar.gz"
            ;;
        arm64)
            adguard_url="https://static.adguard.com/adguardhome/release/AdGuardHome_linux_arm64.tar.gz"
            ;;
        *)
            print_error "Неподдерживаемая архитектура для AdGuard: $ARCH"
            exit 1
            ;;
    esac

    if ! wget -O AdGuardHome.tar.gz "$adguard_url"; then
        print_error "Не удалось скачать AdGuard Home"
        exit 1
    fi

    # Извлечение
    tar -zxf AdGuardHome.tar.gz
    rm AdGuardHome.tar.gz

    # Установка прав
    chmod +x AdGuardHome/AdGuardHome

    # Создание systemd сервиса
    cat > /etc/systemd/system/AdGuardHome.service << EOF
[Unit]
Description=AdGuard Home
After=network.target

[Service]
ExecStart=/opt/AdGuardHome/AdGuardHome -c /opt/AdGuardHome/AdGuardHome.yaml -w /opt/AdGuardHome
WorkingDirectory=/opt/AdGuardHome
User=root
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable AdGuardHome

    print_status "AdGuard Home установлен ✅"
}

# Функция настройки AdGuard Home
configure_adguard() {
    print_header "НАСТРОЙКА ADGUARD HOME"
    save_install_state "configuring_adguard"

    # Создание конфигурационного файла
    cat > /opt/AdGuardHome/AdGuardHome.yaml << EOF
bind_host: 0.0.0.0
bind_port: $ADGUARD_PORT
beta_bind_port: 0
users:
  - name: admin
    password: \$2y\$10\$$(openssl passwd -apr1 "$ADGUARD_PASSWORD" | cut -d'$' -f4-)
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
  statistics_interval: 1
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
  cache_time: 30
  filtering_enabled: true
  filters_update_interval: 24
  parental_enabled: false
  safesearch_enabled: false
  safebrowsing_enabled: false
  resolve_clients: true
  use_private_ptr_resolvers: true
  local_ptr_upstreams: []
  serve_http3: false
  use_http3_upstreams: false
  upstream_dns:
    - https://dns10.quad9.net/dns-query
    - https://dns.cloudflare.com/dns-query
    - https://dns.google/dns-query
  upstream_dns_file: ""
  upstream_timeout: 10s
  private_networks: []
  use_dns64: false
  dns64_prefixes: []
  serve_plain_dns: true
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
    url: https://adaway.org/hosts.txt
    name: AdAway Default Blocklist
    id: 2
whitelist_filters: []
user_rules: []
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

    # Запуск AdGuard Home
    systemctl start AdGuardHome

    # Ожидание запуска
    sleep 5

    # Проверка статуса
    if systemctl is-active --quiet AdGuardHome; then
        print_status "AdGuard Home запущен ✅"
    else
        print_error "Не удалось запустить AdGuard Home"
        systemctl status AdGuardHome
        exit 1
    fi

    print_status "AdGuard Home настроен ✅"
    print_status "Панель управления: http://$DOMAIN:$ADGUARD_PORT"
}

# Функция финальной настройки Nginx
configure_nginx_final() {
    print_header "ФИНАЛЬНАЯ НАСТРОЙКА NGINX"
    save_install_state "configuring_nginx_final"

    # Создание конфигурации с SSL
    cat > /etc/nginx/sites-available/default << EOF
# HTTP -> HTTPS редирект
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

# HTTPS сервер
server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    # SSL конфигурация
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # Безопасность
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # Прокси для 3X-UI
    location /xui/ {
        proxy_pass http://127.0.0.1:$XUI_PORT/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;

        # WebSocket поддержка
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Прокси для AdGuard
    location /adguard/ {
        proxy_pass http://127.0.0.1:$ADGUARD_PORT/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
    }

    # Главная страница
    location / {
        root /var/www/html;
        index index.html;
        try_files \$uri \$uri/ =404;
    }
}
EOF

    # Создание простой главной страницы
    cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPN Server - $DOMAIN</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 0 20px rgba(0,0,0,0.1); }
        h1 { color: #333; text-align: center; }
        .panel { margin: 20px 0; padding: 15px; background: #f8f9fa; border-radius: 5px; }
        .button { display: inline-block; padding: 10px 20px; background: #007bff; color: white; text-decoration: none; border-radius: 5px; margin: 5px; }
        .button:hover { background: #0056b3; }
        .info { background: #d4edda; border: 1px solid #c3e6cb; color: #155724; padding: 10px; border-radius: 5px; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🛡️ VPN Server</h1>
        <div class="info">
            <strong>Сервер успешно настроен!</strong><br>
            Домен: $DOMAIN<br>
            Дата установки: $(date)
        </div>

        <div class="panel">
            <h3>📊 Панели управления</h3>
            <a href="/xui/" class="button">3X-UI Panel</a>
            <a href="/adguard/" class="button">AdGuard Home</a>
        </div>

        <div class="panel">
            <h3>📱 Подключение</h3>
            <p>Используйте панель 3X-UI для создания конфигураций VLESS.</p>
            <p>DNS сервер AdGuard: <code>$DOMAIN:53</code> или IP этого сервера</p>
        </div>

        <div class="panel">
            <h3>🔧 Информация</h3>
            <p>Порты:</p>
            <ul>
                <li>VLESS: $VLESS_PORT</li>
                <li>3X-UI: $XUI_PORT (доступ через /xui/)</li>
                <li>AdGuard: $ADGUARD_PORT (доступ через /adguard/)</li>
                <li>DNS: 53</li>
            </ul>
        </div>
    </div>
</body>
</html>
EOF

    # Проверка конфигурации nginx
    if nginx -t; then
        systemctl reload nginx
        print_status "Nginx перезагружен ✅"
    else
        print_error "Ошибка в конфигурации Nginx"
        exit 1
    fi
}

# Функция создания инструкций
create_instructions() {
    print_header "СОЗДАНИЕ ИНСТРУКЦИЙ"

    local instructions_file="/root/vpn-server-info.txt"

    cat > "$instructions_file" << EOF
╔═══════════════════════════════════════════════════════════════╗
║                    VPN SERVER INFORMATION                    ║
╚═══════════════════════════════════════════════════════════════╝

Дата установки: $(date)
Домен: $DOMAIN
IP сервера: $(curl -s ifconfig.me 2>/dev/null || echo "unknown")

╔═══════════════════════════════════════════════════════════════╗
║                        ДОСТУП К ПАНЕЛЯМ                      ║
╚═══════════════════════════════════════════════════════════════╝

🌐 Веб-интерфейс: https://$DOMAIN

📊 3X-UI Панель: https://$DOMAIN/xui/
   Логин: admin
   Пароль: $XUI_PASSWORD
   Прямой доступ: https://$DOMAIN:$XUI_PORT

🛡️ AdGuard Home: https://$DOMAIN/adguard/
   Логин: admin  
   Пароль: $ADGUARD_PASSWORD
   Прямой доступ: http://$DOMAIN:$ADGUARD_PORT

╔═══════════════════════════════════════════════════════════════╗
║                          ПОРТЫ                               ║
╚═══════════════════════════════════════════════════════════════╝

VLESS: $VLESS_PORT
3X-UI: $XUI_PORT  
AdGuard: $ADGUARD_PORT
DNS: 53
HTTP: 80 (редирект на HTTPS)
HTTPS: 443

╔═══════════════════════════════════════════════════════════════╗
║                      НАСТРОЙКА КЛИЕНТОВ                      ║
╚═══════════════════════════════════════════════════════════════╝

1. Откройте 3X-UI панель
2. Создайте нового пользователя VLESS
3. Скачайте конфигурацию или QR-код
4. Импортируйте в ваш VPN клиент

Рекомендуемые клиенты:
- Android: v2rayNG
- iOS: Shadowrocket, Quantumult X
- Windows: v2rayN, Clash
- macOS: ClashX, V2rayU

╔═══════════════════════════════════════════════════════════════╗
║                      DNS ФИЛЬТРАЦИЯ                          ║
╚═══════════════════════════════════════════════════════════════╝

DNS сервер: $DOMAIN или $(curl -s ifconfig.me 2>/dev/null || echo "IP_сервера")
Порт: 53

В настройках вашего устройства укажите этот DNS сервер
для блокировки рекламы и вредоносных сайтов.

╔═══════════════════════════════════════════════════════════════╗
║                    УПРАВЛЕНИЕ СЕРВИСАМИ                      ║
╚═══════════════════════════════════════════════════════════════╝

Просмотр статуса:
systemctl status x-ui
systemctl status AdGuardHome
systemctl status nginx

Перезапуск сервисов:
systemctl restart x-ui
systemctl restart AdGuardHome
systemctl restart nginx

Просмотр логов:
journalctl -u x-ui -f
journalctl -u AdGuardHome -f
journalctl -u nginx -f

╔═══════════════════════════════════════════════════════════════╗
║                        БЕЗОПАСНОСТЬ                          ║
╚═══════════════════════════════════════════════════════════════╝

✅ SSL сертификат установлен и настроено автообновление
✅ Firewall настроен (разрешены только нужные порты)  
✅ Все сервисы работают с безопасными конфигурациями

Рекомендации:
- Регулярно обновляйте систему: apt update && apt upgrade
- Меняйте пароли панелей каждые 3-6 месяцев
- Мониторьте логи на предмет подозрительной активности

╔═══════════════════════════════════════════════════════════════╗
║                         ПОДДЕРЖКА                            ║
╚═══════════════════════════════════════════════════════════════╝

Логи установки: $LOG_FILE
GitHub: $REPO_URL

Сохраните этот файл в безопасном месте!

EOF

    print_status "Инструкции созданы: $instructions_file"

    # Показ финальной информации
    echo ""
    print_header "УСТАНОВКА ЗАВЕРШЕНА"
    echo ""
    print_status "🎉 VPN-сервер успешно установлен и настроен!"
    echo ""
    echo -e "${GREEN}📊 3X-UI Панель:${NC} https://$DOMAIN/xui/"
    echo -e "${GREEN}   Логин:${NC} admin"
    echo -e "${GREEN}   Пароль:${NC} $XUI_PASSWORD"
    echo ""
    echo -e "${GREEN}🛡️ AdGuard Home:${NC} https://$DOMAIN/adguard/"
    echo -e "${GREEN}   Логин:${NC} admin"  
    echo -e "${GREEN}   Пароль:${NC} $ADGUARD_PASSWORD"
    echo ""
    echo -e "${GREEN}🌐 Главная:${NC} https://$DOMAIN"
    echo ""
    print_warning "Сохраните пароли в безопасном месте!"
    print_status "Подробные инструкции: $instructions_file"
    echo ""
}

# Функция очистки временных файлов
cleanup() {
    print_header "ОЧИСТКА"

    # Удаление временных файлов
    rm -f "$INSTALL_STATE_FILE"
    rm -f /tmp/x-ui.tar.gz
    rm -f /tmp/AdGuardHome.tar.gz

    # Очистка кеша пакетов
    if command -v apt-get &> /dev/null; then
        apt-get autoremove -y
        apt-get autoclean
    elif command -v yum &> /dev/null; then
        yum autoremove -y
        yum clean all
    elif command -v dnf &> /dev/null; then
        dnf autoremove -y
        dnf clean all
    fi

    print_status "Временные файлы удалены ✅"
}

# Основная функция
main() {
    # Парсинг аргументов
    parse_args "$@"

    # Показ баннера
    show_banner

    # Проверка возможности продолжения установки
    if load_install_state; then
        case "$INSTALL_STEP" in
            "parameters_configured")
                print_status "Продолжаем с обновления системы..."
                ;;
            "updating_system")
                print_status "Продолжаем с настройки firewall..."
                configure_firewall
                install_nginx
                install_certbot
                check_domain_dns
                get_ssl_certificate
                install_3x_ui
                configure_3x_ui
                install_adguard
                configure_adguard
                configure_nginx_final
                create_instructions
                cleanup
                return 0
                ;;
            "configuring_firewall")
                print_status "Продолжаем с установки Nginx..."
                install_nginx
                install_certbot
                check_domain_dns
                get_ssl_certificate
                install_3x_ui
                configure_3x_ui
                install_adguard
                configure_adguard
                configure_nginx_final
                create_instructions
                cleanup
                return 0
                ;;
            # Добавьте другие этапы по необходимости
        esac
    fi

    # Проверки
    check_root
    check_dependencies  
    check_system

    # Пользовательский ввод
    get_user_input

    # Дополнительные проверки
    check_ports
    check_domain_dns

    # Установка
    update_system
    configure_firewall
    install_nginx
    install_certbot
    get_ssl_certificate
    install_3x_ui
    configure_3x_ui
    install_adguard
    configure_adguard
    configure_nginx_final
    create_instructions
    cleanup

    print_status "🎉 Все операции завершены успешно!"
}

# Запуск основной функции с передачей всех аргументов
main "$@"
