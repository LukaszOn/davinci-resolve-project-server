"""Write the PostgreSQL connection preset imported on pgAdmin's first start."""

import json
import os
from pathlib import Path


config = Path("/config/servers.json")
server = {
    "Name": "DaVinci Resolve",
    "Group": "Servers",
    "Port": 5432,
    "Username": os.environ["POSTGRES_USER"],
    "Host": "postgres",
    "SSLMode": "prefer",
    "MaintenanceDB": "postgres",
}
temporary = config.with_suffix(".tmp")
temporary.write_text(json.dumps({"Servers": {"1": server}}, indent=2), encoding="utf-8")
temporary.replace(config)
