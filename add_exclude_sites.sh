#!/bin/bash

########################################
# Скрипт для добавления сайтов исключений (whitelist)
# Проверка/установка зависимостей (dig, iptables)
# Добавление iptables-правил для обхода VPN
########################################

########################################
# 1. Определение менеджера пакетов
########################################
detect_package_manager() {
  if command -v apt-get &>/dev/null; then
    echo "apt-get"
  elif command -v yum &>/dev/null; then
    echo "yum"
  elif command -v dnf &>/dev/null; then
    echo "dnf"
  elif command -v pacman &>/dev/null; then
    echo "pacman"
  else
    echo "unknown"
  fi
}

########################################
# 2. Установка необходимых пакетов
########################################
install_packages() {
  local packages=("$@")
  local pkg_manager
  pkg_manager=$(detect_package_manager)

  case "$pkg_manager" in
    apt-get)
      apt-get update -y
      apt-get install -y "${packages[@]}"
      ;;
    yum)
      yum install -y "${packages[@]}"
      ;;
    dnf)
      dnf install -y "${packages[@]}"
      ;;
    pacman)
      pacman -Sy --noconfirm "${packages[@]}"
      ;;
    *)
      echo "Не удалось определить менеджер пакетов. Установите вручную: ${packages[*]}"
      exit 1
      ;;
  esac
}

########################################
# 3. Проверка прав root
########################################
if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите этот скрипт с правами root!"
  exit 1
fi

########################################
# 4. Проверка/установка dig
########################################
if ! command -v dig &>/dev/null; then
  echo "Утилита 'dig' не найдена. Устанавливаем..."
  # dnsutils – для Debian/Ubuntu
  # bind-utils – для CentOS/Fedora
  install_packages dnsutils bind-utils
fi

########################################
# 5. Проверка/установка iptables
########################################
if ! command -v iptables &>/dev/null; then
  echo "Утилита 'iptables' не найдена. Устанавливаем..."
  install_packages iptables
fi

########################################
# 6. Основная логика
########################################

# Файл со списком доменов
WHITELIST_FILE="whitelist"

# Если список не найден, создаём пример
if [ ! -f "$WHITELIST_FILE" ]; then
  echo "example.com" > "$WHITELIST_FILE"
  echo "test.local" >> "$WHITELIST_FILE"
  echo "Файл $WHITELIST_FILE не найден, создан пример."
fi

# Массив для доменов
declare -a WHITELIST

# Читаем домены из файла
while IFS= read -r line; do
  line="$(echo "$line" | xargs)"   # убираем лишние пробелы
  [ -n "$line" ] && WHITELIST+=("$line")
done < "$WHITELIST_FILE"

# Предлагаем пользователю добавить новые домены вручную
echo
read -p "Хотите добавить новые сайты (через запятую)? (Enter, если нет): " USER_SITES
if [ -n "$USER_SITES" ]; then
  IFS=',' read -ra NEW_SITES <<< "$(echo "$USER_SITES" | sed 's/[[:space:]]//g')"
  for site in "${NEW_SITES[@]}"; do
    [ -n "$site" ] && WHITELIST+=("$site")
  done
fi

# Если нет доменов, выходим
if [ ${#WHITELIST[@]} -eq 0 ]; then
  echo "Нет доменов для исключения. Выходим."
  exit 0
fi

echo
echo "Добавляем в whitelist следующие сайты:"
for site in "${WHITELIST[@]}"; do
  echo " - $site"
done
echo

# Обрабатываем каждый домен
for site in "${WHITELIST[@]}"; do
  # Получаем список IP-адресов
  IP_LIST=$(dig +short "$site" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
  if [ -z "$IP_LIST" ]; then
    echo "Не удалось получить IP для $site. Пропуск..."
    continue
  fi

  while IFS= read -r ipaddr; do
    echo "Добавляем iptables-правило для $site ($ipaddr)"
    # Разрешаем прямой выход без VPN (в таблице NAT)
    iptables -t nat -A POSTROUTING -d "$ipaddr" -j ACCEPT
    # Отмечаем пакеты в таблице mangle
    iptables -t mangle -A PREROUTING -d "$ipaddr" -j ACCEPT
  done <<< "$IP_LIST"
done

# Сохраняем правила (если iptables-persistent установлен)
if [ -f /etc/iptables/rules.v4 ]; then
  iptables-save > /etc/iptables/rules.v4
  echo "Правила iptables сохранены в /etc/iptables/rules.v4."
else
  echo "Файл /etc/iptables/rules.v4 не найден. Создаём..."
  iptables-save > /etc/iptables/rules.v4
fi

# Перезаписываем файл whitelist (на случай новых доменов)
{
  for site in "${WHITELIST[@]}"; do
    echo "$site"
  done
} > "$WHITELIST_FILE"

echo "Список доменов обновлён в $WHITELIST_FILE."
echo "Скрипт завершён."
