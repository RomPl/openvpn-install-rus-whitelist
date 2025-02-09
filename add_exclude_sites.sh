#!/bin/bash

########################################
# Скрипт для обработки whitelist
# Добавляет IP-адреса доменов в /etc/iptables/rules.v4
########################################

LOG_FILE="/var/log/openvpn_whitelist.log"
echo "===== Начало выполнения скрипта: $(date) =====" | tee -a "$LOG_FILE"

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
  echo "Ошибка: Запустите этот скрипт с правами root!" | tee -a "$LOG_FILE"
  exit 1
fi

# Проверка/установка iptables-persistent
if ! dpkg -l | grep -qw iptables-persistent; then
  echo "iptables-persistent не установлен. Устанавливаем..." | tee -a "$LOG_FILE"
  apt-get update -y && apt-get install -y iptables-persistent
  if [ $? -ne 0 ]; then
    echo "Ошибка установки iptables-persistent. Завершение скрипта." | tee -a "$LOG_FILE"
    exit 1
  fi
else
  echo "iptables-persistent уже установлен." | tee -a "$LOG_FILE"
fi

# Проверка наличия утилит dig и iptables
if ! command -v dig &>/dev/null; then
  echo "Утилита 'dig' не найдена. Устанавливаем..." | tee -a "$LOG_FILE"
  apt-get install -y dnsutils
  if [ $? -ne 0 ]; then
    echo "Ошибка установки dnsutils (dig). Завершение скрипта." | tee -a "$LOG_FILE"
    exit 1
  fi
fi

if ! command -v iptables &>/dev/null; then
  echo "Утилита 'iptables' не найдена. Устанавливаем..." | tee -a "$LOG_FILE"
  apt-get install -y iptables
  if [ $? -ne 0 ]; then
    echo "Ошибка установки iptables. Завершение скрипта." | tee -a "$LOG_FILE"
    exit 1
  fi
fi

# Основная логика
WHITELIST_FILE="whitelist.txt"
RULES_FILE="/etc/iptables/rules.v4"

# Проверка файла whitelist
if [ ! -f "$WHITELIST_FILE" ]; then
  echo "Ошибка: Файл $WHITELIST_FILE не найден!" | tee -a "$LOG_FILE"
  exit 1
fi

# Очистка предыдущих правил (если необходимо)
echo "Очистка старых правил..." | tee -a "$LOG_FILE"
iptables -F WHITELIST 2>/dev/null
iptables -N WHITELIST 2>/dev/null
iptables -A OUTPUT -j WHITELIST

# Обработка списка доменов
while read -r site; do
  if [[ -n "$site" ]]; then
    ip=$(dig +short "$site" | head -n 1)
    if [[ -n "$ip" ]]; then
      echo "Добавляем правило для $site ($ip)" | tee -a "$LOG_FILE"
      iptables -A WHITELIST -d "$ip" -j ACCEPT
    else
      echo "Ошибка: Не удалось получить IP для $site" | tee -a "$LOG_FILE"
    fi
  fi
done < "$WHITELIST_FILE"

# Сохранение правил
iptables-save > "$RULES_FILE"
netfilter-persistent save

# Проверка, были ли правила действительно добавлены
if iptables -L WHITELIST -v -n | grep -q ACCEPT; then
  echo "Правила успешно применены!" | tee -a "$LOG_FILE"
else
  echo "Ошибка: правила не применены!" | tee -a "$LOG_FILE"
fi

echo "===== Завершение скрипта: $(date) =====" | tee -a "$LOG_FILE"
exit 0
