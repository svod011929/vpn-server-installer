#!/bin/bash

# install_vless_adguard.sh
# Скрипт автоматической установки VPN-сервера с VLESS + TLS + 3X-UI + AdGuard Home
# Автор: KodoDrive
# Версия: 1.0
# Установка: bash <(curl -fsSL https://raw.githubusercontent.com/kododrive/vpn-server-installer/main/install_vless_adguard.sh)

set -e

# Версия скрипта
SCRIPT_VERSION="1.0.0"
SCRIPT_URL="https://raw.githubusercontent.com/kododrive/vpn-server-installer/main/install_vless_adguard.sh"
REPO_URL="https://github.com/kododrive/vpn-server-installer"

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
AUTO_PASSWORD=false
AUTO_CONFIRM=false
DEBUG_MODE=false

# Функции для вывода цветного текста
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1"
    fi
}

print_header() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} $(printf "%-36s" "$1") ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
}

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

  # Установка с пользовательскими паролями
  bash <(curl -fsSL ${SCRIPT_URL}) \\
    --domain "vpn.example.com" \\
    --email "admin@example.com" \\
    --xui-password "secure123" \\
    --adguard-password "secure456"

ПОДДЕРЖКА:
  GitHub: ${REPO_URL}
  Issues: ${REPO_URL}/issues
  Email: support@kododrive.com

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

# Функция проверки системы
check_system() {
    print_header "ПРОВЕРКА СИСТЕМЫ"

    # Проверка ОС
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        print_status "ОС: $OS $VER"
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

    if [ $RAM_MB -lt 1024 ]; then
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

    if [ $DISK_GB -lt 5 ]; then
        print_error "Недостаточно свободного места. Требуется минимум 5GB"
        exit 1
    fi

    # Проверка интернета
    if ! curl -s --max-time 10 https://google.com > /dev/null; then
        print_error "Нет подключения к интернету"
        exit 1
    fi
    print_status "Интернет подключение: ✅"
}

# Остальные функции остаются такими же, но добавим в конец:

# Функция получения пользовательского ввода с поддержкой параметров
get_user_input() {
    print_header "НАСТРОЙКА ПАРАМЕТРОВ"

    # Домен
    if [ -z "$DOMAIN" ]; then
        while true; do
            read -p "Введите ваш домен (например, vpn.example.com): " DOMAIN
            if [[ $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
                break
            else
                print_error "Неверный формат домена. Попробуйте снова."
            fi
        done
    else
        print_status "Домен: $DOMAIN"
    fi

    # Email для SSL
    if [ -z "$EMAIL" ]; then
        while true; do
            read -p "Введите email для SSL сертификата: " EMAIL
            if [[ $EMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                break
            else
                print_error "Неверный формат email. Попробуйте снова."
            fi
        done
    else
        print_status "Email: $EMAIL"
    fi

    # Пароль для 3X-UI
    if [ -z "$XUI_PASSWORD" ]; then
        if [ "$AUTO_PASSWORD" = true ]; then
            XUI_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-12)
            print_status "Сгенерирован пароль для 3X-UI: $XUI_PASSWORD"
        else
            read -p "Введите пароль для панели 3X-UI (оставьте пустым для генерации): " XUI_PASSWORD
            if [ -z "$XUI_PASSWORD" ]; then
                XUI_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-12)
                print_status "Сгенерирован пароль для 3X-UI: $XUI_PASSWORD"
            fi
        fi
    else
        print_status "Пароль 3X-UI: [установлен]"
    fi

    # Пароль для AdGuard
    if [ -z "$ADGUARD_PASSWORD" ]; then
        if [ "$AUTO_PASSWORD" = true ]; then
            ADGUARD_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-12)
            print_status "Сгенерирован пароль для AdGuard: $ADGUARD_PASSWORD"
        else
            read -p "Введите пароль для AdGuard Home (оставьте пустым для генерации): " ADGUARD_PASSWORD
            if [ -z "$ADGUARD_PASSWORD" ]; then
                ADGUARD_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-12)
                print_status "Сгенерирован пароль для AdGuard: $ADGUARD_PASSWORD"
            fi
        fi
    else
        print_status "Пароль AdGuard: [установлен]"
    fi

    # Порт для VLESS
    if [ -z "$VLESS_PORT" ]; then
        VLESS_PORT="443"
    fi
    print_status "Порт VLESS: $VLESS_PORT"

    # Финальное подтверждение
    if [ "$AUTO_CONFIRM" != true ]; then
        echo ""
        print_warning "Проверьте настройки:"
        echo "  Домен: $DOMAIN"
        echo "  Email: $EMAIL"  
        echo "  Порт VLESS: $VLESS_PORT"
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
    sleep 2
}

# Добавим в основную функцию:

# Основная функция
main() {
    # Парсинг аргументов
    parse_args "$@"

    # Показ баннера
    show_banner

    # Проверки
    check_root
    check_system

    # Пользовательский ввод
    get_user_input

    # Остальные функции установки...
    # (все остальные функции остаются такими же)

    print_status "Все операции завершены успешно!"
}

# Запуск основной функции с передачей всех аргументов
main "$@"
