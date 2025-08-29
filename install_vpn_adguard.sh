#!/bin/bash

# install_vpn_adguard.sh
# Скрипт автоматической установки VPN-сервера с VLESS + TLS + 3X-UI + AdGuard Home
# Автор: KodoDrive
# Версия: 2.3 (полностью переписанная)

set -euo pipefail

# Версия скрипта
SCRIPT_VERSION="2.3.0"
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

    # Восстановление DNS
    if [ -f /etc/resolv.conf.backup ]; then
        mv /etc/resolv.conf.backup /etc/resolv.conf 2>/dev/null || true
    fi

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
║              VPN Server Auto Installer v2.3                  ║
║           VLESS + TLS + 3X-UI + AdGuard Home                 ║
║                                                               ║
║                    Made by KodoDrive                         ║
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

    local deps=("curl" "wget" "openssl" "systemctl")
    local missing_deps=()

    # Проверка базовых команд
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
            print_warning "Отсутствует зависимость: $dep"
        else
            print_debug "Найдена зависимость: $dep"
        fi
    done

    # Проверка дополнительных утилит
    if ! command -v netstat &> /dev/null && ! command -v ss &> /dev/null; then
        missing_deps+=("net-tools")
        print_warning "Отсутствуют утилиты для проверки портов"
    fi

    if ! command -v dig &> /dev/null && ! command -v nslookup &> /dev/null; then
        missing_deps+=("dnsutils")
        print_warning "Отсутствуют утилиты DNS"
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_status "Устанавливаю недостающие зависимости..."
        install_dependencies "${missing_deps[@]}"
    fi

    print_status "Все зависимости установлены ✅"
}

# Функция установки зависимостей
install_dependencies() {
    local deps=("$@")

    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        for dep in "${deps[@]}"; do
            case $dep in
                "dnsutils")
                    apt-get install -y -qq dnsutils bind9-utils
                    ;;
                "net-tools")
                    apt-get install -y -qq net-tools
                    ;;
                *)
                    apt-get install -y -qq "$dep"
                    ;;
            esac
        done
    elif command -v yum &> /dev/null; then
        for dep in "${deps[@]}"; do
            case $dep in
                "dnsutils")
                    yum install -y -q bind-utils
                    ;;
                "net-tools")
                    yum install -y -q net-tools
                    ;;
                *)
                    yum install -y -q "$dep"
                    ;;
            esac
        done
    elif command -v dnf &> /dev/null; then
        for dep in "${deps[@]}"; do
            case $dep in
                "dnsutils")
                    dnf install -y -q bind-utils
                    ;;
                "net-tools")
                    dnf install -y -q net-tools
                    ;;
                *)
                    dnf install -y -q "$dep"
                    ;;
            esac
        done
    else
        print_error "Неподдерживаемый менеджер пакетов"
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

    # Проверка RAM
    RAM_MB=$(free -m | awk 'NR==2{print $2}')
    print_status "ОЗУ: ${RAM_MB}MB"

    if [ "$RAM_MB" -lt 512 ]; then
        print_error "Недостаточно RAM. Требуется минимум 512MB, у вас: ${RAM_MB}MB"
        exit 1
    elif [ "$RAM_MB" -lt 1024 ]; then
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

    if [ "$DISK_GB" -lt 2 ]; then
        print_error "Недостаточно свободного места. Требуется минимум 2GB"
        exit 1
    fi

    # Проверка интернета
    print_status "Проверка интернет подключения..."
    if ! timeout 10 curl -s --max-time 10 https://google.com > /dev/null; then
        print_error "Нет подключения к интернету"
        exit 1
    fi
    print_status "Интернет подключение: ✅"

    # Проверка systemd
    if ! command -v systemctl &> /dev/null; then
        print_error "Требуется systemd для управления сервисами"
        exit 1
    fi
}

# Функция проверки портов
check_ports() {
    print_header "ПРОВЕРКА ПОРТОВ"

    local ports=("$VLESS_PORT" "$XUI_PORT" "$ADGUARD_PORT" "80" "53")
    local blocked_ports=()

    for port in "${ports[@]}"; do
        if check_port_in_use "$port"; then
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
                stop_conflicting_services "${blocked_ports[@]}"

                # Повторная проверка
                local still_blocked=()
                for port in "${blocked_ports[@]}"; do
                    if check_port_in_use "$port"; then
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
            stop_conflicting_services "${blocked_ports[@]}"
        fi
    fi

    print_status "Все необходимые порты свободны ✅"
}

# Функция проверки использования порта
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

# Функция остановки конфликтующих сервисов
stop_conflicting_services() {
    local ports=("$@")

    print_status "Остановка конфликтующих сервисов..."

    # Известные сервисы для остановки
    local services_to_stop=("apache2" "httpd" "nginx" "systemd-resolved" "bind9" "named" "dnsmasq")

    for service in "${services_to_stop[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            print_status "Остановка сервиса: $service"
            systemctl stop "$service" 2>/dev/null || true
            systemctl disable "$service" 2>/dev/null || true
        fi
    done

    # Принудительное освобождение портов
    for port in "${ports[@]}"; do
        if [ "$port" = "53" ]; then
            # Особая обработка DNS порта
            systemctl mask systemd-resolved 2>/dev/null || true
            killall -9 dnsmasq 2>/dev/null || true
            killall -9 named 2>/dev/null || true
        fi
    done

    sleep 3
}

