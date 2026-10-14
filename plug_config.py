from pathlib import Path

import environ

from plugs.manager import PlugManager
from plugs.plug import Plug

env = environ.Env()

# plug_config is imported by settings before they read .env, so read it here too
if env.bool("DJANGO_READ_DOT_ENV_FILE", default=False):
    env.read_env(str(Path(__file__).resolve().parent / ".env"))

# An empty version makes pip install each repo's default branch (Plug defaults to "@main").
# Branches move, so rebuild images with a fresh PLUGINS_REFRESH build arg (see prod.Dockerfile).
DEFAULT_BRANCH = ""

care_eaushadhi_plugin = Plug(
    name="care_eaushadhi",
    package_name="git+https://github.com/care-ecosystem/care_eaushadhi.git",
    version="@main",
    configs={
        "EAUSHADHI_API_ENDPOINT": "https://aushada.karnataka.gov.in/e-services/api/instinward/eGovuser",
        "EAUSHADHI_API_SECRET_KEY": env("EAUSHADHI_API_SECRET_KEY", default=""),
        "EAUSHADHI_DEPLOYMENT": "karnataka",
        # "EAUSHADHI_STRICT_QUANTITY_VALIDATION": False,
        "EAUSHADHI_API_RETRY_COUNT": 3,
        "SIMILARITY_THRESHOLD": 0.4,
    },
)

care_superbatch_plugin = Plug(
    name="super_batch_request",
    package_name="git+https://github.com/care-ecosystem/care_super_batch_be.git",
    version=DEFAULT_BRANCH,
    # configs={
    #     "SUPER_BATCH_REQUEST_MAX_REQUESTS_PER_BATCH_REQUEST":
    # },
)

care_radiology_plugin = Plug(
    name="care_radiology",
    package_name="git+https://github.com/care-ecosystem/care_radiology.git",
    version=DEFAULT_BRANCH,
    configs={
        # plugin configs take precedence over env, so read the env here to allow overrides (e.g. k3d)
        "CARE_RADIOLOGY_DCM4CHEE_DICOMWEB_BASEURL": env(
            "CARE_RADIOLOGY_DCM4CHEE_DICOMWEB_BASEURL",
            default="http://arc:8080/dcm4chee-arc/aets/DCM4CHEE",
        ),
        "CARE_RADIOLOGY_WEBHOOK_SECRET": env(
            "CARE_RADIOLOGY_WEBHOOK_SECRET", default=""
        ),
        "CARE_RADIOLOGY_REJECT_DUPLICATE_SOP_INSTANCE": False,
        "CARE_RADIOLOGY_VALIDATE_ACCESSION_NUMBER": False,
        "CARE_RADIOLOGY_UNIQUE_STUDY_PER_SR": False,
        "CARE_RADIOLOGY_DELETE_STUDY_FROM_PACS_ON_ARCHIVE": True,
    },
)

care_pinelabs_plugin = Plug(
    name="care_pinelabs",
    package_name="git+https://github.com/care-ecosystem/care_pinelabs.git",
    version=DEFAULT_BRANCH,
    configs={
        "PINELABS_MERCHANT_ID": 29610,
        "PINELABS_SECURITY_TOKEN": env("PINELABS_SECURITY_TOKEN", default=""),
        "PINELABS_API_BASE_URL": "https://www.plutuscloudserviceuat.in:8201",
        "PINELABS_SECRET_KEY": env("PINELABS_SECRET_KEY", default=""),
    },
)

care_dvdms_plugin = Plug(
    name="care_dvdms",
    package_name="git+https://github.com/care-ecosystem/care_dvdms.git",
    version=DEFAULT_BRANCH,
    configs={
        # "DVDMS_API_ENDPOINT": "https://uatjharkhand.dcservices.in/CDAC_Mobile/rest/dwh",
        # "DVDMS_API_ENDPOINT": "http://172.16.2.76:8600",
        # "DVDMS_API_ENDPOINT": "http://dvdms-mock:8600",
        "DVDMS_API_ENDPOINT": env("DVDMS_API_ENDPOINT", default=""),
        "DVDMS_AUTH_TOKEN": env("DVDMS_AUTH_TOKEN", default=""),
    },
)
# https://dvdms-mock-proxy.care-ecosystem.workers.dev/

care_state_hmis_plugin = Plug(
    name="care_state_hmis",
    package_name="git+https://github.com/care-ecosystem/care_state_hmis.git",
    version=DEFAULT_BRANCH,
    configs={},
)

# all teleicu device apps ship from one repo; identical package strings are installed once
TELEICU_DEVICES_PACKAGE = "git+https://github.com/10bedicu/care_teleicu_devices.git"
TELEICU_DEVICES_VERSION = "@lis-stable"

teleicu_device_plugins = [
    Plug(
        name=app_name,
        package_name=TELEICU_DEVICES_PACKAGE,
        version=TELEICU_DEVICES_VERSION,
        configs={},
    )
    for app_name in (
        "gateway_device",
        "lab_analyzer_device",
        "camera_device",
        "vitals_observation_device",
    )
]

plugs = [
    care_eaushadhi_plugin,
    care_superbatch_plugin,
    care_pinelabs_plugin,
    care_dvdms_plugin,
    care_radiology_plugin,
    *teleicu_device_plugins,
    care_state_hmis_plugin,
]

manager = PlugManager(plugs)
