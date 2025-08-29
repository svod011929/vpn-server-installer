#!/bin/bash

# install_vpn_adguard.sh
# Скрипт автоматической установки VPN-сервера с VLESS + TLS + 3X-UI + AdGuard Home
# Автор: KodoDrive
# Версия: 2.2 (исправленная)

set -euo pipefail

# Версия скрипта
SCRIPT_VERSION="2.2.0"
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

# Переменные по умолчанию
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

# Поддерживаемые дистрибутивы
SUPPORTED_OS=("ubuntu" "debian" "centos" "rhel" "fedora" "almalinux" "rocky")

# URL для загрузки компонентов
XUI_INSTALL_SCRIPT="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
ADGUARD_INSTALL_SCRIPT="https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh"

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
║              VPN Server Auto Installer v2.2                  ║
║           VLESS + TLS + 3X-UI + AdGuard Home                 ║
║                                                               ║
║                    Made by KodoDrive                         ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Функция парсинга аргументов
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
                exit 0
                ;;
            *)
                print_error "Неизвестный параметр: $1"
                exit 1
                ;;
        esac
    done
}

# Функция показа справки
show_help() {
    cat << EOF
VPN Server Auto Installer v${SCRIPT_VERSION}

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

  # Автоматическая установка
  bash <(curl -fsSL ${SCRIPT_URL}) \\
    --domain "vpn.example.com" \\
    --email "admin@example.com" \\
    --auto-password \\
    --auto-confirm

EOF
}

# Функция проверки root прав
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен запускаться с правами root!"
        print_status "Используйте: sudo $0"
        exit 1
    fi
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
            exit 1
        fi
    else
        print_error "Не удалось определить операционную систему"
        exit 1
    fi

    # Проверка архитектуры
    ARCH=$(uname -m)
    print_status "Архитектура: $ARCH"

    # Проверка RAM
    RAM_MB=$(free -m | awk 'NR==2{print $2}')
    print_status "ОЗУ: ${RAM_MB}MB"

    if [ "$RAM_MB" -lt 512 ]; then
        print_error "Недостаточно RAM. Требуется минимум 512MB"
        exit 1
    fi

    # Проверка интернета
    print_status "Проверка интернет подключения..."
    if ! timeout 10 curl -s --max-time 10 https://google.com > /dev/null; then
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

# Функция остановки конфликтующих сервисов
stop_conflicting_services() {
    local services=("apache2" "httpd" "nginx" "systemd-resolved" "bind9" "named")

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            print_status "Остановка сервиса: $service"
            systemctl stop "$service" || true
            systemctl disable "$service" || true
        fi
    done

    # Принудительное освобождение порта 53
    if command -v systemctl &> /dev/null; then
        systemctl mask systemd-resolved || true
    fi

    sleep 3
}

# Функция валидации домена
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

# Функция валидации email
validate_email() {
    local email="$1"

    if [ -z "$email" ]; then
        return 1
    fi

    if ! echo "$email" | grep -E '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' > /dev/null; then
        return 1
    fi

    return 0
}

# Функция получения IP сервера
get_server_ip() {
    local ip=""
    local services=("ifconfig.me" "icanhazip.com" "ipecho.net/plain")

    for service in "${services[@]}"; do
        ip=$(timeout 10 curl -s --max-time 5 "https://$service" 2>/dev/null | tr -d '\n\r' || echo "")
        if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "$ip"
            return 0
        fi
    done

    echo "unknown"
}