# Функция валидации домена
validate_domain() {
    local domain="$1"

    # Проверка на пустое значение
    if [ -z "$domain" ]; then
        return 1
    fi

    # Улучшенная регулярка для доменов
    if [[ ! $domain =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        return 1
    fi

    # Проверка длины
    if [ ${#domain} -gt 253 ]; then
        return 1
    fi

    # Проверка на локальные домены
    if [[ "$domain" =~ \.(local|localhost|test|invalid)$ ]]; then
        print_warning "Использование локального домена может вызвать проблемы с SSL"
    fi

    return 0
}

# Функция валидации email
validate_email() {
    local email="$1"

    # Проверка на пустое значение
    if [ -z "$email" ]; then
        return 1
    fi

    # Основная проверка формата
    if ! echo "$email" | grep -E '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' > /dev/null; then
        return 1
    fi

    # Проверка длины
    if [ ${#email} -gt 254 ]; then
        return 1
    fi

    return 0
}

# Функция проверки DNS
check_domain_dns() {
    print_header "ПРОВЕРКА DNS"

    local server_ip
    local domain_ip

    # Получение IP сервера
    server_ip=$(get_server_ip)

    if [ "$server_ip" = "unknown" ]; then
        print_warning "Не удалось определить IP адрес сервера"
        if [ "$AUTO_CONFIRM" != true ]; then
            read -p "Продолжить без проверки DNS? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
        return 0
    fi

    print_status "IP сервера: $server_ip"

    # Получение IP домена
    domain_ip=$(resolve_domain "$DOMAIN")

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
        print_warning "Сервер: $server_ip, Домен: $domain_ip"
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

# Функция получения IP сервера
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

# Функция разрешения домена
resolve_domain() {
    local domain="$1"
    local ip=""

    if command -v dig &> /dev/null; then
        ip=$(timeout 10 dig +short "$domain" +time=5 2>/dev/null | head -n1)
    elif command -v nslookup &> /dev/null; then
        ip=$(timeout 10 nslookup "$domain" 2>/dev/null | awk '/^Address: / { print $2 }' | head -n1)
    fi

    # Проверка что получили валидный IP
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "$ip"
    else
        echo ""
    fi
}

# Функция генерации безопасных паролей
generate_secure_password() {
    local length=${1:-20}

    # Используем более безопасный метод генерации
    if command -v openssl &> /dev/null; then
        openssl rand -base64 32 | tr -d "=+/" | cut -c1-${length}
    else
        # Fallback метод
        < /dev/urandom tr -dc 'A-Za-z0-9!@#$%^&*' | head -c${length}
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

    # Генерация или ввод паролей
    generate_passwords

    # Валидация портов
    validate_ports

    # Финальное подтверждение
    show_final_confirmation

    print_status "Настройки приняты. Начинаем установку..."
    save_install_state "parameters_configured"
    sleep 2
}

# Функция генерации паролей
generate_passwords() {
    # Пароль для 3X-UI
    if [ -z "$XUI_PASSWORD" ]; then
        if [ "$AUTO_PASSWORD" = true ]; then
            XUI_PASSWORD=$(generate_secure_password 20)
            print_status "Сгенерирован пароль для 3X-UI"
        else
            read -p "Введите пароль для панели 3X-UI (оставьте пустым для автогенерации): " XUI_PASSWORD
            if [ -z "$XUI_PASSWORD" ]; then
                XUI_PASSWORD=$(generate_secure_password 20)
                print_status "Сгенерирован пароль для 3X-UI"
            fi
        fi
    else
        print_status "Пароль 3X-UI: [установлен]"
    fi

    # Пароль для AdGuard
    if [ -z "$ADGUARD_PASSWORD" ]; then
        if [ "$AUTO_PASSWORD" = true ]; then
            ADGUARD_PASSWORD=$(generate_secure_password 20)
            print_status "Сгенерирован пароль для AdGuard"
        else
            read -p "Введите пароль для AdGuard Home (оставьте пустым для автогенерации): " ADGUARD_PASSWORD
            if [ -z "$ADGUARD_PASSWORD" ]; then
                ADGUARD_PASSWORD=$(generate_secure_password 20)
                print_status "Сгенерирован пароль для AdGuard"
            fi
        fi
    else
        print_status "Пароль AdGuard: [установлен]"
    fi
}

# Функция валидации портов
validate_ports() {
    # Проверка что порты являются числами и в правильном диапазоне
    for port_var in VLESS_PORT XUI_PORT ADGUARD_PORT; do
        port_value="${!port_var}"
        if ! [[ "$port_value" =~ ^[0-9]+$ ]] || [ "$port_value" -lt 1 ] || [ "$port_value" -gt 65535 ]; then
            print_error "Неверный порт для $port_var: $port_value"
            exit 1
        fi
    done

    # Проверка что порты не дублируются
    if [ "$VLESS_PORT" = "$XUI_PORT" ] || [ "$VLESS_PORT" = "$ADGUARD_PORT" ] || [ "$XUI_PORT" = "$ADGUARD_PORT" ]; then
        print_error "Порты не должны дублироваться"
        exit 1
    fi

    print_status "Порт VLESS: $VLESS_PORT"
    print_status "Порт 3X-UI: $XUI_PORT"
    print_status "Порт AdGuard: $ADGUARD_PORT"
}

# Функция финального подтверждения
show_final_confirmation() {
    if [ "$AUTO_CONFIRM" != true ]; then
        echo ""
        print_warning "Проверьте настройки:"
        echo "  Домен: $DOMAIN"
        echo "  Email: $EMAIL"  
        echo "  Порт VLESS: $VLESS_PORT"
        echo "  Порт 3X-UI: $XUI_PORT"
        echo "  Порт AdGuard: $ADGUARD_PORT"
        echo "  Пароль 3X-UI: [скрыт]"
        echo "  Пароль AdGuard: [скрыт]"
        echo ""
        read -p "Начать установку? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Установка отменена"
            exit 0
        fi
    fi
}

# Функция обновления системы
update_system() {
    print_header "ОБНОВЛЕНИЕ СИСТЕМЫ"
    save_install_state "updating_system"

    export DEBIAN_FRONTEND=noninteractive

    if command -v apt-get &> /dev/null; then
        print_status "Обновление пакетов (Debian/Ubuntu)..."
        apt-get update -qq
        apt-get upgrade -y -qq
        apt-get install -y -qq curl wget unzip software-properties-common ca-certificates gnupg lsb-release net-tools apache2-utils
    elif command -v yum &> /dev/null; then
        print_status "Обновление пакетов (CentOS/RHEL)..."
        yum update -y -q
        yum install -y -q curl wget unzip epel-release ca-certificates net-tools httpd-tools
    elif command -v dnf &> /dev/null; then
        print_status "Обновление пакетов (Fedora)..."
        dnf update -y -q
        dnf install -y -q curl wget unzip ca-certificates net-tools httpd-tools
    fi

    print_status "Система обновлена ✅"
}

# Функция настройки firewall
configure_firewall() {
    print_header "НАСТРОЙКА FIREWALL"
    save_install_state "configuring_firewall"

    # Установка ufw если не установлен
    if ! command -v ufw &> /dev/null; then
        install_ufw
    fi

    # Сброс правил
    ufw --force reset >/dev/null 2>&1

    # Базовые правила
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1

    # SSH (определяем текущий порт SSH)
    local ssh_port
    ssh_port=$(ss -tlnp 2>/dev/null | awk '/sshd/ && /LISTEN/ {split($4,a,":"); print a[length(a)]}' | head -n1)
    if [ -z "$ssh_port" ]; then
        ssh_port="22"
    fi
    ufw allow "$ssh_port"/tcp comment "SSH" >/dev/null 2>&1

    # HTTP/HTTPS
    ufw allow 80/tcp comment "HTTP" >/dev/null 2>&1
    ufw allow 443/tcp comment "HTTPS" >/dev/null 2>&1

    # Кастомные порты
    if [ "$VLESS_PORT" != "443" ]; then
        ufw allow "$VLESS_PORT"/tcp comment "VLESS" >/dev/null 2>&1
    fi

    ufw allow "$XUI_PORT"/tcp comment "3X-UI" >/dev/null 2>&1
    ufw allow "$ADGUARD_PORT"/tcp comment "AdGuard Web" >/dev/null 2>&1

    # DNS для AdGuard
    ufw allow 53/tcp comment "DNS TCP" >/dev/null 2>&1
    ufw allow 53/udp comment "DNS UDP" >/dev/null 2>&1

    # Включение firewall
    ufw --force enable >/dev/null 2>&1

    print_status "Firewall настроен ✅"
}

# Функция установки UFW
install_ufw() {
    if command -v apt-get &> /dev/null; then
        apt-get install -y -qq ufw
    elif command -v yum &> /dev/null; then
        yum install -y -q ufw
    elif command -v dnf &> /dev/null; then
        dnf install -y -q ufw
    else
        print_warning "Не удалось установить UFW. Пропускаем настройку firewall."
        return 1
    fi
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
    else
        print_error "Не удалось установить Nginx"
        exit 1
    fi

    # Создание директорий
    mkdir -p /var/www/html
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled

    # Остановка nginx (будет запущен после настройки SSL)
    systemctl stop nginx >/dev/null 2>&1 || true
    systemctl enable nginx >/dev/null 2>&1

    print_status "Nginx установлен ✅"
}

# Функция установки Certbot
install_certbot() {
    print_header "УСТАНОВКА CERTBOT"
    save_install_state "installing_certbot"

    if command -v apt-get &> /dev/null; then
        # Установка через snapd для более новой версии
        if command -v snap &> /dev/null; then
            snap install --classic certbot >/dev/null 2>&1 || apt-get install -y -qq certbot python3-certbot-nginx
        else
            apt-get install -y -qq certbot python3-certbot-nginx
        fi
    elif command -v yum &> /dev/null; then
        yum install -y -q certbot python3-certbot-nginx
    elif command -v dnf &> /dev/null; then
        dnf install -y -q certbot python3-certbot-nginx
    else
        print_error "Не удалось установить Certbot"
        exit 1
    fi

    # Создание симлинка если установлен через snap
    if [ -f "/snap/bin/certbot" ] && [ ! -f "/usr/bin/certbot" ]; then
        ln -sf /snap/bin/certbot /usr/bin/certbot
    fi

    print_status "Certbot установлен ✅"
}

# Функция получения SSL сертификата
get_ssl_certificate() {
    print_header "ПОЛУЧЕНИЕ SSL СЕРТИФИКАТА"
    save_install_state "getting_ssl_certificate"

    # Создание базовой конфигурации nginx для верификации
    create_nginx_acme_config

    # Создание директории для веб-рута
    mkdir -p /var/www/html

    # Создание простой тестовой страницы
    echo "Server setup in progress..." > /var/www/html/index.html

    # Запуск nginx
    systemctl start nginx

    # Проверка что nginx запустился
    sleep 3
    if ! systemctl is-active --quiet nginx; then
        print_error "Nginx не запустился"
        systemctl status nginx
        exit 1
    fi

    # Получение сертификата
    print_status "Получение SSL сертификата для $DOMAIN..."

    local certbot_cmd="certbot certonly --webroot --webroot-path=/var/www/html --email $EMAIL --agree-tos --non-interactive --domains $DOMAIN"

    if $certbot_cmd; then
        print_status "SSL сертификат получен ✅"
    else
        print_error "Не удалось получить SSL сертификат"
        print_error "Проверьте что:"
        print_error "1. Домен $DOMAIN указывает на IP $(get_server_ip)"
        print_error "2. Порты 80 и 443 доступны извне"
        print_error "3. Нет блокировки фаерволом"
        exit 1
    fi

    # Настройка автообновления
    setup_certbot_renewal

    print_status "Автообновление SSL настроено ✅"
}

# Функция создания конфигурации nginx для ACME
create_nginx_acme_config() {
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
        try_files \$uri \$uri/ =404;
    }
}
EOF

    # Создание симлинка
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/ 2>/dev/null || true

    # Проверка конфигурации
    if ! nginx -t >/dev/null 2>&1; then
        print_error "Ошибка в конфигурации Nginx"
        nginx -t
        exit 1
    fi
}

# Функция настройки автообновления certbot
setup_certbot_renewal() {
    # Создание скрипта обновления
    cat > /etc/cron.d/certbot-renewal << 'EOF'
0 12 * * * root /usr/bin/certbot renew --quiet --post-hook "systemctl reload nginx"
EOF

    # Проверка что cron работает
    systemctl enable cron >/dev/null 2>&1 || systemctl enable crond >/dev/null 2>&1 || true
    systemctl start cron >/dev/null 2>&1 || systemctl start crond >/dev/null 2>&1 || true
}

# Функция установки 3X-UI
install_3x_ui() {
    print_header "УСТАНОВКА 3X-UI"
    save_install_state "installing_3x_ui"

    print_status "Установка 3X-UI..."

    # Попытка автоматической установки через оригинальный скрипт
    if install_3x_ui_automatic; then
        print_status "3X-UI установлен через автоматический скрипт ✅"
    else
        print_warning "Автоматическая установка не удалась, переходим к ручной установке"
        install_3x_ui_manual
    fi

    # Настройка 3X-UI
    configure_3x_ui

    print_status "3X-UI установлен и настроен ✅"
}

# Функция автоматической установки 3X-UI
install_3x_ui_automatic() {
    print_status "Попытка автоматической установки 3X-UI..."

    # Установка переменных окружения для автоматической настройки
    export INSTALL_PATH="/opt/3x-ui"
    export XUI_USERNAME="$XUI_USERNAME"
    export XUI_PASSWORD="$XUI_PASSWORD"
    export XUI_PORT="$XUI_PORT"

    # Скачивание и модификация скрипта для автоматической установки
    if curl -Ls "$XUI_INSTALL_SCRIPT" > /tmp/3x-ui-install.sh; then
        # Делаем скрипт исполняемым
        chmod +x /tmp/3x-ui-install.sh

        # Попытка установки в автоматическом режиме
        # Подавляем интерактивные запросы
        echo -e "y\n$XUI_USERNAME\n$XUI_PASSWORD\n$XUI_PORT\ny\n" | bash /tmp/3x-ui-install.sh 2>/dev/null

        # Проверка успешности установки
        if [ -f "/opt/3x-ui/x-ui" ] && [ -f "/etc/systemd/system/x-ui.service" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

# Функция ручной установки 3X-UI
install_3x_ui_manual() {
    print_status "Ручная установка 3X-UI..."

    cd /opt || exit 1

    # Получение последней версии
    local latest_version
    latest_version=$(get_latest_3xui_version)

    print_status "Скачивание 3X-UI $latest_version..."

    # Скачивание архива
    local download_url="https://github.com/MHSanaei/3x-ui/releases/download/$latest_version/x-ui-linux-${ARCH}.tar.gz"

    if ! download_with_retry "$download_url" "x-ui.tar.gz"; then
        print_error "Не удалось скачать 3X-UI"
        exit 1
    fi

    # Проверка целостности архива
    if ! tar -tzf x-ui.tar.gz >/dev/null 2>&1; then
        print_error "Поврежденный архив 3X-UI"
        exit 1
    fi

    # Извлечение
    tar -zxf x-ui.tar.gz
    rm x-ui.tar.gz

    # Переименование папки
    if [ -d "x-ui" ]; then
        mv x-ui 3x-ui
    fi

    cd 3x-ui || exit 1

    # Установка прав
    chmod +x x-ui

    # Создание systemd сервиса
    create_3xui_service

    systemctl daemon-reload
    systemctl enable x-ui >/dev/null 2>&1
}

# Функция получения последней версии 3X-UI
get_latest_3xui_version() {
    local version
    version=$(timeout 30 curl -s "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" 2>/dev/null | grep -oP '"tag_name": "\K[^"]*' | head -n1)

    if [ -z "$version" ]; then
        print_warning "Не удалось определить последнюю версию 3X-UI, используем фиксированную версию"
        version="v2.3.4"
    fi

    echo "$version"
}

# Функция создания systemd сервиса для 3X-UI
create_3xui_service() {
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
RestartPreventExitStatus=1
RestartSec=5s
KillMode=mixed
TimeoutStopSec=5s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=x-ui

# Безопасность
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/opt/3x-ui

[Install]
WantedBy=multi-user.target
EOF
}

# Функция скачивания с повторными попытками
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        print_debug "Попытка скачивания $attempt/$max_attempts: $url"

        if timeout 300 wget -q --show-progress --progress=bar:force:noscroll -O "$output" "$url"; then
            return 0
        fi

        print_warning "Попытка $attempt неудачна"
        rm -f "$output"
        attempt=$((attempt + 1))

        if [ $attempt -le $max_attempts ]; then
            sleep 5
        fi
    done

    return 1
}

# Функция настройки 3X-UI
configure_3x_ui() {
    print_status "Настройка 3X-UI..."

    # Запуск 3X-UI
    systemctl start x-ui

    # Ожидание запуска
    wait_for_service "x-ui" 30

    # Проверка статуса
    if systemctl is-active --quiet x-ui; then
        print_status "3X-UI запущен ✅"

        # Настройка через командную строку если возможно
        if [ -f "/opt/3x-ui/x-ui" ]; then
            # Установка настроек через x-ui команду
            /opt/3x-ui/x-ui setting -username "$XUI_USERNAME" -password "$XUI_PASSWORD" -port "$XUI_PORT" 2>/dev/null || true
            systemctl restart x-ui
        fi

        print_status "3X-UI настроен на порту $XUI_PORT"
    else
        print_error "Не удалось запустить 3X-UI"
        systemctl status x-ui
        journalctl -u x-ui --no-pager -n 20
        exit 1
    fi
}

# Функция ожидания запуска сервиса
wait_for_service() {
    local service_name="$1"
    local max_wait="${2:-30}"
    local wait_time=0

    print_status "Ожидание запуска $service_name..."

    while [ $wait_time -lt $max_wait ]; do
        if systemctl is-active --quiet "$service_name"; then
            return 0
        fi
        sleep 2
        wait_time=$((wait_time + 2))
        echo -n "."
    done

    echo ""
    return 1
}

# Функция установки AdGuard Home
install_adguard() {
    print_header "УСТАНОВКА ADGUARD HOME"
    save_install_state "installing_adguard"

    print_status "Скачивание и установка AdGuard Home..."

    # Остановка конфликтующих DNS сервисов
    systemctl stop systemd-resolved 2>/dev/null || true
    systemctl disable systemd-resolved 2>/dev/null || true

    # Создание директории
    mkdir -p /opt/AdGuardHome
    cd /opt/AdGuardHome

    # Скачивание AdGuard Home
    local download_url="https://static.adguard.com/adguardhome/release/AdGuardHome_linux_${ARCH}.tar.gz"
    print_status "Скачивание из: $download_url"

    if ! download_with_retry "$download_url" "AdGuardHome.tar.gz"; then
        print_error "Не удалось скачать AdGuard Home"
        exit 1
    fi

    # Извлечение архива
    if ! tar -zxf AdGuardHome.tar.gz; then
        print_error "Не удалось извлечь архив AdGuard"
        exit 1
    fi

    # Перемещение файлов
    if [ -d "AdGuardHome" ]; then
        mv AdGuardHome/* ./ 2>/dev/null || true
        rmdir AdGuardHome 2>/dev/null || true
    fi

    rm -f AdGuardHome.tar.gz

    # Установка прав
    chmod +x AdGuardHome

    # Создание пользователя (опционально)
    if ! id "adguard" &>/dev/null; then
        useradd -r -s /bin/false adguard 2>/dev/null || true
    fi

    # Создание systemd сервиса
    create_adguard_service

    # Создание начальной конфигурации
    create_adguard_initial_config

    # Установка прав на файлы
    chown -R root:root /opt/AdGuardHome
    chmod 644 /opt/AdGuardHome/AdGuardHome.yaml

    systemctl daemon-reload
    systemctl enable AdGuardHome

    print_status "AdGuard Home установлен ✅"
}

# Функция создания systemd сервиса для AdGuard
create_adguard_service() {
    cat > /etc/systemd/system/AdGuardHome.service << EOF
[Unit]
Description=AdGuard Home
After=network.target
Wants=network.target
StartLimitIntervalSec=5
StartLimitBurst=10

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/AdGuardHome
ExecStart=/opt/AdGuardHome/AdGuardHome --config /opt/AdGuardHome/AdGuardHome.yaml --work-dir /opt/AdGuardHome
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
TimeoutStopSec=10
KillMode=mixed
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/opt/AdGuardHome

[Install]
WantedBy=multi-user.target
EOF
}

# Функция создания начальной конфигурации AdGuard
create_adguard_initial_config() {
    print_status "Создание конфигурации AdGuard Home..."

    # Убеждаемся что директории существуют
    mkdir -p /opt/AdGuardHome/data
    mkdir -p /opt/AdGuardHome/work

    # Генерация bcrypt хеша пароля
    local password_hash
    if command -v htpasswd &> /dev/null; then
        password_hash=$(htpasswd -bnBC 12 "" "$ADGUARD_PASSWORD" | tr -d ':\n' | sed 's/^.*$//')
    else
        # Fallback к простому хешу
        password_hash="\$2a\$12\$$(echo -n "$ADGUARD_PASSWORD" | openssl passwd -apr1 -stdin | cut -d'$' -f4-)"
    fi

    cat > /opt/AdGuardHome/AdGuardHome.yaml << EOF
# AdGuard Home configuration file
# Generated by VPN Auto Installer v$SCRIPT_VERSION
# Date: $(date)

# Web interface settings
bind_host: 0.0.0.0
bind_port: $ADGUARD_PORT
beta_bind_port: 0

# Users and authentication
users:
  - name: admin
    password: $password_hash
auth_attempts: 5
block_auth_min: 15

# Web interface settings
http_proxy: ""
language: ru
theme: auto
debug_pprof: false
web_session_ttl: 720

# DNS server settings
dns:
  bind_hosts:
    - 0.0.0.0
  port: 53

  # Statistics and query logging
  statistics_interval: 90
  querylog_enabled: true
  querylog_file_enabled: true
  querylog_interval: 2160h
  querylog_size_memory: 1000
  anonymize_client_ip: false

  # Protection settings
  protection_enabled: true
  blocking_mode: default
  blocking_ipv4: ""
  blocking_ipv6: ""
  blocked_response_ttl: 10
  parental_block_host: family-block.dns.adguard.com
  safebrowsing_block_host: standard-block.dns.adguard.com

  # Rewrites and custom rules
  rewrites: []

  # Cache settings
  safebrowsing_cache_size: 1048576
  safesearch_cache_size: 1048576
  parental_cache_size: 1048576
  cache_size: 4194304
  cache_ttl_min: 0
  cache_ttl_max: 0
  cache_optimistic: false

  # DNSSEC and IPv6
  bogus_nxdomain: []
  aaaa_disabled: false
  enable_dnssec: false

  # EDNS Client Subnet
  edns_client_subnet:
    custom_ip: ""
    enabled: false
    use_custom: false

  # Performance settings
  max_goroutines: 300
  handle_ddr: true
  ipset: []
  ipset_file: ""

  # Upstream DNS servers
  bootstrap_dns:
    - 9.9.9.10
    - 149.112.112.10
    - 2620:fe::10
    - 2620:fe::fe:10
  all_servers: false
  fastest_addr: false
  fastest_timeout: 1s

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

  # Main upstream DNS servers
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

  # Private networks
  private_networks: []
  use_dns64: false
  dns64_prefixes: []
  serve_plain_dns: true

  # Features
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

# TLS settings (disabled by default)
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

# Default filter lists
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
  - enabled: true
    url: https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext
    name: Peter Lowe's List
    id: 4

# Whitelist filters
whitelist_filters: []

# Custom user rules
user_rules:
  - '@@||speedtest.net^'
  - '@@||fast.com^'
  - '@@||netflix.com^'
  - '@@||youtube.com^'

# DHCP settings (disabled by default)
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

# Client settings
clients:
  runtime_sources:
    whois: true
    arp: true
    rdns: true
    dhcp: true
    hosts: true
  persistent: []

# Logging settings
log_file: ""
log_max_backups: 0
log_max_size: 100
log_max_age: 3
log_compress: false
log_localtime: false
verbose: false

# OS settings
os:
  group: ""
  user: ""
  rlimit_nofile: 0

# Configuration schema version
schema_version: 20
EOF

    print_status "Конфигурация AdGuard создана"
}

# Функция настройки AdGuard Home
configure_adguard() {
    print_header "НАСТРОЙКА ADGUARD HOME"
    save_install_state "configuring_adguard"

    # Проверка что конфигурационный файл существует
    if [ ! -f "/opt/AdGuardHome/AdGuardHome.yaml" ]; then
        print_error "Конфигурационный файл AdGuard не найден"
        create_adguard_initial_config
    fi

    print_status "Запуск AdGuard Home..."

    # Освобождение порта 53 если занят
    if check_port_in_use "53"; then
        print_status "Освобождение порта 53..."
        systemctl stop systemd-resolved 2>/dev/null || true
        killall -9 dnsmasq 2>/dev/null || true

        # Изменение DNS в resolv.conf
        if [ -f /etc/resolv.conf ]; then
            cp /etc/resolv.conf /etc/resolv.conf.backup
            echo "nameserver 8.8.8.8" > /etc/resolv.conf
            echo "nameserver 1.1.1.1" >> /etc/resolv.conf
        fi
    fi

    # Запуск сервиса
    systemctl start AdGuardHome

    # Ожидание запуска с проверкой
    if wait_for_service "AdGuardHome" 30; then
        print_status "AdGuard Home запущен ✅"
        print_status "AdGuard Home работает на порту $ADGUARD_PORT"

        # Проверка доступности веб-интерфейса
        sleep 5
        if timeout 10 curl -s "http://localhost:$ADGUARD_PORT" > /dev/null; then
            print_status "Веб-интерфейс AdGuard доступен ✅"
        else
            print_warning "Веб-интерфейс может быть недоступен сразу"
        fi
    else
        print_error "AdGuard Home не запустился"
        systemctl status AdGuardHome
        journalctl -u AdGuardHome --no-pager -n 20
        diagnose_adguard
        exit 1
    fi
}

# Функция диагностики AdGuard
diagnose_adguard() {
    print_header "ДИАГНОСТИКА ADGUARD"

    # Проверка файлов
    print_status "Проверка файлов AdGuard:"
    ls -la /opt/AdGuardHome/ 2>/dev/null || print_error "Директория не найдена"

    # Проверка прав
    print_status "Права на файлы:"
    ls -la /opt/AdGuardHome/AdGuardHome* 2>/dev/null || print_error "Файлы не найдены"

    # Проверка портов
    print_status "Проверка портов:"
    netstat -tuln | grep -E ":($ADGUARD_PORT|53) " || print_status "Порты свободны"

    # Проверка процессов
    print_status "Проверка процессов:"
    ps aux | grep AdGuardHome | grep -v grep || print_status "Процесс не найден"

    # Попытка ручного запуска для диагностики
    print_status "Попытка ручного запуска..."
    cd /opt/AdGuardHome
    timeout 10 ./AdGuardHome --check-config || print_error "Ошибка в конфигурации"
}

# Функция финальной настройки Nginx
configure_nginx_final() {
    print_header "ФИНАЛЬНАЯ НАСТРОЙКА NGINX"
    save_install_state "configuring_nginx_final"

    # Создание основной конфигурации с SSL
    create_nginx_ssl_config

    # Создание главной страницы
    create_main_page

    # Проверка конфигурации nginx
    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx
        print_status "Nginx перезагружен ✅"
    else
        print_error "Ошибка в конфигурации Nginx"
        nginx -t
        exit 1
    fi

    # Проверка доступности
    sleep 5
    if ! systemctl is-active --quiet nginx; then
        print_error "Nginx не работает после перезагрузки"
        systemctl status nginx
        exit 1
    fi
}

# Функция создания SSL конфигурации Nginx
create_nginx_ssl_config() {
    cat > /etc/nginx/sites-available/default << EOF
# Безопасность: скрытие версии Nginx
server_tokens off;

# HTTP -> HTTPS редирект
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $DOMAIN;

    # ACME challenge для обновления сертификатов
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Редирект всего остального трафика на HTTPS
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

    # Современные SSL настройки
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_stapling on;
    ssl_stapling_verify on;

    # Заголовки безопасности
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Ограничение размера запроса
    client_max_body_size 10M;

    # Главная страница
    location / {
        root /var/www/html;
        index index.html index.htm;
        try_files \$uri \$uri/ =404;

        # Кеширование статики
        location ~* \.(css|js|jpg|jpeg|png|gif|ico|svg)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }

    # Логи
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
}
EOF

    # Включение сайта
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default 2>/dev/null || true
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

        .header p {
            font-size: 1.2rem;
            opacity: 0.9;
        }

        .content {
            padding: 40px;
        }

        .info-card {
            background: #f8f9fa;
            border: 1px solid #e9ecef;
            border-radius: 12px;
            padding: 25px;
            margin-bottom: 25px;
            border-left: 4px solid #28a745;
        }

        .info-card.warning {
            border-left-color: #ffc107;
            background: #fff3cd;
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
            display: flex;
            align-items: center;
        }

        .panel h3::before {
            content: '';
            width: 4px;
            height: 20px;
            background: #007bff;
            margin-right: 12px;
            border-radius: 2px;
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
            box-shadow: 0 2px 4px rgba(0,123,255,0.3);
        }

        .button:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(0,123,255,0.4);
            text-decoration: none;
            color: white;
        }

        .button.secondary {
            background: linear-gradient(135deg, #6c757d, #545b62);
            box-shadow: 0 2px 4px rgba(108,117,125,0.3);
        }

        .button.secondary:hover {
            box-shadow: 0 4px 8px rgba(108,117,125,0.4);
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
            border: 1px solid #e9ecef;
        }

        .stat-item .stat-value {
            font-size: 1.5rem;
            font-weight: 700;
            color: #007bff;
            margin-bottom: 5px;
        }

        .stat-item .stat-label {
            color: #6c757d;
            font-size: 0.9rem;
        }

        .code {
            background: #f8f9fa;
            border: 1px solid #e9ecef;
            border-radius: 6px;
            padding: 8px 12px;
            font-family: 'Monaco', 'Menlo', monospace;
            font-size: 0.9rem;
            color: #e83e8c;
            display: inline-block;
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
            .header h1 {
                font-size: 2rem;
            }

            .content {
                padding: 20px;
            }

            .button {
                display: block;
                text-align: center;
                margin: 10px 0;
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
                <p>Прямой доступ к интерфейсам управления сервисами:</p>
                <a href="https://$DOMAIN:$XUI_PORT" class="button" target="_blank">3X-UI Panel</a>
                <a href="http://$DOMAIN:$ADGUARD_PORT" class="button secondary" target="_blank">AdGuard Home</a>
                <div style="margin-top: 15px; padding: 10px; background: #e9ecef; border-radius: 6px;">
                    <small><strong>Логин для обеих панелей:</strong> admin<br>
                    <strong>Пароли:</strong> указаны в файле инструкций на сервере</small>
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
                <h3>📱 Настройка VPN подключения</h3>
                <p>Пошаговая инструкция для настройки VPN:</p>
                <ol style="margin: 15px 0 15px 20px;">
                    <li>Откройте панель <strong>3X-UI</strong> по ссылке выше</li>
                    <li>Войдите используя логин "admin" и пароль из инструкций</li>
                    <li>Создайте нового пользователя с протоколом VLESS</li>
                    <li>Настройте TLS и укажите ваш домен: <strong>$DOMAIN</strong></li>
                    <li>Скачайте конфигурацию или отсканируйте QR-код</li>
                    <li>Импортируйте в ваш VPN клиент</li>
                </ol>

                <div class="info-card warning">
                    <h5>📱 Рекомендуемые клиенты:</h5>
                    <p><strong>Android:</strong> v2rayNG, Clash for Android</p>
                    <p><strong>iOS:</strong> Shadowrocket, Quantumult X</p>
                    <p><strong>Windows:</strong> v2rayN, Clash for Windows</p>
                    <p><strong>macOS:</strong> ClashX, V2rayU</p>
                    <p><strong>Linux:</strong> v2ray, Clash</p>
                </div>
            </div>

            <div class="panel">
                <h3>🛡️ DNS с блокировкой рекламы</h3>
                <p>Настройте DNS сервер для автоматической блокировки рекламы:</p>
                <div style="margin: 15px 0;">
                    <p><strong>DNS сервер:</strong> <span class="code">$server_ip</span> или <span class="code">$DOMAIN</span></p>
                    <p><strong>Порт:</strong> <span class="code">53</span></p>
                </div>
                <p>Настройте этот DNS в параметрах вашей сети или устройства для блокировки рекламы на всех устройствах.</p>
            </div>

            <div class="panel">
                <h3>⚙️ Системная информация</h3>
                <p><strong>Операционная система:</strong> $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2 2>/dev/null || echo "Unknown")</p>
                <p><strong>Версия скрипта:</strong> $SCRIPT_VERSION</p>
                <p><strong>Архитектура:</strong> $(uname -m)</p>
                <p><strong>Логи установки:</strong> <span class="code">$LOG_FILE</span></p>
                <p><strong>Инструкции:</strong> <span class="code">/root/vpn-server-info.txt</span></p>
            </div>

            <div class="info-card warning">
                <h4>🔐 Важные замечания по безопасности</h4>
                <ul style="margin: 10px 0 10px 20px;">
                    <li>Обязательно сохраните пароли от панелей управления</li>
                    <li>Регулярно обновляйте операционную систему</li>
                    <li>Меняйте пароли каждые 3-6 месяцев</li>
                    <li>Мониторьте логи на предмет подозрительной активности</li>
                    <li>Делайте резервные копии конфигураций</li>
                </ul>
            </div>
        </div>

        <div class="footer">
            <p>🚀 Powered by <strong>VPN Auto Installer v$SCRIPT_VERSION</strong></p>
            <p>Создано с ❤️ для обеспечения вашей безопасности в интернете</p>
        </div>
    </div>

    <script>
        // Простая проверка доступности панелей
        document.addEventListener('DOMContentLoaded', function() {
            console.log('VPN Server Dashboard loaded successfully');

            // Проверка доступности 3X-UI
            fetch('https://$DOMAIN:$XUI_PORT/', {mode: 'no-cors'})
                .catch(() => console.log('3X-UI panel check completed'));

            // Проверка доступности AdGuard
            fetch('http://$DOMAIN:$ADGUARD_PORT/', {mode: 'no-cors'})
                .catch(() => console.log('AdGuard panel check completed'));
        });
    </script>
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

🌐 Веб-интерфейс: https://$DOMAIN

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
║                      НАСТРОЙКА КЛИЕНТОВ                      ║
╚═══════════════════════════════════════════════════════════════╝

1. Откройте 3X-UI панель: https://$DOMAIN:$XUI_PORT
2. Войдите используя логин "$XUI_USERNAME" и пароль выше
3. Создайте нового пользователя VLESS
4. Настройте TLS и укажите домен: $DOMAIN
5. Используйте порт: $VLESS_PORT
6. Скачайте конфигурацию или QR-код
7. Импортируйте в ваш VPN клиент

Рекомендуемые клиенты:
- Android: v2rayNG, Clash for Android
- iOS: Shadowrocket, Quantumult X
- Windows: v2rayN, Clash for Windows
- macOS: ClashX, V2rayU
- Linux: v2ray, Clash

╔═══════════════════════════════════════════════════════════════╗
║                      DNS ФИЛЬТРАЦИЯ                          ║
╚═══════════════════════════════════════════════════════════════╝

DNS сервер: $server_ip или $DOMAIN
Порт: 53

Настройте этот DNS в параметрах сети вашего устройства
для автоматической блокировки рекламы и вредоносных сайтов.

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

Остановка/запуск:
systemctl stop x-ui && systemctl start x-ui
systemctl stop AdGuardHome && systemctl start AdGuardHome

╔═══════════════════════════════════════════════════════════════╗
║                        БЕЗОПАСНОСТЬ                          ║
╚═══════════════════════════════════════════════════════════════╝

✅ SSL сертификат установлен и настроено автообновление
✅ Firewall настроен (разрешены только нужные порты)  
✅ Все сервисы работают с безопасными конфигурациями
✅ Настроены заголовки безопасности для веб-интерфейса

Рекомендации по безопасности:
- Регулярно обновляйте систему: apt update && apt upgrade
- Меняйте пароли панелей каждые 3-6 месяцев  
- Мониторьте логи на предмет подозрительной активности
- Делайте резервные копии конфигураций:
  cp -r /opt/3x-ui /backup/3x-ui-$(date +%Y%m%d)
  cp -r /opt/AdGuardHome /backup/adguard-$(date +%Y%m%d)

╔═══════════════════════════════════════════════════════════════╗
║                       УСТРАНЕНИЕ ПРОБЛЕМ                     ║
╚═══════════════════════════════════════════════════════════════╝

Если панели недоступны:

1. Проверка статуса сервисов:
   systemctl status x-ui AdGuardHome nginx

2. Проверка портов:
   netstat -tuln | grep -E ":(54321|3000|443|80)"

3. Проверка firewall:
   ufw status

4. Перезапуск всех сервисов:
   systemctl restart x-ui AdGuardHome nginx

5. Проверка логов:
   tail -f /var/log/vpn-installer.log

╔═══════════════════════════════════════════════════════════════╗
║                         ПОДДЕРЖКА                            ║
╚═══════════════════════════════════════════════════════════════╝

Версия скрипта: $SCRIPT_VERSION
Логи установки: $LOG_FILE
GitHub: $REPO_URL

СОХРАНИТЕ ЭТОТ ФАЙЛ В БЕЗОПАСНОМ МЕСТЕ!
Особенно важно сохранить пароли от панелей управления.

EOF

    # Защита файла с паролями
    chmod 600 "$instructions_file"
    chown root:root "$instructions_file"

    print_status "Инструкции созданы: $instructions_file"
}

# Функция показа финальной информации
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
    print_status "📋 Подробные инструкции: /root/vpn-server-info.txt"
    print_status "📝 Логи установки: $LOG_FILE"
    echo ""
    print_status "Перейдите на https://$DOMAIN для начала работы"
    echo ""
}

# Функция очистки временных файлов
cleanup() {
    print_header "ОЧИСТКА"

    # Удаление временных файлов
    rm -f "$INSTALL_STATE_FILE"
    rm -f /tmp/3x-ui-install.sh
    rm -f /tmp/x-ui.tar.gz
    rm -f /tmp/AdGuardHome.tar.gz

    # Очистка кеша пакетов
    if command -v apt-get &> /dev/null; then
        apt-get autoremove -y >/dev/null 2>&1 || true
        apt-get autoclean >/dev/null 2>&1 || true
    elif command -v yum &> /dev/null; then
        yum autoremove -y >/dev/null 2>&1 || true
        yum clean all >/dev/null 2>&1 || true
    elif command -v dnf &> /dev/null; then
        dnf autoremove -y >/dev/null 2>&1 || true
        dnf clean all >/dev/null 2>&1 || true
    fi

    # Очистка логов установки (оставляем только последние записи)
    if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 1000 ]; then
        tail -n 500 "$LOG_FILE" > "$LOG_FILE.tmp"
        mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi

    print_status "Временные файлы удалены ✅"
}

# Основная функция с обработкой resume
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
                update_system
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
            "updating_system")
                print_status "Продолжаем с настройки firewall..."
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
            "configuring_firewall")
                print_status "Продолжаем с установки Nginx..."
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

    # Полная установка с начала
    check_root
    check_dependencies  
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
    install_adguard
    configure_adguard
    configure_nginx_final
    create_instructions
    show_final_info
    cleanup

    print_status "🎉 Все операции завершены успешно!"
}

# Запуск основной функции с передачей всех аргументов
main "$@"
