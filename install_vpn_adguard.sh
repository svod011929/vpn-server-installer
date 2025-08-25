#!/bin/bash

# install_vless_adguard.sh
# Скрипт автоматической установки VPN-сервера с VLESS + TLS + 3X-UI + AdGuard Home
# Автор: KodoDrive
# Версия: 1.0

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для вывода цветного текста
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}================================${NC}"
}

# Функция проверки root прав
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен запускаться с правами root!"
        exit 1
    fi
}

# Функция получения пользовательского ввода
get_user_input() {
    print_header "НАСТРОЙКА ПАРАМЕТРОВ"

    # Домен
    while true; do
        read -p "Введите ваш домен (например, vpn.example.com): " DOMAIN
        if [[ $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            print_error "Неверный формат домена. Попробуйте снова."
        fi
    done

    # Email для SSL
    while true; do
        read -p "Введите email для SSL сертификата: " EMAIL
        if [[ $EMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            print_error "Неверный формат email. Попробуйте снова."
        fi
    done

    # Пароль для 3X-UI
    read -p "Введите пароль для панели 3X-UI (оставьте пустым для генерации): " XUI_PASSWORD
    if [ -z "$XUI_PASSWORD" ]; then
        XUI_PASSWORD=$(openssl rand -base64 12)
        print_status "Сгенерирован пароль для 3X-UI: $XUI_PASSWORD"
    fi

    # Пароль для AdGuard
    read -p "Введите пароль для AdGuard Home (оставьте пустым для генерации): " ADGUARD_PASSWORD
    if [ -z "$ADGUARD_PASSWORD" ]; then
        ADGUARD_PASSWORD=$(openssl rand -base64 12)
        print_status "Сгенерирован пароль для AdGuard: $ADGUARD_PASSWORD"
    fi

    # Порт для VLESS
    read -p "Введите порт для VLESS (по умолчанию 443): " VLESS_PORT
    VLESS_PORT=${VLESS_PORT:-443}

    print_status "Настройки приняты. Начинаем установку..."
    sleep 2
}

# Функция обновления системы
update_system() {
    print_header "ОБНОВЛЕНИЕ СИСТЕМЫ"
    apt update && apt upgrade -y
    print_status "Система обновлена"
}

# Функция установки базовых пакетов
install_base_packages() {
    print_header "УСТАНОВКА БАЗОВЫХ ПАКЕТОВ"
    apt install -y curl wget unzip certbot nginx ufw htop nano net-tools
    print_status "Базовые пакеты установлены"
}

# Функция установки Docker
install_docker() {
    print_header "УСТАНОВКА DOCKER"
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        print_status "Docker установлен"
    else
        print_status "Docker уже установлен"
    fi

    # Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        print_status "Docker Compose установлен"
    fi
}

# Функция получения SSL сертификата
get_ssl_certificate() {
    print_header "ПОЛУЧЕНИЕ SSL СЕРТИФИКАТА"

    # Останавливаем nginx если запущен
    systemctl stop nginx 2>/dev/null || true

    # Получаем сертификат
    certbot certonly --standalone -d $DOMAIN --agree-tos --no-eff-email --email $EMAIL --non-interactive

    if [ $? -eq 0 ]; then
        print_status "SSL сертификат получен успешно"

        # Настраиваем автообновление
        echo "0 12 * * * /usr/bin/certbot renew --quiet --deploy-hook 'systemctl reload nginx'" | crontab -
        print_status "Автообновление SSL настроено"
    else
        print_error "Ошибка получения SSL сертификата"
        exit 1
    fi
}

# Функция установки AdGuard Home
install_adguard() {
    print_header "УСТАНОВКА ADGUARD HOME"

    # Создаем директорию
    mkdir -p /opt/adguard
    cd /opt

    # Скачиваем AdGuard Home
    ADGUARD_VERSION=$(curl -s https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    wget -O AdGuardHome.tar.gz https://github.com/AdguardTeam/AdGuardHome/releases/download/$ADGUARD_VERSION/AdGuardHome_linux_amd64.tar.gz
    tar xzf AdGuardHome.tar.gz
    rm AdGuardHome.tar.gz

    # Генерируем хеш пароля
    ADGUARD_HASH=$(htpasswd -bnBC 10 "" $ADGUARD_PASSWORD | tr -d ':\n' | sed 's/^[^$]*$//')

    # Создаем конфигурацию
    cat > /opt/AdGuardHome/AdGuardHome.yaml << EOF
http:
  pprof:
    port: 6060
    enabled: false
  address: 127.0.0.1:3000
  session_ttl: 720h
users:
  - name: admin
    password: $ADGUARD_HASH
web_session_ttl: 720h
dns:
  bind_hosts:
    - 127.0.0.1
    - 0.0.0.0
  port: 53
  https_port: 0
  tls_port: 0
  quic_port: 0
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
  ratelimit: 20
  ratelimit_whitelist: []
  refuse_any: true
  upstream_dns:
    - https://dns10.quad9.net/dns-query
    - https://dns.cloudflare.com/dns-query
    - tls://dns.google:853
  upstream_dns_file: ""
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
  filtering:
    protection_enabled: true
    filtering_enabled: true
    parental_enabled: false
    safebrowsing_enabled: false
  filters:
    - enabled: true
      url: https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
      name: AdGuard DNS filter
      id: 1
    - enabled: true
      url: https://adaway.org/hosts.txt
      name: AdAway Default Blocklist
      id: 2
    - enabled: true
      url: https://someonewhocares.org/hosts/zero/hosts
      name: Dan Pollock's List
      id: 3
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
schema_version: 28
EOF

    # Создаем службу systemd
    cat > /etc/systemd/system/adguardhome.service << EOF
[Unit]
Description=AdGuard Home
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/AdGuardHome/AdGuardHome -c /opt/AdGuardHome/AdGuardHome.yaml -w /opt/AdGuardHome
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Запускаем службу
    systemctl daemon-reload
    systemctl enable adguardhome
    systemctl start adguardhome

    print_status "AdGuard Home установлен и запущен"
}

# Функция установки 3X-UI
install_3xui() {
    print_header "УСТАНОВКА 3X-UI"

    # Скачиваем и устанавливаем 3X-UI
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) << EOF
y
admin
$XUI_PASSWORD
2053
/xui/
EOF

    print_status "3X-UI установлен"
}

# Функция настройки Nginx
configure_nginx() {
    print_header "НАСТРОЙКА NGINX"

    # Удаляем дефолтный сайт
    rm -f /etc/nginx/sites-enabled/default

    # Создаем конфигурацию для домена
    cat > /etc/nginx/sites-available/$DOMAIN << EOF
# Перенаправление HTTP на HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

# HTTPS конфигурация
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    # SSL настройки
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1h;
    ssl_session_tickets off;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;

    # Основная страница
    location / {
        return 200 'Welcome to VPN Server';
        add_header Content-Type text/plain;
    }

    # 3X-UI панель
    location ^~ /xui/ {
        proxy_pass http://127.0.0.1:2053;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # AdGuard панель
    location ^~ /adguard/ {
        proxy_pass http://127.0.0.1:3000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Блокировка доступа к служебным файлам
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF

    # Активируем конфигурацию
    ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

    # Проверяем конфигурацию
    nginx -t
    if [ $? -eq 0 ]; then
        systemctl reload nginx
        print_status "Nginx настроен и перезапущен"
    else
        print_error "Ошибка в конфигурации Nginx"
        exit 1
    fi
}

# Функция настройки файрвола
configure_firewall() {
    print_header "НАСТРОЙКА ФАЙРВОЛА"

    # Настройка UFW
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing

    # Разрешаем необходимые порты
    ufw allow 22/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    ufw allow $VLESS_PORT/tcp comment 'VLESS'
    ufw allow 53 comment 'DNS'

    # Включаем файрвол
    ufw --force enable

    print_status "Файрвол настроен"
}

# Функция создания VLESS конфигурации для 3X-UI
create_vless_config() {
    print_header "НАСТРОЙКА VLESS В 3X-UI"

    # Создаем UUID для клиента
    UUID=$(cat /proc/sys/kernel/random/uuid)

    # Создаем конфигурацию inbound для 3X-UI через API
    sleep 5 # Ждем запуска 3X-UI

    # Получаем cookie для аутентификации
    COOKIE=$(curl -s -c /tmp/3xui_cookies.txt -X POST "http://127.0.0.1:2053/xui/login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin&password=$XUI_PASSWORD" | grep -o 'success":true' || echo "")

    if [[ $COOKIE == *"success"* ]]; then
        # Создаем inbound через API
        curl -s -b /tmp/3xui_cookies.txt -X POST "http://127.0.0.1:2053/xui/inbound/add" \
            -H "Content-Type: application/json" \
            -d '{
                "enable": true,
                "port": '$VLESS_PORT',
                "protocol": "vless",
                "settings": "{\"clients\":[{\"id\":\"'$UUID'\",\"flow\":\"\"}],\"decryption\":\"none\",\"fallbacks\":[]}",
                "streamSettings": "{\"network\":\"tcp\",\"security\":\"tls\",\"tlsSettings\":{\"serverName\":\"'$DOMAIN'\",\"certificates\":[{\"certificateFile\":\"/etc/letsencrypt/live/'$DOMAIN'/fullchain.pem\",\"keyFile\":\"/etc/letsencrypt/live/'$DOMAIN'/privkey.pem\"}]}}",
                "sniffing": "{\"enabled\":true,\"destOverride\":[\"http\",\"tls\"]}",
                "remark": "VLESS-TLS-'$DOMAIN'"
            }' > /dev/null

        print_status "VLESS inbound создан с UUID: $UUID"
    else
        print_warning "Не удалось автоматически создать VLESS inbound. Настройте вручную через веб-интерфейс."
    fi

    # Удаляем временные файлы
    rm -f /tmp/3xui_cookies.txt
}

# Функция создания информационного файла
create_info_file() {
    print_header "СОЗДАНИЕ ИНФОРМАЦИОННОГО ФАЙЛА"

    cat > /root/vpn_server_info.txt << EOF
==============================================
    VPN SERVER INSTALLATION COMPLETE
==============================================

Домен: $DOMAIN
Дата установки: $(date)

ДОСТУПЫ К ПАНЕЛЯМ:
==================
3X-UI Panel: https://$DOMAIN/xui/
  Пользователь: admin
  Пароль: $XUI_PASSWORD

AdGuard Home: https://$DOMAIN/adguard/
  Пользователь: admin
  Пароль: $ADGUARD_PASSWORD

НАСТРОЙКИ VLESS:
================
Адрес: $DOMAIN
Порт: $VLESS_PORT
UUID: $UUID
Encryption: none
Network: tcp
Security: tls
SNI: $DOMAIN

DNS СЕРВЕР:
===========
IP сервера: $(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
DNS порт: 53

УПРАВЛЕНИЕ СЛУЖБАМИ:
====================
systemctl status adguardhome
systemctl status x-ui  
systemctl status nginx

systemctl restart adguardhome
systemctl restart x-ui
systemctl restart nginx

ОБНОВЛЕНИЕ SSL:
===============
certbot renew --dry-run

ФАЙРВОЛ:
========
ufw status
ufw allow [port]

ЛОГИ:
=====
journalctl -u adguardhome -f
journalctl -u x-ui -f
tail -f /var/log/nginx/access.log

==============================================
ВАЖНО: Сохраните этот файл в надежном месте!
==============================================
EOF

    print_status "Информационный файл создан: /root/vpn_server_info.txt"
}

# Функция проверки статуса служб
check_services() {
    print_header "ПРОВЕРКА СТАТУСА СЛУЖБ"

    services=("nginx" "adguardhome" "x-ui")

    for service in "${services[@]}"; do
        if systemctl is-active --quiet $service; then
            print_status "$service: ✅ Работает"
        else
            print_error "$service: ❌ Не работает"
        fi
    done

    # Проверка портов
    print_status "Проверка портов:"
    netstat -tlnp | grep -E ":53 |:80 |:443 |:2053 |:3000 " | while read line; do
        echo "  $line"
    done
}

# Функция финального отчета
final_report() {
    print_header "УСТАНОВКА ЗАВЕРШЕНА"

    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

    echo ""
    echo -e "${GREEN}🎉 VPN сервер успешно установлен и настроен!${NC}"
    echo ""
    echo -e "${BLUE}📋 ИНФОРМАЦИЯ ДЛЯ ПОДКЛЮЧЕНИЯ:${NC}"
    echo -e "   Домен: ${YELLOW}$DOMAIN${NC}"
    echo -e "   IP адрес: ${YELLOW}$SERVER_IP${NC}"
    echo ""
    echo -e "${BLUE}🌐 ПАНЕЛИ УПРАВЛЕНИЯ:${NC}"
    echo -e "   3X-UI: ${YELLOW}https://$DOMAIN/xui/${NC}"
    echo -e "   Логин: ${YELLOW}admin${NC} | Пароль: ${YELLOW}$XUI_PASSWORD${NC}"
    echo ""
    echo -e "   AdGuard: ${YELLOW}https://$DOMAIN/adguard/${NC}"
    echo -e "   Логин: ${YELLOW}admin${NC} | Пароль: ${YELLOW}$ADGUARD_PASSWORD${NC}"
    echo ""
    echo -e "${BLUE}📱 НАСТРОЙКИ КЛИЕНТА:${NC}"
    echo -e "   Протокол: VLESS"
    echo -e "   Адрес: $DOMAIN"
    echo -e "   Порт: $VLESS_PORT"
    echo -e "   UUID: $UUID"
    echo -e "   Encryption: none"
    echo -e "   Network: tcp"
    echo -e "   Security: tls"
    echo -e "   DNS: $SERVER_IP:53"
    echo ""
    echo -e "${BLUE}📄 Подробная информация сохранена в:${NC}"
    echo -e "   ${YELLOW}/root/vpn_server_info.txt${NC}"
    echo ""
    echo -e "${GREEN}Enjoy your VPN server! 🚀${NC}"
}

# Основная функция
main() {
    clear
    print_header "VPN SERVER AUTO INSTALLER"
    echo -e "${BLUE}Автоматическая установка VLESS + TLS + 3X-UI + AdGuard Home${NC}"
    echo -e "${BLUE}Автор: KodoDrive${NC}"
    echo ""

    # Проверки
    check_root

    # Пользовательский ввод
    get_user_input

    # Установка
    update_system
    install_base_packages
    install_docker
    get_ssl_certificate
    install_adguard
    install_3xui
    configure_nginx
    configure_firewall
    create_vless_config
    create_info_file
    check_services
    final_report

    print_status "Все операции завершены успешно!"
}

# Запуск основной функции
main "$@"