# Функция проверки DNS
check_domain_dns() {
    print_header "ПРОВЕРКА DNS"

    local server_ip
    server_ip=$(get_server_ip)

    if [ "$server_ip" = "unknown" ]; then
        print_warning "Не удалось определить IP сервера"
        return 0
    fi

    print_status "IP сервера: $server_ip"

    # Проверка разрешения домена
    local domain_ip=""
    if command -v dig &> /dev/null; then
        domain_ip=$(timeout 10 dig +short "$DOMAIN" 2>/dev/null | head -n1)
    elif command -v nslookup &> /dev/null; then
        domain_ip=$(timeout 10 nslookup "$DOMAIN" 2>/dev/null | awk '/^Address: / { print $2 }' | head -n1)
    fi

    if [ -n "$domain_ip" ]; then
        print_status "IP домена: $domain_ip"
        if [ "$server_ip" != "$domain_ip" ]; then
            print_warning "DNS домена не указывает на этот сервер"
            print_warning "Это может вызвать проблемы с SSL сертификатом"
        else
            print_status "DNS настроен правильно ✅"
        fi
    fi
}

# Функция генерации безопасного пароля
generate_secure_password() {
    local length=${1:-16}

    if command -v openssl &> /dev/null; then
        openssl rand -base64 32 | tr -d "=+/" | cut -c1-${length}
    else
        < /dev/urandom tr -dc 'A-Za-z0-9' | head -c${length}
    fi
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

    # Пароль для 3X-UI
    if [ -z "$XUI_PASSWORD" ]; then
        if [ "$AUTO_PASSWORD" = true ]; then
            XUI_PASSWORD=$(generate_secure_password 16)
            print_status "Сгенерирован пароль для 3X-UI"
        else
            read -p "Введите пароль для 3X-UI (Enter для автогенерации): " XUI_PASSWORD
            if [ -z "$XUI_PASSWORD" ]; then
                XUI_PASSWORD=$(generate_secure_password 16)
                print_status "Сгенерирован пароль для 3X-UI"
            fi
        fi
    fi

    # Пароль для AdGuard
    if [ -z "$ADGUARD_PASSWORD" ]; then
        if [ "$AUTO_PASSWORD" = true ]; then
            ADGUARD_PASSWORD=$(generate_secure_password 16)
            print_status "Сгенерирован пароль для AdGuard"
        else
            read -p "Введите пароль для AdGuard (Enter для автогенерации): " ADGUARD_PASSWORD
            if [ -z "$ADGUARD_PASSWORD" ]; then
                ADGUARD_PASSWORD=$(generate_secure_password 16)
                print_status "Сгенерирован пароль для AdGuard"
            fi
        fi
    fi

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

# Функция обновления системы
update_system() {
    print_header "ОБНОВЛЕНИЕ СИСТЕМЫ"
    save_install_state "updating_system"

    export DEBIAN_FRONTEND=noninteractive

    if command -v apt-get &> /dev/null; then
        print_status "Обновление системы (Debian/Ubuntu)..."
        apt-get update -qq
        apt-get upgrade -y -qq
        apt-get install -y -qq curl wget unzip software-properties-common ca-certificates gnupg lsb-release net-tools
    elif command -v yum &> /dev/null; then
        print_status "Обновление системы (CentOS/RHEL)..."
        yum update -y -q
        yum install -y -q curl wget unzip epel-release ca-certificates net-tools
    elif command -v dnf &> /dev/null; then
        print_status "Обновление системы (Fedora)..."
        dnf update -y -q
        dnf install -y -q curl wget unzip ca-certificates net-tools
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
            apt-get install -y -qq ufw
        elif command -v yum &> /dev/null; then
            yum install -y -q ufw
        elif command -v dnf &> /dev/null; then
            dnf install -y -q ufw
        fi
    fi

    # Настройка ufw
    ufw --force reset >/dev/null 2>&1
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1

    # Получение SSH порта
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
    ufw allow "$ADGUARD_PORT"/tcp comment "AdGuard Web" >/dev/null 2>&1
    ufw allow 53/tcp comment "DNS TCP" >/dev/null 2>&1
    ufw allow 53/udp comment "DNS UDP" >/dev/null 2>&1

    if [ "$VLESS_PORT" != "443" ]; then
        ufw allow "$VLESS_PORT"/tcp comment "VLESS" >/dev/null 2>&1
    fi

    ufw --force enable >/dev/null 2>&1

    print_status "Firewall настроен ✅"
}

# Функция установки Nginx
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

    # Создание простой конфигурации для получения SSL
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

    # Создание тестовой страницы
    echo "Server setup in progress..." > /var/www/html/index.html

    systemctl enable nginx
    systemctl start nginx

    print_status "Nginx установлен ✅"
}

