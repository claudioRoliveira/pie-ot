import RPi.GPIO as GPIO
import json
import time
import os
import json
import datetime

STATUS_FILE = "status.json"
CONFIG_FILE = "config.json"
LOG_FILE = "events.log"
SIM_FILE = "simulation.json"

VALID_TRIGGERS = {"rising", "falling", "high_for", "low_for"}
VALID_ACTIONS = {"on", "off", "pulse"}

rules = []
inputs = {}
timers = {}
debounce_ms = 50

GPIO.setmode(GPIO.BCM)


def log_event(input_pin, state, rule_name, output_pin, action):

    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    line = f"{ts} Input {input_pin} {state} - rule: {rule_name} - output {output_pin} {action}\n"

    with open(LOG_FILE, "a") as f:
        f.write(line)

def get_simulated_inputs():

    if not os.path.exists(SIM_FILE):
        return {}

    try:
        with open(SIM_FILE) as f:
            return json.load(f)
    except:
        return {}


def validate_rule(rule):

    required = ["name", "input", "trigger", "output", "action"]

    for r in required:
        if r not in rule:
            return False

    if rule["trigger"] not in VALID_TRIGGERS:
        return False

    if rule["action"] not in VALID_ACTIONS:
        return False

    if rule["action"] == "pulse" and "pulse_time" not in rule:
        return False

    if rule["trigger"] in ["high_for", "low_for"] and "duration" not in rule:
        return False

    return True


def load_config():

    global rules, debounce_ms

    with open(CONFIG_FILE) as f:
        cfg = json.load(f)

    debounce_ms = cfg.get("debounce_ms", 50)

    new_rules = []

    for r in cfg["rules"]:

        if not validate_rule(r):
            continue

        r["cooldown"] = r.get("cooldown", 0)
        r["last_run"] = 0

        new_rules.append(r)

        i = r["input"]
        o = r["output"]

        if i not in inputs:
            GPIO.setup(i, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
            inputs[i] = {
                "last": GPIO.input(i),
                "since": time.time(),
                "last_change": 0
            }

        GPIO.setup(o, GPIO.OUT)
        GPIO.output(o, 0)

    rules.clear()
    rules.extend(new_rules)


def execute(rule):

    now = time.time()

    if rule["cooldown"] > 0:
        if now - rule["last_run"] < rule["cooldown"]:
            return

    rule["last_run"] = now

    output = rule["output"]

    if rule["action"] == "on":

        GPIO.output(output, 1)
        action = "ON"

    elif rule["action"] == "off":

        GPIO.output(output, 0)
        action = "OFF"

    elif rule["action"] == "pulse":

        GPIO.output(output, 1)
        timers[output] = now + rule["pulse_time"]
        action = "PULSE"

    state = "HIGH" if GPIO.input(rule["input"]) else "LOW"

    log_event(rule["input"], state, rule["name"], output, action)


def update_timers():

    now = time.time()

    for o in list(timers):

        if now >= timers[o]:
            GPIO.output(o, 0)
            del timers[o]


def check_inputs():

    now = time.time()

    for pin in inputs:

        sim = get_simulated_inputs()

        if str(pin) in sim:
            val = sim[str(pin)]
        else:
            val = GPIO.input(pin)
        s = inputs[pin]

        if val != s["last"]:

            if (now - s["last_change"]) * 1000 < debounce_ms:
                continue

            s["last_change"] = now
            s["since"] = now

        for r in rules:

            if r["input"] != pin:
                continue

            if r["trigger"] == "rising":

                if s["last"] == 0 and val == 1:
                    execute(r)

            elif r["trigger"] == "falling":

                if s["last"] == 1 and val == 0:
                    execute(r)

            elif r["trigger"] == "high_for":

                if val == 1 and now - s["since"] >= r["duration"]:
                    execute(r)

            elif r["trigger"] == "low_for":

                if val == 0 and now - s["since"] >= r["duration"]:
                    execute(r)

        s["last"] = val

def feed_watchdog():
    try:
        os.system("systemd-notify WATCHDOG=1")
    except:
        pass

def write_status():

    status = {
        "inputs": {},
        "outputs": {}
    }

    sim = get_simulated_inputs()

    for pin in inputs:

        if str(pin) in sim:
            status["inputs"][pin] = sim[str(pin)]
        else:
            status["inputs"][pin] = GPIO.input(pin)

    for rule in rules:
        o = rule["output"]
        status["outputs"][o] = GPIO.input(o)

    with open(STATUS_FILE, "w") as f:
        json.dump(status, f)

def main():

    load_config()

    last_config = os.path.getmtime(CONFIG_FILE)

    while True:

        check_inputs()
        update_timers()
        write_status()
        feed_watchdog()
        mtime = os.path.getmtime(CONFIG_FILE)

        if mtime != last_config:
            load_config()
            last_config = mtime

        time.sleep(0.1)


if __name__ == "__main__":

    try:
        main()

    finally:
        GPIO.cleanup()