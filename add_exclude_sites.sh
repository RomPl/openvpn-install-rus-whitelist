#!/bin/bash

########################################
# Скрипт для добавления исключений сайтов (whitelist)
# Автоматически устанавливает iptables-persistent
# Сохраняет правила iptables и обрабатывает список сайтов
########################################

########################################
# Проверка прав root
########################################
if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите этот скрипт с правами root!"
  exit 1
fi

########################################
# Проверка/установка iptables-persistent
########################################
if ! dpkg -l | grep -qw iptables-persistent; then
  echo "iptables-persistent не установлен. Устанавливаем..."
  apt-get update -y && apt-get install -y iptables-persistent
  if [ $? -eq 0 ]; then
    echo "iptables-persistent успешно установлен."
  else
    echo "Ошибка установки iptables-persistent. Завершение скрипта."
    exit 1
  fi
else
  echo "iptables-persistent уже установлен."
fi

########################################
# Проверка наличия утилит dig и iptables
########################################
if ! command -v dig &>/dev/null; then
  echo "Утилита 'dig' не найдена. Устанавливаем..."
  apt-get install -y dnsutils
fi

if ! command -v iptables &>/dev/null; then
  echo "Утилита 'iptables' не найдена. Устанавливаем..."
  apt-get install -y iptables
fi

########################################
# Основная логика
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

# Проходим по каждому домену
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

########################################
# Сохранение правил iptables
########################################
# Проверяем наличие каталога /etc/iptables
if [ ! -d "/etc/iptables" ]; then
  echo "Каталог /etc/iptables не найден. Создаём..."
  mkdir -p /etc/iptables
fi

# Сохраняем правила iptables
echo "Сохраняем правила iptables..."
if iptables-save > /etc/iptables/rules.v4; then
  echo "Правила успешно сохранены в /etc/iptables/rules.v4."
else
  echo "Ошибка при сохранении правил! Проверьте права доступа или содержимое iptables."
  exit 1
fi

########################################
# Обновление файла whitelist
########################################
# Перезаписываем файл whitelist (на случай новых доменов)
{
  for site in "${WHITELIST[@]}"; do
    echo "$site"
  done
} > "$WHITELIST_FILE"

echo "Список доменов обновлён в $WHITELIST_FILE."
echo "Скрипт завершён."