# Функция установки Certbot
install_certbot() {
    print_header "УСТАНОВКА CERTBOT"
    save_install_state "installing_certbot"

    if command -v apt-get &> /dev/null; then
        apt-get install -y -qq certbot python3-certbot-nginx
    elif command -v yum &> /dev/null; then
        yum install -y -q certbot python3-certbot-nginx
    elif command -v dnf &> /dev/null; then
        dnf install -y -q certbot python3-certbot-nginx
    fi

    print_status "Certbot установлен ✅"
}

# Функция получения SSL сертификата
get_ssl_certificate() {
    print_header "ПОЛУЧЕНИЕ SSL СЕРТИФИКАТА"
    save_install_state "getting_ssl_certificate"

    # Убеждаемся что nginx работает
    systemctl start nginx
    sleep 3

    print_status "Получение SSL сертификата для $DOMAIN..."

    if certbot certonly --webroot --webroot-path=/var/www/html --email "$EMAIL" --agree-tos --non-interactive --domains "$DOMAIN"; then
        print_status "SSL сертификат получен ✅"

        # Настройка автообновления
        cat > /etc/cron.d/certbot-renewal << 'EOF'
0 12 * * * root /usr/bin/certbot renew --quiet --post-hook "systemctl reload nginx"
EOF

    else
        print_error "Не удалось получить SSL сертификат"
        print_error "Убедитесь что домен $DOMAIN указывает на IP $(get_server_ip)"
        exit 1
    fi
}

# Функция установки 3X-UI
install_3x_ui() {
    print_header "УСТАНОВКА 3X-UI"
    save_install_state "installing_3x_ui"

    print_status "Скачивание и установка 3X-UI..."

    # Установка 3X-UI через оригинальный скрипт
    export XUI_USERNAME="$XUI_USERNAME"
    export XUI_PASSWORD="$XUI_PASSWORD" 
    export XUI_PORT="$XUI_PORT"

    # Скачиваем и модифицируем скрипт установки
    curl -Ls "$XUI_INSTALL_SCRIPT" > /tmp/3x-ui-install.sh

    # Делаем автоматической установку
    sed -i 's/read -p/#read -p/g' /tmp/3x-ui-install.sh

    # Запускаем установку
    bash /tmp/3x-ui-install.sh || {
        print_error "Ошибка установки 3X-UI через скрипт"
        # Альтернативная установка
        install_3x_ui_manual
        return
    }

    # Конфигурируем 3X-UI
    configure_3x_ui_settings

    print_status "3X-UI установлен ✅"
}

# Функция ручной установки 3X-UI
install_3x_ui_manual() {
    print_status "Альтернативная установка 3X-UI..."

    cd /opt

    # Определение архитектуры
    case $(uname -m) in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) print_error "Неподдерживаемая архитектура"; exit 1 ;;
    esac

    # Получение последней версии
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep -oP '"tag_name": "\K[^"]*' || echo "v2.3.4")

    # Скачивание
    local download_url="https://github.com/MHSanaei/3x-ui/releases/download/$latest_version/x-ui-linux-${ARCH}.tar.gz"

    if ! wget -q "$download_url" -O x-ui.tar.gz; then
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

    # Создание systemd сервиса
    cat > /etc/systemd/system/x-ui.service << EOF
[Unit]
Description=3x-ui Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/3x-ui
ExecStart=/opt/3x-ui/x-ui
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable x-ui
}

