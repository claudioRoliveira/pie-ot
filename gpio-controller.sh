#!/bin/bash

APP_DIR="/home/pi/gpio-controller"
STATUS_FILE="$APP_DIR/status.json"
LOG_FILE="$APP_DIR/events.log"

case "$1" in

status)

echo "===== GPIO CONTROLLER STATUS ====="
echo ""

systemctl is-active gpio-controller

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

sudo systemctl restart gpio-controller
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