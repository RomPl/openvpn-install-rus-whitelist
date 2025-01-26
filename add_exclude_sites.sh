#!/bin/bash

########################################
# Скрипт для обработки whitelist
# Проверяет наличие IP-адресов в rules.v4 перед добавлением
########################################

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
  echo "Запустите этот скрипт с правами root!"
  exit 1
fi

# Проверка/установка iptables-persistent
if ! dpkg -l | grep -qw iptables-persistent; then
  echo "iptables-persistent не установлен. Устанавливаем..."
  apt-get update -y && apt-get install -y iptables-persistent
  if [ $? -ne 0 ]; then
    echo "Ошибка установки iptables-persistent. Завершение скрипта."
    exit 1
  fi
else
  echo "iptables-persistent уже установлен."
fi

# Проверка наличия утилит dig и iptables
if ! command -v dig &>/dev/null; then
  echo "Утилита 'dig' не найдена. Устанавливаем..."
  apt-get install -y dnsutils
  if [ $? -ne 0 ]; then
    echo "Ошибка установки dnsutils (dig). Завершение скрипта."
    exit 1
  fi
fi

if ! command -v iptables &>/dev/null; then
  echo "Утилита 'iptables' не найдена. Устанавливаем..."
  apt-get install -y iptables
  if [ $? -ne 0 ]; then
    echo "Ошибка установки iptables. Завершение скрипта."
    exit 1
  fi
fi

# Основная логика
WHITELIST_FILE="whitelist.txt"
RULES_FILE="/etc/iptables/rules.v4"

# Проверка файла whitelist
if [ ! -f "$WHITELIST_FILE" ]; then
  echo "Файл $WHITELIST_FILE не найден. Создаём пример..."
  echo "example.com" > "$WHITELIST_FILE"
  echo "test.local" >> "$WHITELIST_FILE"
  echo "Примерный файл $WHITELIST_FILE создан."
fi

# Чтение доменов из файла
declare -a WHITELIST
while IFS= read -r line; do
  line="$(echo "$line" | xargs)" # Убираем пробелы
  if [ -n "$line" ]; then
    WHITELIST+=("$line")
  fi
done < "$WHITELIST_FILE"

# Отладка: вывод списка доменов
echo "Доменов в whitelist: ${#WHITELIST[@]}"
for site in "${WHITELIST[@]}"; do
  echo " - $site"
done

# Проверяем, если домены не найдены
if [ ${#WHITELIST[@]} -eq 0 ]; then
  echo "Список доменов пуст. Завершаем скрипт."
  exit 1
fi

# Предлагаем добавить новые домены
echo
read -p "Хотите добавить новые сайты (через запятую)? (Enter, если нет): " USER_SITES
if [ -n "$USER_SITES" ]; then
  IFS=',' read -ra NEW_SITES <<< "$(echo "$USER_SITES" | sed 's/[[:space:]]//g')"
  for site in "${NEW_SITES[@]}"; do
    [ -n "$site" ] && WHITELIST+=("$site")
  done
fi

# Обработка каждого домена
IP_RULES=""
for site in "${WHITELIST[@]}"; do
  echo "Обрабатываем домен: $site"
  
  # Получение IP-адресов через dig
  IP_LIST=$(dig +short "$site" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
  
  # Отладка: вывод IP-адресов
  if [ -z "$IP_LIST" ]; then
    echo "Не удалось получить IP-адреса для $site. Пропуск..."
    continue
  else
    echo "Найдены IP-адреса для $site:"
    echo "$IP_LIST"
  fi

  # Проверка каждого IP-адреса в rules.v4
  while IFS= read -r ipaddr; do
    if grep -q "$ipaddr" "$RULES_FILE"; then
      echo "IP $ipaddr уже присутствует в $RULES_FILE. Пропуск..."
    else
      echo "Добавляем правило для $site ($ipaddr)"
      IP_RULES+="
-A POSTROUTING -t nat -d $ipaddr -j ACCEPT
-A PREROUTING -t mangle -d $ipaddr -j ACCEPT"
    fi
  done <<< "$IP_LIST"
done

# Проверка каталога /etc/iptables
if [ ! -d "/etc/iptables" ]; then
  echo "Каталог /etc/iptables не найден. Создаём..."
  mkdir -p /etc/iptables
fi

# Добавление правил в /etc/iptables/rules.v4
echo "Добавляем правила в /etc/iptables/rules.v4..."
{
  echo "*nat"
  echo ":PREROUTING ACCEPT [0:0]"
  echo ":INPUT ACCEPT [0:0]"
  echo ":OUTPUT ACCEPT [0:0]"
  echo ":POSTROUTING ACCEPT [0:0]"
  echo "$IP_RULES"
  echo "COMMIT"
  echo "*mangle"
  echo ":PREROUTING ACCEPT [0:0]"
  echo ":INPUT ACCEPT [0:0]"
  echo ":FORWARD ACCEPT [0:0]"
  echo ":OUTPUT ACCEPT [0:0]"
  echo ":POSTROUTING ACCEPT [0:0]"
  echo "$IP_RULES"
  echo "COMMIT"
  echo "### END OF RULES ###"
} > "$RULES_FILE"

if [ $? -eq 0 ]; then
  echo "Правила успешно добавлены в $RULES_FILE."
else
  echo "Ошибка при добавлении правил в $RULES_FILE!"
  exit 1
fi

# Обновление файла whitelist
echo "Обновляем файл whitelist..."
{
  for site in "${WHITELIST[@]}"; do
    echo "$site"
  done
} > "$WHITELIST_FILE"

echo "Скрипт завершён успешно."