# Функция настройки 3X-UI
configure_3x_ui_settings() {
    print_status "Настройка 3X-UI..."

    # Запуск сервиса
    systemctl start x-ui
    sleep 5

    # Проверка запуска
    if ! systemctl is-active --quiet x-ui; then
        print_error "3X-UI не запустился"
        journalctl -u x-ui --no-pager -n 20
        return 1
    fi

    # Настройка через API (если возможно)
    # Или через файлы конфигурации
    if [ -d "/opt/3x-ui" ]; then
        # Настройка базы данных и конфигурации
        /opt/3x-ui/x-ui setting -username "$XUI_USERNAME" -password "$XUI_PASSWORD" -port "$XUI_PORT" || true
        systemctl restart x-ui
    fi

    print_status "3X-UI настроен на порту $XUI_PORT"
}

# Функция установки AdGuard Home
install_adguard() {
    print_header "УСТАНОВКА ADGUARD HOME"
    save_install_state "installing_adguard"

    print_status "Скачивание и установка AdGuard Home..."

    # Используем официальный скрипт установки
    curl -s -S -L "$ADGUARD_INSTALL_SCRIPT" | sh -s -- -v || {
        print_error "Ошибка установки AdGuard через скрипт"
        install_adguard_manual
        return
    }

    print_status "AdGuard Home установлен ✅"
}

# Функция ручной установки AdGuard
install_adguard_manual() {
    print_status "Альтернативная установка AdGuard Home..."

    cd /opt

    # Определение архитектуры
    case $(uname -m) in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) print_error "Неподдерживаемая архитектура"; exit 1 ;;
    esac

    # Скачивание AdGuard Home
    local download_url="https://static.adguard.com/adguardhome/release/AdGuardHome_linux_${ARCH}.tar.gz"

    if ! wget -q "$download_url" -O AdGuardHome.tar.gz; then
        print_error "Не удалось скачать AdGuard Home"
        exit 1
    fi

    tar -zxf AdGuardHome.tar.gz
    rm AdGuardHome.tar.gz

    chmod +x AdGuardHome/AdGuardHome

    # Создание systemd сервиса
    cat > /etc/systemd/system/AdGuardHome.service << EOF
[Unit]
Description=AdGuard Home
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/opt/AdGuardHome/AdGuardHome -c /opt/AdGuardHome/AdGuardHome.yaml -w /opt/AdGuardHome
WorkingDirectory=/opt/AdGuardHome
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable AdGuardHome
    systemctl start AdGuardHome
}

# Функция настройки AdGuard Home
configure_adguard() {
    print_header "НАСТРОЙКА ADGUARD HOME"
    save_install_state "configuring_adguard"

    # Ожидание запуска AdGuard
    sleep 5

    # Создание начальной конфигурации
    if [ ! -f "/opt/AdGuardHome/AdGuardHome.yaml" ]; then
        create_adguard_config
        systemctl restart AdGuardHome
        sleep 5
    fi

    # Проверка запуска
    if systemctl is-active --quiet AdGuardHome; then
        print_status "AdGuard Home запущен на порту $ADGUARD_PORT ✅"
    else
        print_error "AdGuard Home не запустился"
        journalctl -u AdGuardHome --no-pager -n 20
    fi
}

