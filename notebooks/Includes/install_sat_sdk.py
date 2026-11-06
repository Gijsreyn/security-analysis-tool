# Databricks notebook source
# MAGIC %md
# MAGIC **Notebook name:** install_sat_sdk  
# MAGIC **Functionality:** Installs the necessary sat sdk

# COMMAND ----------

RECOMMENDED_DBR_FOR_SAT= 14.3
import os
#Get databricks runtime configured to run SAT
dbr_version = os.environ.get('DATABRICKS_RUNTIME_VERSION','0.0')
is_sat_compatible = False
is_serverless= False
#sanity check in case there is major and minor version
#strip minor version since we need to compare as number
if(dbr_version.startswith("client")):
    is_sat_compatible = True
    is_serverless = True
else:
    dbrarray = dbr_version.split('.')
    dbr_version =  f'{dbrarray[0]}.{dbrarray[1]}'
    dbr_version = float(dbr_version)
    is_sat_compatible = True if dbr_version >= RECOMMENDED_DBR_FOR_SAT else False

#test version

if is_sat_compatible== False:
    dbutils.notebook.exit(f"Detected DBR version {dbr_version} . Please use the DBR {RECOMMENDED_DBR_FOR_SAT} for SAT and try again , please refer to docs/setup.md")

# COMMAND ----------

SDK_VERSION='0.1.54'

# COMMAND ----------

def getLibPath():
    path = (
        dbutils.notebook.entry_point.getDbutils()
        .notebook()
        .getContext()
        .notebookPath()
        .get()
    )
    path = path[: path.find("/notebooks")]
    return f"/Workspace{path}/lib"

# COMMAND ----------

# Resolve the wheel from the synced lib/ folder.
# Prefer the version this notebook was released with (SDK_VERSION). If that exact
# wheel is absent but lib/ holds exactly one SDK wheel, install that one and warn,
# so a notebooks/lib version drift at deploy time does not abort every run.
# Anything else is a real deployment error: fail with what was actually found.
import glob, os

LIB_PATH = getLibPath()
EXPECTED_WHEEL = f'{LIB_PATH}/dbl_sat_sdk-{SDK_VERSION}-py3-none-any.whl'
available_wheels = sorted(glob.glob(f'{LIB_PATH}/dbl_sat_sdk-*.whl'))

if os.path.exists(EXPECTED_WHEEL):
    WHEEL_PATH = EXPECTED_WHEEL
elif len(available_wheels) == 1:
    WHEEL_PATH = available_wheels[0]
    print(
        f"WARNING: expected dbl_sat_sdk-{SDK_VERSION} in {LIB_PATH} but found "
        f"{os.path.basename(WHEEL_PATH)}. Installing it anyway. "
        f"Deploy notebooks/ and lib/ from the same commit so SDK_VERSION matches the wheel."
    )
else:
    found = ', '.join(os.path.basename(w) for w in available_wheels) or 'none'
    raise FileNotFoundError(
        f"SAT SDK wheel not found. Expected {EXPECTED_WHEEL}. "
        f"Wheels present in {LIB_PATH}: {found}. "
        f"Deploy notebooks/ and lib/ from the same commit and make sure lib/ is synced to the workspace."
    )

print(f"Installing SAT SDK from: {WHEEL_PATH}")

# COMMAND ----------

import subprocess, sys

if is_serverless:
    # Serverless: PyYAML and requests are pre-installed in all env versions.
    # msal is only pre-installed in env v4+; it is a lazy import in dbclient.py (Azure-only).
    # Install the SDK wheel only, with --no-deps to avoid any PyPI resolution.
    subprocess.run([sys.executable, "-m", "pip", "install", "--no-deps", WHEEL_PATH], check=True)
else:
    subprocess.run([sys.executable, "-m", "pip", "install", "PyYAML", WHEEL_PATH], check=True)

# Confirm what actually got installed so the run log shows the effective SDK version.
from importlib.metadata import version as _pkg_version
print(f"SAT SDK installed: dbl-sat-sdk {_pkg_version('dbl-sat-sdk')}")
