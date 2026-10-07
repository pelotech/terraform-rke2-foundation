# Writes the write_files of a cloud-config the way cloud-init would.
import os
import sys

import yaml

doc = yaml.safe_load(open(sys.argv[1]))
for f in doc.get("write_files", []):
    os.makedirs(os.path.dirname(f["path"]), exist_ok=True)
    with open(f["path"], "w") as fh:
        fh.write(f["content"])
    os.chmod(f["path"], int(f.get("permissions", "0644"), 8))