# Функция создания конфигурации AdGuard
create_adguard_config() {
    # Генерация bcrypt хеша пароля
    local password_hash
    if command -v htpasswd &> /dev/null; then
        password_hash=$(htpasswd -bnBC 10 "" "$ADGUARD_PASSWORD" | tr -d ':\n')
    else
        # Простой хеш если htpasswd недоступен
        password_hash=$(echo -n "$ADGUARD_PASSWORD" | sha256sum | cut -d' ' -f1)
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
  parental_enabled: false
  safebrowsing_enabled: true
  safesearch_enabled: false
  resolve_clients: true
  use_private_ptr_resolvers: true
  local_ptr_upstreams: []
  serve_http3: false
  use_http3_upstreams: false
  upstream_dns:
    - https://dns.cloudflare.com/dns-query
    - https://dns.google/dns-query
    - 1.1.1.1
    - 8.8.8.8
  upstream_dns_file: ""
  bootstrap_dns:
    - 9.9.9.10
    - 149.112.112.10
  all_servers: false
  fastest_addr: false
  allowed_clients: []
  disallowed_clients: []
  blocked_hosts:
    - version.bind
    - id.server
    - hostname.bind
  cache_size: 4194304
  cache_ttl_min: 0
  cache_ttl_max: 0
  cache_optimistic: false
  enable_dnssec: false
  aaaa_disabled: false
  use_dns64: false
  dns64_prefixes: []
  serve_plain_dns: true
  edns_client_subnet:
    custom_ip: ""
    enabled: false
    use_custom: false
  max_goroutines: 300
  ipset: []
  ipset_file: ""
tls:
  enabled: false
  server_name: ""
  force_https: false
  port_https: 443
  port_dns_over_tls: 853
  port_dns_over_quic: 853
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
whitelist_filters: []
user_rules: []
dhcp:
  enabled: false
clients:
  runtime_sources:
    whois: true
    arp: true
    rdns: true
    dhcp: true
    hosts: true
  persistent: []
log_compress: false
log_localtime: false
log_max_backups: 0
log_max_size: 100
log_max_age: 3
log_file: ""
verbose: false
os:
  group: ""
  user: ""
  rlimit_nofile: 0
schema_version: 20
EOF
}

# Функция финальной настройки Nginx
configure_nginx_final() {
    print_header "ФИНАЛЬНАЯ НАСТРОЙКА NGINX"
    save_install_state "configuring_nginx_final"

    # Создание конфигурации с SSL и без прокси (прямой доступ к панелям)
    cat > /etc/nginx/sites-available/default << EOF
server_tokens off;

# HTTP -> HTTPS редирект
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

# HTTPS сервер
server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name $DOMAIN;

    # SSL конфигурация
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # SSL настройки
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Заголовки безопасности
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;

    # Главная страница
    location / {
        root /var/www/html;
        index index.html;
        try_files \$uri \$uri/ =404;
    }

    # Логи
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
}
EOF

    # Создание главной страницы
    create_main_page

    # Проверка и перезагрузка nginx
    if nginx -t; then
        systemctl reload nginx
        print_status "Nginx перезагружен ✅"
    else
        print_error "Ошибка в конфигурации Nginx"
        nginx -t
        exit 1
    fi
}

