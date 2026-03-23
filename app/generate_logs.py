import time
import random
import datetime

LEVELS = ["INFO", "WARN", "ERROR"]
MESSAGES = [
    "user login successful",
    "user logout",
    "payment processed",
    "order created",
    "item added to cart",
    "request timeout",
    "database query slow",
    "cache miss",
    "invalid request body",
    "upstream service unavailable",
]

log_file = "/logs/app.log"

while True:
    level = random.choices(LEVELS, weights=[7, 2, 1])[0]
    message = random.choice(MESSAGES)
    user_id = random.randint(1000, 9999)
    timestamp = datetime.datetime.utcnow().isoformat() + "Z"

    line = f'{timestamp} [{level}] user_id={user_id} msg="{message}"'

    with open(log_file, "a") as f:
        f.write(line + "\n")

    print(line, flush=True)
    time.sleep(1)
