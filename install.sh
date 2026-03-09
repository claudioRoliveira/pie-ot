#!/bin/bash
set -euo pipefail
if [ "$EUID" -ne 0 ]; then
  echo "Execute com sudo"
  exit 1
fi


APP_DIR="/opt/gpio-controller"
BASE_URL="https://raw.githubusercontent.com/claudioRoliveira/pie-ot/master"
SERVICE_NAME="gpio-controller"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LOGROTATE_FILE="/etc/logrotate.d/gpio-controller"

echo "==============================="
echo "GPIO Controller Installer"
echo "==============================="

# criar diretório
echo "Criando diretório $APP_DIR"
mkdir -p $APP_DIR

echo "Baixando arquivos..."

curl -fsSL "$BASE_URL/main.py" -o "$APP_DIR/main.py"
curl -fsSL "$BASE_URL/config.json" -o "$APP_DIR/config.json"


# instalar dependências

echo "Instalando dependências..."

apt-get update

apt-get install -y \
    python3 \
    python3-rpi.gpio \
    logrotate \
    watchdog \
    python3-systemd \
    jq

# criar log
if [ ! -f "$APP_DIR/events.log" ]; then
    echo "Criando arquivo de log"
    touch $APP_DIR/events.log
fi

# permissões
chmod 755 $APP_DIR/main.py
chmod 755 -R $APP_DIR
chmod 644 $APP_DIR/config.json
chmod 644 $APP_DIR/events.log

echo "Instalando logrotate..."

tee $LOGROTATE_FILE > /dev/null <<EOF
$APP_DIR/events.log {

    size 1M
    rotate 10
    compress
    delaycompress
    missingok
    notifempty
    copytruncate

}
EOF


echo "Criando CLI gpio-controller..."

tee /usr/local/bin/gpio-controller > /dev/null <<'EOF'
#!/bin/bash

APP_DIR="/opt/gpio-controller"
STATUS_FILE="$APP_DIR/status.json"
if [ ! -f "$APP_DIR/status.json" ]; then
    echo "{}" > $APP_DIR/status.json
fi
LOG_FILE="$APP_DIR/events.log"

case "$1" in

status)

echo "===== GPIO CONTROLLER STATUS ====="
echo ""

systemctl is-active gpio-controller >/dev/null && echo "SERVICE: RUNNING" || echo "SERVICE: STOPPED"

echo ""
echo "Entradas:"

if [ -f "$STATUS_FILE" ]; then
    jq '.inputs' $STATUS_FILE
else
    echo "status indisponível"
fi

echo ""
echo "Saídas:"

if [ -f "$STATUS_FILE" ]; then
    jq '.outputs' $STATUS_FILE
else
    echo "status indisponível"
fi

;;

log)

echo "===== ÚLTIMOS EVENTOS ====="
tail -n 20 $LOG_FILE
;;

restart)

systemctl restart gpio-controller
echo "Serviço reiniciado"

;;

simulate-input)

PIN=$2
VALUE=$3

if [ -z "$PIN" ] || [ -z "$VALUE" ]; then
    echo "Uso: gpio-controller simulate-input <pin> <0|1>"
    exit 1
fi

SIM_FILE="$APP_DIR/simulation.json"

if [ ! -f "$SIM_FILE" ]; then
    echo "{}" > $SIM_FILE
fi

tmp=$(mktemp)

jq --arg pin "$PIN" --argjson val "$VALUE" '.[$pin]=$val' $SIM_FILE > $tmp

mv $tmp $SIM_FILE

echo "Simulação aplicada: GPIO $PIN = $VALUE"

;;

clear-sim)

rm -f $APP_DIR/simulation.json

echo "Simulações removidas"

;;

service)

systemctl status gpio-controller --no-pager

;;

*)

echo "Uso:"
echo "gpio-controller status"
echo "gpio-controller log"
echo "gpio-controller restart"
echo "gpio-controller simulate-input <pin> <0|1>"
echo "gpio-controller clear-sim"
echo "gpio-controller service"
;;

esac
EOF

chmod +x /usr/local/bin/gpio-controller


echo "Criando serviço systemd..."

tee $SERVICE_FILE > /dev/null <<EOF
[Unit]
Description=GPIO Controller
After=multi-user.target

[Service]
ExecStart=/usr/bin/python3 $APP_DIR/main.py
WorkingDirectory=$APP_DIR
Restart=always
RestartSec=3

Type=notify
NotifyAccess=all

# watchdog
WatchdogSec=30

StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF

echo "Recarregando systemd..."

systemctl daemon-reload

echo "Habilitando serviço..."

systemctl enable $SERVICE_NAME

echo "Iniciando serviço..."

systemctl start $SERVICE_NAME

echo ""
echo "================================="
echo "Instalação concluída"
echo "================================="

echo "Status do serviço:"
systemctl status $SERVICE_NAME --no-pager

sync