# Функция создания главной страницы
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
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: #333;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }

        .container {
            max-width: 800px;
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

        .content {
            padding: 40px;
        }

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

        .panel h3 {
            color: #495057;
            margin-bottom: 20px;
            font-size: 1.3rem;
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

        .stat-label {
            color: #6c757d;
            font-size: 0.9rem;
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
        }

        @media (max-width: 768px) {
            .header h1 {
                font-size: 2rem;
            }
            .content {
                padding: 20px;
            }
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
                <p style="margin-top: 15px; font-size: 0.9rem; color: #666;">
                    <strong>Логин:</strong> admin<br>
                    <strong>Пароли:</strong> сохранены в файле инструкций
                </p>
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
                <h3>📱 Подключение к VPN</h3>
                <ol style="margin: 15px 0 15px 20px;">
                    <li>Откройте панель <strong>3X-UI</strong> по ссылке выше</li>
                    <li>Войдите используя логин "admin" и пароль из инструкций</li>
                    <li>Создайте нового пользователя VLESS</li>
                    <li>Скачайте конфигурацию или отсканируйте QR-код</li>
                    <li>Импортируйте в ваш VPN клиент</li>
                </ol>

                <div style="background: #fff3cd; padding: 15px; border-radius: 8px; margin: 15px 0;">
                    <h5>📱 Рекомендуемые клиенты:</h5>
                    <p><strong>Android:</strong> v2rayNG, Clash for Android</p>
                    <p><strong>iOS:</strong> Shadowrocket, Quantumult X</p>
                    <p><strong>Windows:</strong> v2rayN, Clash for Windows</p>
                    <p><strong>macOS:</strong> ClashX, V2rayU</p>
                </div>
            </div>

            <div class="panel">
                <h3>🛡️ DNS с фильтрацией</h3>
                <p>DNS сервер с блокировкой рекламы и вредоносных сайтов:</p>
                <div style="margin: 15px 0; padding: 10px; background: #f8f9fa; border-radius: 6px;">
                    <p><strong>DNS:</strong> $server_ip или $DOMAIN</p>
                    <p><strong>Порт:</strong> 53</p>
                </div>
            </div>
        </div>

        <div class="footer">
            <p>🚀 Powered by <strong>VPN Auto Installer v$SCRIPT_VERSION</strong></p>
            <p>Создано для обеспечения вашей безопасности в интернете</p>
        </div>
    </div>
</body>
</html>
EOF
}

# Функция создания инструкций
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
HTTP: 80 (редирект на HTTPS)
HTTPS: 443

╔═══════════════════════════════════════════════════════════════╗
║                      НАСТРОЙКА VPN                           ║
╚═══════════════════════════════════════════════════════════════╝

1. Откройте 3X-UI: https://$DOMAIN:$XUI_PORT
2. Войдите (логин: $XUI_USERNAME, пароль выше)
3. Создайте нового пользователя VLESS
4. Настройте порт $VLESS_PORT с TLS
5. Используйте домен: $DOMAIN
6. Скачайте конфигурацию или QR-код

Рекомендуемые клиенты:
- Android: v2rayNG
- iOS: Shadowrocket
- Windows: v2rayN
- macOS: ClashX

╔═══════════════════════════════════════════════════════════════╗
║                      DNS ФИЛЬТРАЦИЯ                          ║
╚═══════════════════════════════════════════════════════════════╝

DNS сервер: $server_ip
Порт: 53

Настройте в параметрах сети для блокировки рекламы.

╔═══════════════════════════════════════════════════════════════╗
║                    УПРАВЛЕНИЕ СЕРВИСАМИ                      ║
╚═══════════════════════════════════════════════════════════════╝

Статус сервисов:
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
║                        БЕЗОПАСНОСТЬ                          ║
╚═══════════════════════════════════════════════════════════════╝

✅ SSL сертификат активен (автообновление настроено)
✅ Firewall настроен
✅ Сервисы работают в безопасном режиме

Рекомендации:
- Регулярно обновляйте систему
- Меняйте пароли каждые 3-6 месяцев
- Мониторьте логи сервисов

СОХРАНИТЕ ЭТОТ ФАЙЛ В БЕЗОПАСНОМ МЕСТЕ!

EOF

    chmod 600 "$instructions_file"
    print_status "Инструкции сохранены: $instructions_file"
}

# Функция показа финальной информации
show_final_info() {
    echo ""
    print_header "УСТАНОВКА ЗАВЕРШЕНА"
    echo ""
    print_status "🎉 VPN-сервер успешно установлен!"
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
    print_status "📋 Подробные инструкции: /root/vpn-server-info.txt"
    echo ""
    print_status "Теперь откройте https://$DOMAIN для начала работы"
    echo ""
}

# Функция очистки
cleanup() {
    print_header "ЗАВЕРШЕНИЕ"

    rm -f "$INSTALL_STATE_FILE"
    rm -f /tmp/3x-ui-install.sh

    if command -v apt-get &> /dev/null; then
        apt-get autoremove -y >/dev/null 2>&1
    fi

    print_status "Установка завершена ✅"
}

# Основная функция
main() {
    parse_args "$@"
    show_banner

    check_root
    check_system
    get_user_input
    check_ports
    check_domain_dns

    update_system
    configure_firewall
    install_nginx
    install_certbot
    get_ssl_certificate
    install_3x_ui
    configure_adguard
    configure_nginx_final
    create_instructions
    show_final_info
    cleanup

    print_status "🎉 Все готово к использованию!"
}

# Запуск
main "$@"
